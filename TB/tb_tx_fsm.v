`timescale 1ns / 1ps
//============================================================================
// Testbench: tb_tx_fsm (Simple frame viewer)
//   Drives tx_fsm to transmit one CAN frame and prints the full bit stream
//   on can_tx, broken out by field. Other blocks are faked:
//     - crc_computed : driven with a fixed dummy value (no real can_crc)
//     - tx_stall     : tied 0 (no bit stuffing)
//     - arb_lost     : tied 0 (we win arbitration)
//     - can_rx       : tied 0 (ACK present)
//============================================================================

module tb_tx_fsm;

    parameter CLK_PERIOD = 10;

    reg         clk;
    reg         rst_n;
    reg         bit_tick;
    reg         tx_stall;
    reg         tx_req;
    reg  [10:0] tx_id;
    reg  [3:0]  tx_dlc;
    reg  [63:0] tx_data;
    reg         can_rx;
    reg         arb_lost;
    reg  [14:0] crc_computed;   // dummy CRC value

    wire        can_tx;
    wire        crc_bit;
    wire        tx_busy;
    wire        tx_done;
    wire        ack_error;
    wire        crc_en;
    wire        crc_clear;
    wire        in_arb;

    tx_fsm uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .bit_tick     (bit_tick),
        .tx_stall     (tx_stall),
        .tx_req       (tx_req),
        .tx_id        (tx_id),
        .tx_dlc       (tx_dlc),
        .tx_data      (tx_data),
        .can_rx       (can_rx),
        .arb_lost     (arb_lost),
        .crc_computed (crc_computed),
        .can_tx       (can_tx),
        .crc_bit      (crc_bit),
        .tx_busy      (tx_busy),
        .tx_done      (tx_done),
        .ack_error    (ack_error),
        .crc_en       (crc_en),
        .crc_clear    (crc_clear),
        .in_arb       (in_arb)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Frame storage
    reg [0:79] frame;   // captured bits
    integer    n;       // number of captured bits
    integer    i;

    //------------------------------------------------------------------------
    // Advance one bit time and capture can_tx
    //------------------------------------------------------------------------
    task one_bit(input do_cap);
    begin
        bit_tick = 1;
        @(posedge clk);
        #1;
        if (do_cap) begin
            frame[n] = can_tx;
            n = n + 1;
        end
        bit_tick = 0;
        @(posedge clk);
        #1;
    end
    endtask

    //------------------------------------------------------------------------
    // Print a range of captured bits as a string
    //------------------------------------------------------------------------
    task show(input [127:0] label, input integer lo, input integer hi);
        integer k;
    begin
        $write("  %0s", label);
        for (k = lo; k < hi; k = k + 1) $write("%b", frame[k]);
        $write("\n");
    end
    endtask

    initial begin
        rst_n        = 0;
        bit_tick     = 0;
        tx_stall     = 0;
        tx_req       = 0;
        arb_lost     = 0;
        can_rx       = 0;             // ACK present
        crc_computed = 15'b101010101010101; // dummy CRC

        // Frame contents
        tx_id   = 11'h123;
        tx_dlc  = 4'd1;
        tx_data = 64'hAB00_0000_0000_0000;  // byte0 = 0xAB

        #(CLK_PERIOD * 3);
        @(negedge clk); rst_n = 1;
        #(CLK_PERIOD * 2);

        n = 0;

        // Kick off: IDLE -> SOF (don't capture the idle bit)
        tx_req = 1;
        one_bit(1'b0);
        tx_req = 0;

        // Capture the full frame (55 bits for DLC=1)
        for (i = 0; i < 55; i = i + 1)
            one_bit(1'b1);

        //--------------------------------------------------------------------
        // Print the frame by field
        //   layout: SOF(1) ID(11) RTR(1) IDE(1) r0(1) DLC(4) DATA(8)
        //           CRC(15) CRCdelim(1) ACK(1) ACKdelim(1) EOF(7) IFS(3)
        //--------------------------------------------------------------------
        $display("");
        $display("================= CAN FRAME (ID=0x123, DLC=1, DATA=0xAB) =================");
        $write("  FULL : ");
        for (i = 0; i < n; i = i + 1) $write("%b", frame[i]);
        $write("\n");
        $display("--------------------------------------------------------------------------");
        show("SOF        : ", 0, 1);
        show("ID[10:0]   : ", 1, 12);
        show("RTR        : ", 12, 13);
        show("IDE        : ", 13, 14);
        show("r0         : ", 14, 15);
        show("DLC[3:0]   : ", 15, 19);
        show("DATA byte0 : ", 19, 27);
        show("CRC[14:0]  : ", 27, 42);
        show("CRC delim  : ", 42, 43);
        show("ACK slot   : ", 43, 44);
        show("ACK delim  : ", 44, 45);
        show("EOF        : ", 45, 52);
        show("IFS        : ", 52, 55);
        $display("==========================================================================");
        $display(" (dummy CRC used = %b)", 15'b101010101010101);
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
