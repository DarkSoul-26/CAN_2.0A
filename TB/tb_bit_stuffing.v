`timescale 1ns / 1ps
//============================================================================
// Testbench: tb_bit_stuffing (Simple Demo - horizontal view)
//   Part A: TX stuffing    -> ORIGINAL input vs STUFFED bus stream
//   Part B: RX de-stuffing  -> STUFFED stream vs RECOVERED bits
//
//   The stuff bit is just the complementary (opposite) bit inserted after
//   5 identical bits, so it appears naturally in the stuffed stream.
//   When tx_stall is high, the input bit is NOT consumed (held for next
//   cycle) - the testbench respects that so the streams stay aligned.
//============================================================================

module tb_bit_stuffing;

    parameter CLK_PERIOD = 10;

    reg  clk;
    reg  rst_n;
    reg  tx_en, rx_en;
    reg  bit_tick, sample_tick;
    reg  clear;
    reg  data_in;
    wire data_out;
    wire data_valid;
    wire stuff_err;
    wire tx_stall;

    bit_stuffing uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .tx_en       (tx_en),
        .rx_en       (rx_en),
        .bit_tick    (bit_tick),
        .sample_tick (sample_tick),
        .clear       (clear),
        .data_in     (data_in),
        .data_out    (data_out),
        .data_valid  (data_valid),
        .stuff_err   (stuff_err),
        .tx_stall    (tx_stall)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Input pattern: five 0s force one stuff bit, then two 1s
    parameter N = 7;
    reg [0:N-1] pattern;

    // String buffers (one char per bit)
    reg [8*40:1] s_original;
    reg [8*40:1] s_stuffed;
    reg [8*40:1] s_recovered;

    integer i;

    initial begin
        pattern     = 7'b0000011;   // bit0..bit6

        rst_n       = 0;
        tx_en       = 0;
        rx_en       = 0;
        bit_tick    = 0;
        sample_tick = 0;
        clear       = 0;
        data_in     = 1;
        s_original  = "";
        s_stuffed   = "";
        s_recovered = "";

        #(CLK_PERIOD * 3);
        @(negedge clk); rst_n = 1;

        //====================================================================
        // PART A: TX STUFFING
        //   Present each input bit. On a stall cycle the module inserts the
        //   complementary stuff bit and does NOT consume the input, so we
        //   record the stuff bit on the bus and re-present the same input.
        //====================================================================
        tx_en = 1; rx_en = 0; clear = 1;
        @(negedge clk); clear = 0;
        bit_tick = 1;   // continuous bit ticks for the demo

        i = 0;
        while (i < N) begin
            @(negedge clk);
            data_in = pattern[i];
            @(posedge clk);
            #1;
            if (tx_stall) begin
                // Stuff bit inserted on the bus; input bit held (not consumed)
                s_stuffed = {s_stuffed, (data_out ? "1" : "0")};
            end else begin
                // Normal bit: input consumed and placed on the bus
                s_stuffed  = {s_stuffed,  (data_out     ? "1" : "0")};
                s_original = {s_original, (pattern[i]   ? "1" : "0")};
                i = i + 1;
            end
        end
        @(negedge clk); bit_tick = 0;

        //====================================================================
        // PART B: RX DE-STUFFING
        //   Feed the SAME stuffed bus stream (0 0 0 0 0 1 1 1) back in.
        //   The complementary stuff bit (6th bit) is removed; the rest are
        //   recovered as valid data.
        //====================================================================
        tx_en = 0; rx_en = 1; clear = 1;
        @(negedge clk); clear = 0;

        // Stuffed stream = 0 0 0 0 0 1 1 1  (8 bits)
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            // bits: 0,0,0,0,0,1,1,1
            data_in     = (i < 5) ? 1'b0 : 1'b1;
            sample_tick = 1;
            @(negedge clk);
            sample_tick = 0;
            #1;
            if (data_valid)
                s_recovered = {s_recovered, (data_out ? "1" : "0")};
            // if not valid -> it was the removed stuff bit (append nothing)
        end

        //====================================================================
        // Print all three streams horizontally
        //====================================================================
        $display("");
        $display("=================== BIT STUFFING DEMO ===================");
        $display(" TX original input : %0s", s_original);
        $display(" TX stuffed output : %0s   (extra bit = inserted stuff bit)", s_stuffed);
        $display(" RX recovered bits : %0s", s_recovered);
        $display("=========================================================");
        $display(" recovered should match original input");
        $display("");

        #(CLK_PERIOD * 2);
        $finish;
    end

endmodule
