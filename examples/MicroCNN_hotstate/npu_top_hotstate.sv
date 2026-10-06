`include "main_controller_params.vh"
`include "ila_config.vh"

`timescale 1ns/1ps

// Hotstate-based NPU top-level for the MicroCNN accelerator.
// DROP-IN REPLACEMENT for npu_top.sv (same port interface).
//
// Replaces master_pipeline_fsm + conv1_fsm + conv2_fsm + fc1_fsm + fc2_fsm
// (~850 lines of Verilog FSM code) with a single hotstate microcode engine
// generated from main_controller.c (~170 microcode instructions).
//
// All datapath hardware is unchanged from the original design:
//   - hotstate engine runs at system_clk (always on, like master_pipeline_fsm)
//   - datapath (line buffers, NPU arrays, ROMs, RAMs) runs at npu_clk (gated
//     via DCS in top.sv using the npu_sleep output)
//   - img_ram is instantiated in top.sv (shared with soc_controller writes)

module npu_top_hotstate (
    input  logic        system_clk, // continuous clock (hotstate + master logic)
    input  logic        npu_clk,    // gated clock (datapath)
    input  logic        rst,        // npu_software_rst from soc_controller

    // -- Image RAM Interface (img_ram lives in top.sv) --
    output logic [9:0]  img_addr,
    output logic        img_en,
    input  logic [23:0] img_rdata,  // {R, G, B}

    output logic [2:0]  class_idx,
    output logic        npu_sleep,   // sleep signal to the clock gate
    output logic        npu_done

    // -- Trace probe outputs (on-chip logic analyzer, top_hotstate.sv) --
    // Internal signals exposed while bringing this example up on
    // hardware. Compiled out: ILA_ENABLE is never defined (see
    // ila_config.vh).
`ifdef ILA_ENABLE
    ,
    output logic        trace_fc2_valid_out,
    output logic [2:0]  trace_fc2_current_neuron,
    output logic signed [31:0] trace_fc2_sum,
    output logic [4:0]  trace_layer_phase,
    output logic [2:0]  trace_predicted_class,
    output logic signed [31:0] trace_psum_lane0,
    output logic        trace_system_done,
    output logic        trace_mult_ce,
    output logic        trace_mult_clear,
    output logic        trace_param_en,
    output logic        trace_fc2_param_en_d,
    output logic [63:0] trace_fc2_ram_rdata,
    output logic        trace_fc1_valid_out,
    output logic [4:0]  trace_fc1_current_neuron,
    output logic [7:0]  trace_fc2_wdata,
    output logic [5:0]  trace_fc1_ram_raddr,
    output logic [11:0] trace_pool2_valid_cnt,
    output logic        trace_conv2_channel_done_pulse,
    output logic        trace_conv2_channel_done_pulse_d,
    output logic        trace_conv2_channel_done_pulse_dd,
    output logic        trace_conv2_filter_reset_pulse,
    output logic [7:0]  trace_pool2_col_count,
    output logic         trace_pool2_row_parity,
    output logic [7:0]  trace_pool2_top_left,
    output logic [7:0]  trace_pool2_bottom_left,
    output logic         trace_pool2_reset_valid_overlap,
    output logic [15:0] trace_conv2_valid_gated_cnt,
    output logic        trace_accumulate,          // hotstate's raw one_shot output
    output logic        trace_conv2_accumulate_d,  // 1 more cycle delayed, fed to the router
    output logic        trace_dbg_npu_valid,       // router's raw (ungated) valid
    output logic        trace_conv2_npu_valid_gated,
    output logic        trace_layer_state,
    output logic        trace_conv2_start_pulse,
    output logic [7:0]  trace_c2_pixel_cnt,
    output logic [7:0]  trace_conv2_start_pulse_cnt,
    output logic        trace_conv1_shift_en,
    output logic [4:0]  trace_c2_lb_row,
    output logic [4:0]  trace_c2_lb_col,
    output logic        trace_system_done_pulse,
    output logic        trace_conv2_early_stop,
    output logic [7:0]  trace_pool2_out,
    output logic        trace_pool2_valid,
    output logic [3:0]  trace_c2_filter_cnt,
    output logic [7:0]  trace_npu_out,
    output logic [7:0]  trace_pool1_out,
    output logic        trace_pool1_valid,
    output logic [2:0]  trace_c1_filter_cnt,
    output logic signed [31:0] trace_mac_sum,
    output logic signed [31:0] trace_partial_sum,

    output logic [7:0]  trace_conv2_ram_raddr,
    output logic [7:0]  trace_ram_rdata0,       // channel-0 RAM read data
    output logic         trace_conv2_shift_en,   // raw (pre-delay) shift_en
    output logic         trace_conv2_shift_en_d, // delayed, drives u_lb2
    output logic [7:0]  trace_lb2_newest0,       // buffer-A ch0's newest shifted pixel (window_out[2][2])

    output logic [3:0]  trace_filter_idx_w,
    output logic         trace_conv2_chunk_sel_d,
    output logic signed [31:0] trace_conv2_bias_read_data
