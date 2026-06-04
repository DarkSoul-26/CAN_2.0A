`timescale 1ns / 1ps
//============================================================================
// Testbench: tb_crc (Self-Checking)
//   Feeds known bit sequences into can_crc and compares the result against
//   reference CRC-15 values computed independently (Python golden model).
//   Runs straight through to $finish.
//============================================================================

module tb_crc;

    parameter CLK_PERIOD = 10;

    reg         clk;
    reg         rst_n;
    reg         enable;
    reg         clear;
    reg         data_in;
    wire [14:0] crc_out;

    can_crc uut (
        .clk     (clk),
        .rst_n   (rst_n),
        .enable  (enable),
        .clear   (clear),
        .data_in (data_in),
        .crc_out (crc_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass_cnt, fail_cnt;

    // Shift register holding the test pattern (MSB first)
    reg [63:0] pattern;
    integer    plen;
    integer    i;

    //------------------------------------------------------------------------
    // Task: clear CRC, then shift in 'len' bits of 'pat' (MSB-aligned),
    //       then compare against expected value.
    //------------------------------------------------------------------------
    task run_crc(input [63:0] pat, input integer len, input [14:0] expected,
                 input [127:0] name);
    begin
        // Clear the CRC register
        @(negedge clk);
        clear  = 1;
        enable = 0;
        @(negedge clk);
        clear  = 0;

        // Shift in bits MSB-first
        for (i = 0; i < len; i = i + 1) begin
            @(negedge clk);
            data_in = pat[len-1-i];
            enable  = 1;
            @(negedge clk);
            enable  = 0;
        end

        // Allow last shift to register
        @(negedge clk);

        if (crc_out == expected) begin
            $display("[PASS] %0s : crc=0x%04h", name, crc_out);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] %0s : crc=0x%04h expected=0x%04h", name, crc_out, expected);
            fail_cnt = fail_cnt + 1;
        end
    end
    endtask

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;

        rst_n   = 0;
        enable  = 0;
        clear   = 0;
        data_in = 0;

        #(CLK_PERIOD * 3);
        @(negedge clk); rst_n = 1;

        //====================================================================
        // TEST 0: Reset value is zero
        //====================================================================
        if (crc_out == 15'h0000) begin
            $display("[PASS] Reset: crc=0x0000");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] Reset: crc=0x%04h expected 0x0000", crc_out);
            fail_cnt = fail_cnt + 1;
        end

        //====================================================================
        // Known-good vectors (golden model values)
        //====================================================================
        // single '1'              -> 0x4599
        run_crc(64'b1, 1, 15'h4599, "single 1 bit");

        // 1010                    -> 0x3aac
        run_crc(64'b1010, 4, 15'h3aac, "pattern 1010");

        // 10110010                -> 0x1a01
        run_crc(64'b10110010, 8, 15'h1a01, "pattern 10110010");

        // eleven zeros            -> 0x0000
        run_crc(64'b0, 11, 15'h0000, "eleven zeros");

        // fifteen ones            -> 0x6806
        run_crc(64'b111111111111111, 15, 15'h6806, "fifteen ones");

        // Realistic CAN frame (27 bits): SOF + ID 0x123 + RTR+IDE+r0 +
        // DLC=1 + data 0xAB -> 0x666f
        // Bit string: 0 00100100011 000 0001 10101011
        run_crc(64'b0_00100100011_000_0001_10101011, 27, 15'h666f, "CAN frame ID=0x123 D=0xAB");

        //====================================================================
        // TEST: clear works mid-stream (shift garbage, clear, then real seq)
        //====================================================================
        @(negedge clk); clear = 1; enable = 0;
        @(negedge clk); clear = 0;
        // garbage
        data_in = 1; enable = 1; @(negedge clk);
        data_in = 1; @(negedge clk);
        enable = 0;
        // now run a fresh known vector after re-clear
        run_crc(64'b1, 1, 15'h4599, "clear then single 1");

        // Summary
        $display("");
        $display("========================================");
        $display(" CRC: %0d PASSED, %0d FAILED", pass_cnt, fail_cnt);
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
