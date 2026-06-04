`timescale 1ns / 1ps
//============================================================================
// Testbench: tb_can_reg_file
// Description: Self-checking testbench for CAN register file
//
// Tests:
//   1. Write to writable config registers and read back
//   2. Verify read-only registers cannot be written
//   3. Sticky status bits: set on pulse, clear on read
//   4. Level status bits: updated continuously
//   5. Error counter registers updated from hardware
//   6. RX data registers reflect RX frame data
//============================================================================

module tb_can_reg_file;

    reg         clk;
    reg         rst_n;
    reg         reg_write_en;
    reg         reg_read_en;
    reg  [7:0]  reg_addr;
    reg  [15:0] reg_wdata;
    wire [15:0] reg_rdata;

    // Status inputs
    reg         tx_busy;
    reg         tx_done;
    reg         rx_ready;
    reg         arb_lost;
    reg         bus_off;

    // Error counters
    reg  [7:0]  tec;
    reg  [7:0]  rec;
    reg  [4:0]  err_code;

    // Interrupt register
    reg  [15:0] ir_reg_in;

    // RX frame data
    reg  [10:0] rx_id;
    reg  [3:0]  rx_dlc;
    reg  [15:0] rx_data0;
    reg  [15:0] rx_data1;
    reg  [15:0] rx_data2;
    reg  [15:0] rx_data3;

    // Outputs
    wire        reset_mode;
    wire        loopback_mode;
    wire        listen_only_mode;
    wire [10:0] tx_id;
    wire [3:0]  tx_dlc;
    wire [15:0] tx_data0;
    wire [15:0] tx_data1;
    wire [15:0] tx_data2;
    wire [15:0] tx_data3;
    wire [15:0] btr_reg_out;
    wire [15:0] acr_reg_out;
    wire [15:0] amr_reg_out;
    wire [15:0] int_en_reg_out;

    // Test counters
    integer pass_count;
    integer fail_count;

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    can_reg_file dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .reg_write_en     (reg_write_en),
        .reg_read_en      (reg_read_en),
        .reg_addr         (reg_addr),
        .reg_wdata        (reg_wdata),
        .reg_rdata        (reg_rdata),
        .tx_busy          (tx_busy),
        .tx_done          (tx_done),
        .rx_ready         (rx_ready),
        .arb_lost         (arb_lost),
        .bus_off          (bus_off),
        .tec              (tec),
        .rec              (rec),
        .err_code         (err_code),
        .ir_reg_in        (ir_reg_in),
        .rx_id            (rx_id),
        .rx_dlc           (rx_dlc),
        .rx_data0         (rx_data0),
        .rx_data1         (rx_data1),
        .rx_data2         (rx_data2),
        .rx_data3         (rx_data3),
        .reset_mode       (reset_mode),
        .loopback_mode    (loopback_mode),
        .listen_only_mode (listen_only_mode),
        .tx_id            (tx_id),
        .tx_dlc           (tx_dlc),
        .tx_data0         (tx_data0),
        .tx_data1         (tx_data1),
        .tx_data2         (tx_data2),
        .tx_data3         (tx_data3),
        .btr_reg_out      (btr_reg_out),
        .acr_reg_out      (acr_reg_out),
        .amr_reg_out      (amr_reg_out),
        .int_en_reg_out   (int_en_reg_out)
    );

    //--------------------------------------------------------------------------
    // Clock generation
    //--------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz

    //--------------------------------------------------------------------------
    // Task: Write to register
    //--------------------------------------------------------------------------
    task write_reg;
        input [7:0]  addr;
        input [15:0] data;
        begin
            @(posedge clk);
            reg_write_en = 1'b1;
            reg_addr = addr;
            reg_wdata = data;
            @(posedge clk);
            reg_write_en = 1'b0;
            @(posedge clk);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: Read from register
    //--------------------------------------------------------------------------
    task read_reg;
        input  [7:0]  addr;
        output [15:0] data;
        begin
            @(posedge clk);
            reg_read_en = 1'b1;
            reg_addr = addr;
            @(posedge clk);
            data = reg_rdata;
            reg_read_en = 1'b0;
            @(posedge clk);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: Check register value
    //--------------------------------------------------------------------------
    task check_reg;
        input [7:0]  addr;
        input [15:0] expected;
        input [200*8:1] test_name;
        reg [15:0] actual;
        begin
            read_reg(addr, actual);
            if (actual == expected) begin
                $display("[PASS] %0s (addr=0x%02h, val=0x%04h)", test_name, addr, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s (addr=0x%02h, exp=0x%04h, got=0x%04h)", test_name, addr, expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Main test sequence
    //--------------------------------------------------------------------------
    initial begin
        // Initialize
        pass_count = 0;
        fail_count = 0;
        rst_n = 0;
        reg_write_en = 0;
        reg_read_en = 0;
        reg_addr = 0;
        reg_wdata = 0;
        tx_busy = 0;
        tx_done = 0;
        rx_ready = 0;
        arb_lost = 0;
        bus_off = 0;
        tec = 0;
        rec = 0;
        err_code = 0;
        ir_reg_in = 0;
        rx_id = 0;
        rx_dlc = 0;
        rx_data0 = 0;
        rx_data1 = 0;
        rx_data2 = 0;
        rx_data3 = 0;

        // Reset
        #20;
        rst_n = 1;
        #20;

        $display("========================================");
        $display("CAN REGISTER FILE TESTBENCH");
        $display("========================================");

        //----------------------------------------------------------------------
        // TEST 1: Reset defaults
        //----------------------------------------------------------------------
        check_reg(8'h00, 16'h0001, "Reset: MODE = 0x0001 (reset_mode=1)");
        check_reg(8'h02, 16'h0000, "Reset: INT_EN = 0");
        check_reg(8'h04, 16'h0000, "Reset: BTR = 0");
        check_reg(8'h16, 16'h0000, "Reset: STATUS = 0");

        //----------------------------------------------------------------------
        // TEST 2: Write to writable config registers
        //----------------------------------------------------------------------
        write_reg(8'h00, 16'h0007);  // MODE: all bits set
        check_reg(8'h00, 16'h0007, "Write MODE = 0x0007");
        if (reset_mode && loopback_mode && listen_only_mode) begin
            $display("[PASS] Mode outputs updated correctly");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Mode outputs not updated");
            fail_count = fail_count + 1;
        end

        write_reg(8'h02, 16'hABCD);  // INT_EN
        check_reg(8'h02, 16'hABCD, "Write INT_EN = 0xABCD");

        write_reg(8'h04, 16'h1234);  // BTR
        check_reg(8'h04, 16'h1234, "Write BTR = 0x1234");
        if (btr_reg_out == 16'h1234) begin
            $display("[PASS] BTR output updated correctly");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] BTR output not updated");
            fail_count = fail_count + 1;
        end

        write_reg(8'h06, 16'h5678);  // ACR
        check_reg(8'h06, 16'h5678, "Write ACR = 0x5678");

        write_reg(8'h08, 16'h9ABC);  // AMR
        check_reg(8'h08, 16'h9ABC, "Write AMR = 0x9ABC");

        //----------------------------------------------------------------------
        // TEST 3: Write TX frame registers
        //----------------------------------------------------------------------
        write_reg(8'h0A, 16'h0555);  // TX_ID = 0x555 (11-bit)
        check_reg(8'h0A, 16'h0555, "Write TX_ID = 0x555");
        if (tx_id == 11'h555) begin
            $display("[PASS] TX_ID output = 0x555");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] TX_ID output mismatch");
            fail_count = fail_count + 1;
        end

        write_reg(8'h0C, 16'h0008);  // TX_DLC = 8
        check_reg(8'h0C, 16'h0008, "Write TX_DLC = 8");

        write_reg(8'h0E, 16'hDEAD);  // TX_DATA0
        write_reg(8'h10, 16'hBEEF);  // TX_DATA1
        write_reg(8'h12, 16'hCAFE);  // TX_DATA2
        write_reg(8'h14, 16'hBABE);  // TX_DATA3
        check_reg(8'h0E, 16'hDEAD, "Write TX_DATA0 = 0xDEAD");
        check_reg(8'h10, 16'hBEEF, "Write TX_DATA1 = 0xBEEF");
        check_reg(8'h12, 16'hCAFE, "Write TX_DATA2 = 0xCAFE");
        check_reg(8'h14, 16'hBABE, "Write TX_DATA3 = 0xBABE");

        //----------------------------------------------------------------------
        // TEST 4: Read-only registers cannot be written
        //----------------------------------------------------------------------
        write_reg(8'h16, 16'hFFFF);  // Try to write STATUS
        check_reg(8'h16, 16'h0000, "Read-only: STATUS not writable");

        write_reg(8'h1A, 16'hFFFF);  // Try to write TEC
        check_reg(8'h1A, 16'h0000, "Read-only: TEC not writable");

        write_reg(8'h20, 16'hFFFF);  // Try to write RX_ID
        check_reg(8'h20, 16'h0000, "Read-only: RX_ID not writable");

        //----------------------------------------------------------------------
        // TEST 5: Level status bits (tx_busy, bus_off) updated continuously
        //----------------------------------------------------------------------
        tx_busy = 1;
        bus_off = 1;
        #20;
        check_reg(8'h16, 16'h0011, "Level bits: tx_busy=1, bus_off=1 (STATUS[4:0]=10001)");

        tx_busy = 0;
        bus_off = 0;
        #20;
        check_reg(8'h16, 16'h0000, "Level bits: tx_busy=0, bus_off=0");

        //----------------------------------------------------------------------
        // TEST 6: Sticky status bits (tx_done, rx_ready, arb_lost)
        //----------------------------------------------------------------------
        // Generate tx_done pulse
        tx_done = 1;
        #10;
        tx_done = 0;
        #20;
        check_reg(8'h16, 16'h0002, "Sticky: tx_done pulse sets STATUS[1]");
        // Note: previous read cleared tx_done

        // Generate rx_ready pulse
        rx_ready = 1;
        #10;
        rx_ready = 0;
        #20;
        check_reg(8'h16, 16'h0004, "Sticky: rx_ready pulse sets STATUS[2] (0x0004)");
        // Note: previous read cleared rx_ready

        // Generate arb_lost pulse
        arb_lost = 1;
        #10;
        arb_lost = 0;
        #20;
        check_reg(8'h16, 16'h0008, "Sticky: arb_lost pulse sets STATUS[3] (0x0008)");

        // Read STATUS again - sticky bits should clear
        check_reg(8'h16, 16'h0000, "Sticky: clear-on-read (STATUS = 0)");

        //----------------------------------------------------------------------
        // TEST 7: Multiple sticky pulses before read
        //----------------------------------------------------------------------
        tx_done = 1;
        #10;
        tx_done = 0;
        #10;
        rx_ready = 1;
        #10;
        rx_ready = 0;
        #10;
        arb_lost = 1;
        #10;
        arb_lost = 0;
        #20;
        check_reg(8'h16, 16'h000E, "Sticky: multiple pulses accumulate (0x000E)");
        check_reg(8'h16, 16'h0000, "Sticky: cleared on next read");

        //----------------------------------------------------------------------
        // TEST 8: Error counter registers
        //----------------------------------------------------------------------
        tec = 8'd42;
        rec = 8'd99;
        err_code = 5'd17;
        #20;
        check_reg(8'h1A, 16'h002A, "TEC = 42 (0x2A)");
        check_reg(8'h1C, 16'h0063, "REC = 99 (0x63)");
        check_reg(8'h1E, 16'h0011, "ERR_CODE = 17 (0x11)");

        // Test bus-off threshold
        tec = 8'd255;
        rec = 8'd128;
        #20;
        check_reg(8'h1A, 16'h00FF, "TEC = 255 (bus-off threshold)");
        check_reg(8'h1C, 16'h0080, "REC = 128");

        //----------------------------------------------------------------------
        // TEST 9: Interrupt register passthrough
        //----------------------------------------------------------------------
        ir_reg_in = 16'h5A5A;
        #20;
        check_reg(8'h18, 16'h5A5A, "IR passthrough = 0x5A5A");

        ir_reg_in = 16'hA5A5;
        #20;
        check_reg(8'h18, 16'hA5A5, "IR passthrough = 0xA5A5");

        //----------------------------------------------------------------------
        // TEST 10: RX frame data registers
        //----------------------------------------------------------------------
        rx_id = 11'h3FF;
        rx_dlc = 4'd8;
        rx_data0 = 16'h1122;
        rx_data1 = 16'h3344;
        rx_data2 = 16'h5566;
        rx_data3 = 16'h7788;
        #20;
        check_reg(8'h20, 16'h03FF, "RX_ID = 0x3FF");
        check_reg(8'h22, 16'h0008, "RX_DLC = 8");
        check_reg(8'h24, 16'h1122, "RX_DATA0 = 0x1122");
        check_reg(8'h26, 16'h3344, "RX_DATA1 = 0x3344");
        check_reg(8'h28, 16'h5566, "RX_DATA2 = 0x5566");
        check_reg(8'h2A, 16'h7788, "RX_DATA3 = 0x7788");

        //----------------------------------------------------------------------
        // TEST 11: Sticky bits with tx_busy level active
        //----------------------------------------------------------------------
        tx_busy = 1;
        tx_done = 1;
        #10;
        tx_done = 0;
        #20;
        check_reg(8'h16, 16'h0003, "Sticky + level: tx_busy=1, tx_done=1 (STATUS=0x0003)");
        // Note: previous read cleared tx_done sticky bit
        
        tx_busy = 0;
        #20;
        check_reg(8'h16, 16'h0000, "After read: tx_busy=0, tx_done cleared (STATUS=0x0000)");

        //----------------------------------------------------------------------
        // Summary
        //----------------------------------------------------------------------
        #50;
        $display("========================================");
        $display("CAN REGISTER FILE: %0d PASSED, %0d FAILED", pass_count, fail_count);
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