`endif
);

    // ── Layer completion flags / start signals ───────────────────────
    logic conv1_layer_done, conv2_layer_done, fc1_layer_done, fc2_layer_done;
    logic layer_state, system_done;

    // ── 1-cycle conv1_start pulse on reset release ───────────────────
    // Matches the original master_pipeline_fsm, which auto-starts
    // (IDLE → RUN_CONV1) as soon as npu_software_rst deasserts.
    //
    // BUG (fixed): the previous version registered conv1_start_signal as
    // `<= ~rst_d`, which is correct for exactly one cycle but then stays
    // permanently stuck HIGH forever after (nothing ever ANDs it back
    // against the live `rst`) instead of falling back to 0 — so every
    // run after the very first power-on inference saw a `conv1_start`
    // extern input that was already asserted throughout the ENTIRE prior
    // run, not a fresh 1-cycle pulse. Found via real hardware: the first
    // hw-infer after programming classified correctly, every subsequent
    // one (different image, different true label) returned the same
    // wrong class 7 — while flashing the vendor Gowin-IDE bitstream
    // (same datapath, original master_pipeline_fsm control plane) and
    // running the identical sequence of images classified each one
    // correctly, isolating the bug to this control-plane signal.
    //
    // Fix, take 2: a clean-but-*wide* pulse. main_controller.c's IDLE
    // state (layer_phase==0) is a 2-cycle polling loop --
    // `conv1_start_latched = conv1_start;` (sample, cycle A) then
    // `if (conv1_start_latched) layer_phase = 1;` (check, cycle B),
    // looping back to sample again if the check misses. An exact
    // 1-cycle-wide pulse (either the same-edge-race version tried first,
    // or a clean 2-flop version) has ~50% odds of landing on a "check"
    // cycle instead of a "sample" cycle and being missed outright --
    // confirmed on real hardware: both attempts regressed to a complete
    // NPU timeout on *every* run, including the first (previously
    // reliable). Hold the pulse for COUNT cycles instead, wide enough to
    // guarantee straddling at least one sample cycle regardless of poll
    // phase, but still bounded well short of a full inference (~67ms) --
    // conv1_start is only ever read in phase 0 (grep confirms no other
    // reference in main_controller.c), so once caught it can't affect
    // anything later; deasserting before that phase is even revisited
    // avoids reproducing the original stuck-high bug's suspected role in
    // corrupting later phases of the run.
    localparam int CONV1_START_PULSE_CYCLES = 8;
    logic [3:0] conv1_start_cnt;
    logic conv1_start_active;
    always_ff @(posedge system_clk or posedge rst) begin
        if (rst) begin
            conv1_start_cnt    <= CONV1_START_PULSE_CYCLES[3:0];
            conv1_start_active <= 1'b1;
        end else if (conv1_start_active) begin
            if (conv1_start_cnt == 4'd0) conv1_start_active <= 1'b0;
            else                         conv1_start_cnt    <= conv1_start_cnt - 4'd1;
        end
    end
    logic conv1_start_signal;
    assign conv1_start_signal = conv1_start_active;

    // ── Hotstate control engine (runs at system_clk, like master_fsm) ─
    main_controller u_hotstate (
        .clk                  (system_clk),
        .rst                  (rst),
        .conv1_layer_done     (conv1_layer_done),
        .conv2_layer_done     (conv2_layer_done),
        .fc1_layer_done       (fc1_layer_done),
        .fc2_layer_done       (fc2_layer_done),
        .conv1_start          (conv1_start_signal),
        // State variable outputs — drive the datapath directly
        .img_addr             (img_addr),
        .img_en               (img_en),
        .weight_en            (conv1_weight_en),
        .bias_en              (conv1_bias_en),
        .shift_en             (conv1_shift_en),
        .compute_en           (hotstate_compute_en),
        .accumulate           (conv2_accumulate),
        .chunk_sel            (conv2_chunk_sel),
        .mult_ce              (hotstate_mult_ce),
        .mult_clear           (hotstate_mult_clear),
        .param_en             (hotstate_param_en),
        .fc1_valid_out        (fc1_valid_out),
        .fc2_valid_out        (fc2_valid_out),
        .filter_idx           (filter_idx_w),    // 4-bit: conv1 (0-7) / conv2 (0-15)
        .ram_raddr            (conv2_ram_raddr), // 8-bit conv2 chunk RAM addr
        .fc1_ram_raddr        (fc1_raddr),       // 6-bit fc1 buffer RAM addr
        .fc1_weight_raddr     (fc1_weight_raddr),// 11-bit fc1 weight ROM addr
        .fc1_bias_raddr       (fc1_bias_raddr),  // 5-bit fc1 bias ROM addr
        .fc2_ram_raddr        (fc2_raddr),       // 2-bit fc2 buffer RAM addr
        .fc2_weight_raddr     (fc2_weight_raddr),// 5-bit fc2 weight ROM addr
        .fc2_bias_raddr       (fc2_bias_raddr),  // 3-bit fc2 bias ROM addr
        .layer_state          (layer_state),
        .npu_sleep            (npu_sleep),
        .npu_done             (system_done),
        // Counter/debug outputs used for derived control
        .layer_phase          (layer_phase),
        .c1_pixel_cnt         (c1_pixel_cnt),
        .c1_filter_cnt        (c1_filter_cnt),
        .c2_pixel_cnt         (c2_pixel_cnt),
        .c2_filter_cnt        (c2_filter_cnt),
        .c2_lb_row            (c2_lb_row),
        .c2_lb_col            (c2_lb_col),
        .fc1_neuron_cnt       (fc1_neuron_cnt),
        .fc2_neuron_cnt       (fc2_neuron_cnt)
    );
    assign npu_done = system_done;

    // ── Hotstate counter/debug wires ─────────────────────────────────
    // layer_phase is genuinely 5 bits (main_controller_template.v:
    // "output wire [4:0] layer_phase") -- 0..18 needs bit 4. A [3:0]
    // wire here would silently truncate the MSB, aliasing phases 16-18
    // onto 0-2 for every comparison below that reads this wire
    // (fc2_start, fc_layer_state, conv2_channel_done).
    logic [4:0]  layer_phase;
    logic [9:0]  c1_pixel_cnt;
    logic [2:0]  c1_filter_cnt;
    logic [7:0]  c2_pixel_cnt;
    logic [3:0]  c2_filter_cnt;
    logic [4:0]  c2_lb_row;
    logic [4:0]  c2_lb_col;
    logic [4:0]  fc1_neuron_cnt;
    logic [2:0]  fc2_neuron_cnt;

    // ── Conv1 control signals ────────────────────────────────────────
    logic       conv1_weight_en, conv1_bias_en, conv1_shift_en;
    logic [3:0] filter_idx_w;

    // ── Conv2 control signals (delayed by 1 cycle, as in original) ───
    logic [7:0]  conv2_ram_raddr;
    logic        conv2_shift_en, conv2_chunk_sel, conv2_accumulate;
    logic        conv2_shift_en_d, conv2_chunk_sel_d, conv2_accumulate_d,
                 conv2_compute_en_d, conv2_channel_done_d;
    logic        conv2_compute_en;
    logic        conv2_channel_done;
    // A second delay stage on conv2_accumulate, used ONLY to gate
    // tdm_npu_router's conv2_valid_out_gated (its conv2_accumulate_gate
    // port). mux_accumulate keeps using conv2_accumulate_d. The fold
    // written on conv2_accumulate_d isn't visible on npu_out until the
    // next cycle, so gating on conv2_accumulate_d itself would read the
    // pre-fold value.
    logic        conv2_accumulate_dd;

    // Original conv2_fsm output: compute_en = (COMPUTE_0 || COMPUTE_1);
    // the hotstate asserts compute_en during conv2 compute phases 6-7.
    assign conv2_compute_en = hotstate_compute_en;
    assign conv2_shift_en   = conv1_shift_en;  // shared shift stream (phase 5)
    // channel_done: main_controller.c case 7's filter-boundary check,
    // copied by hand (it must use the same constant). Diagnostic only: it
    // and its edge-detected/delayed pulses below feed trace ports.
    // maxpool2's per-filter reset is conv2_filter_reset_pulse, further
    // down, which counts real pixels instead of following microcode timing.
    assign conv2_channel_done = (layer_phase == 5'd7) && (c2_pixel_cnt == 8'd169);
    logic conv2_channel_done_pulse;
    assign conv2_channel_done_pulse = conv2_channel_done && !conv2_channel_done_d;
    logic conv2_channel_done_pulse_d;
    logic conv2_channel_done_pulse_dd;

    always_ff @(posedge npu_clk or posedge rst) begin
        if (rst) begin
            conv2_shift_en_d           <= 1'b0;
            conv2_chunk_sel_d          <= 1'b0;
            conv2_accumulate_d         <= 1'b0;
            conv2_accumulate_dd        <= 1'b0;
            conv2_compute_en_d         <= 1'b0;
            conv2_channel_done_d       <= 1'b0;
            conv2_channel_done_pulse_d  <= 1'b0;
            conv2_channel_done_pulse_dd <= 1'b0;
        end else begin
            conv2_shift_en_d           <= conv2_shift_en;
            conv2_chunk_sel_d          <= conv2_chunk_sel;
            conv2_accumulate_d         <= conv2_accumulate;
            conv2_accumulate_dd        <= conv2_accumulate_d;
            conv2_compute_en_d         <= conv2_compute_en;
            conv2_channel_done_d       <= conv2_channel_done;
            conv2_channel_done_pulse_d  <= conv2_channel_done_pulse;
            conv2_channel_done_pulse_dd <= conv2_channel_done_pulse_d;
        end
    end

    // ── FC layer state + start pulses (derived from hotstate phases) ─
    // FC1 phases 9-13, FC2 phases 14-17. fc_layer_state: 0=FC1, 1=FC2.
    logic fc_layer_state;
    logic fc2_start;
    assign fc_layer_state = (layer_phase >= 5'd14) ? 1'b1 : 1'b0;
    // BUG (fixed): fc2_start was `(layer_phase == 5'd14)`. Per
    // main_controller.c's actual phase structure, phase 14 is "FC2 — clear
    // NPU accumulators for new neuron", entered once from phase 13 (FC1
    // done, one-time transition into FC2) AND every subsequent time phase
    // 17 loops back for the next neuron -- 8 times per inference, not
    // once. argmax_layer resets its running max/best-index tracker on
    // every fc2_start pulse, so this fired 8 spurious mid-layer resets,
    // making the comparison always win for whichever neuron was most
    // recently processed (confirmed via a full cycle-accurate Verilator
    // simulation with per-neuron signal tracing: predicted_class tracked
    // current_neuron exactly, 0,1,2,...,7, regardless of each neuron's
    // actual summed value). Phase 13 is the real one-time "just arrived
    // at FC2" transition -- visited exactly once per inference, never
    // looped back to -- so gating on it instead fires fc2_start exactly
    // once, one cycle before the first neuron's own phase-14 mult_clear.
    assign fc2_start = (layer_phase == 5'd13);

    // ── Window validity gating for conv1 (unchanged from original) ───
    logic [9:0] current_pixel_idx;
    logic [9:0] lb1_row, lb1_col;
    logic       window1_valid_combo, window1_valid_synced;

    always_ff @(posedge npu_clk) begin
        if (img_en) current_pixel_idx <= img_addr;
    end
    assign lb1_row = current_pixel_idx / 28;
    assign lb1_col = current_pixel_idx % 28;
    assign window1_valid_combo = conv1_shift_en && (lb1_row >= 2) && (lb1_col >= 2);
    always_ff @(posedge npu_clk or posedge rst) begin
        if (rst) window1_valid_synced <= 1'b0;
        else     window1_valid_synced <= window1_valid_combo;
    end

    // ── Split the 24-bit RAM output back into 3 channels ─────────────
    logic [7:0] img_r_data, img_g_data, img_b_data;
    assign img_r_data = img_rdata[23:16];
    assign img_g_data = img_rdata[15:8];
    assign img_b_data = img_rdata[7:0];

    logic [7:0] lb1_data_in [0:3];
    assign lb1_data_in[0] = img_r_data;
    assign lb1_data_in[1] = img_g_data;
    assign lb1_data_in[2] = img_b_data;
    assign lb1_data_in[3] = 8'd0;

    // ── Conv1 param ROM ──────────────────────────────────────────────
    logic [7:0]  conv1_npu_weights [0:3][0:2][0:2];
    logic [31:0] conv1_bias_read_data;
    conv1_param_rom u_conv1_params (
        .clk(npu_clk), .weight_en(conv1_weight_en), .bias_en(conv1_bias_en),
        .filter_idx(filter_idx_w[2:0]), .npu_weights(conv1_npu_weights),
        .bias_out(conv1_bias_read_data)
    );

    // ── Conv1 line buffer ────────────────────────────────────────────
    logic [7:0] lb1_window_out [0:3][0:2][0:2];
    unified_line_buffer #(.NUM_CHANNELS(4), .IMAGE_WIDTH(28)) u_lb1 (
        .clk(npu_clk), .rst(rst), .shift_en(conv1_shift_en),
        .data_in(lb1_data_in), .window_out(lb1_window_out)
    );

    // ── Conv2 line buffer wrapper ────────────────────────────────────
    logic [7:0] ram_rdata [0:7];
    logic [7:0] lb2_window_out [0:3][0:2][0:2];
    conv2_line_buffer_wrapper u_lb2 (
        .clk(npu_clk), .rst(rst),
        .shift_en(conv2_shift_en_d), .chunk_sel(conv2_chunk_sel_d),
        .ram_data_in(ram_rdata), .muxed_window_out(lb2_window_out)
    );

    // ── Conv2 param ROM ──────────────────────────────────────────────
    logic [7:0]  conv2_npu_weights [0:3][0:2][0:2];
    logic [31:0] conv2_bias_read_data;
    conv2_param_rom u_conv2_params (
        .clk(npu_clk), .weight_en(1'b1), .bias_en(1'b1),
        .filter_idx(filter_idx_w[3:0]), .chunk_sel(conv2_chunk_sel_d),
        .npu_weights(conv2_npu_weights), .bias_out(conv2_bias_read_data)
    );

    // ── Conv TDM router + MaxPool 1 ──────────────────────────────────
    logic [7:0] npu_out;
    logic       conv1_npu_valid, conv2_npu_valid_gated;
    logic       dbg_npu_valid;
    logic signed [31:0] dbg_mac_sum, dbg_partial_sum;
    tdm_npu_router u_tdm_router (
        .clk(npu_clk), .rst(rst), .layer_state(layer_state),
        .conv1_compute_en(window1_valid_synced),
        .conv1_data_in(lb1_window_out), .conv1_weight_in(conv1_npu_weights),
        .conv1_bias_in(conv1_bias_read_data),
        // conv2_compute_en/conv2_accumulate: the 1-cycle-delayed copies.
        // An isolated Verilator testbench of ws_conv_core_gowin.sv
        // confirms the fold is correct with this timing.
        .conv2_compute_en(conv2_compute_en_d),
        .conv2_accumulate(conv2_accumulate_d),
        // conv2_accumulate_gate: one cycle further delayed than
        // conv2_accumulate above, for conv2_valid_out_gated only (see
        // conv2_accumulate_dd's declaration).
        .conv2_accumulate_gate(conv2_accumulate_dd),
        .conv2_data_in(lb2_window_out), .conv2_weight_in(conv2_npu_weights),
        .conv2_bias_in(conv2_bias_read_data),
        .npu_out(npu_out),
        .conv1_valid_out(conv1_npu_valid),
        .conv2_valid_out_gated(conv2_npu_valid_gated),
        .dbg_npu_valid(dbg_npu_valid),
        .dbg_mac_sum(dbg_mac_sum),
        .dbg_partial_sum(dbg_partial_sum)
    );

    logic pool1_valid;
    logic [7:0] pool1_out;
    maxpool2x2 #(.IN_WIDTH(26), .OUT_WIDTH(13)) u_maxpool1 (
        .clk(npu_clk), .rst(rst), .valid_in(conv1_npu_valid),
        .data_in(npu_out), .valid_out(pool1_valid), .max_out(pool1_out)
    );

    logic [7:0] ram_we, ram_waddr, ram_wdata;
    conv1_to_conv2_router u_router (
        .clk(npu_clk), .rst(rst), .pool_valid(pool1_valid), .pool_data(pool1_out),
        .ram_we(ram_we), .ram_waddr(ram_waddr), .ram_wdata(ram_wdata)
    );

    genvar i;
    generate
        for (i = 0; i < 8; i++) begin : conv2_ram_banks
            conv2_input_ram u_ram (
                .clka(npu_clk), .cea(ram_we[i]), .reseta(rst), .ada(ram_waddr), .din(ram_wdata),
                .clkb(npu_clk), .ceb(1'b1),  .oce(1'b1),  .resetb(rst),
                .adb(conv2_ram_raddr), .dout(ram_rdata[i])
            );
        end
    endgenerate

    // maxpool2's per-filter reset. It counts conv2_npu_valid_gated pulses
    // (maxpool2x2's own valid_in) and fires one cycle after each filter's
    // 121st pixel. A reset derived from microcode timing (the
    // conv2_channel_done_pulse chain above) landed before the filter's
    // last pixel: real conv2 pixels arrive ~30 npu_clk cycles apart, so a
    // cycle or two of delay can't move the reset past that pixel. Counting
    // pixels doesn't depend on microcode or TDM timing at all.
    logic [7:0] conv2_pixel_in_filter_cnt;
    logic       conv2_filter_last_pixel;
    logic       conv2_filter_reset_pulse;

    always_ff @(posedge npu_clk or posedge rst) begin
        if (rst) begin
            conv2_pixel_in_filter_cnt <= 8'd0;
            conv2_filter_reset_pulse  <= 1'b0;
        end else begin
            conv2_filter_reset_pulse <= conv2_filter_last_pixel;
            if (conv2_npu_valid_gated) begin
                if (conv2_pixel_in_filter_cnt == 8'd120) begin
                    conv2_pixel_in_filter_cnt <= 8'd0;
                end else begin
                    conv2_pixel_in_filter_cnt <= conv2_pixel_in_filter_cnt + 1'b1;
                end
            end
        end
    end

    // The 121st real pixel of a filter (0-indexed count == 120, the last
    // one before it would wrap): fires on the SAME cycle as that pixel's
    // own valid_in, so it must NOT be used directly as the reset (would
    // coincide with valid_in and silently eat that last pixel via
    // maxpool2x2's `if(rst)...else if(valid_in)` priority).
    // conv2_filter_reset_pulse above is the registered, one-cycle-later
    // copy that actually drives the reset.
    assign conv2_filter_last_pixel = conv2_npu_valid_gated
                                      && (conv2_pixel_in_filter_cnt == 8'd120);

    // ── MaxPool 2 + FC1 input buffer ─────────────────────────────────
    logic pool2_valid;
    logic [7:0] pool2_out;
    maxpool2x2 #(.IN_WIDTH(11), .OUT_WIDTH(5)) u_maxpool2 (
        .clk(npu_clk), .rst(rst | conv2_filter_reset_pulse),
        .valid_in(conv2_npu_valid_gated),
        .data_in(npu_out), .valid_out(pool2_valid), .max_out(pool2_out),
        .dbg_col_count(trace_pool2_col_count),
        .dbg_row_parity(trace_pool2_row_parity),
        .dbg_top_left(trace_pool2_top_left),
        .dbg_bottom_left(trace_pool2_bottom_left),
        .dbg_reset_valid_overlap(trace_pool2_reset_valid_overlap)
    );

    logic [63:0] fc1_rdata;
    logic [5:0]  fc1_raddr;
    fc1_buffer_ram u_fc1_ram (
        .clk(npu_clk), .rst(rst), .we(pool2_valid),
        .wdata(pool2_out), .raddr(fc1_raddr), .rdata(fc1_rdata)
    );

    // Diagnostic counters and pulses for the trace ports (whole-inference
    // valid counts, conv2/system start and done edges, an
    // early stop trigger). They only feed ILA_ENABLE ports, so synthesis
    // removes them in normal builds. Counters are sized so a full
    // inference can't wrap: a narrower one silently reports count mod 2^N.
    logic [11:0] pool2_valid_cnt;
    always_ff @(posedge npu_clk or posedge rst) begin
        if (rst)              pool2_valid_cnt <= 12'd0;
        else if (pool2_valid) pool2_valid_cnt <= pool2_valid_cnt + 1'b1;
    end

    logic layer_state_prev;
    always_ff @(posedge npu_clk or posedge rst) begin
        if (rst) layer_state_prev <= 1'b0;
        else     layer_state_prev <= layer_state;
    end
    logic conv2_start_pulse;
    assign conv2_start_pulse = layer_state && !layer_state_prev;

    logic [15:0] conv2_valid_gated_cnt;
    always_ff @(posedge npu_clk or posedge rst) begin
        if (rst)                        conv2_valid_gated_cnt <= 16'd0;
        else if (conv2_npu_valid_gated) conv2_valid_gated_cnt <= conv2_valid_gated_cnt + 1'b1;
    end

    logic [7:0] conv2_start_pulse_cnt;
    always_ff @(posedge npu_clk or posedge rst) begin
        if (rst)                   conv2_start_pulse_cnt <= 8'd0;
        else if (conv2_start_pulse) conv2_start_pulse_cnt <= conv2_start_pulse_cnt + 1'b1;
    end

    logic [12:0] conv2_local_cycle_cnt;
    always_ff @(posedge npu_clk or posedge rst) begin
        if (rst)             conv2_local_cycle_cnt <= 13'd0;
        else if (layer_state) conv2_local_cycle_cnt <= conv2_local_cycle_cnt + 1'b1;
    end
    logic conv2_early_stop;
    assign conv2_early_stop = (conv2_local_cycle_cnt == 13'd7800);

    logic system_done_prev;
    always_ff @(posedge npu_clk or posedge rst) begin
        if (rst) system_done_prev <= 1'b0;
        else     system_done_prev <= system_done;
    end
    logic system_done_pulse;
    assign system_done_pulse = system_done && !system_done_prev;

    // ── FC datapath signals ──────────────────────────────────────────
    logic [10:0] fc1_weight_raddr;
    logic [4:0]  fc1_bias_raddr;
    logic        fc1_param_en;
    logic [63:0] fc1_weight_rdata;
    logic [31:0] fc1_bias_rdata;
    logic        fc1_mult_ce, fc1_mult_clear;
    logic        fc1_valid_out;
    logic [4:0]  fc1_current_neuron;
    logic [7:0]  fc2_wdata;

    logic [4:0]  fc2_weight_raddr;
    logic [2:0]  fc2_bias_raddr;
    logic        fc2_param_en;
    logic [63:0] fc2_weight_rdata;
    logic [31:0] fc2_bias_rdata;
    logic        fc2_mult_ce, fc2_mult_clear;
    logic        fc2_valid_out;
    logic [2:0]  fc2_current_neuron;

    logic [1:0]  fc2_raddr;
    logic [63:0] fc2_ram_rdata;

    logic signed [31:0] shared_fc_psum_lanes [0:7];
    logic fc2_param_en_d;

    // The hotstate drives one shared mult_ce/mult_clear/param_en; the
    // tdm_fc_router muxes by fc_layer_state (FC1 vs FC2 phases).
    assign fc1_mult_ce    = hotstate_mult_ce;
    assign fc1_mult_clear = hotstate_mult_clear;
    assign fc2_mult_ce    = hotstate_mult_ce;
    assign fc2_mult_clear = hotstate_mult_clear;
    assign fc1_param_en   = hotstate_param_en;
    assign fc2_param_en   = hotstate_param_en;

    // current_neuron comes from the hotstate's neuron counters
    assign fc1_current_neuron = fc1_neuron_cnt;
    assign fc2_current_neuron = fc2_neuron_cnt;

    always_ff @(posedge npu_clk or posedge rst) begin
        if (rst) fc2_param_en_d <= 1'b0;
        else     fc2_param_en_d <= fc2_param_en;
    end

    // ── FC TDM router + shared NPU array ─────────────────────────────
    tdm_fc_router u_tdm_fc_router (
        .clk(npu_clk), .rst(rst), .fc_layer_state(fc_layer_state),
        .fc1_mult_ce      (fc1_mult_ce),
        .fc1_mult_clear   (fc1_mult_clear),
        .fc1_rdata        (fc1_rdata),
        .fc1_weight_rdata (fc1_weight_rdata),
        .fc2_mult_ce      (fc2_mult_ce),
        .fc2_mult_clear   (fc2_mult_clear),
        .fc2_rdata        (fc2_param_en_d ? fc2_ram_rdata : 64'd0),
        .fc2_weight_rdata (fc2_param_en_d ? fc2_weight_rdata : 64'd0),
        .psum_lanes_out   (shared_fc_psum_lanes)
    );

    // ── FC1 param ROM + reduction ────────────────────────────────────
    fc1_param_rom u_fc1_params (
        .clk(npu_clk), .en(fc1_param_en),
        .weight_addr(fc1_weight_raddr), .bias_addr(fc1_bias_raddr),
        .weights_out(fc1_weight_rdata), .bias_out(fc1_bias_rdata)
    );

    fc1_reduction_tree u_fc1_reduction (
        .psum_lanes(shared_fc_psum_lanes),
        .bias_in(fc1_bias_rdata),
        .fc2_wdata(fc2_wdata)
    );

    // ── FC2 buffer RAM ───────────────────────────────────────────────
    fc2_buffer_ram u_fc2_ram (
        .clk(npu_clk), .rst(rst),
        .we(fc1_valid_out),
        .waddr(fc1_current_neuron),
        .wdata(fc2_wdata),
        .raddr(fc2_raddr),
        .rdata(fc2_ram_rdata)
    );

    // ── FC2 param ROM + reduction + argmax ───────────────────────────
    fc2_param_rom u_fc2_params (
        .clk(npu_clk), .en(fc2_param_en),
        .weight_addr(fc2_weight_raddr), .bias_addr(fc2_bias_raddr),
        .weights_out(fc2_weight_rdata), .bias_out(fc2_bias_rdata)
    );

    logic signed [31:0] fc2_sum;
    logic [2:0] predicted_class;
    fc2_reduction_tree u_fc2_reduction (
        .psum_lanes(shared_fc_psum_lanes),
        .bias_in(fc2_bias_rdata),
        .fc2_out_32b(fc2_sum)
    );

    argmax_layer u_argmax (
        .clk(npu_clk), .rst(rst),
        .fc2_start       (fc2_start),
        .fc2_valid_in    (fc2_valid_out),
        .current_neuron  (fc2_current_neuron),
        .data_in         (fc2_sum),
        .predicted_class (predicted_class),
        .argmax_done     (fc2_layer_done)
    );

    // ── Layer completion flags fed back to hotstate ──────────────────
    // The hotstate microcode phases use internal counters for sequencing,
    // so these are tied off (the phases are fixed-duration in microcode).
    assign conv1_layer_done = 1'b0;
    assign conv2_layer_done = 1'b0;
    assign fc1_layer_done   = 1'b0;

    // ── class_idx output (matches original npu_top.sv) ───────────────
    always_comb begin
        if (system_done) class_idx = predicted_class;
        else             class_idx = {conv1_start_signal, 1'b0, fc2_start};
    end

    // ── Trace probe outputs (see module port comment) ────────────────
`ifdef ILA_ENABLE
    assign trace_fc2_valid_out       = fc2_valid_out;
    assign trace_fc2_current_neuron  = fc2_current_neuron;
    assign trace_fc2_sum             = fc2_sum;
    assign trace_layer_phase         = layer_phase;
    assign trace_predicted_class     = predicted_class;
    assign trace_psum_lane0          = shared_fc_psum_lanes[0];
    assign trace_system_done         = system_done;
    assign trace_mult_ce             = hotstate_mult_ce;
    assign trace_mult_clear          = hotstate_mult_clear;
    assign trace_param_en            = hotstate_param_en;
    assign trace_fc2_param_en_d      = fc2_param_en_d;
    assign trace_fc2_ram_rdata        = fc2_ram_rdata;
    assign trace_fc1_valid_out        = fc1_valid_out;
    assign trace_fc1_current_neuron   = fc1_current_neuron;
    assign trace_fc2_wdata            = fc2_wdata;
    assign trace_fc1_ram_raddr        = fc1_raddr;
    assign trace_pool2_valid_cnt      = pool2_valid_cnt;
    assign trace_conv2_channel_done_pulse = conv2_channel_done_pulse;
    assign trace_conv2_channel_done_pulse_d = conv2_channel_done_pulse_d;
    assign trace_conv2_channel_done_pulse_dd = conv2_channel_done_pulse_dd;
    assign trace_conv2_filter_reset_pulse = conv2_filter_reset_pulse;
    assign trace_conv2_valid_gated_cnt    = conv2_valid_gated_cnt;
    assign trace_accumulate               = conv2_accumulate;   // hotstate's raw one_shot output
    assign trace_conv2_accumulate_d       = conv2_accumulate_d; // fed to the router
    assign trace_dbg_npu_valid            = dbg_npu_valid;
    assign trace_conv2_npu_valid_gated    = conv2_npu_valid_gated;
    assign trace_layer_state              = layer_state;
    assign trace_conv2_start_pulse        = conv2_start_pulse;
    assign trace_c2_pixel_cnt             = c2_pixel_cnt;
    assign trace_conv2_start_pulse_cnt    = conv2_start_pulse_cnt;
    assign trace_conv1_shift_en           = conv1_shift_en;
    assign trace_c2_lb_row                = c2_lb_row;
    assign trace_c2_lb_col                = c2_lb_col;
    assign trace_system_done_pulse        = system_done_pulse;
    assign trace_conv2_early_stop         = conv2_early_stop;
    assign trace_pool2_out                = pool2_out;
    assign trace_pool2_valid              = pool2_valid;
    assign trace_c2_filter_cnt            = c2_filter_cnt;
    assign trace_npu_out                  = npu_out;
    assign trace_pool1_out                = pool1_out;
    assign trace_pool1_valid              = pool1_valid;
    assign trace_c1_filter_cnt            = c1_filter_cnt;
    assign trace_mac_sum                  = dbg_mac_sum;
    assign trace_partial_sum              = dbg_partial_sum;
    assign trace_conv2_ram_raddr          = conv2_ram_raddr;
    assign trace_ram_rdata0               = ram_rdata[0];
    assign trace_conv2_shift_en           = conv2_shift_en;
    assign trace_conv2_shift_en_d         = conv2_shift_en_d;
    assign trace_lb2_newest0              = lb2_window_out[0][2][2];
    assign trace_filter_idx_w             = filter_idx_w;
    assign trace_conv2_chunk_sel_d        = conv2_chunk_sel_d;
    assign trace_conv2_bias_read_data     = conv2_bias_read_data;
`endif

    // ── Unused hotstate control names (kept for clarity) ─────────────
    logic hotstate_compute_en, hotstate_mult_ce, hotstate_mult_clear,
          hotstate_param_en;

endmodule
