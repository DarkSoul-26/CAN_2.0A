`timescale 1ns / 1ps
//============================================================================
// Testbench: tb_arbitration (Simple Self-Checking)
//   Simulates arbitration scenarios and checks arb_lost detection.
//============================================================================

module tb_arbitration;

    parameter CLK_PERIOD = 10;

    reg  clk;
    reg  rst_n;
    reg  bit_tick;
    reg  tx_active;
    reg  can_tx;
    reg  can_rx;
    wire arb_lost;

    can_arbitration uut (
        .clk       (clk),
        .rst_n     (rst_n),
        .bit_tick  (bit_tick),
        .tx_active (tx_active),
        .can_tx    (can_tx),
        .can_rx    (can_rx),
        .arb_lost  (arb_lost)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass_cnt, fail_cnt;

    // Task: present one bit scenario and check arb_lost
    task do_check(input tx, input rx, input exp_lost, input [127:0] name);
    begin
        @(negedge clk);
        tx_active = 1;
        can_tx    = tx;
        can_rx    = rx;
        bit_tick  = 1;
        @(negedge clk);
        bit_tick  = 0;
        #1;
        if (arb_lost == exp_lost) begin
            $display("[PASS] %0s : tx=%b rx=%b lost=%b", name, tx, rx, arb_lost);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] %0s : tx=%b rx=%b lost=%b expected=%b",
                     name, tx, rx, arb_lost, exp_lost);
            fail_cnt = fail_cnt + 1;
        end
    end
    endtask

    initial begin
        pass_cnt  = 0;
        fail_cnt  = 0;

        rst_n     = 0;
        bit_tick  = 0;
        tx_active = 0;
        can_tx    = 1;
        can_rx    = 1;

        #(CLK_PERIOD * 3);
        @(negedge clk); rst_n = 1;
        #(CLK_PERIOD * 2);

        //====================================================================
        // TEST: Various arbitration scenarios
        //====================================================================
        do_check(1'b0, 1'b0, 1'b0, "tx=0 rx=0 (both dominant)");
        do_check(1'b1, 1'b1, 1'b0, "tx=1 rx=1 (both recessive)");
        do_check(1'b0, 1'b1, 1'b0, "tx=0 rx=1 (impossible: bus more recessive than tx)");
        do_check(1'b1, 1'b0, 1'b1, "tx=1 rx=0 (LOST: tx recessive, bus dominant)");

        // No loss when tx_active=0
        @(negedge clk);
        tx_active = 0;
        can_tx    = 1;
        can_rx    = 0;
        bit_tick  = 1;
        @(negedge clk);
        bit_tick  = 0;
        #1;
        if (arb_lost == 1'b0) begin
            $display("[PASS] tx_active=0: no arb_lost");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] tx_active=0: arb_lost fired unexpectedly");
            fail_cnt = fail_cnt + 1;
        end

        // Summary
        $display("");
        $display("========================================");
        $display(" ARBITRATION: %0d PASSED, %0d FAILED", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display(" *** ALL TESTS PASSED ***");
        else
            $display(" *** SOME TESTS FAILED ***");
        $display("========================================");
        $finish;
    end

    // Watchdog
    initial begin
        #(CLK_PERIOD * 20000);
        $display("[ERROR] Timeout");
        $finish;
    end

endmodule
