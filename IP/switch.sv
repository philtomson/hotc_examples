//////////////////////////////////////////////////////////////////////////////////
// Company: HotWright Inc.
// Copyright (c) 2022 
// All rights reserved
// Engineer: Steve Casselman 
// Create Date: 09/13/2021 03:27:34 PM
// Design Name: 
// Module Name: switch
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: finds the offset into the a table. 
// The table has the addresses of the case statements code. 
// jadr adds an offset into the table to handel mutiple switches
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 10ns / 1ns


module switch #(parameter ADR_BUS_WIDTH = 8,
                parameter SWITCH_MEM_BITS = 8,
                parameter SWITCH_MEM_WORDS = 256,
                parameter FILENAME = "",
                parameter STANDALONE = 0,
                parameter DUAL_BANK = 0     // STANDALONE=0 only: 1 = ping-pong hot-swap, 0 = cheap single-bank streamed-once
                )(
    input [ADR_BUS_WIDTH - 1:0] switch_tdata,
    input switch_tvalid,
    input load_init,       // pulse before streaming a new switch table
    input switch_trigger,  // shared bank-flip trigger (STANDALONE=0 only)
    input [ADR_BUS_WIDTH - 1:0] jmp_adr,
    input [SWITCH_MEM_BITS - 1:0] switch_offset_adr,
    input switch_active,
    input clk,
    input rst,
    output ready,
    output [ADR_BUS_WIDTH - 1:0] switch_adr
    );


    wire [$clog2(SWITCH_MEM_WORDS)-1:0] memadr;

    generate
    if (STANDALONE == 1) begin : gen_standalone
    reg [ADR_BUS_WIDTH-1:0] switch_mem [SWITCH_MEM_WORDS - 1:0];
    // Guarded: yosys elaborates this module's default parameterization
    // (FILENAME="") at least once while building the design hierarchy, even
    // under a generate-if whose condition (STANDALONE==1) only holds for the
    // real, correctly-parameterized instance -- an unguarded $readmemh("")
    // hard-errors synthesis before the real instance is ever reached. An
    // empty FILENAME legitimately means "don't preload" (matches every
    // other loader in this file, and mem.v's SYNTHESIS-guarded zero-fill
    // elsewhere in the tree), not a fatal error.
    initial if (FILENAME != "") $readmemh(FILENAME,switch_mem, 0,SWITCH_MEM_WORDS -1);
    assign switch_adr = switch_active?switch_mem[memadr]:0;
    assign ready = 1'b1;

    end else begin : gen_not_standalone
      if (DUAL_BANK == 1) begin : gen_dual_bank
    // ── Dual-bank ping-pong for runtime loading with hot-swap ──────────
    // Only built when DUAL_BANK=1 (--profile active). Mirrors IP/
    // microcode.sv's dual-bank design exactly, INCLUDING its ever_swapped
    // first-boot bypass -- unlike IP/variable.sv (which has a ROM-seeded
    // bank A and must NOT auto-flip), switch.sv's STANDALONE=0 path has
    // never had a ROM seed of any kind (confirmed: the prior single-bank
    // version above had no $readmemh at all for STANDALONE=0). So both
    // banks genuinely start empty here, exactly like microcode.sv, and the
    // same ever_swapped bypass is needed to avoid a first-boot chicken-
    // and-egg deadlock.
    reg [ADR_BUS_WIDTH-1:0] switch_mem_a [SWITCH_MEM_WORDS - 1:0];  // bank 0
    reg [ADR_BUS_WIDTH-1:0] switch_mem_b [SWITCH_MEM_WORDS - 1:0];  // bank 1

    reg bank_sel;     // 0 = active A / load B; 1 = active B / load A
    reg [$clog2(SWITCH_MEM_WORDS)-1:0] address_wr;
    reg pending_switch;
    reg load_done_a, load_done_b;
    reg ever_swapped;

    wire effective_trigger = switch_trigger | ~ever_swapped;

    wire [ADR_BUS_WIDTH-1:0] active_switch_mem_out =
        bank_sel ? switch_mem_b[memadr] : switch_mem_a[memadr];
    assign switch_adr = switch_active ? active_switch_mem_out : 0;

     always @ (posedge clk) begin
        // load_init: prepare the inactive bank for a new table stream.
        if (load_init) begin
            address_wr     <= 0;
            pending_switch <= 1'b0;
            if (~bank_sel) load_done_b <= 1'b0;
            else           load_done_a <= 1'b0;

        end else if (switch_tvalid && !pending_switch) begin
            // Write incoming entry to the inactive bank
            if (~bank_sel) switch_mem_b[address_wr] <= switch_tdata;
            else           switch_mem_a[address_wr] <= switch_tdata;

            if (address_wr < (SWITCH_MEM_WORDS - 1)) begin
                address_wr <= address_wr + 1;
            end else begin
                // write that fills the last entry
                pending_switch <= 1'b1;
                if (~bank_sel) load_done_b <= 1'b1;
                else           load_done_a <= 1'b1;
            end
        end

        // Bank flip: swap active/inactive when switch_trigger fires
        // (or immediately on first boot via ever_swapped=0).
        if (pending_switch && effective_trigger) begin
            bank_sel       <= ~bank_sel;
            pending_switch <= 1'b0;
            ever_swapped   <= 1'b1;
        end
     end

    // ready: the currently-active bank holds a complete table.
    assign ready = bank_sel ? load_done_b : load_done_a;
      end else begin : gen_single_bank
    // ── Cheap default tier (DUAL_BANK=0): single bank, streamed once ───
    // No second bank, no bank_sel/pending_switch/ever_swapped -- just a
    // write pointer and a load_done latch. switch.sv has never had a ROM
    // fallback for STANDALONE=0, so streaming is still required to get any
    // content at all, but a live bank-flip is not: no existing example
    // (runtime_load_switch_demo included) ever re-streams a second,
    // different table while the machine is running -- they all load once
    // during reset, then run. switch_trigger is accepted on the port list
    // for interface uniformity with gen_dual_bank but is unused here.
    reg [ADR_BUS_WIDTH-1:0] switch_mem [SWITCH_MEM_WORDS - 1:0];
    reg [$clog2(SWITCH_MEM_WORDS)-1:0] address_wr;
    reg load_done;

    assign switch_adr = switch_active ? switch_mem[memadr] : 0;
    assign ready = load_done;

    always @ (posedge clk) begin
        if (load_init) begin
            address_wr <= 0;
            load_done  <= 1'b0;
        end else if (switch_tvalid && !load_done) begin
            switch_mem[address_wr] <= switch_tdata;
            if (address_wr < (SWITCH_MEM_WORDS - 1)) begin
                address_wr <= address_wr + 1;
            end else begin
                load_done <= 1'b1;
            end
        end
    end
      end
    end
    endgenerate

   assign memadr = {jmp_adr,switch_offset_adr};

endmodule
