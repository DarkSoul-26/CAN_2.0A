`timescale 1ns / 1ps
//============================================================================
// Module: rx_fsm
// Description: CAN 2.0A Receive FSM (standard 11-bit identifier, data frame)
//
//   Receives a CAN frame bit-by-bit (de-stuffed) and extracts:
//     ID, DLC, data bytes, validates CRC, sends ACK.
//
//   Inputs:
//     - sample_tick : 1-clk pulse from bit_timing at the sample point.
//     - data_valid  : from bit_stuffing RX; HIGH when data_in is a real
//                     bit (stuff bits removed).
//     - data_in     : de-stuffed serial bit sampled at sample_tick.
//     - crc_rx      : CRC-15 computed by external can_crc over received bits.
//     - rx_release  : CPU clears the RX buffer (buf_full).
//
//   Outputs:
//     - rx_id, rx_dlc, rx_data0..3 : captured frame fields.
//     - rx_ready    : 1-clk pulse when a valid frame is stored.
//     - ack_bit     : driven onto can_tx during ACK slot (dominant).
//     - crc_en      : 1-clk pulse to feed data_in to can_crc.
//     - crc_clear   : 1-clk pulse to zero can_crc at SOF.
//     - crc_err     : 1-clk pulse if received CRC != computed CRC.
//     - form_err    : 1-clk pulse on format violation.
//     - rx_active   : HIGH while receiving a frame.
//
//   The FSM advances only when sample_tick && data_valid (real sampled bit).
//============================================================================

module rx_fsm (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        sample_tick,   // Sample point pulse (from bit_timing)
    input  wire        data_valid,    // Real bit present (from bit_stuffing)
    input  wire        data_in,       // De-stuffed serial bit

    input  wire [14:0] crc_rx,        // Computed CRC from external can_crc
    input  wire        rx_release,    // CPU releases RX buffer

    output reg         ack_bit,       // ACK slot bit (goes to can_tx)
    output wire        crc_en,        // 1-clk pulse: feed data_in to can_crc
    output wire        crc_clear,     // 1-clk pulse: clear can_crc at SOF

    output reg  [10:0] rx_id,
    output reg  [3:0]  rx_dlc,
    output reg  [15:0] rx_data0,
    output reg  [15:0] rx_data1,
    output reg  [15:0] rx_data2,
    output reg  [15:0] rx_data3,
    output reg         rx_ready,      // 1-clk pulse: frame stored

    output reg         crc_err,
    output reg         form_err,
    output reg         rx_active
);

    // States
    localparam IDLE         = 4'd0;
    localparam ARB          = 4'd1;
    localparam CONTROL      = 4'd2;
    localparam DATA         = 4'd3;
    localparam CRC_RCV      = 4'd4;
    localparam CRC_DELIM    = 4'd5;
    localparam ACK_SLOT     = 4'd6;
    localparam ACK_DELIM    = 4'd7;
    localparam EOF          = 4'd8;
    localparam INTERMISSION = 4'd9;

    reg [3:0]  state, next_state;
    reg [5:0]  bit_cnt;
    reg [3:0]  byte_cnt;
    reg [10:0] id_shift;
    reg [3:0]  dlc_shift;
    reg [14:0] crc_rcvd;
    reg [63:0] data_shift;
    reg        buf_full;

    wire tick = sample_tick & data_valid;

    // CRC covers SOF through data field (same as TX)
    wire crc_covered = (state == ARB) || (state == CONTROL) || (state == DATA);
    assign crc_en    = tick & crc_covered;
    assign crc_clear = tick & (state == IDLE) & (data_in == 1'b0); // SOF detected

    //--------------------------------------------------------------------------
    // State register
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else if (tick)
            state <= next_state;
    end

    //--------------------------------------------------------------------------
    // Next-state logic
    //--------------------------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:     if (data_in == 1'b0)    next_state = ARB;  // SOF
            ARB:      if (bit_cnt == 6'd11)   next_state = CONTROL;
            CONTROL:  if (bit_cnt == 6'd5) begin
                          if (dlc_shift == 4'd0 && data_in == 1'b0)
                              next_state = CRC_RCV;  // DLC=0
                          else
                              next_state = DATA;
                      end
            DATA:     if ((byte_cnt + 4'd1 == rx_dlc) && (bit_cnt == 6'd7))
                          next_state = CRC_RCV;
            CRC_RCV:  if (bit_cnt == 6'd14)   next_state = CRC_DELIM;
            CRC_DELIM:                        next_state = ACK_SLOT;
            ACK_SLOT:                         next_state = ACK_DELIM;
            ACK_DELIM:                        next_state = EOF;
            EOF:      if (bit_cnt == 6'd6)    next_state = INTERMISSION;
            INTERMISSION: if (bit_cnt == 6'd2) next_state = IDLE;
            default:                          next_state = IDLE;
        endcase
    end

    //--------------------------------------------------------------------------
    // Datapath
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt    <= 6'd0;
            byte_cnt   <= 4'd0;
            id_shift   <= 11'd0;
            dlc_shift  <= 4'd0;
            crc_rcvd   <= 15'd0;
            data_shift <= 64'd0;
            buf_full   <= 1'b0;
            ack_bit    <= 1'b1;
            rx_id      <= 11'd0;
            rx_dlc     <= 4'd0;
            rx_data0   <= 16'd0;
            rx_data1   <= 16'd0;
            rx_data2   <= 16'd0;
            rx_data3   <= 16'd0;
            rx_ready   <= 1'b0;
            crc_err    <= 1'b0;
            form_err   <= 1'b0;
            rx_active  <= 1'b0;
        end else begin
            // Pulse outputs default low
            rx_ready  <= 1'b0;
            crc_err   <= 1'b0;
            form_err  <= 1'b0;
            ack_bit   <= 1'b1;

            if (rx_release)
                buf_full <= 1'b0;

            if (tick) begin
                //--------------------------------------------------------------
                // bit_cnt / byte_cnt management
                //--------------------------------------------------------------
                if (next_state != state) begin
                    bit_cnt <= 6'd0;
                end else if (state == DATA && bit_cnt == 6'd7) begin
                    bit_cnt  <= 6'd0;
                    byte_cnt <= byte_cnt + 4'd1;
                end else begin
                    bit_cnt <= bit_cnt + 6'd1;
                end

                //--------------------------------------------------------------
                // Per-state logic
                //--------------------------------------------------------------
                case (state)
                    IDLE: begin
                        rx_active <= 1'b0;
                        if (data_in == 1'b0) begin
                            // SOF detected
                            rx_active  <= 1'b1;
                            id_shift   <= 11'd0;
                            dlc_shift  <= 4'd0;
                            data_shift <= 64'd0;
                            crc_rcvd   <= 15'd0;
                            byte_cnt   <= 4'd0;
                        end
                    end

                    ARB: begin
                        id_shift <= {id_shift[9:0], data_in};
                        if (bit_cnt == 6'd10)
                            rx_id <= {id_shift[9:0], data_in};  // capture after 11 bits
                    end

                    CONTROL: begin
                        // bit 0 = IDE (must be 0 for standard frame)
                        if (bit_cnt == 6'd0 && data_in != 1'b0)
                            form_err <= 1'b1;
                        // bits 2..5 = DLC
                        if (bit_cnt >= 6'd2)
                            dlc_shift <= {dlc_shift[2:0], data_in};
                        if (bit_cnt == 6'd5)
                            rx_dlc <= {dlc_shift[2:0], data_in};
                    end

                    DATA: begin
                        data_shift <= {data_shift[62:0], data_in};
                    end

                    CRC_RCV: begin
                        crc_rcvd <= {crc_rcvd[13:0], data_in};
                    end

                    CRC_DELIM: begin
                        if (data_in != 1'b1)
                            form_err <= 1'b1;
                        // crc_rcvd was fully populated in CRC_RCV; compare it now
                        if (crc_rcvd != crc_rx)
                            crc_err <= 1'b1;
                    end

                    ACK_SLOT: begin
                        ack_bit <= 1'b0;  // drive dominant ACK
                    end

                    ACK_DELIM: begin
                        if (data_in != 1'b1)
                            form_err <= 1'b1;
                    end

                    EOF: begin
                        if (data_in != 1'b1)
                            form_err <= 1'b1;
                        if (bit_cnt == 6'd6) begin
                            // Store frame if no errors and buffer free
                            if (!crc_err && !form_err && !buf_full) begin
                                rx_ready <= 1'b1;
                                buf_full <= 1'b1;
                                rx_data0 <= data_shift[63:48];
                                rx_data1 <= data_shift[47:32];
                                rx_data2 <= data_shift[31:16];
                                rx_data3 <= data_shift[15:0];
                            end
                        end
                    end

                    INTERMISSION: begin
                        if (bit_cnt == 6'd2)
                            rx_active <= 1'b0;
                    end

                    default: ;
                endcase
            end
        end
    end

endmodule
