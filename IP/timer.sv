//////////////////////////////////////////////////////////////////////////////////
// Company: HotWright Inc.
// Engineer: Steve Casseslman
// Copyright (c) 2022
// All Rights Reserved 
// Create Date: 05/27/2021 04:07:58 PM
// Design Name: 
// Module Name: timer
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
 
`timescale 10ns / 1ns
 
module timer #(parameter NUM_TIMERS = 1,
               parameter TIMER_WIDTH = 8,
               parameter TIM_MEM_WORDS = 1,
               parameter TIM_MEM_ADR_WIDTH = 1,
               parameter TIM_EX_WORDS = 1,
               parameter FILENAME = "",
               parameter STANDALONE = 0,
               parameter DUAL_BANK = 0     // STANDALONE=0 only: 1 = ping-pong hot-swap, 0 = cheap static ROM (default)
               )(
    input [TIMER_WIDTH-1:0] timer_data,
    input [TIM_EX_WORDS-1:0][TIMER_WIDTH-1:0] timer_ex_data,
    input [TIM_MEM_ADR_WIDTH-1:0] timer_mem_adr,
    input [NUM_TIMERS-1:0] timer_ld,
    input [NUM_TIMERS-1:0] timer_sel,
    input external,
    input tim_tvalid,
    input load_init,       // pulse before streaming a new timer-limit table (shared with sm/vd/switch's load_init)
    input switch_trigger,  // shared bank-flip trigger (STANDALONE=0, DUAL_BANK=1 only)
    input clk,
    input rst,
    output ready,
    output [NUM_TIMERS-1:0] timer_done,
    output [NUM_TIMERS-1:0][TIMER_WIDTH-1:0] count_out   // current count values (always present)
    );

    reg [TIMER_WIDTH-1:0] count [NUM_TIMERS-1:0];
    // Combinational read of the currently-active timer-limit storage,
    // indexed by timer_mem_adr; driven differently per STANDALONE/DUAL_BANK
    // tier below. Declared outside any generate block since it's consumed
    // by the per-timer for-loop further down, which also lives outside.
    wire [TIMER_WIDTH-1:0] timer_mem_out;
    // Pulses for one cycle when the active timer-limit bank flips
    // (DUAL_BANK=1 only) -- see the swap-time count-reset design note below.
    wire count_reset;

    generate
    if (STANDALONE == 1) begin : gen_standalone
        reg [TIMER_WIDTH-1:0] timer_mem [TIM_MEM_WORDS -1:0];
        initial begin
            if (FILENAME != "") $readmemh(FILENAME, timer_mem, 0, TIM_MEM_WORDS -1);
        end
        assign timer_mem_out = timer_mem[timer_mem_adr];
        assign ready = 1'b1;
        assign count_reset = 1'b0;
    end else begin : gen_not_standalone
      if (DUAL_BANK == 1) begin : gen_dual_bank
        // ── Dual-bank ping-pong for runtime loading with hot-swap ────────
        // Only built when DUAL_BANK=1 (--profile active). Mirrors IP/
        // variable.sv's pattern (not switch.sv's): timer_mem, like vardata,
        // already had a $readmemh ROM seed even before dual-bank existed
        // (limits were historically assumed fixed across swapped
        // algorithms), so bank A is valid from cycle 0 and no ever_swapped
        // first-boot bypass is needed or wanted -- every bank flip,
        // including the first one that ever streams real data, requires an
        // explicit switch_trigger pulse, same reasoning as Section 1.
        reg [TIMER_WIDTH-1:0] timer_mem_a [TIM_MEM_WORDS -1:0];  // bank 0
        reg [TIMER_WIDTH-1:0] timer_mem_b [TIM_MEM_WORDS -1:0];  // bank 1

        initial begin
            if (FILENAME != "") $readmemh(FILENAME, timer_mem_a, 0, TIM_MEM_WORDS -1);
        end

        reg bank_sel;                       // 0 = active A / load B; 1 = active B / load A
        reg [TIM_MEM_ADR_WIDTH-1:0] address_wr; // write pointer into the inactive bank
        reg pending_switch;
        reg load_done_a = 1'b1;             // bank A is ROM-seeded and valid from cycle 0
        reg load_done_b = 1'b0;             // bank B is genuinely empty until streamed

        assign timer_mem_out = bank_sel ? timer_mem_b[timer_mem_adr] : timer_mem_a[timer_mem_adr];
        assign ready = bank_sel ? load_done_b : load_done_a;
        // Design decision (Section 9, option a): reset all count[i] on the
        // same pulse that flips the bank, so a swap never leaves a stale
        // count around from the previous program's limits. Cheap: this
        // pulse is already computed for the bank-flip itself.
        assign count_reset = pending_switch && switch_trigger;

        always @(posedge clk) begin
            if (load_init) begin
                address_wr     <= 0;
                pending_switch <= 1'b0;
                if (~bank_sel) load_done_b <= 1'b0;
                else           load_done_a <= 1'b0;

            end else if (tim_tvalid && !pending_switch) begin
                if (~bank_sel) timer_mem_b[address_wr] <= timer_data;
                else           timer_mem_a[address_wr] <= timer_data;

                if (address_wr < (TIM_MEM_WORDS - 1)) begin
                    address_wr <= address_wr + 1;
                end else begin
                    pending_switch <= 1'b1;
                    if (~bank_sel) load_done_b <= 1'b1;
                    else           load_done_a <= 1'b1;
                end
            end

            if (pending_switch && switch_trigger) begin
                bank_sel       <= ~bank_sel;
                pending_switch <= 1'b0;
            end
        end
      end else begin : gen_single_bank
        // ── Cheap default tier (DUAL_BANK=0): single ROM-seeded bank ────
        // No second bank, no streaming write path at all -- tim_tvalid/
        // timer_data/load_init/switch_trigger are accepted on the port
        // list for interface uniformity with gen_dual_bank but are
        // intentionally unused here. This reproduces what every existing
        // --runtime-load example has always actually needed: timer limits
        // fixed across swapped algorithms, loaded once from FILENAME at
        // elaboration.
        reg [TIMER_WIDTH-1:0] timer_mem [TIM_MEM_WORDS -1:0];
        initial begin
            if (FILENAME != "") $readmemh(FILENAME, timer_mem, 0, TIM_MEM_WORDS -1);
        end
        assign timer_mem_out = timer_mem[timer_mem_adr];
        assign ready = 1'b1;
        assign count_reset = 1'b0;
      end
    end
    endgenerate

    generate
    genvar i;

    // here we generate the timers
    for(i=0;i<NUM_TIMERS;i = i + 1)
    begin


    always @(posedge clk) begin
    if(rst == 1 || count_reset)  count[i] <= 0;

    else if (timer_ld[i] == 1 && timer_sel[i] == 1) begin
        /* verilator lint_off WIDTHTRUNC */
        if (external == 1) count[i] <= timer_ex_data[timer_mem_adr];
        else count[i] <= timer_mem_out;
        /* verilator lint_on WIDTHTRUNC */
    end

    else if (timer_sel[i] == 1 && count[i] > 0 ) count[i] <= count[i] - 1;
    end

    assign timer_done[i] = (count[i] == 0 && timer_sel[i] == 1 && timer_ld[i] == 0);
    assign count_out[i]  = count[i];

    end
    endgenerate

endmodule
