// tm_top.v - Top-level wrapper (simulation mode)
// Hotstate clause sequencer (tm_seq_controller) + enable-pulse core (tm_core_v2).
// Sequential argmax is now computed inside tm_seq_controller.

`timescale 1ns / 1ps
`include "gen/tm_config.vh"

module tm_top #(
    parameter N_CLAUSES = `TM_N_CLAUSES,
    parameter FC_W      = $clog2(N_CLAUSES + 1)
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        go,
    output wire        done,
    output wire [3:0]  result,
    input  wire [6:0]  img_waddr,
    input  wire [7:0]  img_wdata,
    input  wire        img_wen,
    output wire [6:0]  ctrl_debug_adr,
    // Full sequencer state bus. Was [23:0], which silently dropped 14 of
    // tm_seq_controller's 38 state bits -- nothing consumed the narrow
    // version, and the ILA probe (plans/sandbox_multi_machine_ila.md)
    // needs the whole bus to be worth watching.
    output wire [37:0] ctrl_states_out,
    output wire        ctrl_ready,
    output wire [2:0]  core_state,
    output wire [7:0]  core_clause_idx,
    output wire signed [10:0] vote_0, vote_1, vote_2, vote_3, vote_4,
    output wire signed [10:0] vote_5, vote_6, vote_7, vote_8, vote_9,
    output wire [FC_W-1:0] fire_count,
    output wire [9:0]  clause0_viol,
    output wire        clause0_fired,
    output wire [7:0]  rom16,
    output wire        dbg_clause_done
`ifdef ILA_PROBE_ROM
    ,
    output wire [15:0] ila_rom_addr,
    output wire [15:0] ila_rom_data
`endif
`ifdef ILA_PROBE_CLAUSE
    ,
    output wire [15:0] ila_clause_a,
    output wire [15:0] ila_clause_b
`endif
`ifdef ILA_PROBE_VOTE
    ,
    output wire [15:0] ila_vote_a,
    output wire [15:0] ila_vote_b
`endif
`ifdef ILA_PROBE_ARGMAX
    ,
    output wire [15:0] ila_argmax_a,   // {done, 3'b0, winner_out[3:0], 1'b0, debug_adr[6:0]}
    output wire [15:0] ila_argmax_b    // {5'b0, current_max[10:0]}
