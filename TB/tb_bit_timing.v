`timescale 1ns / 1ps

module tb_bit_timing;

    parameter CLK_PERIOD = 10;
    parameter SIM_TIME   = 5000;

    reg         clk;
    reg         rst_n;
    reg  [15:0] btr_reg;
    reg         can_rx;
    reg         bus_idle;
    wire        tq_tick;
    wire        sample_tick;
    wire        bit_tick;

    can_bit_timing uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .btr_reg     (btr_reg),
        .can_rx      (can_rx),
        .bus_idle    (bus_idle),
        .tq_tick     (tq_tick),
        .sample_tick (sample_tick),
        .bit_tick    (bit_tick)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer tq_cnt, sample_cnt, bit_cnt;
    integer pass_cnt, fail_cnt;

    always @(posedge clk) begin
        if (tq_tick)     tq_cnt = tq_cnt + 1;
        if (sample_tick) sample_cnt = sample_cnt + 1;
        if (bit_tick)    bit_cnt = bit_cnt + 1;
    end

    initial begin
        pass_cnt   = 0;
        fail_cnt   = 0;
        tq_cnt     = 0;
        sample_cnt = 0;
        bit_cnt    = 0;

        rst_n    = 0;
        btr_reg  = 16'b0_00_001_0011_000100;
        can_rx   = 1;
        bus_idle = 1;

        // Reset phase
        #(CLK_PERIOD * 10);
        if (tq_tick == 0 && sample_tick == 0 && bit_tick == 0) begin
            $display("[PASS] Reset: outputs low");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] Reset: outputs low");
            fail_cnt = fail_cnt + 1;
        end

        @(posedge clk); rst_n = 1;

        // Test 1: Free-run 350 clks (expect ~10 bits at 35 clks each)
        tq_cnt = 0; sample_cnt = 0; bit_cnt = 0;
        #(CLK_PERIOD * 350);

        if (tq_cnt >= 68 && tq_cnt <= 72) begin
            $display("[PASS] tq_tick rate (%0d)", tq_cnt);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] tq_tick rate (%0d, expect ~70)", tq_cnt);
            fail_cnt = fail_cnt + 1;
        end

        if (bit_cnt >= 9 && bit_cnt <= 11) begin
            $display("[PASS] bit_tick rate (%0d)", bit_cnt);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] bit_tick rate (%0d, expect ~10)", bit_cnt);
            fail_cnt = fail_cnt + 1;
        end

        if (sample_cnt >= bit_cnt - 1 && sample_cnt <= bit_cnt + 1) begin
            $display("[PASS] One sample per bit (%0d samples, %0d bits)", sample_cnt, bit_cnt);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] One sample per bit (%0d samples, %0d bits)", sample_cnt, bit_cnt);
            fail_cnt = fail_cnt + 1;
        end

        // Test 2: Hard sync - falling edge while idle forces bit_tick
        #(CLK_PERIOD * 50);  // settle mid-bit
        bit_cnt = 0;
        can_rx = 0;          // falling edge
        #(CLK_PERIOD * 5);   // 2 clk sync + 1 clk response
        if (bit_cnt >= 1) begin
            $display("[PASS] Hard sync fires");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] Hard sync fires (bit_cnt=%0d)", bit_cnt);
            fail_cnt = fail_cnt + 1;
        end
        can_rx = 1;
        #(CLK_PERIOD * 70);  // let things settle

        // Test 3: No hard sync when bus not idle
        bus_idle = 0;
        #(CLK_PERIOD * 50);  // settle
        bit_cnt = 0;
        can_rx = 0;          // falling edge
        #(CLK_PERIOD * 5);
        if (bit_cnt == 0) begin
            $display("[PASS] No hard sync when bus active");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] No hard sync when bus active (bit_cnt=%0d)", bit_cnt);
            fail_cnt = fail_cnt + 1;
        end
        can_rx = 1;
        bus_idle = 1;

        // Test 4: New BTR config
        #(CLK_PERIOD * 70);
        btr_reg = 16'b0_01_011_0111_000001;
        #(CLK_PERIOD * 30);
        bit_cnt = 0;
        #(CLK_PERIOD * 130);
        if (bit_cnt >= 4 && bit_cnt <= 6) begin
            $display("[PASS] New BTR bit rate (%0d)", bit_cnt);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] New BTR bit rate (%0d, expect ~5)", bit_cnt);
            fail_cnt = fail_cnt + 1;
        end

        // Summary
        $display("");
        $display("========================================");
        $display(" BIT TIMING: %0d PASSED, %0d FAILED", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display(" *** ALL TESTS PASSED ***");
        else
            $display(" *** SOME TESTS FAILED ***");
        $display("========================================");
        $finish;
    end

endmodule
