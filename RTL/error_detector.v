`timescale 1ns / 1ps
//============================================================================
// Module: can_error_detector
// Description: CAN 2.0A Error Management (TEC/REC counters, bus-off)
//
//   Implements ISO 11898-1 error counter rules:
//     - TEC (Transmit Error Counter): +8 per TX error, -1 per TX success
//     - REC (Receive Error Counter):  +1 per RX error, -1 per RX success
//     - Error Active:   TEC < 128 && REC < 128 && !bus_off
//     - Error Passive:  TEC >= 128 || REC >= 128
//     - Bus-Off:        TEC >= 256 (node disconnects from bus)
//
//   Bus-off recovery:
//     After entering bus-off, the node must wait for 128 occurrences of
//     11 consecutive recessive bits (monitored externally). The CPU then
//     clears bus-off via reset_mode=1, which resets TEC/REC to 0.
//
//   Inputs (1-cycle pulses):
//     - bit_err, stuff_err, crc_err, form_err, ack_err, arb_lost
//     - tx_done (successful TX), rx_ready (successful RX)
//     - reset_mode (CPU-initiated recovery from bus-off)
//
//   Outputs:
//     - tec[7:0], rec[7:0] : error counters (for status reporting)
//     - err_code[4:0]      : encoded last error type
//     - bus_off            : node is bus-off (frozen, cannot transmit)
//     - err_passive        : node is error passive (>= 128)
//     - err_active         : node is error active
//============================================================================

module can_error_detector (
    input  wire       clk,
    input  wire       rst_n,

    // Error event pulses
    input  wire       bit_err,
    input  wire       stuff_err,
    input  wire       crc_err,
    input  wire       form_err,
    input  wire       ack_err,
    input  wire       arb_lost,

    // Success event pulses
    input  wire       tx_done,
    input  wire       rx_ready,

    // Control
    input  wire       reset_mode,   // CPU clears bus-off (from mode register)

    // Outputs
    output reg  [7:0] tec,
    output reg  [7:0] rec,
    output reg  [4:0] err_code,
    output reg        bus_off,
    output wire       err_passive,
    output wire       err_active
);

    // Error code encoding
    localparam ERR_NONE  = 5'd0;
    localparam ERR_BIT   = 5'd1;
    localparam ERR_STUFF = 5'd2;
    localparam ERR_CRC   = 5'd3;
    localparam ERR_FORM  = 5'd4;
    localparam ERR_ACK   = 5'd5;
    localparam ERR_ARB   = 5'd6;

    reg [8:0] tec_full; // 9-bit to detect TEC >= 256

    assign err_passive = (tec >= 8'd128) || (rec >= 8'd128);
    assign err_active  = ~err_passive & ~bus_off;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tec_full <= 9'd0;
            tec      <= 8'd0;
            rec      <= 8'd0;
            err_code <= ERR_NONE;
            bus_off  <= 1'b0;
        end else begin
            err_code <= ERR_NONE;

            //------------------------------------------------------------------
            // Bus-off recovery (CPU-initiated via reset_mode)
            //------------------------------------------------------------------
            if (reset_mode) begin
                bus_off  <= 1'b0;
                tec_full <= 9'd0;
                tec      <= 8'd0;
                rec      <= 8'd0;
                err_code <= ERR_NONE;
            end
            //------------------------------------------------------------------
            // Normal error/success handling (only when not bus-off)
            //------------------------------------------------------------------
            else if (!bus_off) begin
                //--------------------------------------------------------------
                // TX errors (increment TEC by 8)
                //--------------------------------------------------------------
                if (bit_err && !arb_lost) begin
                    tec_full <= tec_full + 9'd8;
                    err_code <= ERR_BIT;
                end else if (ack_err) begin
                    tec_full <= tec_full + 9'd8;
                    err_code <= ERR_ACK;
                end
                //--------------------------------------------------------------
                // TX success (decrement TEC by 1, min 0)
                //--------------------------------------------------------------
                else if (tx_done && tec_full > 9'd0) begin
                    tec_full <= tec_full - 9'd1;
                end

                //--------------------------------------------------------------
                // RX errors (increment REC by 1, max 255)
                //--------------------------------------------------------------
                if (stuff_err) begin
                    rec      <= (rec < 8'd255) ? rec + 8'd1 : rec;
                    err_code <= ERR_STUFF;
                end else if (crc_err) begin
                    rec      <= (rec < 8'd255) ? rec + 8'd1 : rec;
                    err_code <= ERR_CRC;
                end else if (form_err) begin
                    rec      <= (rec < 8'd255) ? rec + 8'd1 : rec;
                    err_code <= ERR_FORM;
                end
                //--------------------------------------------------------------
                // RX success (decrement REC by 1, min 0)
                //--------------------------------------------------------------
                else if (rx_ready && rec > 8'd0) begin
                    rec <= rec - 8'd1;
                end

                //--------------------------------------------------------------
                // Arbitration lost (not an error, just record it)
                //--------------------------------------------------------------
                if (arb_lost)
                    err_code <= ERR_ARB;

                //--------------------------------------------------------------
                // Bus-off detection (TEC >= 256)
                // Cap TEC display at 255 when bus-off
                //--------------------------------------------------------------
                if (tec_full >= 9'd256) begin
                    bus_off <= 1'b1;
                    tec     <= 8'd255;
                end else begin
                    tec <= tec_full[7:0];
                end
            end
        end
    end

endmodule
