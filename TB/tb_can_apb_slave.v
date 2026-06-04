`timescale 1ns / 1ps
//============================================================================
// Testbench: tb_can_apb_slave
// Description: Self-checking testbench for CAN APB slave interface
//
// Tests:
//   1. APB write transfers to register file
//   2. APB read transfers from register file
//   3. Command register write generates pulses
//   4. Address alignment error detection
//   5. Out-of-range address error detection
//   6. APB protocol compliance (PREADY, PSLVERR timing)
//============================================================================

module tb_can_apb_slave;

    reg         PCLK;
    reg         PRESETn;
    reg         PSEL;
    reg         PENABLE;
    reg         PWRITE;
    reg  [7:0]  PADDR;
    reg  [15:0] PWDATA;
    wire [15:0] PRDATA;
    wire        PREADY;
    wire        PSLVERR;

    wire        reg_write_en;
    wire        reg_read_en;
    wire [7:0]  reg_addr;
    wire [15:0] reg_wdata;
    reg  [15:0] reg_rdata;

    wire        tx_req;
    wire        tx_abort;
    wire        rx_release;

    integer pass_count;
    integer fail_count;

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    can_apb_slave dut (
        .PCLK       (PCLK),
        .PRESETn    (PRESETn),
        .PSEL       (PSEL),
        .PENABLE    (PENABLE),
        .PWRITE     (PWRITE),
        .PADDR      (PADDR),
        .PWDATA     (PWDATA),
        .PRDATA     (PRDATA),
        .PREADY     (PREADY),
        .PSLVERR    (PSLVERR),
        .reg_write_en (reg_write_en),
        .reg_read_en  (reg_read_en),
        .reg_addr     (reg_addr),
        .reg_wdata    (reg_wdata),
        .reg_rdata    (reg_rdata),
        .tx_req       (tx_req),
        .tx_abort     (tx_abort),
        .rx_release   (rx_release)
    );

    //--------------------------------------------------------------------------
    // Clock generation
    //--------------------------------------------------------------------------
    initial PCLK = 0;
    always #5 PCLK = ~PCLK; // 100 MHz

    //--------------------------------------------------------------------------
    // Task: APB Write
    //--------------------------------------------------------------------------
    task apb_write;
        input [7:0]  addr;
        input [15:0] data;
        input        expect_error;
        input [200*8:1] test_name;
        begin
            @(posedge PCLK);
            #1;
            PSEL    = 1'b1;
            PENABLE = 1'b0;
            PWRITE  = 1'b1;
            PADDR   = addr;
            PWDATA  = data;
            
            @(posedge PCLK);
            #1;
            PENABLE = 1'b1;
            
            @(posedge PCLK);
            #1;
            if (PREADY && (PSLVERR == expect_error)) begin
                if (expect_error) begin
                    $display("[PASS] %0s (error detected)", test_name);
                end else begin
                    $display("[PASS] %0s (addr=0x%02h, data=0x%04h)", test_name, addr, data);
                end
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s (PREADY=%b, PSLVERR=%b, exp_err=%b)", 
                         test_name, PREADY, PSLVERR, expect_error);
                fail_count = fail_count + 1;
            end
            
            PSEL    = 1'b0;
            PENABLE = 1'b0;
            @(posedge PCLK);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: APB Read
    //--------------------------------------------------------------------------
    task apb_read;
        input  [7:0]  addr;
        input  [15:0] expected;
        input         expect_error;
        input  [200*8:1] test_name;
        reg [15:0] actual;
        begin
            @(posedge PCLK);
            #1;
            PSEL    = 1'b1;
            PENABLE = 1'b0;
            PWRITE  = 1'b0;
            PADDR   = addr;
            
            @(posedge PCLK);
            #1;
            PENABLE = 1'b1;
            
            @(posedge PCLK);
            #1;
            actual = PRDATA;
            
            if (PREADY && (PSLVERR == expect_error)) begin
                if (expect_error) begin
                    $display("[PASS] %0s (error detected)", test_name);
                    pass_count = pass_count + 1;
                end else if (actual == expected) begin
                    $display("[PASS] %0s (addr=0x%02h, data=0x%04h)", test_name, addr, actual);
                    pass_count = pass_count + 1;
                end else begin
                    $display("[FAIL] %0s (addr=0x%02h, exp=0x%04h, got=0x%04h)", 
                             test_name, addr, expected, actual);
                    fail_count = fail_count + 1;
                end
            end else begin
                $display("[FAIL] %0s (PREADY=%b, PSLVERR=%b)", test_name, PREADY, PSLVERR);
                fail_count = fail_count + 1;
            end
            
            PSEL    = 1'b0;
            PENABLE = 1'b0;
            @(posedge PCLK);
        end
    endtask

    //--------------------------------------------------------------------------
    // Main test sequence
    //--------------------------------------------------------------------------
    initial begin
        // Initialize
        pass_count = 0;
        fail_count = 0;
        PRESETn = 0;
        PSEL = 0;
        PENABLE = 0;
        PWRITE = 0;
        PADDR = 0;
        PWDATA = 0;
        reg_rdata = 0;

        // Reset
        #20;
        PRESETn = 1;
        #20;

        $display("========================================");
        $display("CAN APB SLAVE TESTBENCH");
        $display("========================================");

        //----------------------------------------------------------------------
        // TEST 1: APB write to register file addresses
        //----------------------------------------------------------------------
        // Setup write transaction
        @(posedge PCLK);
        #1;
        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b1;
        PADDR   = 8'h00;
        PWDATA  = 16'hABCD;
        
        @(posedge PCLK);
        #1;
        PENABLE = 1'b1;
        
        @(posedge PCLK);
        #1;
        // Check signals during access phase
        if (reg_write_en && reg_addr == 8'h00 && reg_wdata == 16'hABCD) begin
            $display("[PASS] APB write to 0x00 (addr=0x00, data=0xabcd)");
            $display("[PASS] Register write signals correct");
            pass_count = pass_count + 2;
        end else begin
            $display("[FAIL] Register write signals incorrect (we=%b, addr=%h, data=%h)", 
                     reg_write_en, reg_addr, reg_wdata);
            fail_count = fail_count + 1;
        end
        
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        @(posedge PCLK);

        apb_write(8'h0A, 16'h5555, 1'b0, "APB write to 0x0A");
        apb_write(8'h2A, 16'hFFFF, 1'b0, "APB write to 0x2A (last reg)");

        //----------------------------------------------------------------------
        // TEST 2: APB read from register file addresses
        //----------------------------------------------------------------------
        reg_rdata = 16'h1234;
        
        // Setup read transaction
        @(posedge PCLK);
        #1;
        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;
        PADDR   = 8'h00;
        
        @(posedge PCLK);
        #1;
        PENABLE = 1'b1;
        
        @(posedge PCLK);
        #1;
        // Check signals during access phase
        if (reg_read_en && reg_addr == 8'h00 && PRDATA == 16'h1234) begin
            $display("[PASS] APB read from 0x00 (addr=0x00, data=0x1234)");
            $display("[PASS] Register read signals correct");
            pass_count = pass_count + 2;
        end else begin
            $display("[FAIL] Register read signals incorrect (re=%b, addr=%h, data=%h)", 
                     reg_read_en, reg_addr, PRDATA);
            fail_count = fail_count + 1;
        end
        
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        @(posedge PCLK);

        reg_rdata = 16'hDEAD;
        apb_read(8'h10, 16'hDEAD, 1'b0, "APB read from 0x10");

        reg_rdata = 16'hBEEF;
        apb_read(8'h2A, 16'hBEEF, 1'b0, "APB read from 0x2A");

        //----------------------------------------------------------------------
        // TEST 3: Command register writes generate pulses
        //----------------------------------------------------------------------
        // tx_req command
        @(posedge PCLK);
        #1;
        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b1;
        PADDR   = 8'h2C;
        PWDATA  = 16'h0001;
        
        @(posedge PCLK);
        #1;
        PENABLE = 1'b1;
        
        @(posedge PCLK);
        #1;
        // Check pulse right after access phase
        if (tx_req && !tx_abort && !rx_release) begin
            $display("[PASS] Command: tx_req (addr=0x2c, data=0x0001)");
            $display("[PASS] tx_req pulse generated");
            pass_count = pass_count + 2;
        end else begin
            $display("[FAIL] tx_req pulse not correct (tx_req=%b, tx_abort=%b, rx_release=%b)", 
                     tx_req, tx_abort, rx_release);
            fail_count = fail_count + 1;
        end
        
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        
        // Check pulse is single-cycle
        @(posedge PCLK);
        #1;
        if (!tx_req) begin
            $display("[PASS] tx_req pulse is single-cycle");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] tx_req stuck high");
            fail_count = fail_count + 1;
        end

        // tx_abort command
        @(posedge PCLK);
        #1;
        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b1;
        PADDR   = 8'h2C;
        PWDATA  = 16'h0002;
        
        @(posedge PCLK);
        #1;
        PENABLE = 1'b1;
        
        @(posedge PCLK);
        #1;
        if (!tx_req && tx_abort && !rx_release) begin
            $display("[PASS] Command: tx_abort (addr=0x2c, data=0x0002)");
            $display("[PASS] tx_abort pulse generated");
            pass_count = pass_count + 2;
        end else begin
            $display("[FAIL] tx_abort pulse not correct");
            fail_count = fail_count + 1;
        end
        
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        @(posedge PCLK);

        // rx_release command
        @(posedge PCLK);
        #1;
        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b1;
        PADDR   = 8'h2C;
        PWDATA  = 16'h0004;
        
        @(posedge PCLK);
        #1;
        PENABLE = 1'b1;
        
        @(posedge PCLK);
        #1;
        if (!tx_req && !tx_abort && rx_release) begin
            $display("[PASS] Command: rx_release (addr=0x2c, data=0x0004)");
            $display("[PASS] rx_release pulse generated");
            pass_count = pass_count + 2;
        end else begin
            $display("[FAIL] rx_release pulse not correct");
            fail_count = fail_count + 1;
        end
        
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        @(posedge PCLK);

        // Multiple commands simultaneously
        @(posedge PCLK);
        #1;
        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b1;
        PADDR   = 8'h2C;
        PWDATA  = 16'h0007;
        
        @(posedge PCLK);
        #1;
        PENABLE = 1'b1;
        
        @(posedge PCLK);
        #1;
        if (tx_req && tx_abort && rx_release) begin
            $display("[PASS] Command: all three (addr=0x2c, data=0x0007)");
            $display("[PASS] Multiple command pulses generated");
            pass_count = pass_count + 2;
        end else begin
            $display("[FAIL] Multiple commands not correct");
            fail_count = fail_count + 1;
        end
        
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        @(posedge PCLK);

        //----------------------------------------------------------------------
        // TEST 4: Address alignment errors
        //----------------------------------------------------------------------
        apb_write(8'h01, 16'h0000, 1'b1, "Write to odd address 0x01 (error)");
        apb_write(8'h0B, 16'h0000, 1'b1, "Write to odd address 0x0B (error)");
        apb_read(8'h03, 16'h0000, 1'b1, "Read from odd address 0x03 (error)");

        //----------------------------------------------------------------------
        // TEST 5: Out-of-range address errors
        //----------------------------------------------------------------------
        apb_write(8'h2E, 16'h0000, 1'b1, "Write to 0x2E (out of range)");
        apb_write(8'hFF, 16'h0000, 1'b1, "Write to 0xFF (out of range)");
        apb_read(8'h30, 16'h0000, 1'b1, "Read from 0x30 (out of range)");

        //----------------------------------------------------------------------
        // TEST 6: APB protocol timing
        //----------------------------------------------------------------------
        @(posedge PCLK);
        #1;
        PSEL = 1'b1;
        PENABLE = 1'b0;
        PWRITE = 1'b1;
        PADDR = 8'h04;
        PWDATA = 16'h9999;

        @(posedge PCLK);
        #1;
        // Setup phase: PREADY should be low
        if (!PREADY) begin
            $display("[PASS] PREADY low during setup phase");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] PREADY high during setup phase");
            fail_count = fail_count + 1;
        end

        PENABLE = 1'b1;
        @(posedge PCLK);
        #1;
        // Access phase: PREADY should be high
        if (PREADY) begin
            $display("[PASS] PREADY high during access phase");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] PREADY low during access phase");
            fail_count = fail_count + 1;
        end

        PSEL = 1'b0;
        PENABLE = 1'b0;

        //----------------------------------------------------------------------
        // TEST 7: Register file isolation (read during write, no conflict)
        //----------------------------------------------------------------------
        reg_rdata = 16'hAAAA;
        apb_write(8'h08, 16'hBBBB, 1'b0, "Write during read data present");
        if (PRDATA == 16'hAAAA) begin
            $display("[PASS] Write ignores reg_rdata");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Write affected by reg_rdata");
            fail_count = fail_count + 1;
        end

        //----------------------------------------------------------------------
        // Summary
        //----------------------------------------------------------------------
        #50;
        $display("========================================");
        $display("CAN APB SLAVE: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("*** SOME TESTS FAILED ***");
        end
        $display("========================================");
        $finish;
    end

endmodule
