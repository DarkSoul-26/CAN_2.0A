`timescale 1ns / 1ps
//============================================================================
// Testbench: tb_acceptance_filter (Simple Self-Checking)
//   Presents IDs with various ACR/AMR settings and checks accept/reject.
//   Runs straight through to $finish.
//============================================================================

module tb_acceptance_filter;

    parameter CLK_PERIOD = 10;

    reg         clk;
    reg         rst_n;
    reg  [15:0] acr_reg;
    reg  [15:0] amr_reg;
    reg  [10:0] rx_id;
    reg         rx_ready_in;
    wire        rx_accepted;
    wire        rx_filtered;

    can_acceptance_filter uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .acr_reg     (acr_reg),
        .amr_reg     (amr_reg),
        .rx_id       (rx_id),
        .rx_ready_in (rx_ready_in),
        .rx_accepted (rx_accepted),
        .rx_filtered (rx_filtered)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass_cnt, fail_cnt;

    //------------------------------------------------------------------------
    // Present an ID for one cycle and check the expected result.
    //   exp_acc = 1 -> expect rx_accepted, 0 -> expect rx_filtered
    //------------------------------------------------------------------------
    task do_check(input [10:0] id, input exp_acc, input [127:0] name);
    begin
        @(negedge clk);
        rx_id       = id;
        rx_ready_in = 1;
        @(negedge clk);          // pulse captured on this posedge
        rx_ready_in = 0;
        #1;                      // let registered outputs settle
        if (exp_acc) begin
            if (rx_accepted && !rx_filtered) begin
                $display("[PASS] %0s : ID=0x%03h ACCEPTED", name, id);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] %0s : ID=0x%03h acc=%b filt=%b (expected ACCEPT)",
                         name, id, rx_accepted, rx_filtered);
                fail_cnt = fail_cnt + 1;
            end
        end else begin
            if (rx_filtered && !rx_accepted) begin
                $display("[PASS] %0s : ID=0x%03h REJECTED", name, id);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] %0s : ID=0x%03h acc=%b filt=%b (expected REJECT)",
                         name, id, rx_accepted, rx_filtered);
                fail_cnt = fail_cnt + 1;
            end
        end
    end
    endtask

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;

        rst_n       = 0;
        acr_reg     = 16'd0;
        amr_reg     = 16'd0;
        rx_id       = 11'd0;
        rx_ready_in = 0;

        #(CLK_PERIOD * 3);
        @(negedge clk); rst_n = 1;

        //====================================================================
        // GROUP 1: Exact match (AMR = 0 -> all bits must match)
        //====================================================================
        acr_reg = 16'h123;   // accept only ID 0x123
        amr_reg = 16'h000;   // no don't-cares

        do_check(11'h123, 1, "exact match hit");
        do_check(11'h124, 0, "exact match miss");
        do_check(11'h000, 0, "exact match zero");
        do_check(11'h7FF, 0, "exact match all-ones");

        //====================================================================
        // GROUP 2: Full don't-care (AMR = all 1 -> accept everything)
        //====================================================================
        acr_reg = 16'h000;
        amr_reg = 16'h7FF;   // every bit don't-care

        do_check(11'h000, 1, "accept-all zero");
        do_check(11'h123, 1, "accept-all 0x123");
        do_check(11'h7FF, 1, "accept-all 0x7FF");

        //====================================================================
        // GROUP 3: Partial mask (lower 4 bits don't-care)
        //   ACR upper bits = 0x12_, AMR = 0x00F -> low nibble ignored
        //====================================================================
        acr_reg = 16'h120;
        amr_reg = 16'h00F;   // bits [3:0] don't-care

        do_check(11'h120, 1, "partial: 0x120 hit");
        do_check(11'h12F, 1, "partial: 0x12F hit (low nibble ignored)");
        do_check(11'h125, 1, "partial: 0x125 hit");
        do_check(11'h130, 0, "partial: 0x130 miss (upper differs)");
        do_check(11'h020, 0, "partial: 0x020 miss");

        // Summary
        $display("");
        $display("========================================");
        $display(" ACCEPTANCE FILTER: %0d PASSED, %0d FAILED", pass_cnt, fail_cnt);
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
