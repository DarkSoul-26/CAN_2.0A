`timescale 1ns / 1ps
//============================================================================
// Module: can_apb_slave
// Description: APB interface for CAN 2.0A Controller
//
// APB Protocol:
//   - APB3 compliant with PREADY and PSLVERR
//   - 16-bit data width, byte-addressed (word-aligned)
//   - Zero wait-state transfers (PREADY always high when valid)
//
// Address Map:
//   0x00 - 0x2A: Register file (forwarded to can_reg_file)
//   0x2C: COMMAND register (write-only, generates pulses)
//         [0] tx_req    : Start transmission
//         [1] tx_abort  : Abort current transmission
//         [2] rx_release: Release RX buffer (mark as read)
//
// Error Handling:
//   - PSLVERR = 1 for:
//     * Unaligned address (PADDR[0] != 0)
//     * Out-of-range address (PADDR > 0x2C)
//============================================================================

module can_apb_slave (
    input  wire        PCLK,
    input  wire        PRESETn,
    
    // APB3 interface
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [7:0]  PADDR,
    input  wire [15:0] PWDATA,
    output wire [15:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,

    // Register file interface
    output wire        reg_write_en,
    output wire        reg_read_en,
    output wire [7:0]  reg_addr,
    output wire [15:0] reg_wdata,
    input  wire [15:0] reg_rdata,

    // Command outputs (pulses)
    output reg         tx_req,
    output reg         tx_abort,
    output reg         rx_release
);

    //--------------------------------------------------------------------------
    // APB transfer detection
    //--------------------------------------------------------------------------
    wire apb_setup  = PSEL && !PENABLE;
    wire apb_access = PSEL &&  PENABLE;

    //--------------------------------------------------------------------------
    // Address validation
    //   - Must be even (word-aligned)
    //   - Must be within range 0x00 - 0x2C
    //--------------------------------------------------------------------------
    wire addr_aligned = (PADDR[0] == 1'b0);
    wire addr_in_range = (PADDR <= 8'h2C);
    wire addr_valid = addr_aligned && addr_in_range;

    //--------------------------------------------------------------------------
    // Address decode
    //--------------------------------------------------------------------------
    wire is_reg_file = (PADDR <= 8'h2A);        // 0x00 - 0x2A: register file
    wire is_command  = (PADDR == 8'h2C);        // 0x2C: command register

    //--------------------------------------------------------------------------
    // APB response (combinational for zero wait-state)
    //--------------------------------------------------------------------------
    assign PREADY  = apb_access;                // Always ready when selected
    assign PSLVERR = apb_access && !addr_valid; // Error on invalid address
    assign PRDATA  = reg_rdata;                 // Read data from register file

    //--------------------------------------------------------------------------
    // Register file control
    //--------------------------------------------------------------------------
    assign reg_write_en = apb_access && PWRITE && is_reg_file && addr_valid;
    assign reg_read_en  = apb_access && !PWRITE && is_reg_file && addr_valid;
    assign reg_addr     = PADDR;
    assign reg_wdata    = PWDATA;

    //--------------------------------------------------------------------------
    // Command register (write-only, generates single-cycle pulses)
    //--------------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tx_req     <= 1'b0;
            tx_abort   <= 1'b0;
            rx_release <= 1'b0;
        end else begin
            // Default: pulses are single-cycle
            tx_req     <= 1'b0;
            tx_abort   <= 1'b0;
            rx_release <= 1'b0;

            // Generate pulses on command write
            if (apb_access && PWRITE && is_command && addr_valid) begin
                tx_req     <= PWDATA[0];
                tx_abort   <= PWDATA[1];
                rx_release <= PWDATA[2];
            end
        end
    end

endmodule
