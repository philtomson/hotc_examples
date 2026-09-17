////////////////////////////////////////////////////////////////////////////////
// Company: HotWright Inc.
// Copyright (c) 2022
// All Rights Reserved
// Engineer: Steve Casselman
//
// Module Name: microcode
// Description:
//   STANDALONE=1 or COMPILER_MODE=1: single ROM bank preloaded from file,
//     ready always 1. load_init and switch_trigger are ignored.
//
//   STANDALONE=0, COMPILER_MODE=0: dual-bank ping-pong for hot-swap JIT.
//     Bank A and Bank B alternate as active (execute) and inactive (load).
//     load_init  — pulse before streaming a new program; resets write
//                  pointer and clears the inactive bank's load_done flag.
//     switch_trigger — when pending_switch is set and switch_trigger fires,
//                  the banks swap.  On first boot (ever_swapped=0) the swap
//                  happens immediately after loading completes without waiting
//                  for switch_trigger, breaking the chicken-and-egg deadlock.
//
////////////////////////////////////////////////////////////////////////////////
`timescale 10ns / 1ns

module microcode #(
    parameter NUM_ADDRESS_LINES = 5,
    parameter NUM_WORDS         = 32,
    parameter NUM_VARSEL_BITS   = 3,
    parameter NUM_TIMERS        = 0,
    parameter NUM_STATE_BITS    = 4,
    parameter NUM_SWITCH_BITS   = 1,
    parameter NUM_CONTROL_BITS  = 32,
    parameter EXPR_SEL_BITS     = 0,   // 0 = no expression circuits
    parameter NUM_EXPRS         = 0,   // number of expression circuits
    parameter DATA_STACK_WIDTH  = 0,   // 0 = no data stack; >0 = --hw-stack active
    parameter FILENAME          = "",
    parameter STANDALONE        = 0,
    parameter COMPILER_MODE     = 0,
    parameter [NUM_STATE_BITS-1:0] RESET_VALUES = 0,
    parameter [NUM_STATE_BITS-1:0] ONE_SHOT_MASK = 0
)(
    input  [NUM_CONTROL_BITS+(2*NUM_STATE_BITS)-1:0] smdata_word,
    input  [NUM_ADDRESS_LINES-1:0] address,
    // Expression results: flat vector of NUM_EXPRS × NUM_STATE_BITS bits.
    // Unused when EXPR_SEL_BITS=0 (tied to 0 in generated template).
    input  [(EXPR_SEL_BITS > 0 ? NUM_EXPRS * NUM_STATE_BITS : 1) - 1 : 0] expr_results_flat,
    // Hardware data stack interface (DATA_STACK_WIDTH > 0 only).
    // top_data: registered TOS from data_stack; valid the cycle after a push/pop.
    // push_data: value to push this cycle (= effective_state_value[DATA_STACK_WIDTH-1:0]).
    input  [(DATA_STACK_WIDTH > 0 ? DATA_STACK_WIDTH : 1)-1:0] top_data,
    output push_en,
    output pop_en,
    output [(DATA_STACK_WIDTH > 0 ? DATA_STACK_WIDTH : 1)-1:0] push_data,
    input  smload,
    input  load_init,       // pulse before streaming a new program
    input  switch_trigger,  // safe-point signal (e.g. out_valid) for bank swap
    input  rst,
    input  clk,
    input  hlt,
    output reg [NUM_STATE_BITS-1:0] states,
    output [NUM_ADDRESS_LINES-1:0] jmp_adr,
    output [NUM_VARSEL_BITS-1:0] varSel,
    output [NUM_TIMERS > 0 ? NUM_TIMERS-1 : 0 : 0] timerSel,
    output [NUM_TIMERS > 0 ? NUM_TIMERS-1 : 0 : 0] timerLd,
    output [NUM_SWITCH_BITS > 0 ? NUM_SWITCH_BITS-1 : 0 : 0] switch_sel,
    output switch_active,
    output var_or_timer,
    output branch,
    output forced_jmp,
    output sub,
    output rtn,
    output state_capture,
    output external,
    output ready,
    output stream_valid,
    output stream_ready
);

localparam WORD_WIDTH = NUM_CONTROL_BITS + (2*NUM_STATE_BITS);

// top_data's actual declared width (see the port declaration above): when
// DATA_STACK_WIDTH==0 it's clamped to 1 bit rather than 0, to avoid an
// illegal [-1:0] vector. top_data_ext/top_data_ext2's zero-padding below
// must subtract THIS width, not the raw DATA_STACK_WIDTH parameter -- using
// the raw parameter under-counts the concatenation by 1 bit whenever
// DATA_STACK_WIDTH==0 (NUM_STATE_BITS zero bits + top_data's real 1-bit
// width = NUM_STATE_BITS+1, one wider than the ternary's other branch),
// which is dead-code width-inference noise (the DATA_STACK_WIDTH>0 branch
// is never selected when DATA_STACK_WIDTH==0) but still a real elaboration
// warning/error since Verilog sizes both sides of `?:` regardless of which
// one is live.
localparam TOP_DATA_WIDTH = (DATA_STACK_WIDTH > 0) ? DATA_STACK_WIDTH : 1;

// ── Control field decoding ──────────────────────────────────────────────────
// Hoisted above the generate blocks that use these (gen_stack_flags below,
// gen_expr_sel_state further down): a forward reference to a localparam
// declared later in the same module is legal under two-pass elaboration
// (Verilator, real hardware) but rejected by Icarus Verilog, which is
// stricter about generate-block declaration order. See
// plans/icarus_web_sim_regression.md.
localparam JMP_ADR_START    = 0;
localparam VAR_SEL_START    = NUM_ADDRESS_LINES;
localparam TIMER_SEL_START  = VAR_SEL_START    + NUM_VARSEL_BITS;
localparam TIMER_LD_START   = TIMER_SEL_START  + NUM_TIMERS;
localparam SWITCH_SEL_START = TIMER_LD_START   + NUM_TIMERS;
localparam EXPR_SEL_START   = SWITCH_SEL_START + NUM_SWITCH_BITS;
localparam FLAGS_START      = EXPR_SEL_START   + EXPR_SEL_BITS;

// ── Instruction word and decoded fields ─────────────────────────────────────
wire [WORD_WIDTH-1:0] microcode_bits;

wire [NUM_STATE_BITS-1:0]  state_value      = microcode_bits[NUM_STATE_BITS-1:0];
wire [NUM_STATE_BITS-1:0]  transition_value = microcode_bits[(2*NUM_STATE_BITS)-1:NUM_STATE_BITS];
wire [NUM_CONTROL_BITS-1:0] ctl_out          = microcode_bits[WORD_WIDTH-1:2*NUM_STATE_BITS];

// ── Code RAM and ready: generate per mode ───────────────────────────────────
generate
    if (STANDALONE == 1 || COMPILER_MODE == 1) begin : gen_standalone
        // Single ROM bank, preloaded from file.  load_init / switch_trigger unused.
        reg [WORD_WIDTH-1:0] code [NUM_WORDS-1:0];
        // Guarded like IP/timer.sv, IP/variable.sv, IP/switch.sv: yosys
        // elaborates this module's default parameterization (FILENAME="")
        // at least once while building the hierarchy, even under a
        // generate-if that only holds for the real instance -- an
        // unguarded $readmemh("") hard-errors synthesis before that.
        initial if (FILENAME != "") $readmemh(FILENAME, code, 0, NUM_WORDS-1);
        assign microcode_bits = code[address];
        assign ready = 1'b1;

    end else begin : gen_not_standalone
        // ── Dual-bank ping-pong for runtime loading with hot-swap ──────────
        reg [WORD_WIDTH-1:0] code_a [NUM_WORDS-1:0];  // bank 0
        reg [WORD_WIDTH-1:0] code_b [NUM_WORDS-1:0];  // bank 1

        // Declaration-time initializers (not an `if (rst)` reset): these give
        // FPGA targets a real, synthesizable power-on state (SRAM-configured
        // initial FF value) without making `rst` re-clobber bank_sel on every
        // pulse -- callers like shader_JIT_top.v intentionally re-pulse `rst`
        // between loads (to settle output state) while relying on bank_sel/
        // ever_swapped surviving untouched; only load_init (below) is meant to
        // reinitialize per-load state. Without SOME defined initial value here,
        // these regs power up undefined on real silicon / a 4-state simulator
        // (verified via Icarus Verilog: X propagates through the
        // address_wr/NUM_WORDS-1 comparison forever and the machine never
        // produces a defined address) -- this was previously masked because a
        // 2-state simulator silently defaults uninitialized regs to 0,
        // matching this same idiom already used for load_done_a/b below and
        // in variable.sv/timer.sv.
        reg bank_sel = 1'b0;     // 0 = execute A / load B;  1 = execute B / load A
        reg [NUM_ADDRESS_LINES-1:0] address_wr = 0;
        reg pending_switch = 1'b0;
        reg load_done_a = 1'b0, load_done_b = 1'b0;
        // ever_swapped: 0 on first boot → skip switch_trigger, swap immediately.
        // Prevents deadlock when no pixel has been processed yet.
        reg ever_swapped = 1'b0;

        wire effective_trigger = switch_trigger | ~ever_swapped;

        // Execute from the active bank
        assign microcode_bits = bank_sel ? code_b[address] : code_a[address];

        always @(posedge clk) begin
            // load_init: prepare the inactive bank for a new program stream.
            // Clears the write pointer and the inactive bank's load_done flag.
            if (load_init) begin
                address_wr     <= 0;
                pending_switch <= 1'b0;
                if (~bank_sel) load_done_b <= 1'b0;
                else           load_done_a <= 1'b0;

            end else if (smload && !pending_switch) begin
                // Write incoming word to the inactive bank
                if (~bank_sel) code_b[address_wr] <= smdata_word;
                else           code_a[address_wr] <= smdata_word;

                if (address_wr < NUM_WORDS - 1) begin
                    address_wr <= address_wr + 1;
                end else begin
                    // All words received; mark the inactive bank done and
                    // request a switch at the next safe point.
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

        // ready: the currently-active bank holds a complete program
        assign ready = bank_sel ? load_done_b : load_done_a;
    end
endgenerate

// ── Stream status (unused; kept for port compatibility) ──────────────────────
assign stream_valid = 1'b0;
assign stream_ready = 1'b1;

// ── State registers ─────────────────────────────────────────────────────────
genvar i;
// ── Hardware data stack flag decoding ──────────────────────────────────────
// push_en and pop_en are at FLAGS_START+8 and FLAGS_START+9.
// When DATA_STACK_WIDTH=0 these are tied to 0 (no overhead).
generate
    if (DATA_STACK_WIDTH > 0) begin : gen_stack_flags
        assign push_en = ctl_out[FLAGS_START + 8];
        assign pop_en  = ctl_out[FLAGS_START + 9];
    end else begin : gen_no_stack_flags
        assign push_en = 1'b0;
        assign pop_en  = 1'b0;
    end
endgenerate

generate
    if (EXPR_SEL_BITS > 0) begin : gen_expr_sel_state
        // Decode expr_sel from control word
        wire [EXPR_SEL_BITS-1:0] expr_sel_field =
            ctl_out[EXPR_SEL_START +: EXPR_SEL_BITS];

        // Unpack flat expression results into per-expression vectors
        wire [NUM_STATE_BITS-1:0] expr_results [0:NUM_EXPRS-1];
        genvar e;
        for (e = 0; e < NUM_EXPRS; e = e+1)
            assign expr_results[e] = expr_results_flat[e*NUM_STATE_BITS +: NUM_STATE_BITS];

        // 3-way mux: pop_en wins (TOS), then expr_sel, then literal state_value
        wire [NUM_STATE_BITS-1:0] top_data_ext =
            (DATA_STACK_WIDTH > 0)
                ? {{(NUM_STATE_BITS - TOP_DATA_WIDTH){1'b0}}, top_data}
                : {NUM_STATE_BITS{1'b0}};

        // capture X from EXPR | Y = LITERAL fusion: expr_results[] is
        // zero-padded outside the captured variable's own bit range (by
        // codegen), and the compiler never writes literal state[] bits in
        // that same range (only in a merged state-set's range) — so OR'ing
        // them together combines expr-sourced bits with literal-sourced
        // bits from the same instruction instead of letting the expr
        // vector's padding zeros clobber a fused literal state assignment.
        wire [NUM_STATE_BITS-1:0] effective_state_value =
            pop_en            ? top_data_ext :
            (expr_sel_field != 0) ? (expr_results[expr_sel_field - 1] | state_value) :
                                state_value;

        // E2: lower NUM_ADDRESS_LINES bits of selected expr result → jump address candidate
        wire [NUM_ADDRESS_LINES-1:0] expr_jmp_adr =
            (expr_sel_field != 0) ? expr_results[expr_sel_field - 1][NUM_ADDRESS_LINES-1:0]
                                  : {NUM_ADDRESS_LINES{1'b0}};

        // push_data: truncate effective_state_value to DATA_STACK_WIDTH bits
        if (DATA_STACK_WIDTH > 0) begin : gen_push_data_expr
            assign push_data = effective_state_value[DATA_STACK_WIDTH-1:0];
        end else begin : gen_push_data_noexpr
            assign push_data = 1'b0;
        end

        for (i = 0; i < NUM_STATE_BITS; i = i+1)
            always @(posedge clk)
                if (rst == 1) states[i] <= RESET_VALUES[i];
                else if (!hlt && state_capture & transition_value[i])
                    states[i] <= effective_state_value[i];
                else if (!hlt && ONE_SHOT_MASK[i])
                    states[i] <= RESET_VALUES[i];

    end else begin : gen_no_expr_sel_state
        // No expression circuits: simple 2-way mux (pop_en or literal)
        wire [NUM_STATE_BITS-1:0] top_data_ext2 =
            (DATA_STACK_WIDTH > 0)
                ? {{(NUM_STATE_BITS - TOP_DATA_WIDTH){1'b0}}, top_data}
                : {NUM_STATE_BITS{1'b0}};

        wire [NUM_STATE_BITS-1:0] effective_state_value2 =
            pop_en ? top_data_ext2 : state_value;

        if (DATA_STACK_WIDTH > 0) begin : gen_push_data_noexpr_ds
            assign push_data = effective_state_value2[DATA_STACK_WIDTH-1:0];
        end else begin : gen_push_data_noexpr_nods
            assign push_data = 1'b0;
        end

        for (i = 0; i < NUM_STATE_BITS; i = i+1)
            always @(posedge clk)
                if (rst == 1) states[i] <= RESET_VALUES[i];
                else if (!hlt && state_capture & transition_value[i])
                    states[i] <= effective_state_value2[i];
                else if (!hlt && ONE_SHOT_MASK[i])
                    states[i] <= RESET_VALUES[i];
    end
endgenerate

// E2: when forced_jmp=1 and expr_sel!=0, use expression circuit result as jump address.
// The literal jmp_adr field in the instruction word is ignored in that case.
// Excludes state_capture=1: expr_sel is also used to select the capture source
// expression (AINSTR_CAPTURE), which is unrelated to computed-goto (AINSTR_JMP_INDIRECT,
// which never sets state_capture). Without this term, a fused `capture | jmp` would
// wrongly route the captured expression's value through as the jump address.
wire [NUM_ADDRESS_LINES-1:0] literal_jmp_adr = ctl_out[VAR_SEL_START-1:JMP_ADR_START];
generate
    if (EXPR_SEL_BITS > 0) begin : gen_jmp_adr_mux
        assign jmp_adr = (forced_jmp && !sub && !state_capture && gen_expr_sel_state.expr_sel_field != 0)
                         ? gen_expr_sel_state.expr_jmp_adr : literal_jmp_adr;
    end else begin : gen_jmp_adr_literal
        assign jmp_adr = literal_jmp_adr;
    end
endgenerate
// NUM_VARSEL_BITS can be 0 (no state-var indirect selection needed, e.g.
// computed-index BRAM writes route through expr_sel instead) -- guarded the
// same way NUM_TIMERS/NUM_SWITCH_BITS already are just below: an unguarded
// part-select degenerates to an inverted-order (empty) range in that case,
// which Icarus rejects at elaboration (Verilator tolerates it silently).
generate
    if (NUM_VARSEL_BITS > 0) begin : gen_varsel
        assign varSel = ctl_out[TIMER_SEL_START-1:VAR_SEL_START];
    end else begin : no_varsel
        assign varSel = 0;
    end
endgenerate

generate
    if (NUM_TIMERS > 0) begin : gen_timers
        assign timerSel = ctl_out[TIMER_LD_START-1:TIMER_SEL_START];
        assign timerLd  = ctl_out[SWITCH_SEL_START-1:TIMER_LD_START];
    end else begin : no_timers
        assign timerSel = 0;
        assign timerLd  = 0;
    end

    if (NUM_SWITCH_BITS > 0) begin : gen_switches
        assign switch_sel = ctl_out[FLAGS_START-1:SWITCH_SEL_START];
    end else begin : no_switches
        assign switch_sel = 0;
    end
endgenerate

assign switch_active = ctl_out[FLAGS_START + 0];
assign state_capture = ctl_out[FLAGS_START + 1];
assign var_or_timer  = ctl_out[FLAGS_START + 2];
assign branch        = ctl_out[FLAGS_START + 3];
assign forced_jmp    = ctl_out[FLAGS_START + 4];
assign sub           = ctl_out[FLAGS_START + 5];
assign rtn           = ctl_out[FLAGS_START + 6];
assign external      = ctl_out[FLAGS_START + 7];

endmodule
