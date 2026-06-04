`timescale 1ns / 1ps
//============================================================================
// Testbench: tb_can_top_simple
// Description: Simplified diagnostic testbench for CAN controller top
//============================================================================

module tb_can_top_simple;

    reg         clk;
    reg         rst_n;
    reg         PSEL;
    reg         PENABLE;
    reg         PWRITE;
    reg  [7:0]  PADDR;
    reg  [15:0] PWDATA;
    wire [15:0] PRDATA;
    wire        PREADY;
    wire        PSLVERR;
    wire        can_tx;
    reg         can_rx;
    wire        can_interrupt;

    // DUT
    can_controller_top dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .PSEL          (PSEL),
        .PENABLE       (PENABLE),
        .PWRITE        (PWRITE),
        .PADDR         (PADDR),
        .PWDATA        (PWDATA),
        .PRDATA        (PRDATA),
        .PREADY        (PREADY),
        .PSLVERR       (PSLVERR),
        .can_tx        (can_tx),
        .can_rx        (can_rx),
        .can_interrupt (can_interrupt)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // APB Write task
    task apb_write;
        input [7:0]  addr;
        input [15:0] data;
        begin
            @(posedge clk);
            #1;
            PSEL = 1'b1; PENABLE = 1'b0; PWRITE = 1'b1;
            PADDR = addr; PWDATA = data;
            @(posedge clk);
            #1;
            PENABLE = 1'b1;
            @(posedge clk);
            #1;
            PSEL = 1'b0; PENABLE = 1'b0;
            @(posedge clk);
        end
    endtask

    // APB Read task
    task apb_read;
        input  [7:0]  addr;
        output [15:0] data;
        begin
            @(posedge clk);
            #1;
            PSEL = 1'b1; PENABLE = 1'b0; PWRITE = 1'b0;
            PADDR = addr;
            @(posedge clk);
            #1;
            PENABLE = 1'b1;
            @(posedge clk);
            #1;
            data = PRDATA;
            PSEL = 1'b0; PENABLE = 1'b0;
            @(posedge clk);
        end
    endtask

    // Monitor internal signals
    wire bit_tick = dut.bit_tick;
    wire sample_tick = dut.sample_tick;
    wire tx_busy = dut.tx_busy;
    wire rx_active = dut.rx_active;
    wire bus_idle = dut.bus_idle;
    wire can_rx_internal = dut.can_rx_internal;
    wire rx_data_out = dut.rx_data_out;
    wire rx_data_valid = dut.rx_data_valid;
    wire rx_stuffing_en = dut.rx_stuffing_en;
    wire [3:0] rx_state = dut.u_rx_fsm.state;
    
    integer bit_tick_count;
    integer sample_tick_count;
    integer rx_bits_count;
    integer data_valid_count;

    always @(posedge clk) begin
        if (bit_tick) bit_tick_count = bit_tick_count + 1;
        if (sample_tick) sample_tick_count = sample_tick_count + 1;
        if (sample_tick && rx_data_valid) rx_bits_count = rx_bits_count + 1;
        if (rx_data_valid) data_valid_count = data_valid_count + 1;
    end

    // Test
    reg [15:0] read_data;
    
    initial begin
        // Init
        rst_n = 0;
        PSEL = 0; PENABLE = 0; PWRITE = 0;
        PADDR = 0; PWDATA = 0;
        can_rx = 1;
        bit_tick_count = 0;
        sample_tick_count = 0;
        rx_bits_count = 0;
        data_valid_count = 0;

        #100;
        rst_n = 1;
        #100;

        $display("\n=== CAN CONTROLLER DIAGNOSTIC TEST ===\n");

        // Configure with simpler bit timing for faster sim
        $display("[CONFIG] Starting configuration...");
        
        // Enter reset mode
        apb_write(8'h00, 16'h0001);
        apb_read(8'h00, read_data);
        $display("  MODE after reset_mode set: 0x%04h", read_data);
        
        // Set bit timing: BRP=1 (2 clk/tq), TSEG1=3 (4tq), TSEG2=1 (2tq), SJW=0 (1tq)
        // Bit time = 1+4+2 = 7 tq, bit rate = 100MHz/(2*7) = 7.14 MHz (very fast for sim)
        apb_write(8'h04, 16'h0581);
        apb_read(8'h04, read_data);
        $display("  BTR set to: 0x%04h", read_data);
        
        // Enable loopback mode (stay in reset mode for now)
        apb_write(8'h00, 16'h0003);  // reset_mode=1, loopback=1
        
        // Load simple TX frame
        $display("[TX LOAD] Loading test frame...");
        apb_write(8'h0A, 16'h0123);  // ID
        apb_write(8'h0C, 16'h0002);  // DLC=2 (short frame)
        apb_write(8'h0E, 16'hAA55);  // DATA0
        
        // Exit reset mode (go online in loopback)
        $display("[CONFIG] Going online (loopback mode)...");
        apb_write(8'h00, 16'h0002);  // loopback=1, reset_mode=0
        apb_read(8'h00, read_data);
        $display("  MODE after online: 0x%04h", read_data);
        
        // Wait for bit timing to start
        $display("[TIMING] Waiting for bit_tick...");
        #1000;
        $display("  bit_tick_count = %0d", bit_tick_count);
        $display("  sample_tick_count = %0d", sample_tick_count);
        
        if (bit_tick_count == 0) begin
            $display("  [ERROR] No bit_tick generated! Bit timing not working.");
            $finish;
        end else begin
            $display("  [OK] Bit timing is running");
        end
        
        // Check bus idle
        $display("[STATUS] Checking bus state...");
        $display("  tx_busy = %b", tx_busy);
        $display("  rx_active = %b", rx_active);
        $display("  bus_idle = %b", bus_idle);
        $display("  can_rx_internal = %b", can_rx_internal);
        $display("  rx_stuffing_en = %b", rx_stuffing_en);
        
        // Start transmission
        $display("[TX] Starting transmission...");
        apb_write(8'h2C, 16'h0001);  // tx_req
        
        #100;
        $display("  After tx_req:");
        $display("    tx_busy = %b", tx_busy);
        $display("    can_tx = %b", can_tx);
        
        if (!tx_busy) begin
            $display("  [ERROR] tx_busy not asserted! TX not starting.");
            apb_read(8'h00, read_data);
            $display("  MODE register: 0x%04h", read_data);
            apb_read(8'h16, read_data);
            $display("  STATUS register: 0x%04h", read_data);
            $finish;
        end else begin
            $display("  [OK] Transmission started");
        end
        
        // Wait for transmission (monitor)
        $display("[TX] Waiting for transmission to complete...");
        
        fork
            begin
                // Timeout
                #100000;
                $display("[TIMEOUT] Transmission did not complete in time");
                $display("  Final bit_tick_count = %0d", bit_tick_count);
                $display("  tx_busy = %b", tx_busy);
                apb_read(8'h16, read_data);
                $display("  STATUS = 0x%04h", read_data);
                $finish;
            end
            
            begin
                // Wait for tx_done
                while (tx_busy) #100;
                $display("[TX DONE] Transmission completed!");
                $display("  Total bit_ticks = %0d", bit_tick_count);
                $display("  Total sample_ticks = %0d", sample_tick_count);
                $display("  RX bits received = %0d", rx_bits_count);
                $display("  data_valid pulses = %0d", data_valid_count);
                $display("  rx_active ever = %b", rx_active);
                $display("  rx_stuffing_en = %b", rx_stuffing_en);
                $display("  rx_state = %0d", rx_state);
                
                // Read status
                apb_read(8'h16, read_data);
                $display("  STATUS = 0x%04h", read_data);
                
                if (read_data & 16'h0002) begin
                    $display("  [OK] tx_done flag set");
                end
                
                // Check if frame received (loopback)
                if (read_data & 16'h0004) begin
                    $display("  [OK] rx_ready flag set (loopback successful)");
                    
                    apb_read(8'h20, read_data);
                    $display("  RX_ID = 0x%04h", read_data);
                    apb_read(8'h22, read_data);
                    $display("  RX_DLC = 0x%04h", read_data);
                    apb_read(8'h24, read_data);
                    $display("  RX_DATA0 = 0x%04h", read_data);
                end else begin
                    $display("  [WARN] rx_ready not set (RX may have failed)");
                end
                
                $display("\n=== TEST COMPLETED ===");
                $finish;
            end
        join
    end

    // Display CAN bus transitions
    reg can_tx_d;
    reg rx_active_d;
    
    always @(posedge clk) begin
        can_tx_d <= can_tx;
        rx_active_d <= rx_active;
        
        if (can_tx != can_tx_d && tx_busy) begin
            $display("    [%0t] CAN TX: %b", $time, can_tx);
        end
        
        if (rx_active && !rx_active_d) begin
            $display("    [%0t] RX FSM ACTIVATED (SOF detected)", $time);
        end
        
        if (!rx_active && rx_active_d) begin
            $display("    [%0t] RX FSM DEACTIVATED", $time);
        end
        
        if (sample_tick && rx_data_valid && rx_active) begin
            $display("    [%0t] RX bit: %b (state=%0d)", $time, rx_data_out, rx_state);
        end
        
        // Show first few data_valid events regardless of rx_active
        if (sample_tick && rx_data_valid && data_valid_count < 5) begin
            $display("    [%0t] data_valid: bit=%b, rx_active=%b, state=%0d", 
                     $time, rx_data_out, rx_active, rx_state);
        end
    end

endmodule
