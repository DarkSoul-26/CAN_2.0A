`timescale 1ns / 1ps
//============================================================================
// Module: can_crc
// Description: CAN 2.0A CRC-15 generator
//   Polynomial: x^15 + x^14 + x^10 + x^8 + x^7 + x^4 + x^3 + 1 = 0x4599
//
//   Standard CAN serial CRC. One bit is shifted in per 'enable' cycle:
//     crc_next = data_in XOR crc_reg[14]
//     crc_reg  = (crc_reg << 1) XOR (crc_next ? 0x4599 : 0)
//
//   'clear' must be pulsed at Start-Of-Frame (SOF) to zero the register
//   before the first bit is shifted in. The CRC covers SOF, arbitration,
//   control and data fields (per CAN spec) - the controlling FSM gates
//   'enable' accordingly.
//============================================================================

module can_crc (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,    // Shift one bit (data_in) into the CRC
    input  wire        clear,     // Synchronous clear to 0 (pulse at SOF)
    input  wire        data_in,   // Serial input bit
    output wire [14:0] crc_out    // Current CRC-15 value
);

    localparam [14:0] CRC_POLY = 15'h4599;

    reg [14:0] crc_reg;

    assign crc_out = crc_reg;

    wire crc_next = data_in ^ crc_reg[14];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            crc_reg <= 15'd0;
        else if (clear)
            crc_reg <= 15'd0;
        else if (enable)
            crc_reg <= {crc_reg[13:0], 1'b0} ^ (crc_next ? CRC_POLY : 15'd0);
    end

endmodule
