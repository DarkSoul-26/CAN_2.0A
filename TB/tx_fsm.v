`timescale 1ns / 1ps
//============================================================================
// Module: tx_fsm
// Description: CAN 2.0A Transmit FSM (standard 11-bit identifier, data frame)
//
//   Frame format produced on can_tx (pre-bit-stuffing, raw bits):
//     SOF(1) | ID[10:0] | RTR(1) | IDE(1) r0(1) DLC[3:0] |
//     DATA(8*DLC) | CRC[14:0] | CRC_DELIM(1) | ACK(1) | ACK_DELIM(1) |
//     EOF(7) | INTERMISSION(3)
//
//   Timing:
//     - All bit activity advances on 'tick' = bit_tick & ~tx_stall.
//     - During tx_stall (bit stuffing inserting a stuff bit) the FSM holds;
//       the bit_stuffing block drives the actual stuff bit onto the bus.
//
//   CRC interface (feeds external can_crc):
//     - crc_bit   : combinational current transmit bit (raw, pre-stuff).
//     - crc_en    : 1-clk pulse, asserted for each CRC-covered bit
//                   (SOF..DATA). The can_crc samples crc_bit on this pulse.
//     - crc_clear : 1-clk pulse at frame start to zero the CRC register.
//     The same crc_bit is registered into can_tx on the same clock edge,
//     so the bus bit and the CRC input are always identical (no off-by-one).
//
//   Arbitration:
//     - in_arb  : HIGH while in the arbitration field (for the arbitration
//                 monitor block).
//     - arb_lost: when asserted during ARB, the transmission is aborted
//                 (returns to IDLE, tx_busy cleared).
//============================================================================

module tx_fsm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bit_tick,       // Bit boundary pulse (from bit timing)
    input  wire        tx_stall,       // Bit stuffing inserting a stuff bit
    input  wire        tx_req,         // Request to transmit a frame
    input  wire [10:0] tx_id,          // 11-bit identifier
    input  wire [3:0]  tx_dlc,         // Data length code (0..8)
    input  wire [63:0] tx_data,        // Up to 8 data bytes, MSB = byte0[7]
    input  wire        can_rx,          // RX bus (for ACK slot sampling)
    input  wire        arb_lost,        // Arbitration lost (from arbitration)
    input  wire [14:0] crc_computed,   // CRC-15 from external can_crc
    output reg         can_tx,         // Transmitted bit (registered, pre-stuff)
    output wire        crc_bit,        // Combinational current bit for CRC feed
    output reg         tx_busy,        // HIGH while a frame is being sent
    output reg         tx_done,        // 1-clk pulse when frame fully sent
    output reg         ack_error,       // 1-clk pulse: no ACK received in slot
    output wire        crc_en,         // 1-clk pulse: feed crc_bit to can_crc
    output wire        crc_clear,      // 1-clk pulse: clear can_crc at SOF
    output wire        in_arb          // HIGH during arbitration field
);

    // States
    localparam IDLE         = 4'd0;
    localparam SOF          = 4'd1;
    localparam ARB          = 4'd2;
    localparam CONTROL      = 4'd3;
    localparam DATA         = 4'd4;
    localparam CRC          = 4'd5;
    localparam CRC_DELIM    = 4'd6;
    localparam ACK          = 4'd7;
    localparam ACK_DELIM    = 4'd8;
    localparam EOF          = 4'd9;
    localparam INTERMISSION = 4'd10;

    reg [3:0]  state, next_state;
    reg [10:0] id_reg;
    reg        rtr_reg;
    reg [63:0] data_shift;
    reg [5:0]  control_reg;   // {IDE, r0, DLC[3:0]}
    reg [14:0] crc_shift;
    reg [4:0]  bit_cnt;
    reg [3:0]  byte_cnt;

    wire tick = bit_tick & ~tx_stall;

    assign in_arb = (state == ARB);

    //--------------------------------------------------------------------------
    // Combinational current transmit bit (raw, pre-stuffing)
    //--------------------------------------------------------------------------
    reg tx_bit;
    always @(*) begin
        case (state)
            SOF:     tx_bit = 1'b0;                                   // dominant
            ARB:     tx_bit = (bit_cnt < 5'd11) ? id_reg[10] : rtr_reg;
            CONTROL: tx_bit = control_reg[5];
            DATA:    tx_bit = data_shift[63];
            CRC:     tx_bit = (bit_cnt == 5'd0) ? crc_computed[14] : crc_shift[14];
            default: tx_bit = 1'b1;   // IDLE, delimiters, ACK, EOF, INTERMISSION
        endcase
    end

    assign crc_bit = tx_bit;

    // CRC covers SOF, arbitration, control and data fields
    wire crc_covered = (state == SOF) || (state == ARB) ||
                       (state == CONTROL) || (state == DATA);

    assign crc_en    = tick & crc_covered;
    assign crc_clear = tick & (state == IDLE) & tx_req;

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
            IDLE:     if (tx_req)             next_state = SOF;
            SOF:                              next_state = ARB;
            ARB:      if (arb_lost)           next_state = IDLE;          // abort
                      else if (bit_cnt == 5'd11) next_state = CONTROL;
            CONTROL:  if (bit_cnt == 5'd5)    next_state = (tx_dlc == 4'd0) ? CRC : DATA;
            DATA:     if ((byte_cnt + 4'd1 == tx_dlc) && (bit_cnt == 5'd7))
                                              next_state = CRC;
            CRC:      if (bit_cnt == 5'd14)   next_state = CRC_DELIM;
            CRC_DELIM:                        next_state = ACK;
            ACK:                              next_state = ACK_DELIM;
            ACK_DELIM:                        next_state = EOF;
            EOF:      if (bit_cnt == 5'd6)    next_state = INTERMISSION;
            INTERMISSION: if (bit_cnt == 5'd2) next_state = IDLE;
            default:                          next_state = IDLE;
        endcase
    end

    //--------------------------------------------------------------------------
    // Datapath
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            can_tx      <= 1'b1;
            tx_busy     <= 1'b0;
            tx_done     <= 1'b0;
            ack_error   <= 1'b0;
            bit_cnt     <= 5'd0;
            byte_cnt    <= 4'd0;
            id_reg      <= 11'd0;
            rtr_reg     <= 1'b0;
            data_shift  <= 64'd0;
            control_reg <= 6'd0;
            crc_shift   <= 15'd0;
        end else begin
            tx_done   <= 1'b0;   // pulse
            ack_error <= 1'b0;   // pulse

            if (tick) begin
                // Register the current bit onto the bus
                can_tx <= tx_bit;

                //--------------------------------------------------------------
                // bit_cnt / byte_cnt management
                //--------------------------------------------------------------
                if (next_state != state) begin
                    bit_cnt <= 5'd0;             // reset on every state change
                end else if (state == DATA && bit_cnt == 5'd7) begin
                    bit_cnt  <= 5'd0;            // byte boundary inside DATA
                    byte_cnt <= byte_cnt + 4'd1;
                end else begin
                    bit_cnt <= bit_cnt + 5'd1;
                end

                //--------------------------------------------------------------
                // Per-state shift registers and control
                //--------------------------------------------------------------
                case (state)
                    IDLE: begin
                        tx_busy <= 1'b0;
                        if (tx_req) begin
                            tx_busy     <= 1'b1;
                            id_reg      <= tx_id;
                            rtr_reg     <= 1'b0;                 // data frame
                            data_shift  <= tx_data;
                            control_reg <= {1'b0, 1'b0, tx_dlc}; // IDE=0,r0=0,DLC
                            byte_cnt    <= 4'd0;
                        end
                    end

                    ARB: begin
                        if (bit_cnt < 5'd11)
                            id_reg <= {id_reg[9:0], 1'b0};
                        if (arb_lost)
                            tx_busy <= 1'b0;                     // aborted
                    end

                    CONTROL: begin
                        control_reg <= {control_reg[4:0], 1'b0};
                    end

                    DATA: begin
                        data_shift <= {data_shift[62:0], 1'b0};
                    end

                    CRC: begin
                        if (bit_cnt == 5'd0)
                            crc_shift <= {crc_computed[13:0], 1'b0};
                        else
                            crc_shift <= {crc_shift[13:0], 1'b0};
                    end

                    EOF: begin
                        if (bit_cnt == 5'd6) begin
                            tx_done <= 1'b1;     // frame transmitted
                        end
                    end

                    ACK: begin
                        // Transmitter sends recessive; a receiver should drive
                        // it dominant. If still recessive -> no acknowledge.
                        if (can_rx == 1'b1)
                            ack_error <= 1'b1;
                    end

                    INTERMISSION: begin
                        if (bit_cnt == 5'd2)
                            tx_busy <= 1'b0;
                    end

                    default: ; // CRC_DELIM, ACK_DELIM: recessive, nothing to shift
                endcase
            end
        end
    end

endmodule
