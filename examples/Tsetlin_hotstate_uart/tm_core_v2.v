// tm_core_v2.v - Simplified TM inference core (external clause dispatch)
//
// Interface change from tm_core.v:
//   - start/core_done replaced by per-clause handshake:
//       start_clause (in, pulse), clause_done (out, pulse)
//   - vote_rst (in, pulse): reset all vote accumulators and clause counter
//   - fire, is_pos, class_idx (out, stable until next start_clause):
//       clause results read by tm_seq_controller for enable-pulse dispatch
//   - v{0..9}_{up/dn} (in, 1-cycle pulses from hotstate):
//       weighted vote accumulation (weight = clause_output latched at clause_done)
//   - v_out_0..v_out_9 (out, signed 11-bit): vote totals exposed for hotstate argmax
//
// Voting:  v[N] += clause_output (weighted, LF-viol) when vN_up fires
//          v[N] -= clause_output                      when vN_dn fires
// The hotstate gates these pulses with fire, so tm_core_v2 applies them
// unconditionally.

`include "gen/tm_config.vh"

module tm_core_v2 #(
    parameter N_CLAUSES = `TM_N_CLAUSES,
    parameter N_CLASSES = `TM_N_CLASSES,
    parameter N_BYTES   = `TM_INPUT_BYTES,
    parameter LF        = `TM_LF,
    parameter N_CPC     = `TM_N_CLAUSES / `TM_N_CLASSES,
    parameter POS_END   = N_CPC / 2 - 1,
    parameter CLAUSE_W  = $clog2(N_CLAUSES),
    parameter CPC_W     = $clog2(N_CPC),
    parameter ROM_DEPTH = N_BYTES * N_CLAUSES,
    parameter ROM_AW    = $clog2(ROM_DEPTH),
    parameter FC_W      = $clog2(N_CLAUSES + 1)
) (
    input  wire        clk, rst,

    // Image write port (BRAM load)
    input  wire [6:0]  img_waddr,
    input  wire [7:0]  img_wdata,
    input  wire        img_wen,

    // Clause handshake from/to tm_seq_controller
    input  wire        start_clause,  // pulse: begin processing next clause
    input  wire        vote_rst,      // pulse: reset votes and clause counter

    // Enable pulses from tm_seq_controller (one per class × direction)
    input  wire        v0_up,  v0_dn,
    input  wire        v1_up,  v1_dn,
    input  wire        v2_up,  v2_dn,
    input  wire        v3_up,  v3_dn,
    input  wire        v4_up,  v4_dn,
    input  wire        v5_up,  v5_dn,
    input  wire        v6_up,  v6_dn,
    input  wire        v7_up,  v7_dn,
    input  wire        v8_up,  v8_dn,
    input  wire        v9_up,  v9_dn,

    // Clause results (stable from clause_done until next start_clause)
    output wire        clause_done,
    output wire        fire,
    output wire        is_pos,
    output wire [3:0]  class_idx,

    // Clause strength: LF - violations (0-LF), stable from clause_done until next start_clause
    output wire [6:0]  clause_strength,

    // Vote totals exposed for hotstate argmax
    output wire signed [10:0] v_out_0, v_out_1, v_out_2, v_out_3, v_out_4,
    output wire signed [10:0] v_out_5, v_out_6, v_out_7, v_out_8, v_out_9,

    output reg  [FC_W-1:0] fire_count,

    // Debug
    output wire signed [10:0] dbg_v0, dbg_v1, dbg_v2, dbg_v3, dbg_v4,
    output wire signed [10:0] dbg_v5, dbg_v6, dbg_v7, dbg_v8, dbg_v9,
    output reg  [9:0]  dbg_clause0_viol,
    output reg         dbg_clause0_fired,
    output wire [7:0]  dbg_rom16
`ifdef ILA_PROBE_ROM
    ,
    output wire [15:0] ila_rom_addr,   // {rd_valid, rom_addr[14:0]}
    output wire [15:0] ila_rom_data    // {inv_mask_byte, mask_byte}
