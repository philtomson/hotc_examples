//////////////////////////////////////////////////////////////////////////////////
// Company: Hotwright Inc.
// Copyright (c) 2022 
// All Rights Reserved
// Engineer: Steve Casselman
//
// Create Date: 06/24/2020
// Module Name: variable
// Description: Unified UberLUT (Truth Table). 
// Each row in the LUT contains results for all possible varSel values 
// for a given state of the variable input bus.
//
//////////////////////////////////////////////////////////////////////////////////

`timescale 10ns / 1ns

module variable #(
               parameter NUM_VARS = 10,           // Width of the input variable bus
               parameter NUM_VARS_ADDR_BITS = NUM_VARS, // Truth-table address width (clamped to <=25 by the
                                                   // compiler's generate_vardata_mem_file() correctness clamp --
                                                   // must match here, since the table array is sized off this,
                                                   // not off NUM_VARS. Defaults to NUM_VARS for any caller that
                                                   // doesn't override it, matching this module's pre-clamp behavior.
               parameter NUM_VARSEL = 1,          // (unused in this implementation)
               parameter NUM_VARSEL_BITS = 4,     // Number of bits for selecting which expression
               parameter FILENAME = "",
               parameter STANDALONE = 0,
               parameter DUAL_BANK = 0            // STANDALONE=0 only: 1 = ping-pong hot-swap, 0 = cheap single ROM bank
               )(
               input clk,
               input rst,
               input [NUM_VARS-1:0] variable,     // Input variable bus (Address)
               input [NUM_VARSEL_BITS-1:0] varSel, // Expression selector (Bit Index)
               input [(1 << NUM_VARSEL_BITS)-1:0] vd_tdata, // Full truth-table row, streamed one row/cycle
               input vd_tvalid,                   // Row-valid strobe for vd_tdata
               input vd_load_init,                // Pulse before streaming a new table; resets write pointer
               input switch_trigger,              // Shared bank-flip trigger (STANDALONE=0 only)
               output ready,
               output lhs
               );

// Truth table: 2^NUM_VARS entries, each (1 << NUM_VARSEL_BITS) wide.
// This layout allows each BRAM row to store all expression results for a given input state.
// STANDALONE=1 only: single ROM bank, preloaded from file, read directly by `lhs` below.
// (STANDALONE=0's dual-bank equivalent, code_a/code_b, is declared inside gen_not_standalone.)
if (STANDALONE == 1) begin : gen_standalone
    reg [ (1 << NUM_VARSEL_BITS)-1 : 0 ] code [ (1 << NUM_VARS_ADDR_BITS)-1 : 0 ];
    initial begin
        $display("DEBUG_VARS: NUM_VARSEL_BITS=%0d NUM_VARS=%0d NUM_VARS_ADDR_BITS=%0d FILENAME=%s", NUM_VARSEL_BITS, NUM_VARS, NUM_VARS_ADDR_BITS, FILENAME);
        if (FILENAME != "") begin
            $readmemh(FILENAME, code);
        end
    end
    // Address with only the low NUM_VARS_ADDR_BITS of `variable` -- correct
    // ONLY while any bits above that stay 0 at runtime (the same correctness
    // caveat generate_vardata_mem_file()'s clamp warning documents).
    assign lhs = code[variable[NUM_VARS_ADDR_BITS-1:0]][varSel];
end

generate
if (STANDALONE == 0) begin : gen_not_standalone
  if (DUAL_BANK == 1) begin : gen_dual_bank
    // ── Dual-bank ping-pong for runtime loading with hot-swap ──────────
    // Only built when DUAL_BANK=1 (--profile active): this is the tier
    // that costs a second full table (measured ~2x LUT4/RAM on switch.sv
    // at comparable sizes) plus bank-flip control logic. Gated off by
    // default because the vast majority of --runtime-load designs only
    // ever hot-swap smdata between sibling programs that share one static
    // vardata table (algo_swap, shader_JIT, systolic_dynamic, tutorials/
    // runtime_swap) -- none of them need a second vardata bank, so they
    // get the cheap gen_single_bank tier below instead.
    //
    // Mirrors IP/microcode.sv's dual-bank design, with one deliberate
    // difference: microcode.sv's banks start empty (nothing is usable
    // until the first full smdata stream completes), so it needs the
    // ever_swapped=0 bypass to auto-flip on first load and break that
    // chicken-and-egg deadlock. Here, bank A is ROM-seeded from FILENAME
    // at elaboration (same as every existing --runtime-load example
    // relies on today — the vardata table has historically been static
    // and shared across swapped programs), so bank A is already valid at
    // cycle 0. An ever_swapped-style bypass would therefore be actively
    // wrong: it would auto-flip on the very first real vardata stream
    // (into bank B) the moment loading completes, without waiting for
    // switch_trigger — racing ahead of the other three dual-bank modules
    // (microcode/switch/timer) and breaking the atomic, trigger-gated
    // flip that Section 11 of the runtime-reloadable-microcode plan
    // relies on. So: every bank flip here, including the first one that
    // ever streams real data, requires an explicit switch_trigger pulse.
    reg [ (1 << NUM_VARSEL_BITS)-1 : 0 ] code_a [ (1 << NUM_VARS_ADDR_BITS)-1 : 0 ];  // bank 0
    reg [ (1 << NUM_VARSEL_BITS)-1 : 0 ] code_b [ (1 << NUM_VARS_ADDR_BITS)-1 : 0 ];  // bank 1

    initial begin
        if (FILENAME != "") begin
            $readmemh(FILENAME, code_a);
        end
    end

    reg bank_sel;                            // 0 = active A / load B; 1 = active B / load A
    reg [NUM_VARS_ADDR_BITS-1:0] address_wr; // write pointer into the inactive bank
    reg pending_switch;
    // load_done_a starts TRUE: bank A is ROM-seeded and valid from cycle 0,
    // matching this module's historical `ready = 1'b1` behavior for every
    // existing example that never streams vardata at all. load_done_b
    // starts FALSE: bank B is genuinely empty until actually streamed.
    reg load_done_a = 1'b1;
    reg load_done_b = 1'b0;

    wire [ (1 << NUM_VARSEL_BITS)-1 : 0 ] active_row = bank_sel ? code_b[variable[NUM_VARS_ADDR_BITS-1:0]] : code_a[variable[NUM_VARS_ADDR_BITS-1:0]];
    assign lhs = active_row[varSel];

    always @(posedge clk) begin
        // vd_load_init: prepare the inactive bank for a new table stream.
        // Clears the write pointer and the inactive bank's load_done flag.
        if (vd_load_init) begin
            address_wr     <= 0;
            pending_switch <= 1'b0;
            if (~bank_sel) load_done_b <= 1'b0;
            else           load_done_a <= 1'b0;

        end else if (vd_tvalid && !pending_switch) begin
            // Write incoming row to the inactive bank
            if (~bank_sel) code_b[address_wr] <= vd_tdata;
            else           code_a[address_wr] <= vd_tdata;

            if (address_wr < (1 << NUM_VARS_ADDR_BITS) - 1) begin
                address_wr <= address_wr + 1;
            end else begin
                // All rows received; mark the inactive bank done and
                // request a switch at the next switch_trigger pulse.
                pending_switch <= 1'b1;
                if (~bank_sel) load_done_b <= 1'b1;
                else           load_done_a <= 1'b1;
            end
        end

        // Bank flip: swap active/inactive when switch_trigger fires.
        if (pending_switch && switch_trigger) begin
            bank_sel       <= ~bank_sel;
            pending_switch <= 1'b0;
        end
    end

    // ready: the currently-active bank holds a complete/valid table.
    assign ready = bank_sel ? load_done_b : load_done_a;
  end else begin : gen_single_bank
    // ── Cheap default tier (DUAL_BANK=0): single ROM-seeded bank ───────
    // No second bank, no bank_sel/pending_switch/ever_swapped control
    // logic -- vd_tvalid/vd_tdata/vd_load_init/switch_trigger are accepted
    // on the port list for interface uniformity with gen_dual_bank but are
    // intentionally left unused here. This reproduces exactly what every
    // existing --runtime-load example (none of which ever pulse vd_tvalid)
    // has always actually exercised: a table loaded once from FILENAME at
    // elaboration, valid from cycle 0.
    reg [ (1 << NUM_VARSEL_BITS)-1 : 0 ] code [ (1 << NUM_VARS_ADDR_BITS)-1 : 0 ];
    initial begin
        if (FILENAME != "") begin
            $readmemh(FILENAME, code);
        end
    end
    assign lhs   = code[variable[NUM_VARS_ADDR_BITS-1:0]][varSel];
    assign ready = 1'b1;
  end
end else begin : gen_standalone_ready
    // lhs is driven by the gen_standalone block above (STANDALONE==1).
    assign ready = 1'b1;
end
endgenerate

endmodule
