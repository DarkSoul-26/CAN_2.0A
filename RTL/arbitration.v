`timescale 1ns / 1ps
//============================================================================
// Module: can_arbitration
// Description: CAN 2.0A Arbitration Monitor
//
//   During the arbitration field (ID transmission), each node monitors the
//   bus. If a node transmits recessive (1) but reads dominant (0) on the
//   bus, another node is transmitting a lower (dominant) ID → this node
//   loses arbitration and must stop transmitting.
//
//   Inputs:
//     - bit_tick   : bit boundary pulse (from bit timing)
//     - tx_active  : HIGH when TX FSM is in the arbitration field
//     - can_tx     : bit this node is transmitting (pre-stuff)
//     - can_rx     : bit observed on the bus (synchronized)
//
//   Output:
//     - arb_lost   : 1-clk pulse when arbitration is lost
//                    (TX FSM aborts on this signal)
//
//   CAN arbitration rule:
//     Dominant (0) wins over recessive (1).
//     If (can_tx==1 && can_rx==0 during arb) => lost.
//============================================================================

module can_arbitration (
    input  wire clk,
    input  wire rst_n,
    input  wire bit_tick,
    input  wire tx_active,   // HIGH during TX arbitration field
    input  wire can_tx,      // Bit being transmitted
    input  wire can_rx,      // Bit observed on bus
    output reg  arb_lost     // 1-clk pulse: arbitration lost
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arb_lost <= 1'b0;
        end else begin
            // Default: arb_lost is a 1-cycle pulse
            arb_lost <= 1'b0;

            // Detect arbitration loss: transmitting recessive but bus is dominant
            if (bit_tick && tx_active && can_tx && !can_rx)
                arb_lost <= 1'b1;
        end
    end

endmodule