`endif
`ifdef ILA_PROBE_CLAUSE
    ,
    output wire [15:0] ila_clause_a,   // {vld, 3'b0, class_lut[3:0], clause_idx[7:0]}
    output wire [15:0] ila_clause_b    // {5'b0, fire, viol_total[9:0]}
`endif
`ifdef ILA_PROBE_VOTE
    ,
    output wire [15:0] ila_vote_a,   // {vld, up, dn, 1'b0, class[3:0], clause_idx[7:0]}
    output wire [15:0] ila_vote_b    // {5'b0, vote value AFTER the update}
`endif
);

    // ── ROM and input BRAM ──────────────────────────────────────────────
    reg [7:0] include_mask_rom     [0:ROM_DEPTH-1];
    reg [7:0] include_inv_mask_rom [0:ROM_DEPTH-1];
    initial begin
        $readmemh("gen/include_mask.hex",     include_mask_rom);
        $readmemh("gen/include_inv_mask.hex", include_inv_mask_rom);
    end

    reg [7:0] input_bram [0:N_BYTES-1];
    always @(posedge clk) if (img_wen) input_bram[img_waddr] <= img_wdata;

    // ── State machine ───────────────────────────────────────────────────
    localparam S_IDLE=3'd0, S_CLAUSE_RD=3'd1, S_CLAUSE_PROC=3'd2;
    localparam S_CLAUSE_DONE=3'd3;
    // fsm_encoding="none": preventive fix carried over from examples/webserver's
    // response_streamer.v (see its own comment + plans/bugs.md item 7). That
    // hand-written case-based FSM synthesized and simulated cleanly but never
    // advanced on real Tang Nano hardware -- root-caused to yosys's automatic
    // FSM extraction/re-encoding pass (part of synth_gowin's default flow)
    // mis-handling the state register. This `state` register has the same
    // shape (plain reg driving a `case` in an always block, synthesized via
    // the same synth_gowin flow) so it's opted out proactively rather than
    // waiting to hit the same silent-on-hardware failure mode.
    (* fsm_encoding = "none" *) reg [2:0] state;

    // ── Clause sequencing ───────────────────────────────────────────────
    reg [CLAUSE_W-1:0] clause_idx;
    reg [6:0]          byte_cnt;
    reg [9:0]          viol_accum;
    reg [ROM_AW-1:0]   rom_addr;
    reg                pipe_valid;
    reg [7:0]          p_mask_byte, p_mask_inv_byte, p_input_byte;

    // ── Clause result latches ───────────────────────────────────────────
    reg [6:0]  clause_output_reg;
    reg        fire_r, is_pos_r;
    reg [3:0]  class_idx_r;
    reg        clause_done_r;

    // ── Vote registers (signed 11-bit) ──────────────────────────────────
    reg signed [10:0] v0, v1, v2, v3, v4, v5, v6, v7, v8, v9;

    // ── Combinatorial clause evaluation ────────────────────────────────
    function [3:0] popcount8;
        input [7:0] in; integer j;
        begin popcount8=4'd0;
            for(j=0;j<8;j=j+1) popcount8=popcount8+{3'd0,in[j]};
        end
    endfunction

    wire [9:0] viol_inc;
    assign viol_inc = {6'd0, popcount8(
        (~p_input_byte & p_mask_byte) | (p_input_byte & p_mask_inv_byte))};
    wire [9:0] viol_total;
    assign viol_total = viol_accum + viol_inc;
    wire [6:0] clause_output;
    assign clause_output = (viol_total < LF) ? (7'(LF) - viol_total[6:0]) : 7'd0;

    // class_lut: which class does clause_idx belong to?
    reg [$clog2(N_CLASSES)-1:0] class_lut;
    wire [CLAUSE_W-1:0] class_boundary [0:N_CLASSES];
    genvar ci;
    generate
        for (ci = 0; ci < N_CLASSES; ci = ci + 1) begin : gen_cb
            assign class_boundary[ci] = ci * N_CPC;
        end
    endgenerate

    always @* begin
        if      (clause_idx < class_boundary[1]) class_lut = 'd0;
        else if (clause_idx < class_boundary[2]) class_lut = 'd1;
        else if (clause_idx < class_boundary[3]) class_lut = 'd2;
        else if (clause_idx < class_boundary[4]) class_lut = 'd3;
        else if (clause_idx < class_boundary[5]) class_lut = 'd4;
        else if (clause_idx < class_boundary[6]) class_lut = 'd5;
        else if (clause_idx < class_boundary[7]) class_lut = 'd6;
        else if (clause_idx < class_boundary[8]) class_lut = 'd7;
        else if (clause_idx < class_boundary[9]) class_lut = 'd8;
        else                                     class_lut = 'd9;
    end

    // is_pos: first half of each class's clauses are positive.
    // class_start_lut[i] = i * N_CPC (mod 2^CPC_W): N_CLASSES-entry ROM replaces
    // the class_lut * N_CPC hardware multiplier with a parameterized mux/LUT.
    wire [CPC_W-1:0] class_start_lut [0:N_CLASSES-1];
    genvar cls;
    generate
        for (cls = 0; cls < N_CLASSES; cls = cls + 1) begin : gen_csl
            assign class_start_lut[cls] = cls * N_CPC;
        end
    endgenerate
    wire [CPC_W-1:0] class_start_val = class_start_lut[class_lut];
    wire [CPC_W-1:0] clause_offset   = clause_idx[CPC_W-1:0] - class_start_val;
    wire             clause_is_pos   = (clause_offset <= POS_END[CPC_W-1:0]);

    // ── Main FSM ────────────────────────────────────────────────────────
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= S_IDLE;
            clause_idx      <= 'd0;
            byte_cnt        <= 7'd0;
            viol_accum      <= 10'd0;
            rom_addr        <= 'd0;
            pipe_valid      <= 1'b0;
            clause_done_r   <= 1'b0;
            fire_count      <= 'd0;
            fire_r          <= 1'b0;
            is_pos_r        <= 1'b0;
            class_idx_r     <= 4'd0;
            clause_output_reg <= 7'd0;
            p_mask_byte     <= 8'd0;
            p_mask_inv_byte <= 8'd0;
            p_input_byte    <= 8'd0;
            dbg_clause0_viol  <= 10'd0;
            dbg_clause0_fired <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (vote_rst) begin
                        clause_idx    <= 'd0;
                        fire_count    <= 'd0;
                        clause_done_r <= 1'b0;
                    end else if (start_clause) begin
                        clause_done_r <= 1'b0;
                        byte_cnt   <= 7'd0;
                        viol_accum <= 10'd0;
                        pipe_valid <= 1'b0;
                        rom_addr   <= clause_idx * N_BYTES;
                        state      <= S_CLAUSE_RD;
                    end
                end

                S_CLAUSE_RD: begin
                    p_mask_byte     <= include_mask_rom[rom_addr];
                    p_mask_inv_byte <= include_inv_mask_rom[rom_addr];
                    p_input_byte    <= input_bram[byte_cnt];
                    pipe_valid      <= 1'b1;
                    rom_addr        <= rom_addr + 'd1;
                    byte_cnt        <= 7'd1;
                    state           <= S_CLAUSE_PROC;
                end

                S_CLAUSE_PROC: begin
                    p_mask_byte     <= include_mask_rom[rom_addr];
                    p_mask_inv_byte <= include_inv_mask_rom[rom_addr];
                    p_input_byte    <= input_bram[byte_cnt];
                    if (pipe_valid) viol_accum <= viol_accum + viol_inc;
                    pipe_valid <= 1'b1;
                    if (byte_cnt == N_BYTES-1)
                        state <= S_CLAUSE_DONE;
                    else begin
                        rom_addr <= rom_addr + 'd1;
                        byte_cnt <= byte_cnt + 7'd1;
                    end
                end

                S_CLAUSE_DONE: begin
                    // Latch clause results for tm_seq_controller to read
                    clause_output_reg <= clause_output;
                    fire_r            <= (viol_total < LF);
                    is_pos_r          <= clause_is_pos;
                    class_idx_r       <= class_lut;

                    // Debug capture for clause 0
                    if (clause_idx == 'd0) begin
                        dbg_clause0_viol  <= viol_total;
                        dbg_clause0_fired <= (viol_total < LF);
                    end

                    // Accumulate fire count
                    if (viol_total < LF) fire_count <= fire_count + 'd1;

                    // Assert clause_done (level) - held until start_clause acks
                    clause_done_r <= 1'b1;

                    // Advance clause counter; always return to S_IDLE
                    clause_idx <= clause_idx + 'd1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // The probe blocks below sit HERE, not beside the ROM declarations, because
    // they reference clause_idx, viol_total, class_lut and v0..v9 -- all declared
    // above this point. yosys tolerates declaration-after-use; Icarus does not,
    // and a probe that cannot simulate cannot have its host-side model validated
    // against a known-good reference, which is the only way a probe earns trust.
`ifdef ILA_PROBE_ROM
    // ROM READBACK PROBE (plans/bugs.md: the GW2A-18C miscompute).
    //
    // Every other test on that bug eliminated a guess; this one answers the
    // question none of them asked -- is the ROM data arriving at the logic the
    // data that was stored? It exposes the address, both ROM bytes read at that
    // address, and a valid flag, so a captured trace can be diffed directly
    // against gen/include_{mask,inv_mask}.hex.
    //
    // The address is REGISTERED here rather than tapped raw, and that is the
    // whole trick: `p_mask_byte <= include_mask_rom[rom_addr]` latches the data
    // while rom_addr advances in the same always block, so probing rom_addr and
    // p_mask_byte together would pair an address with the PREVIOUS byte. Sampling
    // rom_addr into ila_rom_addr_q on that same edge makes the pair line up --
    // at T+1 both hold the values belonging to the read issued at T.
    //
    // rom_rd_q marks the cycles where a read actually happened; on any other
    // cycle p_mask_byte is stale while rom_addr may have moved, and the pair
    // would be a false mismatch. The host MUST ignore samples with it low.
    reg [ROM_AW-1:0] ila_rom_addr_q;
    reg              ila_rom_rd_q;
    always @(posedge clk) begin
        ila_rom_addr_q <= rom_addr;
        ila_rom_rd_q   <= (state == S_CLAUSE_RD) || (state == S_CLAUSE_PROC);
    end
    assign ila_rom_addr = {ila_rom_rd_q, ila_rom_addr_q};
    assign ila_rom_data = {p_mask_inv_byte, p_mask_byte};