`endif
);

    // ── Hotstate → Core control signals ─────────────────────────────
    wire        start_clause, vote_rst;

    // ── Core → Hotstate feedback signals ────────────────────────────
    wire        clause_done, fire, is_pos;
    wire [3:0]  class_idx;
    wire [6:0]  clause_strength;

    // ── Vote totals from core → hotstate argmax ──────────────────────
    wire signed [10:0] v_out_0, v_out_1, v_out_2, v_out_3, v_out_4;
    wire signed [10:0] v_out_5, v_out_6, v_out_7, v_out_8, v_out_9;

    // ── Hotstate enable pulses → Core vote accumulators ─────────────
    wire v0_up, v0_dn, v1_up, v1_dn, v2_up, v2_dn, v3_up, v3_dn, v4_up, v4_dn;
    wire v5_up, v5_dn, v6_up, v6_dn, v7_up, v7_dn, v8_up, v8_dn, v9_up, v9_dn;

    // ── Winner from hotstate argmax ──────────────────────────────────
    wire [3:0]  winner_out;
    wire [10:0] ctrl_current_max;
    wire [37:0] ctrl_states_full;

    // ── Hotstate clause sequencer ────────────────────────────────────
    tm_seq_controller ctrl (
        .clk              (clk),
        .rst              (rst),
        .go               (go),
        .fire             (fire),
        .is_pos           (is_pos),
        .clause_done      (clause_done),
        .clause_strength  (clause_strength),
        .class_idx        (class_idx),
        .v_out_0          (v_out_0),
        .v_out_1          (v_out_1),
        .v_out_2          (v_out_2),
        .v_out_3          (v_out_3),
        .v_out_4          (v_out_4),
        .v_out_5          (v_out_5),
        .v_out_6          (v_out_6),
        .v_out_7          (v_out_7),
        .v_out_8          (v_out_8),
        .v_out_9          (v_out_9),
        .start_clause     (start_clause),
        .vote_rst         (vote_rst),
        .v0_up(v0_up), .v0_dn(v0_dn),
        .v1_up(v1_up), .v1_dn(v1_dn),
        .v2_up(v2_up), .v2_dn(v2_dn),
        .v3_up(v3_up), .v3_dn(v3_dn),
        .v4_up(v4_up), .v4_dn(v4_dn),
        .v5_up(v5_up), .v5_dn(v5_dn),
        .v6_up(v6_up), .v6_dn(v6_dn),
        .v7_up(v7_up), .v7_dn(v7_dn),
        .v8_up(v8_up), .v8_dn(v8_dn),
        .v9_up(v9_up), .v9_dn(v9_dn),
        .done             (done),
        .winner_out       (winner_out),
        .current_max      (ctrl_current_max),
        .debug_adr        (ctrl_debug_adr),
        .states_out       (ctrl_states_full),
        .ready            (ctrl_ready),
        .lhs_out          (),
        .jmp_flag_out     (),
        .jmp_bus_out      (),
        .br_out           (),
        .fj_out           (),
        .next_pc          (),
        .state_capture    ()
    );

    // ── Enable-pulse inference core ──────────────────────────────────
    tm_core_v2 core (
        .clk              (clk),
        .rst              (rst),
        .img_waddr        (img_waddr),
        .img_wdata        (img_wdata),
        .img_wen          (img_wen),
        .start_clause     (start_clause),
        .vote_rst         (vote_rst),
        .v0_up(v0_up), .v0_dn(v0_dn),
        .v1_up(v1_up), .v1_dn(v1_dn),
        .v2_up(v2_up), .v2_dn(v2_dn),
        .v3_up(v3_up), .v3_dn(v3_dn),
        .v4_up(v4_up), .v4_dn(v4_dn),
        .v5_up(v5_up), .v5_dn(v5_dn),
        .v6_up(v6_up), .v6_dn(v6_dn),
        .v7_up(v7_up), .v7_dn(v7_dn),
        .v8_up(v8_up), .v8_dn(v8_dn),
        .v9_up(v9_up), .v9_dn(v9_dn),
        .clause_done      (clause_done),
        .fire             (fire),
        .is_pos           (is_pos),
        .class_idx        (class_idx),
        .clause_strength  (clause_strength),
        .v_out_0          (v_out_0),
        .v_out_1          (v_out_1),
        .v_out_2          (v_out_2),
        .v_out_3          (v_out_3),
        .v_out_4          (v_out_4),
        .v_out_5          (v_out_5),
        .v_out_6          (v_out_6),
        .v_out_7          (v_out_7),
        .v_out_8          (v_out_8),
        .v_out_9          (v_out_9),
        .fire_count       (fire_count),
        .dbg_v0(vote_0), .dbg_v1(vote_1), .dbg_v2(vote_2),
        .dbg_v3(vote_3), .dbg_v4(vote_4), .dbg_v5(vote_5),
        .dbg_v6(vote_6), .dbg_v7(vote_7), .dbg_v8(vote_8), .dbg_v9(vote_9),
        .dbg_clause0_viol  (clause0_viol),
        .dbg_clause0_fired (clause0_fired),
        .dbg_rom16         (rom16)
    `ifdef ILA_PROBE_ROM
        , .ila_rom_addr(ila_rom_addr), .ila_rom_data(ila_rom_data)
`endif
    `ifdef ILA_PROBE_CLAUSE
        , .ila_clause_a(ila_clause_a), .ila_clause_b(ila_clause_b)
`endif
    `ifdef ILA_PROBE_VOTE
        , .ila_vote_a(ila_vote_a), .ila_vote_b(ila_vote_b)
`endif
    );

`ifdef ILA_PROBE_ARGMAX
    // ARGMAX PROBE (plans/bugs.md). The last stage standing: ROM, clause
    // pipeline and vote accumulator have all been measured correct on hardware
    // that misclassifies, while the winner comes out wrong -- so the fault is in
    // this nine-compare scan.
    //
    // Sampled EVERY cycle, not per event, and triggered on `done`: the scan runs
    // immediately before done asserts, so the 128 pre-trigger samples hold it
    // whole, with the program counter (debug_adr) identifying each compare. That
    // is why capture is NOT gated here -- the interesting thing is the cycle-by-
    // cycle sequence, including the cycles where current_max fails to update.
    reg [15:0] ila_argmax_a_q, ila_argmax_b_q;
    always @(posedge clk) begin
        // Bit 7 flags "the PC is inside the argmax scan" (pc >= 56; the scan runs
        // 56..88, see sim_argmax_*.txt). The ILA keeps only PRE-trigger samples,
        // so with a free-running capture the 128-deep buffer holds whatever
        // happened to precede the trigger -- in practice the clause-wait loop,
        // over and over. Gating capture on this bit means the buffer can ONLY
        // contain argmax cycles, which makes the capture independent of exactly
        // when the trigger fires.
        ila_argmax_a_q <= {done, 3'b000, winner_out,
                           (ctrl_debug_adr >= 7'd56), ctrl_debug_adr};
        ila_argmax_b_q <= {5'b00000, ctrl_current_max};
    end
    assign ila_argmax_a = ila_argmax_a_q;
    assign ila_argmax_b = ila_argmax_b_q;
`endif

    assign result          = winner_out;
    assign ctrl_states_out = ctrl_states_full;

    assign core_state      = core.state;
    assign core_clause_idx = core.clause_idx;
    assign dbg_clause_done = clause_done;

endmodule
