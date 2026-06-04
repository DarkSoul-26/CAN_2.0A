`timescale 1ns / 1ps
//============================================================================
// Testbench: tb_can_frame_viewer
// Description: Shows TX and RX CAN frame in horizontal format
//============================================================================

module tb_can_frame_viewer;

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

    initial clk = 0;
    always #5 clk = ~clk;

    // Capture TX bits
    wire bit_tick = dut.bit_tick;
    wire tx_busy  = dut.tx_busy;
    reg [127:0] tx_bits;
    integer     tx_cnt;
    reg         was_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_bits  <= 128'd0;
            tx_cnt   <= 0;
            was_busy <= 0;
        end else begin
            was_busy <= tx_busy;
            if (tx_busy && !was_busy) begin
                tx_bits <= 128'd0;
                tx_cnt  <= 0;
            end
            if (tx_busy && bit_tick && tx_cnt < 128) begin
                tx_bits[tx_cnt] <= can_tx;
                tx_cnt <= tx_cnt + 1;
            end
        end
    end

    // APB tasks
    task apb_write;
        input [7:0] addr; input [15:0] data;
        begin
            @(posedge clk); #1;
            PSEL=1; PENABLE=0; PWRITE=1; PADDR=addr; PWDATA=data;
            @(posedge clk); #1; PENABLE=1;
            @(posedge clk); #1; PSEL=0; PENABLE=0;
            @(posedge clk);
        end
    endtask

    task apb_read;
        input [7:0] addr; output [15:0] data;
        begin
            @(posedge clk); #1;
            PSEL=1; PENABLE=0; PWRITE=0; PADDR=addr;
            @(posedge clk); #1; PENABLE=1;
            @(posedge clk); #1; data=PRDATA; PSEL=0; PENABLE=0;
            @(posedge clk);
        end
    endtask

    // Print bits horizontally
    task print_bits_horiz;
        input integer start;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1)
                $write("%b", tx_bits[start + i]);
        end
    endtask

    // Test
    reg [15:0] rid, rdlc, rd0, rd1, rd2, rd3;

    initial begin
        rst_n = 0;
        PSEL = 0; PENABLE = 0; PWRITE = 0;
        PADDR = 0; PWDATA = 0; can_rx = 1;
        #100; rst_n = 1; #100;

        $display("");
        $display("================================================================================");
        $display("                    CAN 2.0A FRAME TRANSMISSION VIEWER");
        $display("================================================================================");

        // Configure
        apb_write(8'h00, 16'h0001);  // reset mode
        apb_write(8'h04, 16'h0581);  // fast BTR
        apb_write(8'h06, 16'h0000);  // accept all
        apb_write(8'h08, 16'h07FF);
        apb_write(8'h00, 16'h0002);  // loopback mode
        #200;

        $display("\nTransmitting:  ID = 0x123 (00010010011)");
        $display("              DLC = 4 (0100)");
        $display("             DATA = 0xDEADBEEF");
        $display("");

        // Load frame
        apb_write(8'h0A, 16'h0123);  // ID
        apb_write(8'h0C, 16'h0004);  // DLC=4
        apb_write(8'h0E, 16'hDEAD);  // DATA0
        apb_write(8'h10, 16'hBEEF);  // DATA1
        apb_write(8'h2C, 16'h0001);  // tx_req

        wait (tx_busy);
        wait (!tx_busy);
        #500;

        // Display TX frame horizontally
        $display("--------------------------------------------------------------------------------");
        $display("TX FRAME (%0d bits):", tx_cnt);
        $display("--------------------------------------------------------------------------------");
        
        // Labels
        $write("Field:   SOF ID[10:0]      RTR IDE r0 DLC   ");
        $write("DATA0      DATA1      DATA2      DATA3      ");
        $write("CRC[14:0]        D ACK D EOF       IFS\n");
        
        // Bits
        $write("TX Bits: ");
        // SOF (1)
        print_bits_horiz(0, 1); $write(" ");
        // ID (11)
        print_bits_horiz(1, 11); $write(" ");
        // RTR IDE r0 (3)
        print_bits_horiz(12, 3); $write(" ");
        // DLC (4)
        print_bits_horiz(15, 4); $write(" ");
        // DATA0 (8)
        print_bits_horiz(19, 8); $write(" ");
        // DATA1 (8)
        print_bits_horiz(27, 8); $write(" ");
        // DATA2 (8)
        print_bits_horiz(35, 8); $write(" ");
        // DATA3 (8)
        print_bits_horiz(43, 8); $write(" ");
        // CRC (15)
        print_bits_horiz(51, 15); $write(" ");
        // CRC_DELIM ACK ACK_DELIM (3)
        print_bits_horiz(66, 3); $write(" ");
        // EOF (7)
        print_bits_horiz(69, 7); $write(" ");
        // IFS (3)
        print_bits_horiz(76, 3);
        $display("");
        
        $display("--------------------------------------------------------------------------------");
        $display("");

        // Read RX
        apb_read(8'h20, rid);
        apb_read(8'h22, rdlc);
        apb_read(8'h24, rd0);
        apb_read(8'h26, rd1);
        apb_read(8'h28, rd2);
        apb_read(8'h2A, rd3);

        // Display RX frame
        $display("RX FRAME (from register file - loopback):");
        $display("--------------------------------------------------------------------------------");
        $display("  ID [10:0] = %011b (0x%03h)", rid[10:0], rid[10:0]);
        $display("  DLC [3:0] = %04b (%0d bytes)", rdlc[3:0], rdlc[3:0]);
        $display("  DATA[0]   = %08b (0x%02h)", rd0[15:8], rd0[15:8]);
        $display("  DATA[1]   = %08b (0x%02h)", rd0[7:0], rd0[7:0]);
        $display("  DATA[2]   = %08b (0x%02h)", rd1[15:8], rd1[15:8]);
        $display("  DATA[3]   = %08b (0x%02h)", rd1[7:0], rd1[7:0]);
        $display("--------------------------------------------------------------------------------");

        // Verify
        $display("");
        if (rid[10:0] == 11'h123 && rdlc[3:0] == 4'd4 && 
            rd0 == 16'hDEAD && rd1 == 16'hBEEF) begin
            $display("[PASS] TX and RX frames match!");
        end else begin
            $display("[FAIL] Frame mismatch!");
        end

        $display("");
        $display("================================================================================");
        $display("                         FRAME VIEWER COMPLETE");
        $display("================================================================================");
        $finish;
    end

    initial begin
        #1000000;
        $display("[TIMEOUT]");
        $finish;
    end

endmodule
