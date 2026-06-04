`timescale 1ns / 1ps
//============================================================================
// Module: can_reg_file
// Description: CAN 2.0A Register File (16-bit registers, byte-addressed)
//
//   Register Map (address is byte-aligned, 16-bit words):
//     0x00  MODE      - Mode control (reset_mode, loopback, listen_only)
//     0x02  INT_EN    - Interrupt enable mask
//     0x04  BTR       - Bit Timing Register
//     0x06  ACR       - Acceptance Code Register
//     0x08  AMR       - Acceptance Mask Register
//     0x0A  TX_ID     - Transmit ID (11-bit)
//     0x0C  TX_DLC    - Transmit DLC (4-bit)
//     0x0E  TX_DATA0  - TX data bytes 0..1
//     0x10  TX_DATA1  - TX data bytes 2..3
//     0x12  TX_DATA2  - TX data bytes 4..5
//     0x14  TX_DATA3  - TX data bytes 6..7
//     0x16  STATUS    - Status register (read-only, sticky)
//     0x18  IR        - Interrupt register (read-only, from interrupt block)
//     0x1A  TEC       - Transmit Error Counter (read-only)
//     0x1C  REC       - Receive Error Counter (read-only)
//     0x1E  ERR_CODE  - Last error code (read-only)
//     0x20  RX_ID     - Received ID (read-only)
//     0x22  RX_DLC    - Received DLC (read-only)
//     0x24  RX_DATA0  - RX data bytes 0..1 (read-only)
//     0x26  RX_DATA1  - RX data bytes 2..3 (read-only)
//     0x28  RX_DATA2  - RX data bytes 4..5 (read-only)
//     0x2A  RX_DATA3  - RX data bytes 6..7 (read-only)
//
//   STATUS register bits (sticky, clear-on-read at 0x16):
//     [0] tx_busy    : Transmission in progress (level)
//     [1] tx_done    : Transmission completed (sticky pulse)
//     [2] rx_ready   : Frame received (sticky pulse)
//     [3] arb_lost   : Arbitration lost (sticky pulse)
//     [4] bus_off    : Node is bus-off (level)
//
//   MODE register bits:
//     [0] reset_mode      : 1 = offline (no TX/RX), 0 = normal operation
//     [1] loopback_mode   : 1 = internal loopback (for self-test)
//     [2] listen_only_mode: 1 = monitor-only (no ACK, no error frames)
//============================================================================

module can_reg_file (
    input  wire        clk,
    input  wire        rst_n,

    // APB interface (from can_apb_slave)
    input  wire        reg_write_en,
    input  wire        reg_read_en,
    input  wire [7:0]  reg_addr,
    input  wire [15:0] reg_wdata,
    output reg  [15:0] reg_rdata,

    // Status inputs (from TX/RX FSMs, error detector, etc.)
    input  wire        tx_busy,
    input  wire        tx_done,
    input  wire        rx_ready,
    input  wire        arb_lost,
    input  wire        bus_off,

    // Error counters (from error_detector)
    input  wire [7:0]  tec,
    input  wire [7:0]  rec,
    input  wire [4:0]  err_code,

    // Interrupt register (from can_interrupt)
    input  wire [15:0] ir_reg_in,

    // RX frame data (from rx_fsm)
    input  wire [10:0] rx_id,
    input  wire [3:0]  rx_dlc,
    input  wire [15:0] rx_data0,
    input  wire [15:0] rx_data1,
    input  wire [15:0] rx_data2,
    input  wire [15:0] rx_data3,

    // Mode control outputs
    output wire        reset_mode,
    output wire        loopback_mode,
    output wire        listen_only_mode,

    // TX frame data outputs (to tx_fsm)
    output wire [10:0] tx_id,
    output wire [3:0]  tx_dlc,
    output wire [15:0] tx_data0,
    output wire [15:0] tx_data1,
    output wire [15:0] tx_data2,
    output wire [15:0] tx_data3,

    // Configuration outputs
    output wire [15:0] btr_reg_out,
    output wire [15:0] acr_reg_out,
    output wire [15:0] amr_reg_out,
    output wire [15:0] int_en_reg_out
);

    //--------------------------------------------------------------------------
    // Writable registers
    //--------------------------------------------------------------------------
    reg [15:0] mode_reg;
    reg [15:0] int_en_reg;
    reg [15:0] btr_reg;
    reg [15:0] acr_reg;
    reg [15:0] amr_reg;
    reg [15:0] tx_id_reg;
    reg [15:0] tx_dlc_reg;
    reg [15:0] tx_data0_reg;
    reg [15:0] tx_data1_reg;
    reg [15:0] tx_data2_reg;
    reg [15:0] tx_data3_reg;

    //--------------------------------------------------------------------------
    // Read-only status/error registers (updated from hardware)
    //--------------------------------------------------------------------------
    reg [15:0] status_reg;   // Sticky status bits
    reg [15:0] tec_reg;
    reg [15:0] rec_reg;
    reg [15:0] err_reg;

    //--------------------------------------------------------------------------
    // Write: CPU updates writable registers
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode_reg     <= 16'h0001;  // reset_mode = 1 (offline by default)
            int_en_reg   <= 16'd0;
            btr_reg      <= 16'd0;
            acr_reg      <= 16'd0;
            amr_reg      <= 16'd0;
            tx_id_reg    <= 16'd0;
            tx_dlc_reg   <= 16'd0;
            tx_data0_reg <= 16'd0;
            tx_data1_reg <= 16'd0;
            tx_data2_reg <= 16'd0;
            tx_data3_reg <= 16'd0;
        end else if (reg_write_en) begin
            case (reg_addr)
                8'h00: mode_reg     <= reg_wdata;
                8'h02: int_en_reg   <= reg_wdata;
                8'h04: btr_reg      <= reg_wdata;
                8'h06: acr_reg      <= reg_wdata;
                8'h08: amr_reg      <= reg_wdata;
                8'h0A: tx_id_reg    <= reg_wdata;
                8'h0C: tx_dlc_reg   <= reg_wdata;
                8'h0E: tx_data0_reg <= reg_wdata;
                8'h10: tx_data1_reg <= reg_wdata;
                8'h12: tx_data2_reg <= reg_wdata;
                8'h14: tx_data3_reg <= reg_wdata;
                // Read-only registers (0x16..0x2A) ignore writes
                default: ;
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Status register: sticky pulses + levels
    //   - tx_busy, bus_off are levels (updated every cycle)
    //   - tx_done, rx_ready, arb_lost are sticky (set on pulse, clear on read)
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            status_reg <= 16'd0;
        end else begin
            // Level bits: updated every cycle
            status_reg[0] <= tx_busy;
            status_reg[4] <= bus_off;

            // Sticky bits: set on event pulse
            if (tx_done)   status_reg[1] <= 1'b1;
            if (rx_ready)  status_reg[2] <= 1'b1;
            if (arb_lost)  status_reg[3] <= 1'b1;

            // Clear sticky bits on read of STATUS register (0x16)
            if (reg_read_en && reg_addr == 8'h16) begin
                status_reg[1] <= 1'b0;  // clear tx_done
                status_reg[2] <= 1'b0;  // clear rx_ready
                status_reg[3] <= 1'b0;  // clear arb_lost
            end
        end
    end

    //--------------------------------------------------------------------------
    // Error/counter registers: updated from hardware
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tec_reg <= 16'd0;
            rec_reg <= 16'd0;
            err_reg <= 16'd0;
        end else begin
            tec_reg     <= {8'd0, tec};
            rec_reg     <= {8'd0, rec};
            err_reg[4:0] <= err_code;
        end
    end

    //--------------------------------------------------------------------------
    // Read: CPU reads any register
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_rdata <= 16'd0;
        end else if (reg_read_en) begin
            case (reg_addr)
                // Writable config registers
                8'h00: reg_rdata <= mode_reg;
                8'h02: reg_rdata <= int_en_reg;
                8'h04: reg_rdata <= btr_reg;
                8'h06: reg_rdata <= acr_reg;
                8'h08: reg_rdata <= amr_reg;
                8'h0A: reg_rdata <= tx_id_reg;
                8'h0C: reg_rdata <= tx_dlc_reg;
                8'h0E: reg_rdata <= tx_data0_reg;
                8'h10: reg_rdata <= tx_data1_reg;
                8'h12: reg_rdata <= tx_data2_reg;
                8'h14: reg_rdata <= tx_data3_reg;

                // Read-only status/error registers
                8'h16: reg_rdata <= status_reg;
                8'h18: reg_rdata <= ir_reg_in;
                8'h1A: reg_rdata <= tec_reg;
                8'h1C: reg_rdata <= rec_reg;
                8'h1E: reg_rdata <= err_reg;

                // Read-only RX frame data
                8'h20: reg_rdata <= {5'd0, rx_id};
                8'h22: reg_rdata <= {12'd0, rx_dlc};
                8'h24: reg_rdata <= rx_data0;
                8'h26: reg_rdata <= rx_data1;
                8'h28: reg_rdata <= rx_data2;
                8'h2A: reg_rdata <= rx_data3;

                default: reg_rdata <= 16'd0;
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Output assignments
    //--------------------------------------------------------------------------
    assign reset_mode       = mode_reg[0];
    assign loopback_mode    = mode_reg[1];
    assign listen_only_mode = mode_reg[2];

    assign tx_id    = tx_id_reg[10:0];
    assign tx_dlc   = tx_dlc_reg[3:0];
    assign tx_data0 = tx_data0_reg;
    assign tx_data1 = tx_data1_reg;
    assign tx_data2 = tx_data2_reg;
    assign tx_data3 = tx_data3_reg;

    assign btr_reg_out    = btr_reg;
    assign acr_reg_out    = acr_reg;
    assign amr_reg_out    = amr_reg;
    assign int_en_reg_out = int_en_reg;

endmodule
