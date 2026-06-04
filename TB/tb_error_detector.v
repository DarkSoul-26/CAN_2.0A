`timescale 1ns / 1ps
//============================================================================
// Testbench: tb_error_detector (Simple Self-Checking)
//   Tests error counter increments, state transitions, and bus-off.
//============================================================================

module tb_error_detector;

    parameter CLK_PERIOD = 10;

    reg        clk;
    reg        rst_n;
    reg        bit_err;
    reg        stuff_err;
    reg        crc_err;
    reg        form_err;
    reg        ack_err;
    reg        arb_lost;
    reg        tx_done;
    reg        rx_ready;
    reg        reset_mode;

    wire [7:0] tec;
    wire [7:0] rec;
    wire [4:0] err_code;
    wire       bus_off;
    wire       err_passive;
    wire       err_active;

    can_error_detector uut (
        .clk        (clk),
        .rst_n      (rst_n),
        .bit_err    (bit_err),
        .stuff_err  (stuff_err),
        .crc_err    (crc_err),
        .form_err   (form_err),
        .ack_err    (ack_err),
        .arb_lost   (arb_lost),
        .tx_done    (tx_done),
        .rx_ready   (rx_ready),
        .reset_mode (reset_mode),
        .tec        (tec),
        .rec        (rec),
        .err_code   (err_code),
        .bus_off    (bus_off),
        .err_passive(err_passive),
        .err_active (err_active)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass_cnt, fail_cnt;
    integer i;

    initial begin
        pass_cnt   = 0;
        fail_cnt   = 0;

        rst_n      = 0;
        bit_err    = 0;
        stuff_err  = 0;
        crc_err    = 0;
        form_err   = 0;
        ack_err    = 0;
        arb_lost   = 0;
        tx_done    = 0;
        rx_ready   = 0;
        reset_mode = 0;

        #(CLK_PERIOD * 3);
        @(negedge clk); rst_n = 1;
        #(CLK_PERIOD * 2);

        //====================================================================
        // TEST 1: Initial state = error active
        //====================================================================
        if (err_active && !err_passive && !bus_off) begin
            $display("[PASS] Initial: error active, TEC=%0d REC=%0d", tec, rec);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] Initial: wrong state");
            fail_cnt = fail_cnt + 1;
        end

        //====================================================================
        // TEST 2: TX error increments TEC by 8
        //====================================================================
        @(negedge clk); ack_err = 1; @(negedge clk); ack_err = 0;
        #(CLK_PERIOD);
        if (tec == 8) begin
            $display("[PASS] TX error: TEC=%0d", tec);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] TX error: TEC=%0d expected 8", tec);
            fail_cnt = fail_cnt + 1;
        end

        //====================================================================
        // TEST 3: RX error increments REC by 1
        //====================================================================
        @(negedge clk); stuff_err = 1; @(negedge clk); stuff_err = 0;
        #(CLK_PERIOD);
        if (rec == 1) begin
            $display("[PASS] RX error: REC=%0d", rec);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] RX error: REC=%0d expected 1", rec);
            fail_cnt = fail_cnt + 1;
        end

        //====================================================================
        // TEST 4: TX success decrements TEC by 1
        //====================================================================
        @(negedge clk); tx_done = 1; @(negedge clk); tx_done = 0;
        #(CLK_PERIOD);
        if (tec == 7) begin
            $display("[PASS] TX success: TEC=%0d", tec);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] TX success: TEC=%0d expected 7", tec);
            fail_cnt = fail_cnt + 1;
        end

        //====================================================================
        // TEST 5: RX success decrements REC by 1
        //====================================================================
        @(negedge clk); rx_ready = 1; @(negedge clk); rx_ready = 0;
        #(CLK_PERIOD);
        if (rec == 0) begin
            $display("[PASS] RX success: REC=%0d", rec);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] RX success: REC=%0d expected 0", rec);
            fail_cnt = fail_cnt + 1;
        end

        //====================================================================
        // TEST 6: Error passive threshold (TEC >= 128)
        //====================================================================
        // Generate 16 TX errors (16*8 = 128)
        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk); ack_err = 1; @(negedge clk); ack_err = 0;
            #(CLK_PERIOD);
        end
        if (err_passive && !err_active && tec >= 128) begin
            $display("[PASS] Error passive: TEC=%0d", tec);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] Error passive: TEC=%0d passive=%b", tec, err_passive);
            fail_cnt = fail_cnt + 1;
        end

        //====================================================================
        // TEST 7: Bus-off (TEC >= 256)
        //====================================================================
        // Generate 16 more TX errors (total 256)
        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk); ack_err = 1; @(negedge clk); ack_err = 0;
            #(CLK_PERIOD);
        end
        if (bus_off && tec == 255) begin
            $display("[PASS] Bus-off: TEC=%0d", tec);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] Bus-off: TEC=%0d bus_off=%b", tec, bus_off);
            fail_cnt = fail_cnt + 1;
        end

        //====================================================================
        // TEST 8: Bus-off recovery via reset_mode
        //====================================================================
        @(negedge clk); reset_mode = 1; @(negedge clk); reset_mode = 0;
        #(CLK_PERIOD);
        if (!bus_off && tec == 0 && rec == 0 && err_active) begin
            $display("[PASS] Bus-off recovery: TEC=%0d REC=%0d", tec, rec);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] Bus-off recovery: TEC=%0d REC=%0d bus_off=%b",
                     tec, rec, bus_off);
            fail_cnt = fail_cnt + 1;
        end

        // Summary
        $display("");
        $display("========================================");
        $display(" ERROR DETECTOR: %0d PASSED, %0d FAILED", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display(" *** ALL TESTS PASSED ***");
        else
            $display(" *** SOME TESTS FAILED ***");
        $display("========================================");
        $finish;
    end

    // Watchdog
    initial begin
        #(CLK_PERIOD * 200000);
        $display("[ERROR] Timeout");
        $finish;
    end

endmodule
