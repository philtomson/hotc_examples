`timescale 1ns/1ps

// Time-Division Multiplexing (TDM) Router for the NPU.
// Hot-swaps inputs to the shared ws_conv_core_gowin between Layer 1
// and Layer 2 based on the layer_state flag. Demultiplexes and 
// gates the output valid signals.

module tdm_npu_router (
    input  logic        clk,
    input  logic        rst,
    
    // Control Flag (from Master FSM)
    input  logic        layer_state, // 0 = Conv1, 1 = Conv2
    
    // Conv1 Inputs
    input  logic        conv1_compute_en,
    input  logic [7:0]  conv1_data_in [0:3][0:2][0:2],
    input  logic [7:0]  conv1_weight_in [0:3][0:2][0:2],
    input  logic [31:0] conv1_bias_in,
    
    // Conv2 Inputs
    input  logic        conv2_compute_en,
    input  logic        conv2_accumulate,
    input  logic [7:0]  conv2_data_in [0:3][0:2][0:2],
    input  logic [7:0]  conv2_weight_in [0:3][0:2][0:2],
    input  logic [31:0] conv2_bias_in,

    // FIX (2026-08-21, troubleshooting_progress.md item (p)): a SEPARATE
    // input specifically for conv2_valid_out_gated's own sampling below --
    // do NOT reuse conv2_accumulate for this. conv2_accumulate (fed
    // conv2_accumulate_d at the instantiation site) is correctly timed for
    // mux_accumulate's OWN use (selects ws_conv_core_gowin's fold-vs-fresh
    // branch, confirmed correct via an isolated Verilator testbench of that
    // module) -- but a register's newly-written value isn't visible until
    // the cycle AFTER the write, so gating the OUTPUT read on that same
    // signal samples one cycle too early, latching the pre-fold partial
    // into pool2 on every single pixel. Root-caused via a probe-only
    // hardware experiment (extra delay register on the ILA capture path
    // only, no datapath change): npu_out sampled one cycle later matched
    // golden 1824/1824 exactly, every filter -- see item (p) for the full
    // derivation. This port carries that same extra-delayed signal
    // (conv2_accumulate_dd, one MORE cycle behind conv2_accumulate_d) into
    // the real datapath gate.
    input  logic        conv2_accumulate_gate,
    
    // Shared NPU Output
    output logic [7:0]  npu_out,
    
    // Demultiplexed Valid Signals
    output logic        conv1_valid_out,
    output logic        conv2_valid_out_gated,

    // Debug tap: the raw (ungated) valid_out from the shared MAC core,
    // for tracing the conv2_valid_out_gated pulse-count investigation --
    // see hotc_microcnn_hotstate_classifier_bug_hunt.md. Unconditional
    // (not `ifdef`-guarded) since it's a single harmless extra wire.
    output logic        dbg_npu_valid,

    // Debug taps (2026-08-20, uncommitted): ws_conv_core_gowin's own
    // mac_sum_dbg/partial_sum_dbg, passed straight through -- see that
    // module's port comment for why (tracing the "gated(N)==golden(N-1)"
    // stale-fold hazard, troubleshooting_progress.md Open Problem #1).
    output logic signed [31:0] dbg_mac_sum,
    output logic signed [31:0] dbg_partial_sum
);

    // TDM MUX Routing Logic
    logic        mux_compute_en;
    logic        mux_accumulate;
    logic [7:0]  mux_data_in [0:3][0:2][0:2];
    logic [7:0]  mux_weight_in [0:3][0:2][0:2];
    logic [31:0] mux_bias_in;
    logic [3:0]  mux_shift_val;

    always_comb begin
        if (layer_state == 1'b0) begin
            // Route Conv1 Signals
            mux_compute_en = conv1_compute_en;
            mux_accumulate = 1'b0;                // Conv1 does not accumulate
            mux_data_in    = conv1_data_in;      
            mux_weight_in  = conv1_weight_in;   
            mux_bias_in    = conv1_bias_in;
            mux_shift_val  = 4'd9;
        end else begin
            // Route Conv2 Signals
            mux_compute_en = conv2_compute_en;  
            mux_accumulate = conv2_accumulate;  
            mux_data_in    = conv2_data_in;      
            mux_weight_in  = conv2_weight_in;
            mux_bias_in    = conv2_bias_in;
            mux_shift_val  = 4'd8;
        end
    end

    // Shared NPU Core Instantiation
    logic npu_valid;

    ws_conv_core_gowin #(
        .NUM_CORES(4)
    ) u_npu (
        .clk(clk),
        .rst(rst),
        .compute_en(mux_compute_en),
        .accumulate(mux_accumulate),
        .data_in(mux_data_in),
        .weight_in(mux_weight_in),
        .bias_in(mux_bias_in),
        .shift_val(mux_shift_val), 
        .mac_out(npu_out),
        .valid_out(npu_valid),
        .mac_sum_dbg(dbg_mac_sum),
        .partial_sum_dbg(dbg_partial_sum)
    );

    // Output Demultiplexer & Validation Gate
    
    // Conv1 gets the valid signal directly when active
    assign conv1_valid_out = npu_valid & (layer_state == 1'b0);

    // Gate polarity: npu_valid & conv2_accumulate (conv2_accumulate is wired
    // to conv2_accumulate_d one level up in npu_top_hotstate.sv, i.e. the
    // ONE-CYCLE-DELAYED copy of the one_shot `accumulate`). This is the
    // polarity actually built and measured on hardware 2026-08-20 (see
    // troubleshooting_progress.md, "hazard caught live" table): a dedicated
    // {dbg_npu_valid, conv2_npu_valid_gated, accumulate_raw, accumulate_d}
    // probe showed npu_valid pulses HIGH for 2 consecutive cycles per real
    // output pixel (pre-fold partial, then post-fold folded value) and this
    // gate passes ONLY the second (accumulate_d=1) and blocks the first
    // (accumulate_d=0), 4/4 repeats identical -- i.e. this polarity is
    // hardware-confirmed correct at the pulse-selection level; the residual
    // bug is the gated VALUE occasionally being stale, not which pulse gets
    // through.
    //
    // A same-day edit briefly flipped this to `!conv2_accumulate`, reasoning
    // from the reference (non-hotstate) design's own polarity by paper
    // derivation alone -- but the reference's `accumulate` signal has
    // different timing semantics (not a one_shot delayed-by-one pulse), and
    // by the same cycle-by-cycle derivation used above, `!conv2_accumulate_d`
    // would PASS the pre-fold partial (cycle where accumulate_d=0) and BLOCK
    // the folded result (accumulate_d=1) -- i.e. it directly contradicts the
    // already-measured hardware behavior above and would reintroduce the
    // exact bug Fixed-table row #3 already fixed. Reverted here before a
    // rebuild, per the project's own methodology note ("measure, don't just
    // reason" -- troubleshooting_progress.md). Do not re-flip without a new
    // hardware measurement that specifically contradicts the table above.
    //
    // FIX (2026-08-21, item (p)): the paragraph above was right that pulse
    // SELECTION (which of npu_valid's 2 cycles) was already correct -- the
    // remaining bug was exactly the "gated VALUE occasionally being stale"
    // note above, now fully explained: `mac_out`'s register write triggered
    // by accumulate_d isn't VISIBLE until the following cycle, so sampling
    // on accumulate_d itself is one cycle early regardless of which pulse
    // it picks. Switched the qualifier from `conv2_accumulate` (still
    // correctly used, unchanged, by `mux_accumulate` above) to the new
    // `conv2_accumulate_gate` port -- one more cycle of delay, dedicated to
    // this consumer only.
    assign conv2_valid_out_gated = npu_valid & (layer_state == 1'b1) & conv2_accumulate_gate;

    assign dbg_npu_valid = npu_valid;

endmodule