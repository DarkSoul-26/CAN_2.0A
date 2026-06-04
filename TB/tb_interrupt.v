`timescale 1ns / 1ps
//============================================================================
// Testbench: tb_interrupt (Simple Self-Checking)
//   Tests interrupt flag setting, clearing, masking, and IRQ generation.
//============================================================================

module tb_interrupt;

    parameter CLK_PERIOD = 10;

    reg         clk;
    reg         rst_n;
    reg  [15:0] int_en_reg;
    reg         tx_done;
    reg         rx_ready;
    reg         crc_err;
    reg         form_err;
    reg         stuff_err;
    reg         arb_lost;
    reg         bus_off;
    reg         ir_clr;

    wire [15:0] ir_reg;
    wire        irq;

    can_interrupt uut (
        .clk        (clk),
        .rst_n      (rst_n),
        .int_en_reg (int_en_reg),
        .tx_done    (tx_done),
        .rx_ready   (rx_ready),
        .crc_err    (crc_err),
        .form_err   (form_err),
        .stuff_err  (stuff_err),
        .arb_lost   (arb_lost),
        .bus_off    (bus_off),
        .ir_clr     (ir_clr),
        .ir_reg     (ir_reg),
        .irq        (irq)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass_cnt, fail_cnt;

    initial begin
        pass_cnt   = 0;
        fail_cnt   = 0;

        rst_n      = 0;
        int_en_reg = 16'h001F; // Enable all 5 interrupt sources
        tx_done    = 0;
        rx_ready   = 0;
        crc_err    = 0;
        form_err   = 0;
        stuff_err  = 0;
        arb_lost   = 0;
        bus_off    = 0;
        ir_clr     = 0;

        #(CLK_PERIOD * 3);
        @(negedge clk); rst_n = 1;
        #(CLK_PERIOD * 2);

        //====================================================================
        // TEST 1: tx_done sets IR[0] and generates IRQ
        //====================================================================
        @(negedge clk); tx_done = 1; @(negedge clk); tx_done = 0;
        #(CLK_PERIOD);
        if (ir_reg[0] == 1 && irq == 1) begin
            $display("[PASS] tx_done: IR[0]=%b irq=%b", ir_reg[0], irq);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] tx_done: IR[0]=%b irq=%b", ir_reg[0], irq);
            fail_cnt = fail_cnt + 1;
        end

        //====================================================================
        // TEST 2: ir_clr clears the IR register
        //====================================================================
        @(negedge clk); ir_clr = 1; @(negedge clk); ir_clr = 0;
        #(CLK_PERIOD);
        if (ir_reg == 0 && irq == 0) begin
            $display("[PASS] ir_clr: IR=0x%04h irq=%b", ir_reg, irq);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] ir_clr: IR=0x%04h irq=%b", ir_reg, irq);
            fail_cnt = fail_cnt + 1;
        end

        //====================================================================
        // TEST 3: rx_ready sets IR[1]
        //====================================================================
        @(negedge clk); rx_ready = 1; @(negedge clk); rx_ready = 0;
        #(CLK_PERIOD);
        if (ir_reg[1] == 1) begin
            $display("[PASS] rx_ready: IR[1]=%b", ir_reg[1]);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] rx_ready: IR[1]=%b", ir_reg[1]);
            fail_cnt = fail_cnt + 1;
        end

        // Clear for next test
        @(negedge clk); ir_clr = 1; @(negedge clk); ir_clr = 0;
        #(CLK_PERIOD);

        //====================================================================
        // TEST 4: any_err (crc_err) sets IR[2]
        //====================================================================
        @(negedge clk); crc_err = 1; @(negedge clk); crc_err = 0;
        #(CLK_PERIOD);
        if (ir_reg[2] == 1) begin
            $display("[PASS] crc_err: IR[2]=%b", ir_reg[2]);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] crc_err: IR[2]=%b", ir_reg[2]);
            fail_cnt = fail_cnt + 1;
        end

        @(negedge clk); ir_clr = 1; @(negedge clk); ir_clr = 0;
        #(CLK_PERIOD);

        //====================================================================
        // TEST 5: arb_lost sets IR[3]
        //====================================================================
        @(negedge clk); arb_lost = 1; @(negedge clk); arb_lost = 0;
        #(CLK_PERIOD);
        if (ir_reg[3] == 1) begin
            $display("[PASS] arb_lost: IR[3]=%b", ir_reg[3]);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] arb_lost: IR[3]=%b", ir_reg[3]);
            fail_cnt = fail_cnt + 1;
        end

        @(negedge clk); ir_clr = 1; @(negedge clk); ir_clr = 0;
        #(CLK_PERIOD);

        //====================================================================
        // TEST 6: bus_off (level) sets IR[4]
        //====================================================================
        @(negedge clk); bus_off = 1;
        #(CLK_PERIOD);
        if (ir_reg[4] == 1) begin
            $display("[PASS] bus_off: IR[4]=%b", ir_reg[4]);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] bus_off: IR[4]=%b", ir_reg[4]);
            fail_cnt = fail_cnt + 1;
        end
        bus_off = 0;

        @(negedge clk); ir_clr = 1; @(negedge clk); ir_clr = 0;
        #(CLK_PERIOD);

        //====================================================================
        // TEST 7: Interrupt masking (disable tx_done interrupt)
        //====================================================================
        int_en_reg = 16'h001E; // Disable bit[0], enable others
        @(negedge clk); tx_done = 1; @(negedge clk); tx_done = 0;
        #(CLK_PERIOD);
        if (ir_reg[0] == 1 && irq == 0) begin
            $display("[PASS] Masking: IR[0]=%b irq=%b (masked)", ir_reg[0], irq);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] Masking: IR[0]=%b irq=%b", ir_reg[0], irq);
            fail_cnt = fail_cnt + 1;
        end

        @(negedge clk); ir_clr = 1; @(negedge clk); ir_clr = 0;
        #(CLK_PERIOD);

        //====================================================================
        // TEST 8: Simultaneous ir_clr and new event (event should be kept)
        //====================================================================
        // Set a flag first
        @(negedge clk); rx_ready = 1; @(negedge clk); rx_ready = 0;
        #(CLK_PERIOD);
        // Now clear and set tx_done simultaneously
        @(negedge clk);
        ir_clr  = 1;
        tx_done = 1;
        @(negedge clk);
        ir_clr  = 0;
        tx_done = 0;
        #(CLK_PERIOD);
        // IR[1] should be cleared, but IR[0] should be set (new event captured)
        if (ir_reg[0] == 1 && ir_reg[1] == 0) begin
            $display("[PASS] Simultaneous clear+event: IR[0]=%b IR[1]=%b", ir_reg[0], ir_reg[1]);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] Simultaneous clear+event: IR[0]=%b IR[1]=%b", ir_reg[0], ir_reg[1]);
            fail_cnt = fail_cnt + 1;
        end

        // Summary
        $display("");
        $display("========================================");
        $display(" INTERRUPT: %0d PASSED, %0d FAILED", pass_cnt, fail_cnt);
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
