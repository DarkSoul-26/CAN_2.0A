`timescale 1ns / 1ps
//============================================================================
// Module: bit_stuffing
// Description: CAN 2.0A Bit Stuffing / De-stuffing unit
//
//   TX (stuffing):   After 5 consecutive identical bits, asserts tx_stall
//                    and outputs a complementary stuff bit on data_out.
//                    The TX FSM must hold (not advance) while tx_stall=1,
//                    and the transmitted bus bit must be taken from data_out.
//
//   RX (de-stuffing):After 5 consecutive identical sampled bits, the next
//                    bit is the expected stuff bit and is discarded
//                    (data_valid=0). If that 6th bit is NOT complementary
//                    (i.e. 6 identical bits), stuff_err is pulsed.
//
//   TX is driven by bit_tick; RX is driven by sample_tick.
//   tx_en and rx_en are mutually exclusive (enforced by if/else).
//
//   Counter convention: cnt = number of consecutive identical bits in the
//   current run (starts at 1 for the first bit of a run). A stuff event
//   occurs when cnt == 5 and a new bit arrives.
//============================================================================

module bit_stuffing (
    input  wire clk,
    input  wire rst_n,

    input  wire tx_en,        // Enable TX stuffing path
    input  wire rx_en,        // Enable RX de-stuffing path
    input  wire bit_tick,     // TX bit boundary (from bit timing)
    input  wire sample_tick,  // RX sample point (from bit timing)
    input  wire clear,        // Synchronous clear (e.g. at SOF / idle)
    input  wire data_in,      // TX: raw bit from FSM / RX: sampled bus bit

    output reg  data_out,     // TX: bit to transmit / RX: de-stuffed bit
    output reg  data_valid,   // RX: HIGH for one clk when data_out is a real bit
    output reg  stuff_err,    // RX: HIGH for one clk on stuff error (6 identical)
    output wire tx_stall      // TX: HIGH during the cycle a stuff bit is inserted
);

    reg [2:0] cnt;       // Consecutive identical bit counter (1..5)
    reg       last_bit;  // Last accepted bit value

    // Stall the TX FSM exactly on the bit_tick where a stuff bit is inserted
    assign tx_stall = tx_en && bit_tick && (cnt == 3'd5);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt        <= 3'd1;
            last_bit   <= 1'b1;   // Idle bus is recessive
            data_out   <= 1'b1;
            data_valid <= 1'b0;
            stuff_err  <= 1'b0;
        end else if (clear) begin
            cnt        <= 3'd1;
            last_bit   <= 1'b1;
            data_out   <= 1'b1;
            data_valid <= 1'b0;
            stuff_err  <= 1'b0;
        end else begin
            // Default: pulse outputs deasserted
            data_valid <= 1'b0;
            stuff_err  <= 1'b0;

            //------------------------------------------------------------------
            // TX path (stuffing) - mutually exclusive with RX
            //------------------------------------------------------------------
            if (tx_en) begin
                if (bit_tick) begin
                    if (cnt == 3'd5) begin
                        // Insert complementary stuff bit
                        data_out <= ~last_bit;
                        last_bit <= ~last_bit;
                        cnt      <= 3'd1;
                    end else begin
                        // Pass raw bit through, update run counter
                        data_out <= data_in;
                        if (data_in == last_bit)
                            cnt <= cnt + 3'd1;
                        else begin
                            last_bit <= data_in;
                            cnt      <= 3'd1;
                        end
                    end
                end
            end
            //------------------------------------------------------------------
            // RX path (de-stuffing)
            //------------------------------------------------------------------
            else if (rx_en) begin
                if (sample_tick) begin
                    if (cnt == 3'd5) begin
                        // This bit must be the complementary stuff bit
                        if (data_in == last_bit) begin
                            // 6 identical bits -> stuff error, drop the bit
                            stuff_err  <= 1'b1;
                            data_valid <= 1'b0;
                            data_out   <= data_in;
                            cnt        <= 3'd1;
                            last_bit   <= data_in;
                        end else begin
                            // Expected stuff bit -> discard (not real data)
                            data_valid <= 1'b0;
                            last_bit   <= data_in;
                            cnt        <= 3'd1;
                        end
                    end else begin
                        // Normal payload bit -> forward to FSM
                        data_out   <= data_in;
                        data_valid <= 1'b1;
                        if (data_in == last_bit)
                            cnt <= cnt + 3'd1;
                        else begin
                            last_bit <= data_in;
                            cnt      <= 3'd1;
                        end
                    end
                end
            end
        end
    end

endmodule