`endif

`ifdef ILA_PROBE_CLAUSE
    // CLAUSE-ACCUMULATOR PROBE (plans/bugs.md). One stage downstream of
    // ILA_PROBE_ROM, which proved the ROM bytes arriving here are correct --
    // so the fault is in what this stage does WITH them, or later.
    //
    // Captures one sample per CLAUSE rather than per cycle: sampled when the FSM
    // reaches S_CLAUSE_DONE, which is where viol_total is final and fire/class
    // are latched. That makes 128 ILA samples cover 128 of the 200 clauses
    // instead of ~1.3 clauses, and it makes each sample directly comparable to a
    // software model -- viol_total is just
    //   sum over the clause's 98 bytes of popcount((~img & mask) | (img & inv))
    // which the host recomputes from gen/*.hex and the image it sent.
    //
    // Everything is sampled on the SAME edge, so the tuple is coherent:
    // clause_idx has not yet advanced (it increments in this same state), and
    // viol_total/class_lut are combinational off values that are stable here.
    reg        ila_cl_vld_q;
    reg [7:0]  ila_cl_idx_q;
    reg [9:0]  ila_cl_viol_q;
    reg        ila_cl_fire_q;
    reg [3:0]  ila_cl_class_q;
    always @(posedge clk) begin
        ila_cl_vld_q   <= (state == S_CLAUSE_DONE);
        ila_cl_idx_q   <= clause_idx;
        ila_cl_viol_q  <= viol_total;
        ila_cl_fire_q  <= (viol_total < LF);
        ila_cl_class_q <= class_lut;
    end
    assign ila_clause_a = {ila_cl_vld_q, 3'b000, ila_cl_class_q, ila_cl_idx_q};
    assign ila_clause_b = {5'b00000, ila_cl_fire_q, ila_cl_viol_q};
`endif

`ifdef ILA_PROBE_VOTE
    // VOTE-ACCUMULATOR PROBE (plans/bugs.md). The stage after the clause
    // pipeline, which ILA_PROBE_CLAUSE showed is correct even on builds that
    // misclassify -- so the fault is here or in the argmax past it.
    //
    // This stage is unlike the ones before it: the votes are driven by TWENTY
    // separate enable pulses (v0_up/v0_dn .. v9_up/v9_dn) produced by
    // tm_seq_controller, a hotstate machine. A pulse that fails to arrive, or
    // arrives for the wrong class, suppresses exactly one class's tally -- which
    // is the symptom. So the probe captures the pulses themselves, not just the
    // result.
    //
    // One sample per VOTE UPDATE (gate the ILA on bit 31), carrying which class
    // was updated, in which direction, on which clause, and the resulting
    // accumulator value. The value is read one cycle later, when the update has
    // landed: ila_v_cls_q then names the class updated on the previous edge and
    // the mux below reads that class's POST-update value, so each sample is a
    // complete before/after record the host can replay.
    wire [19:0] ila_vpulse = {v9_dn,v9_up, v8_dn,v8_up, v7_dn,v7_up, v6_dn,v6_up,
                              v5_dn,v5_up, v4_dn,v4_up, v3_dn,v3_up, v2_dn,v2_up,
                              v1_dn,v1_up, v0_dn,v0_up};
    reg  [3:0] ila_v_cls_c;
    reg        ila_v_up_c, ila_v_dn_c;
    integer    ila_vi;
    always @* begin
        ila_v_cls_c = 4'd0; ila_v_up_c = 1'b0; ila_v_dn_c = 1'b0;
        for (ila_vi = 0; ila_vi < 10; ila_vi = ila_vi + 1) begin
            if (ila_vpulse[2*ila_vi])     begin ila_v_cls_c = ila_vi[3:0]; ila_v_up_c = 1'b1; end
            if (ila_vpulse[2*ila_vi + 1]) begin ila_v_cls_c = ila_vi[3:0]; ila_v_dn_c = 1'b1; end
        end
    end
    reg        ila_v_vld_q, ila_v_up_q, ila_v_dn_q;
    reg  [3:0] ila_v_cls_q;
    reg  [7:0] ila_v_clause_q;
    always @(posedge clk) begin
        ila_v_vld_q    <= |ila_vpulse;
        ila_v_cls_q    <= ila_v_cls_c;
        ila_v_up_q     <= ila_v_up_c;
        ila_v_dn_q     <= ila_v_dn_c;
        ila_v_clause_q <= clause_idx;
    end
    wire signed [10:0] ila_v_sel =
        (ila_v_cls_q == 4'd0) ? v0 : (ila_v_cls_q == 4'd1) ? v1 :
        (ila_v_cls_q == 4'd2) ? v2 : (ila_v_cls_q == 4'd3) ? v3 :
        (ila_v_cls_q == 4'd4) ? v4 : (ila_v_cls_q == 4'd5) ? v5 :
        (ila_v_cls_q == 4'd6) ? v6 : (ila_v_cls_q == 4'd7) ? v7 :
        (ila_v_cls_q == 4'd8) ? v8 : v9;
    assign ila_vote_a = {ila_v_vld_q, ila_v_up_q, ila_v_dn_q, 1'b0,
                         ila_v_cls_q, ila_v_clause_q};
    assign ila_vote_b = {5'b00000, ila_v_sel};
`endif

    // ── Vote update (enable-pulse driven, parallel to FSM) ─────────────
    // clause_output_reg is stable from clause_done until next start_clause.
    // The hotstate gates these pulses with fire, so no gating needed here.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            v0<=11'd0; v1<=11'd0; v2<=11'd0; v3<=11'd0; v4<=11'd0;
            v5<=11'd0; v6<=11'd0; v7<=11'd0; v8<=11'd0; v9<=11'd0;
        end else if (vote_rst) begin
            v0<=11'd0; v1<=11'd0; v2<=11'd0; v3<=11'd0; v4<=11'd0;
            v5<=11'd0; v6<=11'd0; v7<=11'd0; v8<=11'd0; v9<=11'd0;
        end else begin
            if (v0_up) v0 <= v0 + {4'd0, clause_output_reg};
            if (v0_dn) v0 <= v0 - {4'd0, clause_output_reg};
            if (v1_up) v1 <= v1 + {4'd0, clause_output_reg};
            if (v1_dn) v1 <= v1 - {4'd0, clause_output_reg};
            if (v2_up) v2 <= v2 + {4'd0, clause_output_reg};
            if (v2_dn) v2 <= v2 - {4'd0, clause_output_reg};
            if (v3_up) v3 <= v3 + {4'd0, clause_output_reg};
            if (v3_dn) v3 <= v3 - {4'd0, clause_output_reg};
            if (v4_up) v4 <= v4 + {4'd0, clause_output_reg};
            if (v4_dn) v4 <= v4 - {4'd0, clause_output_reg};
            if (v5_up) v5 <= v5 + {4'd0, clause_output_reg};
            if (v5_dn) v5 <= v5 - {4'd0, clause_output_reg};
            if (v6_up) v6 <= v6 + {4'd0, clause_output_reg};
            if (v6_dn) v6 <= v6 - {4'd0, clause_output_reg};
            if (v7_up) v7 <= v7 + {4'd0, clause_output_reg};
            if (v7_dn) v7 <= v7 - {4'd0, clause_output_reg};
            if (v8_up) v8 <= v8 + {4'd0, clause_output_reg};
            if (v8_dn) v8 <= v8 - {4'd0, clause_output_reg};
            if (v9_up) v9 <= v9 + {4'd0, clause_output_reg};
            if (v9_dn) v9 <= v9 - {4'd0, clause_output_reg};
        end
    end

    // ── Output assignments ──────────────────────────────────────────────
    assign clause_done     = clause_done_r;
    assign fire            = fire_r;
    assign is_pos          = is_pos_r;
    assign class_idx       = class_idx_r;
    assign clause_strength = clause_output_reg;

    assign v_out_0 = v0; assign v_out_1 = v1; assign v_out_2 = v2;
    assign v_out_3 = v3; assign v_out_4 = v4; assign v_out_5 = v5;
    assign v_out_6 = v6; assign v_out_7 = v7; assign v_out_8 = v8;
    assign v_out_9 = v9;

    assign dbg_v0=v0; assign dbg_v1=v1; assign dbg_v2=v2;
    assign dbg_v3=v3; assign dbg_v4=v4; assign dbg_v5=v5;
    assign dbg_v6=v6; assign dbg_v7=v7; assign dbg_v8=v8; assign dbg_v9=v9;
    assign dbg_rom16 = include_mask_rom[16];

endmodule
