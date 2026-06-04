`timescale 1ns / 1ps
//============================================================================
// Module: can_bit_timing
// Description: CAN 2.0A Bit Timing Generator
//   Generates time quanta (tq_tick), sample point (sample_tick), and
//   bit boundary (bit_tick) from system clock. Implements hard sync
//   (bus idle only) and resynchronization (clamped by SJW).
//
// Parameters from btr_reg:
//   [5:0]   BRP    - Baud Rate Prescaler (tq = (BRP+1) * clk period)
//   [9:6]   TSEG1  - Time Segment 1 (prop + phase1), value 0-15 => 1-16 tq
//   [12:10] TSEG2  - Time Segment 2 (phase2), value 0-7 => 1-8 tq
//   [14:13] SJW    - Synchronization Jump Width, value 0-3 => 1-4 tq
//
// Bit time = 1(sync) + (TSEG1+1) + (TSEG2+1) time quanta
//============================================================================

module can_bit_timing (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] btr_reg,
    input  wire        can_rx,
    input  wire        bus_idle,
    output reg         tq_tick,
    output reg         sample_tick,
    output reg         bit_tick
);

    // Decode BTR fields
    wire [5:0] brp_val   = btr_reg[5:0];
    wire [3:0] tseg1_val = btr_reg[9:6];
    wire [2:0] tseg2_val = btr_reg[12:10];
    wire [1:0] sjw_val   = btr_reg[14:13];

    // Actual counts (field + 1)
    wire [6:0] tseg1_cnt = {3'd0, tseg1_val} + 7'd1;
    wire [6:0] tseg2_cnt = {4'd0, tseg2_val} + 7'd1;
    wire [6:0] sjw_cnt   = {5'd0, sjw_val}   + 7'd1;
    wire [6:0] bit_time  = 7'd1 + tseg1_cnt + tseg2_cnt;

    // Edge detection (2-stage sync)
    reg can_rx_d1, can_rx_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            can_rx_d1 <= 1'b1;
            can_rx_d2 <= 1'b1;
        end else begin
            can_rx_d1 <= can_rx;
            can_rx_d2 <= can_rx_d1;
        end
    end
    wire rx_falling_edge = can_rx_d2 & ~can_rx_d1;

    // Main timing logic (single always block)
    reg [5:0] prescaler_cnt;
    reg [6:0] tq_cnt;
    reg       hard_sync_done;
    wire      prescaler_wrap = (prescaler_cnt >= brp_val);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prescaler_cnt  <= 6'd0;
            tq_tick        <= 1'b0;
            tq_cnt         <= 7'd0;
            sample_tick    <= 1'b0;
            bit_tick       <= 1'b0;
            hard_sync_done <= 1'b0;
        end else begin
            // Defaults
            sample_tick <= 1'b0;
            bit_tick    <= 1'b0;
            tq_tick     <= 1'b0;

            //------------------------------------------------------------------
            // Hard Sync: resets everything immediately on falling edge + idle
            //------------------------------------------------------------------
            if (rx_falling_edge && bus_idle && !hard_sync_done) begin
                prescaler_cnt  <= 6'd0;
                tq_cnt         <= 7'd0;
                tq_tick        <= 1'b0;
                bit_tick       <= 1'b1;
                hard_sync_done <= 1'b1;
            end else begin
                //--------------------------------------------------------------
                // Prescaler
                //--------------------------------------------------------------
                if (prescaler_wrap) begin
                    prescaler_cnt <= 6'd0;
                    tq_tick       <= 1'b1;

                    //----------------------------------------------------------
                    // Bit timing counter (advances on each tq)
                    //----------------------------------------------------------
                    if (tq_cnt >= (bit_time - 7'd1)) begin
                        tq_cnt   <= 7'd0;
                        bit_tick <= 1'b1;
                    end else begin
                        tq_cnt <= tq_cnt + 7'd1;
                    end

                    // Sample point
                    if (tq_cnt == tseg1_cnt)
                        sample_tick <= 1'b1;

                    //----------------------------------------------------------
                    // Resynchronization (during frame)
                    //----------------------------------------------------------
                    if (rx_falling_edge && !bus_idle) begin
                        if (tq_cnt > tseg1_cnt) begin
                            if ((bit_time - 7'd1 - tq_cnt) > sjw_cnt)
                                tq_cnt <= tq_cnt + sjw_cnt;
                            else begin
                                tq_cnt   <= 7'd0;
                                bit_tick <= 1'b1;
                            end
                        end else if (tq_cnt != 7'd0 && tq_cnt <= tseg1_cnt) begin
                            if (tq_cnt > sjw_cnt)
                                tq_cnt <= tq_cnt - sjw_cnt;
                            else
                                tq_cnt <= 7'd0;
                        end
                    end
                end else begin
                    prescaler_cnt <= prescaler_cnt + 6'd1;
                end
            end

            // Clear hard_sync_done when bus goes idle
            if (bus_idle)
                hard_sync_done <= 1'b0;
        end
    end

endmodule
