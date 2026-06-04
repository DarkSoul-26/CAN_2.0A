`timescale 1ns / 1ps
//============================================================================
// Module: can_controller_top
// Description: CAN 2.0A Controller Top-Level Integration
//
//   Complete CAN controller IP with APB interface. Integrates all verified
//   sub-blocks into a functional CAN 2.0A node (standard 11-bit ID only).
//
//   Features:
//     - APB3 slave interface for CPU access
//     - Bit timing generation with hard sync and resynchronization
//     - TX/RX frame processing (SOF through EOF)
//     - Bit stuffing / de-stuffing
//     - CRC-15 generation and checking
//     - Arbitration handling
//     - Error detection and management (TEC/REC, bus-off)
//     - Acceptance filtering
//     - Interrupt generation
//
//   External Interface:
//     - APB bus (PCLK, PRESETn, PSEL, PENABLE, PWRITE, PADDR, PWDATA, PRDATA,
//                PREADY, PSLVERR)
//     - CAN physical interface (can_tx, can_rx)
//     - Interrupt output (can_interrupt)
//
//   Register Map: See can_reg_file.v for complete register descriptions
//     0x00 - 0x2A: Register file (configuration, status, TX/RX data)
//     0x2C:        Command register (tx_req, tx_abort, rx_release)
//============================================================================

module can_controller_top (
    // System clock and reset
    input  wire        clk,
    input  wire        rst_n,

    // APB3 Slave Interface
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [7:0]  PADDR,
    input  wire [15:0] PWDATA,
    output wire [15:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,

    // CAN Physical Interface
    output wire        can_tx,
    input  wire        can_rx,

    // Interrupt Output
    output wire        can_interrupt
);

    //==========================================================================
    // Internal Signals - APB to Register File
    //==========================================================================
    wire        reg_write_en;
    wire        reg_read_en;
    wire [7:0]  reg_addr;
    wire [15:0] reg_wdata;
    wire [15:0] reg_rdata;

    // Command signals (from APB slave)
    wire        tx_req_pulse;
    wire        tx_abort;
    wire        rx_release;
    
    // Latch tx_req pulse until TX starts
    reg         tx_req_pending;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_req_pending <= 1'b0;
        end else begin
            if (tx_req_pulse && !reset_mode && !bus_off)
                tx_req_pending <= 1'b1;
            else if (tx_busy)
                tx_req_pending <= 1'b0;
        end
    end
    
    wire tx_req_latched = tx_req_pending || (tx_req_pulse && !reset_mode && !bus_off);

    //==========================================================================
    // Internal Signals - Register File Outputs
    //==========================================================================
    wire        reset_mode;
    wire        loopback_mode;
    wire        listen_only_mode;
    wire [10:0] tx_id;
    wire [3:0]  tx_dlc;
    wire [15:0] tx_data0, tx_data1, tx_data2, tx_data3;
    wire [63:0] tx_data = {tx_data0, tx_data1, tx_data2, tx_data3};
    wire [15:0] btr_reg;
    wire [15:0] acr_reg;
    wire [15:0] amr_reg;
    wire [15:0] int_en_reg;
    
    //==========================================================================
    // Loopback Mode Support
    //   In loopback mode, copy TX frame to RX after transmission completes
    //==========================================================================
    reg         loopback_rx_ready;
    reg  [10:0] loopback_rx_id;
    reg  [3:0]  loopback_rx_dlc;
    reg  [15:0] loopback_rx_data0, loopback_rx_data1, loopback_rx_data2, loopback_rx_data3;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            loopback_rx_ready <= 1'b0;
            loopback_rx_id    <= 11'd0;
            loopback_rx_dlc   <= 4'd0;
            loopback_rx_data0 <= 16'd0;
            loopback_rx_data1 <= 16'd0;
            loopback_rx_data2 <= 16'd0;
            loopback_rx_data3 <= 16'd0;
        end else begin
            loopback_rx_ready <= 1'b0;  // pulse
            
            // When TX completes in loopback mode, copy frame to RX
            if (loopback_mode && tx_done) begin
                loopback_rx_ready <= 1'b1;
                loopback_rx_id    <= tx_id;
                loopback_rx_dlc   <= tx_dlc;
                loopback_rx_data0 <= tx_data0;
                loopback_rx_data1 <= tx_data1;
                loopback_rx_data2 <= tx_data2;
                loopback_rx_data3 <= tx_data3;
            end
        end
    end
    
    // Mux RX signals: loopback or real RX
    wire        rx_ready_muxed = loopback_mode ? loopback_rx_ready : rx_ready;
    wire [10:0] rx_id_muxed    = loopback_mode ? loopback_rx_id    : rx_id;
    wire [3:0]  rx_dlc_muxed   = loopback_mode ? loopback_rx_dlc   : rx_dlc;
    wire [15:0] rx_data0_muxed = loopback_mode ? loopback_rx_data0 : rx_data0;
    wire [15:0] rx_data1_muxed = loopback_mode ? loopback_rx_data1 : rx_data1;
    wire [15:0] rx_data2_muxed = loopback_mode ? loopback_rx_data2 : rx_data2;
    wire [15:0] rx_data3_muxed = loopback_mode ? loopback_rx_data3 : rx_data3;

    //==========================================================================
    // Internal Signals - Bit Timing
    //==========================================================================
    wire        tq_tick;
    wire        sample_tick;
    wire        bit_tick;
    wire        bus_idle;

    //==========================================================================
    // Internal Signals - TX FSM
    //==========================================================================
    wire        tx_can_tx;      // TX output (pre-stuffing)
    wire        tx_crc_bit;     // TX bit for CRC feed
    wire        tx_busy;
    wire        tx_done;
    wire        tx_ack_error;
    wire        tx_crc_en;
    wire        tx_crc_clear;
    wire        tx_in_arb;

    //==========================================================================
    // Internal Signals - RX FSM
    //==========================================================================
    wire [10:0] rx_id;
    wire [3:0]  rx_dlc;
    wire [15:0] rx_data0, rx_data1, rx_data2, rx_data3;
    wire        rx_ready;
    wire        rx_ack_bit;
    wire        rx_crc_en;
    wire        rx_crc_clear;
    wire        rx_crc_err;
    wire        rx_form_err;
    wire        rx_active;

    //==========================================================================
    // Internal Signals - Bit Stuffing
    //==========================================================================
    wire        tx_data_out;
    wire        tx_stall;
    wire        rx_data_out;
    wire        rx_data_valid;
    wire        stuff_err;

    //==========================================================================
    // Internal Signals - CRC
    //==========================================================================
    wire [14:0] crc_tx_out;
    wire [14:0] crc_rx_out;

    //==========================================================================
    // Internal Signals - Arbitration
    //==========================================================================
    wire        arb_lost;

    //==========================================================================
    // Internal Signals - Error Detector
    //==========================================================================
    wire [7:0]  tec;
    wire [7:0]  rec;
    wire [4:0]  err_code;
    wire        bus_off;
    wire        err_passive;
    wire        err_active;

    //==========================================================================
    // Internal Signals - Interrupt Controller
    //==========================================================================
    wire [15:0] ir_reg;

    //==========================================================================
    // Bus Idle Detection (TX and RX both idle)
    //==========================================================================
    assign bus_idle = !tx_busy && !rx_active;

    //==========================================================================
    // CAN Bus Arbitration (TX vs RX)
    //   - TX drives bus when transmitting (unless lost arbitration)
    //   - RX drives ACK slot when receiving valid frame
    //   - Otherwise bus is recessive (idle)
    //   - Loopback mode: TX stuffed output loops back to RX input
    //==========================================================================
    wire can_tx_internal;
    wire can_rx_internal;

    // TX drives bus during transmission, RX drives during ACK slot
    assign can_tx_internal = (tx_busy && !arb_lost) ? tx_data_out :
                             (rx_active) ? rx_ack_bit : 1'b1;

    // Loopback mode: feed back stuffed TX output
    // Normal mode: use external can_rx input
    assign can_rx_internal = loopback_mode ? tx_data_out : can_rx;

    // External CAN bus output
    assign can_tx = can_tx_internal;

    //==========================================================================
    // Bit Stuffing Control
    //   - TX stuffing: enabled during transmission
    //   - RX de-stuffing: enabled during reception (or in loopback when TX active)
    //   - Clear on bus idle (between frames)
    //   - In loopback mode, don't clear RX stuffing while TX is active
    //==========================================================================
    wire tx_stuffing_clear = bus_idle;
    wire rx_stuffing_clear = loopback_mode ? (!tx_busy && !rx_active) : bus_idle;

    //==========================================================================
    // BLOCK INSTANTIATIONS
    //==========================================================================

    //--------------------------------------------------------------------------
    // APB Slave Interface
    //--------------------------------------------------------------------------
    can_apb_slave u_apb_slave (
        .PCLK         (clk),
        .PRESETn      (rst_n),
        .PSEL         (PSEL),
        .PENABLE      (PENABLE),
        .PWRITE       (PWRITE),
        .PADDR        (PADDR),
        .PWDATA       (PWDATA),
        .PRDATA       (PRDATA),
        .PREADY       (PREADY),
        .PSLVERR      (PSLVERR),
        .reg_write_en (reg_write_en),
        .reg_read_en  (reg_read_en),
        .reg_addr     (reg_addr),
        .reg_wdata    (reg_wdata),
        .reg_rdata    (reg_rdata),
        .tx_req       (tx_req_pulse),
        .tx_abort     (tx_abort),
        .rx_release   (rx_release)
    );

    //--------------------------------------------------------------------------
    // Register File
    //--------------------------------------------------------------------------
    can_reg_file u_reg_file (
        .clk              (clk),
        .rst_n            (rst_n),
        .reg_write_en     (reg_write_en),
        .reg_read_en      (reg_read_en),
        .reg_addr         (reg_addr),
        .reg_wdata        (reg_wdata),
        .reg_rdata        (reg_rdata),
        .tx_busy          (tx_busy),
        .tx_done          (tx_done),
        .rx_ready         (rx_ready_muxed),
        .arb_lost         (arb_lost),
        .bus_off          (bus_off),
        .tec              (tec),
        .rec              (rec),
        .err_code         (err_code),
        .ir_reg_in        (ir_reg),
        .rx_id            (rx_id_muxed),
        .rx_dlc           (rx_dlc_muxed),
        .rx_data0         (rx_data0_muxed),
        .rx_data1         (rx_data1_muxed),
        .rx_data2         (rx_data2_muxed),
        .rx_data3         (rx_data3_muxed),
        .reset_mode       (reset_mode),
        .loopback_mode    (loopback_mode),
        .listen_only_mode (listen_only_mode),
        .tx_id            (tx_id),
        .tx_dlc           (tx_dlc),
        .tx_data0         (tx_data0),
        .tx_data1         (tx_data1),
        .tx_data2         (tx_data2),
        .tx_data3         (tx_data3),
        .btr_reg_out      (btr_reg),
        .acr_reg_out      (acr_reg),
        .amr_reg_out      (amr_reg),
        .int_en_reg_out   (int_en_reg)
    );

    //--------------------------------------------------------------------------
    // Bit Timing Generator
    //--------------------------------------------------------------------------
    can_bit_timing u_bit_timing (
        .clk         (clk),
        .rst_n       (rst_n),
        .btr_reg     (btr_reg),
        .can_rx      (can_rx_internal),
        .bus_idle    (bus_idle),
        .tq_tick     (tq_tick),
        .sample_tick (sample_tick),
        .bit_tick    (bit_tick)
    );

    //--------------------------------------------------------------------------
    // Transmit FSM
    //--------------------------------------------------------------------------
    tx_fsm u_tx_fsm (
        .clk           (clk),
        .rst_n         (rst_n),
        .bit_tick      (bit_tick),
        .tx_stall      (tx_stall),
        .tx_req        (tx_req_latched),
        .tx_id         (tx_id),
        .tx_dlc        (tx_dlc),
        .tx_data       (tx_data),
        .can_rx        (can_rx_internal),
        .arb_lost      (arb_lost),
        .crc_computed  (crc_tx_out),
        .can_tx        (tx_can_tx),
        .crc_bit       (tx_crc_bit),
        .tx_busy       (tx_busy),
        .tx_done       (tx_done),
        .ack_error     (tx_ack_error),
        .crc_en        (tx_crc_en),
        .crc_clear     (tx_crc_clear),
        .in_arb        (tx_in_arb)
    );

    //--------------------------------------------------------------------------
    // Receive FSM
    //--------------------------------------------------------------------------
    rx_fsm u_rx_fsm (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_tick  (sample_tick),
        .data_valid   (rx_data_valid),
        .data_in      (rx_data_out),
        .crc_rx       (crc_rx_out),
        .rx_release   (rx_release),
        .ack_bit      (rx_ack_bit),
        .crc_en       (rx_crc_en),
        .crc_clear    (rx_crc_clear),
        .rx_id        (rx_id),
        .rx_dlc       (rx_dlc),
        .rx_data0     (rx_data0),
        .rx_data1     (rx_data1),
        .rx_data2     (rx_data2),
        .rx_data3     (rx_data3),
        .rx_ready     (rx_ready),
        .crc_err      (rx_crc_err),
        .form_err     (rx_form_err),
        .rx_active    (rx_active)
    );

    //--------------------------------------------------------------------------
    // Bit Stuffing (TX path)
    //--------------------------------------------------------------------------
    bit_stuffing u_tx_stuffing (
        .clk         (clk),
        .rst_n       (rst_n),
        .tx_en       (tx_busy),
        .rx_en       (1'b0),
        .bit_tick    (bit_tick),
        .sample_tick (1'b0),
        .clear       (tx_stuffing_clear),
        .data_in     (tx_can_tx),
        .data_out    (tx_data_out),
        .data_valid  (),              // unused in TX mode
        .stuff_err   (),              // unused in TX mode
        .tx_stall    (tx_stall)
    );

    //--------------------------------------------------------------------------
    // Bit Stuffing (RX path)
    // In loopback mode, RX must be enabled even before rx_active to detect SOF
    //--------------------------------------------------------------------------
    wire rx_stuffing_en = rx_active || (loopback_mode && tx_busy);
    
    bit_stuffing u_rx_stuffing (
        .clk         (clk),
        .rst_n       (rst_n),
        .tx_en       (1'b0),
        .rx_en       (rx_stuffing_en),
        .bit_tick    (1'b0),
        .sample_tick (sample_tick),
        .clear       (rx_stuffing_clear),
        .data_in     (can_rx_internal),
        .data_out    (rx_data_out),
        .data_valid  (rx_data_valid),
        .stuff_err   (stuff_err),
        .tx_stall    ()               // unused in RX mode
    );

    //--------------------------------------------------------------------------
    // CRC Generator (TX path)
    //--------------------------------------------------------------------------
    can_crc u_tx_crc (
        .clk      (clk),
        .rst_n    (rst_n),
        .enable   (tx_crc_en),
        .clear    (tx_crc_clear),
        .data_in  (tx_crc_bit),
        .crc_out  (crc_tx_out)
    );

    //--------------------------------------------------------------------------
    // CRC Checker (RX path)
    //--------------------------------------------------------------------------
    can_crc u_rx_crc (
        .clk      (clk),
        .rst_n    (rst_n),
        .enable   (rx_crc_en),
        .clear    (rx_crc_clear),
        .data_in  (rx_data_out),
        .crc_out  (crc_rx_out)
    );

    //--------------------------------------------------------------------------
    // Arbitration Monitor (disabled in loopback mode)
    //--------------------------------------------------------------------------
    can_arbitration u_arbitration (
        .clk        (clk),
        .rst_n      (rst_n),
        .bit_tick   (bit_tick),
        .tx_active  (tx_in_arb & ~loopback_mode),  // Disable in loopback
        .can_tx     (tx_can_tx),
        .can_rx     (can_rx_internal),
        .arb_lost   (arb_lost)
    );

    //--------------------------------------------------------------------------
    // Error Detector
    //--------------------------------------------------------------------------
    can_error_detector u_error_detector (
        .clk        (clk),
        .rst_n      (rst_n),
        .bit_err    (1'b0),           // TODO: bit error detection
        .stuff_err  (stuff_err),
        .crc_err    (rx_crc_err),
        .form_err   (rx_form_err),
        .ack_err    (tx_ack_error),
        .arb_lost   (arb_lost),
        .tx_done    (tx_done),
        .rx_ready   (rx_ready),
        .reset_mode (reset_mode),
        .tec        (tec),
        .rec        (rec),
        .err_code   (err_code),
        .bus_off    (bus_off),
        .err_passive(err_passive),
        .err_active (err_active)
    );

    //--------------------------------------------------------------------------
    // Acceptance Filter
    //--------------------------------------------------------------------------
    wire rx_accepted;
    wire rx_filtered;
    
    can_acceptance_filter u_acceptance_filter (
        .clk          (clk),
        .rst_n        (rst_n),
        .acr_reg      (acr_reg),
        .amr_reg      (amr_reg),
        .rx_id        (rx_id_muxed),
        .rx_ready_in  (rx_ready_muxed),
        .rx_accepted  (rx_accepted),
        .rx_filtered  (rx_filtered)
    );

    //--------------------------------------------------------------------------
    // Interrupt Controller
    //--------------------------------------------------------------------------
    can_interrupt u_interrupt (
        .clk          (clk),
        .rst_n        (rst_n),
        .int_en_reg   (int_en_reg),
        .tx_done      (tx_done),
        .rx_ready     (rx_accepted),      // Only interrupt on accepted frames
        .crc_err      (rx_crc_err),
        .form_err     (rx_form_err),
        .stuff_err    (stuff_err),
        .arb_lost     (arb_lost),
        .bus_off      (bus_off),
        .ir_clr       (1'b0),             // TODO: Add IR clear from APB
        .ir_reg       (ir_reg),
        .irq          (can_interrupt)
    );

endmodule
