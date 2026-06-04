`timescale 1ns / 1ps
//============================================================================
// Module: can_acceptance_filter
// Description: CAN 2.0A standard (11-bit) identifier acceptance filter.
//
//   Compares an incoming 11-bit identifier against an Acceptance Code
//   Register (ACR) under an Acceptance Mask Register (AMR), SJA1000 style:
//     AMR bit = 1 -> "don't care" (that ID bit is ignored)
//     AMR bit = 0 -> "must match" (that ID bit must equal the ACR bit)
//
//   Match condition:
//     id_match = ( (rx_id XOR acr) AND ~amr ) == 0
//
//   On rx_ready_in (1-cycle pulse from RX FSM when a valid frame ID is
//   available) the filter pulses exactly one of:
//     rx_accepted - ID passed the filter (store frame)
//     rx_filtered - ID rejected (discard frame)
//============================================================================

module can_acceptance_filter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] acr_reg,      // Acceptance Code Register
    input  wire [15:0] amr_reg,      // Acceptance Mask Register (1=don't care)
    input  wire [10:0] rx_id,        // Received 11-bit identifier
    input  wire        rx_ready_in,  // 1-cycle pulse: rx_id valid
    output reg         rx_accepted,  // 1-cycle pulse: ID accepted
    output reg         rx_filtered   // 1-cycle pulse: ID rejected
);

    wire [10:0] acr = acr_reg[10:0];
    wire [10:0] amr = amr_reg[10:0];

    // All non-masked (AMR=0) bits must equal the ACR
    wire id_match = (((rx_id ^ acr) & ~amr) == 11'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_accepted <= 1'b0;
            rx_filtered <= 1'b0;
        end else begin
            // Default: outputs are single-cycle pulses
            rx_accepted <= 1'b0;
            rx_filtered <= 1'b0;

            if (rx_ready_in) begin
                if (id_match) rx_accepted <= 1'b1;
                else          rx_filtered <= 1'b1;
            end
        end
    end

endmodule
