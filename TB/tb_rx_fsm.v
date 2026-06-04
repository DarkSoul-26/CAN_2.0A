`timescale 1ns / 1ps
//============================================================================
// Testbench: tb_rx_fsm (Simple frame viewer)
//   Feeds a known CAN frame bit-by-bit into rx_fsm and prints what it
//   extracted (ID, DLC, data bytes). CRC is faked with a fixed value.
//   No bit stuffing simulation (data_valid tied high).
//============================================================================

module tb_rx_fsm;

    parameter CLK_PERIOD = 10;

    reg         clk;
    reg         rst_n;
    reg         sample_tick;
    reg         data_valid;
    reg         data_in;
    reg  [14:0] crc_rx;         // dummy CRC
    reg         rx_release;

    wire        ack_bit;
    wire        crc_en;
    wire        crc_clear;
    wire [10:0] rx_id;
    wire [3:0]  rx_dlc;
    wire [15:0] rx_data0, rx_data1, rx_data2, rx_data3;
    wire        rx_ready;
    wire        crc_err;
    wire        form_err;
    wire        rx_active;

    rx_fsm uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_tick (sample_tick),
        .data_valid  (data_valid),
        .data_in     (data_in),
        .crc_rx      (crc_rx),
        .rx_release  (rx_release),
        .ack_bit     (ack_bit),
        .crc_en      (crc_en),
        .crc_clear   (crc_clear),
        .rx_id       (rx_id),
        .rx_dlc      (rx_dlc),
        .rx_data0    (rx_data0),
        .rx_data1    (rx_data1),
        .rx_data2    (rx_data2),
        .rx_data3    (rx_data3),
        .rx_ready    (rx_ready),
        .crc_err     (crc_err),
        .form_err    (form_err),
        .rx_active   (rx_active)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Frame to feed: ID=0x123, DLC=1, DATA=0xAB, CRC=dummy 0x2AAA
    //   SOF | ID[10:0] | RTR | IDE r0 DLC[3:0] | DATA(8) | CRC[14:0] |
    //   CRC_DELIM | ACK | ACK_DELIM | EOF(7) | IFS(3)
    reg [0:54] frame;
    integer i;

    task feed_bit(input b);
    begin
        sample_tick = 1;
        data_valid  = 1;
        data_in     = b;
        @(posedge clk);
        #1;
        sample_tick = 0;
        @(posedge clk);
        #1;
    end
    endtask

    initial begin
        rst_n       = 0;
        sample_tick = 0;
        data_valid  = 1;        // no bit stuffing in this test
        data_in     = 1;
        crc_rx      = 15'h2AAA; // dummy CRC value (matches what we send)
        rx_release  = 0;

        #(CLK_PERIOD * 3);
        @(negedge clk); rst_n = 1;
        #(CLK_PERIOD * 2);

        //====================================================================
        // Build the frame: ID=0x123, DLC=1, DATA=0xAB, CRC=0x2AAA
        //====================================================================
        i = 0;
        // SOF
        frame[i] = 0; i = i + 1;
        // ID[10:0] = 0x123 = 00100100011
        frame[i] = 0; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 1; i = i + 1;
        // RTR = 0
        frame[i] = 0; i = i + 1;
        // IDE = 0
        frame[i] = 0; i = i + 1;
        // r0 = 0
        frame[i] = 0; i = i + 1;
        // DLC[3:0] = 1 = 0001
        frame[i] = 0; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 1; i = i + 1;
        // DATA byte0 = 0xAB = 10101011
        frame[i] = 1; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 1; i = i + 1;
        // CRC[14:0] = 0x2AAA = 010101010101010
        frame[i] = 0; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 0; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 0; i = i + 1;
        // CRC delimiter = 1
        frame[i] = 1; i = i + 1;
        // ACK slot = 1 (no one else, but RX FSM drives it dominant internally)
        frame[i] = 1; i = i + 1;
        // ACK delimiter = 1
        frame[i] = 1; i = i + 1;
        // EOF = 1111111
        frame[i] = 1; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 1; i = i + 1;
        // Intermission = 111
        frame[i] = 1; i = i + 1;
        frame[i] = 1; i = i + 1;
        frame[i] = 1; // i = 55

        //====================================================================
        // Feed the frame bit by bit
        //====================================================================
        $display("Feeding frame: ID=0x123, DLC=1, DATA=0xAB");
        for (i = 0; i < 55; i = i + 1)
            feed_bit(frame[i]);

        // Wait for rx_ready pulse
        #(CLK_PERIOD * 2);

        //====================================================================
        // Print extracted fields
        //====================================================================
        $display("");
        $display("==================== RX FSM EXTRACTED ====================");
        $display("  rx_id      : 0x%03h", rx_id);
        $display("  rx_dlc     : %0d", rx_dlc);
        $display("  rx_data0   : 0x%04h (byte0=%02h byte1=%02h)",
                 rx_data0, rx_data0[15:8], rx_data0[7:0]);
        $display("  rx_data1   : 0x%04h", rx_data1);
        $display("  rx_data2   : 0x%04h", rx_data2);
        $display("  rx_data3   : 0x%04h", rx_data3);
        $display("  rx_ready   : %b", rx_ready);
        $display("  crc_err    : %b", crc_err);
        $display("  form_err   : %b", form_err);
        $display("==========================================================");
        $display(" (CRC was faked to 0x2AAA to match fed frame)");
        $display("");

        #(CLK_PERIOD * 4);
        $finish;
    end

    // Watchdog
    initial begin
        #(CLK_PERIOD * 50000);
        $display("[ERROR] Timeout");
        $finish;
    end

endmodule
