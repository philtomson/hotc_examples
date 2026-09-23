`include "ila_config.vh"

// System clock frequency, for the UART baud divisors. 30 MHz is what the
// Tang Nano 20K's Gowin_rPLL produces; a board built with NO_RPLL passes its
// oscillator frequency instead (e.g. -D SYS_CLK_HZ=50_000_000).
`ifndef SYS_CLK_HZ
`define SYS_CLK_HZ 30_000_000
`endif

`timescale 1ns/1ps

module top (
    input  logic       clk,    
    input  logic       rst,    
    output logic [5:0] led,    
    input  logic       rx_in,
    output logic       tx_out
);

    logic system_clk;
    logic npu_clk;
    logic npu_sleep;
    logic npu_done;
    logic [2:0] class_result;

    // DIAGNOSTIC (2026-08-20, uncommitted): system_clk driven from the
    // PLL's CLKOUTD tap (exact /2 of the same locked VCO, see
    // gowin_rpll.v's comment) instead of the primary 30MHz CLKOUT, to test
    // whether the conv2 stale-capture hazard (troubleshooting_progress.md,
    // "1d") is timing-margin-sensitive -- if it goes away or gets rarer at
    // half speed, that's real evidence for a margin/hazard explanation
    // rather than a deterministic logic bug. uart_rx/uart_tx's CLK_FREQ
    // below is updated to match (15_000_000) so the baud rate stays
    // correct. Revert both (back to .clkout + default CLK_FREQ) once the
    // test is done.
    logic system_clk_full, system_clk_half;
`ifdef NO_RPLL
    // Boards without the GW1N/GW2A rPLL (Tang Primer 25K, GW5A): run straight
    // off the board oscillator. SYS_CLK_HZ must then be that oscillator's
    // frequency, so the UARTs' baud divisors stay right.
    assign system_clk_full = clk;
    assign system_clk_half = 1'b0;
`else
    Gowin_rPLL u_pll (
        .clkout(system_clk_full),
        .clkoutd(system_clk_half),
        .clkin(clk)
    );
`endif
    assign system_clk = system_clk_full;  // TEMP: full-speed baseline re-check for the same 30-image sweep

    // Hotstate runs at system_clk; the datapath is clocked from the same
    // continuous clock.  We deliberately bypass Gowin_DCS clock gating:
    // the original repo documents that nextpnr-himbaechel needs one more
    // DCS than the chip has (9/8) and silently produces a broken clock
    // tree on real hardware (see MicroCNN-TangNano20k/Makefile notes).
    // npu_sleep is still driven to the outside world (power gating intent)
    // but no longer stops the clock inside this design.
    assign npu_clk = system_clk;

    logic [7:0] rx_data;
    logic       rx_valid;

    uart_rx #(.CLK_FREQ(`SYS_CLK_HZ)) u_uart_rx (
        .clk(system_clk),
        .rst(rst),
        .rx_in(rx_in),
        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    logic        img_we;
    logic [9:0]  img_waddr;
    logic [23:0] img_wdata;
    logic        npu_software_rst;

    logic npu_software_rst_raw;
    logic soc_loading;

    soc_controller u_soc_ctrl (
        .clk(system_clk),
        .rst(rst),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .img_we(img_we),
        .img_waddr(img_waddr),
        .img_wdata(img_wdata),
        .npu_rst_out(npu_software_rst_raw),
        .loading(soc_loading)
    );

    // npu_rst_out above is purely combinational and fans out widely as an
    // async `posedge rst` to every flop in u_npu/u_ila_capture; nextpnr
    // never checks reset recovery/removal timing (see reset_sync.sv for
    // the full explanation). Synchronize the deassertion edge so that
    // hazard becomes an ordinary, STA-checked FF-to-FF path.
    reset_sync u_npu_rst_sync (
        .clk(system_clk),
        .async_rst_in(npu_software_rst_raw),
        .sync_rst_out(npu_software_rst)
    );

    logic [9:0]  img_raddr;
    logic        img_ren;
    logic [23:0] img_rdata;

    img_ram u_img_ram (
        .wr_clk(system_clk),
        .we(img_we),
        .waddr(img_waddr),
        .wdata(img_wdata),
        .rd_clk(npu_clk),
        .re(img_ren),
        .raddr(img_raddr),
        .rdata(img_rdata)
    );

`ifdef ILA_ENABLE
    logic        trace_fc2_valid_out;
    logic [2:0]  trace_fc2_current_neuron;
    logic signed [31:0] trace_fc2_sum;
    logic [4:0]  trace_layer_phase;
    logic [2:0]  trace_predicted_class;
    logic signed [31:0] trace_psum_lane0;
    logic        trace_system_done;
    logic        trace_mult_ce;
    logic        trace_mult_clear;
    logic        trace_param_en;
    logic        trace_fc2_param_en_d;
    logic [63:0] trace_fc2_ram_rdata;
    logic        trace_fc1_valid_out;
    logic [4:0]  trace_fc1_current_neuron;
    logic [7:0]  trace_fc2_wdata;
    logic [5:0]  trace_fc1_ram_raddr;
    logic [11:0] trace_pool2_valid_cnt;
    logic        trace_conv2_channel_done_pulse;
    logic        trace_conv2_channel_done_pulse_d;
    logic        trace_conv2_channel_done_pulse_dd;
    logic        trace_conv2_filter_reset_pulse;
    logic [7:0]  trace_pool2_col_count;
    logic        trace_pool2_row_parity;
    logic [7:0]  trace_pool2_top_left;
    logic [7:0]  trace_pool2_bottom_left;
    logic        trace_pool2_reset_valid_overlap;
    logic [15:0] trace_conv2_valid_gated_cnt;
    logic        trace_accumulate;
    logic        trace_conv2_accumulate_d;
    logic        trace_dbg_npu_valid;
    logic        trace_conv2_npu_valid_gated;
    logic        trace_layer_state;
    logic        trace_conv2_start_pulse;
    logic [7:0]  trace_c2_pixel_cnt;
    logic [7:0]  trace_conv2_start_pulse_cnt;
    logic        trace_conv1_shift_en;
    logic [4:0]  trace_c2_lb_row;
    logic [4:0]  trace_c2_lb_col;
    logic        trace_system_done_pulse;
    logic        trace_conv2_early_stop;
    logic [7:0]  trace_pool2_out;
    logic        trace_pool2_valid;
    logic [3:0]  trace_c2_filter_cnt;
    logic [7:0]  trace_npu_out;
    logic [7:0]  trace_pool1_out;
    logic        trace_pool1_valid;
    logic [2:0]  trace_c1_filter_cnt;
    logic signed [31:0] trace_mac_sum;
    logic signed [31:0] trace_partial_sum;
    logic [7:0]  trace_conv2_ram_raddr;
    logic [7:0]  trace_ram_rdata0;
    logic        trace_conv2_shift_en;
    logic        trace_conv2_shift_en_d;
    logic [7:0]  trace_lb2_newest0;
    logic [3:0]  trace_filter_idx_w;
    logic        trace_conv2_chunk_sel_d;
    logic signed [31:0] trace_conv2_bias_read_data;
`endif

    npu_top_hotstate u_npu (
        .system_clk(system_clk),
        .npu_clk(npu_clk),
        .rst(npu_software_rst),
        .img_addr(img_raddr),
        .img_en(img_ren),
        .img_rdata(img_rdata),
        .class_idx(class_result),
        .npu_sleep(npu_sleep),
        .npu_done(npu_done)
`ifdef ILA_ENABLE
        ,
        .trace_fc2_valid_out(trace_fc2_valid_out),
        .trace_fc2_current_neuron(trace_fc2_current_neuron),
        .trace_fc2_sum(trace_fc2_sum),
        .trace_layer_phase(trace_layer_phase),
        .trace_predicted_class(trace_predicted_class),
        .trace_psum_lane0(trace_psum_lane0),
        .trace_system_done(trace_system_done),
        .trace_mult_ce(trace_mult_ce),
        .trace_mult_clear(trace_mult_clear),
        .trace_param_en(trace_param_en),
        .trace_fc2_param_en_d(trace_fc2_param_en_d),
        .trace_fc2_ram_rdata(trace_fc2_ram_rdata),
        .trace_fc1_valid_out(trace_fc1_valid_out),
        .trace_fc1_current_neuron(trace_fc1_current_neuron),
        .trace_fc2_wdata(trace_fc2_wdata),
        .trace_fc1_ram_raddr(trace_fc1_ram_raddr),
        .trace_pool2_valid_cnt(trace_pool2_valid_cnt),
        .trace_conv2_channel_done_pulse(trace_conv2_channel_done_pulse),
        .trace_conv2_channel_done_pulse_d(trace_conv2_channel_done_pulse_d),
        .trace_conv2_channel_done_pulse_dd(trace_conv2_channel_done_pulse_dd),
        .trace_conv2_filter_reset_pulse(trace_conv2_filter_reset_pulse),
        .trace_pool2_col_count(trace_pool2_col_count),
        .trace_pool2_row_parity(trace_pool2_row_parity),
        .trace_pool2_top_left(trace_pool2_top_left),
        .trace_pool2_bottom_left(trace_pool2_bottom_left),
        .trace_pool2_reset_valid_overlap(trace_pool2_reset_valid_overlap),
        .trace_conv2_valid_gated_cnt(trace_conv2_valid_gated_cnt),
        .trace_accumulate(trace_accumulate),
        .trace_conv2_accumulate_d(trace_conv2_accumulate_d),
        .trace_dbg_npu_valid(trace_dbg_npu_valid),
        .trace_conv2_npu_valid_gated(trace_conv2_npu_valid_gated),
        .trace_layer_state(trace_layer_state),
        .trace_conv2_start_pulse(trace_conv2_start_pulse),
        .trace_c2_pixel_cnt(trace_c2_pixel_cnt),
        .trace_conv2_start_pulse_cnt(trace_conv2_start_pulse_cnt),
        .trace_conv1_shift_en(trace_conv1_shift_en),
        .trace_c2_lb_row(trace_c2_lb_row),
        .trace_c2_lb_col(trace_c2_lb_col),
        .trace_system_done_pulse(trace_system_done_pulse),
        .trace_conv2_early_stop(trace_conv2_early_stop),
        .trace_pool2_out(trace_pool2_out),
        .trace_pool2_valid(trace_pool2_valid),
        .trace_c2_filter_cnt(trace_c2_filter_cnt),
        .trace_npu_out(trace_npu_out),
        .trace_pool1_out(trace_pool1_out),
        .trace_pool1_valid(trace_pool1_valid),
        .trace_c1_filter_cnt(trace_c1_filter_cnt),
        .trace_mac_sum(trace_mac_sum),
        .trace_partial_sum(trace_partial_sum),
        .trace_conv2_ram_raddr(trace_conv2_ram_raddr),
        .trace_ram_rdata0(trace_ram_rdata0),
        .trace_conv2_shift_en(trace_conv2_shift_en),
        .trace_conv2_shift_en_d(trace_conv2_shift_en_d),
        .trace_lb2_newest0(trace_lb2_newest0),
        .trace_filter_idx_w(trace_filter_idx_w),
        .trace_conv2_chunk_sel_d(trace_conv2_chunk_sel_d),
        .trace_conv2_bias_read_data(trace_conv2_bias_read_data)
`endif
    );

    // class_tx_data/class_tx_start/class_sent -- declared here (rather
    // than right next to uart_tx below) so class_tx_data can be included
    // directly in the ILA probe bus when ILA_ENABLE is on.
    logic class_tx_start;
    logic [7:0] class_tx_data;
    logic class_sent;

`ifdef ILA_ENABLE
    // ── Minimal on-chip logic analyzer (ila_capture.sv / ila_dump.sv) ──
    // Opt-in: `make ILA=1 ...`. Built for, and
    // documented across, the classifier-stuck-on-one-class investigation
    // (see hotc_microcnn_hotstate_classifier_bug_hunt.md) -- root cause
    // found (yosys/nextpnr mis-synthesizing an asymmetric Gowin SDPB
    // primitive), kept here in case a similar hardware-only bug needs
    // this kind of instrumentation again. Off by default: costs BRAM and
    // routing resources, and the shared-uart_tx arbitration below adds a
    // small amount of complexity to the TX path that a normal build
    // doesn't need.
    // Re-purposed again (2026-08-19): earlier per-neuron-triggered probes
    // (one rebuild per neuron) confirmed FC1 neuron 6 reads 0 on hardware
    // vs golden's 21, and confirmed this is independent of FC2's control
    // timing (2 null experiments there) and independent of this session's
    // own case-11 CE-gating fix (A/B tested by reverting it -- no change).
    // THIS probe captures the FULL 32-neuron fc1_shifted vector in one
    // pass instead of one neuron per rebuild: ila_capture.sv now takes a
    // `capture_en` gate (see its own comment) tied here to
    // trace_fc1_valid_out, so the buffer holds one sample per
    // fc1_valid_out pulse instead of one per clock. Sized generously
    // (512, ADDR_WIDTH=9) since fc1_valid_out's true pulse count per run
    // is exactly what's under investigation -- a prior 64-slot buffer
    // wrapped (>64 real pulses seen with an experimental fix in place),
    // and reconstructing chronological order from a hardcoded assumed
    // count produced an ambiguous/wrong-looking vector. ila_dump.sv now
    // sends `wr_ptr` as a 2-byte header before the sample stream so the
    // host can determine the real valid-sample count directly instead
    // of guessing -- see uart_ila_dump.py's "FC1 full vector" mode.
    // TEMP DIAGNOSTIC (2026-08-20, part 3 -- direct chain trace):
    // conv2_npu_valid_gated's channel-0 pulse count measured 512 (not
    // ~121), and conv1-era contamination of the counter is ruled out
    // (measured identical with the counter reset at conv2's own start).
    // This free-running probe instead watches the whole
    // accumulate->valid chain cycle-by-cycle around real pixels in
    // channel 0, to find which signal is wider/misaligned than the RTL
    // reading predicts. Stop trigger unchanged (first
    // conv2_channel_done_pulse) -- the buffer will wrap well before
    // channel 0 finishes (2048 samples vs. ~3600+ cycles for 121
    // pixels), so read the TAIL of the dump (most recent samples, right
    // before the stop) for steady-state pixels. See
    // hotc_microcnn_hotstate_classifier_bug_hunt.md.
    //   {c2_pixel_cnt[7:0], 4'b0 pad, layer_state, conv2_accumulate_d,
    //    dbg_npu_valid, conv2_npu_valid_gated} = EXACTLY 16 bits
    //    (8+4+1+1+1+1). Pad width computed explicitly this time -- a
    //    previous version of this probe padded with only 3'b0 (14 bits
    //    total), which Verilog silently auto-zero-extended by 2 MORE
    //    implicit bits at the top, shifting every field down by 2 from
    //    what the decode script assumed. `layer_state` re-added: the
    //    "channel 0" window this probe captures starts at c2_pixel_cnt=129,
    //    not 0 -- meaning conv2_start_pulse (layer_state's rising edge)
    //    is NOT firing at conv2's true beginning. Need to see directly
    //    whether layer_state genuinely toggles mid-channel.
    // Direct test: does conv2_start_pulse (layer_state's rising edge)
    // fire more than once per inference? If so, every earlier
    // conv2_start_pulse-reset counter measurement (the 512 count, its
    // fix/no-fix A/B) was measuring "since the LAST such edge before the
    // stop", not "since conv2's true start". Free-running, stopped on
    // system_done (end of the WHOLE inference) so the counter has seen
    // every possible edge across all 16 channels.
    // conv2_start_pulse confirmed fires exactly once/inference (dedicated
    // counter, immune to buffer-depth issues) -- ruling that out. Direct
    // chain traces all look clean but were never confirmed to cover the
    // true start of channel 0 (buffer too shallow, always wraps to a
    // tail). Instead of a bigger free-running buffer, gate capture_en on
    // conv1_shift_en (the shared shift pulse, fires exactly once per RAW
    // pixel in case 5) -- one sample per raw pixel instead of one per
    // clock, so the WHOLE channel fits easily in a small buffer
    // regardless of how many real cycles each pixel takes. Directly
    // answers: does c2_lb_row/c2_lb_col wrap correctly once per 13x13=169
    // raw pixels, or does something cause far more than 169 shift events
    // for one channel (the current leading hypothesis for the
    // 512-vs-121 conv2_npu_valid_gated discrepancy)? See
    // hotc_microcnn_hotstate_classifier_bug_hunt.md.
    // Keep c2_lb_row/c2_lb_col at FULL width (5 bits each) -- truncating
    // either would hide exactly the kind of "counter exceeds its
    // expected 0-12 range" bug this trace exists to catch. c2_pixel_cnt
    // trimmed to its low 6 bits instead (still enough to see wrap-around
    // /restart behavior within a channel; the exact absolute count is
    // already known from the c2_pixel_cnt-only probe used earlier).
    // ADVISOR-DIRECTED PIVOT (2026-08-20): the row/col trace above proved
    // c2_lb_row climbs monotonically ACROSS filter boundaries (never
    // resets to 0 per channel -- only the (row>=2 && col>=2) validity gate
    // cares about row's absolute value), so every earlier "channel 0"
    // pixel_cnt = row*13+col estimate, and every counter this session that
    // was reset/read around a single "channel 0" stop trigger (the 512
    // conv2_npu_valid_gated count, the 115 pool2_valid count), was really
    // measuring an ARBITRARY multi-filter window, not one true channel.
    // conv2_pixel_cnt itself steps cleanly 1-per-sample in lockstep with
    // col in that same trace, so the comparator/counter logic is correct;
    // the bug (if any) is not there.
    // Whole-inference conv2_valid_gated_cnt read at system_done confirmed
    // 320 (stable across 3 images) vs. 1936 expected -- a genuine ~6x
    // UNDER-count. Not yet known whether that's ~20/filter spread evenly
    // across all 16 filters, or concentrated in a few filters while most
    // produce zero (a much more severe control-flow bug). PER-FILTER
    // BREAKDOWN: capture the cumulative counter's value at each of the 16
    // conv2_channel_done_pulse edges across the whole inference instead of
    // one final read -- the host diffs consecutive samples to get each
    // filter's own pulse count. ADDR_WIDTH=5 (32 slots, 2x margin over the
    // 16 real samples expected). Stop on system_done_pulse (fires right
    // after the 16th channel's done pulse) so wr_ptr's real-sample-count
    // header tells the host exactly how many channel boundaries fired --
    // itself a useful cross-check against "exactly 16" if the per-filter
    // loop isn't iterating the right number of times.
    // Per-filter breakdown confirmed ~532 conv2_npu_valid_gated pulses per
    // filter, UNIFORMLY across all 16 filters (vs. ~121 expected) -- a
    // uniform per-filter over-count matches a level/pulse-width defect in
    // the accumulate->valid chain, not a structural per-filter loop bug.
    // Direct chain trace attempt #2: gate capture_en on layer_state itself
    // (only genuinely conv2-era cycles ever enter the buffer, so sample 0
    // is unambiguously conv2's true first cycle -- no more buffer-wrap
    // tail-slice risk) and stop on a small dedicated cycle counter
    // (conv2_early_stop, fires at cycle 300 of conv2 -- a few pixels'
    // worth, comfortably inside a non-wrapping buffer).
    // Retargeted a 3rd time: conv1/pool1 confirmed exact-match vs golden
    // and conv2's raw output confirmed 1461/1935 (~75.5%) with small
    // scattered per-pixel deltas (not scrambling) -- see
    // troubleshooting_progress.md. Before touching ws_conv_core_gowin.sv's
    // arithmetic, checking a specific hand-traced hypothesis about its
    // CONTROL inputs first: the module's `valid_out <= compute_en;` is
    // unconditional every cycle, and case 7's 2-cycle compute_en pulse
    // (chunk0-pulse then chunk1+accumulate-pulse) means compute_en (as
    // seen through the extra 1-cycle `_d` register in this file) is high
    // for 2 CONSECUTIVE cycles -- so valid_out (1 more cycle behind) should
    // ALSO pulse high for 2 consecutive cycles: once for the WRONG
    // chunk0-only partial sum (mac_out registered the cycle compute_en
    // first went high), once for the CORRECT folded sum (mac_out
    // registered the following cycle, after partial_sum_reg absorbed
    // chunk1). The router's gate (`conv2_valid_out_gated = npu_valid &
    // !conv2_accumulate`, RAW undelayed accumulate) checks a signal that,
    // by the time either of those 2 valid_out cycles arrives, has already
    // auto-cleared back to 0 (one_shot, only high the single cycle it's
    // written) -- so on paper BOTH cycles should pass the gate, and
    // ila_capture.sv writes a sample every cycle capture_en is high (no
    // edge-detection), so this would show as 2 gated pulses per real
    // output pixel. That contradicts the already-measured ~121
    // (not ~242) samples/filter on the conv2-raw probe, so either this
    // derivation has an error, or the SECOND (correct) pulse is somehow
    // suppressed/merged. Capturing the raw valid, gated valid, raw
    // accumulate, and delayed accumulate together, cycle-by-cycle, for
    // the first couple of real output pixels settles it directly instead
    // of continuing paper derivation.
    // pulse train mechanism is exonerated for every pixel checked; that
    // trace was taken around filter 0's first 2 pixels, which turned out
    // to capture correctly. The per-(row,col) mismatch map built from the
    // conv2-raw-vs-golden comparison instead found a specific, reproducible
    // hazard signature: 37/40 checked mismatches (filters 9/12/13) exactly
    // satisfy hw[flat_i] == golden[flat_i - 1] -- a STALE capture (holding
    // the previous pixel's mac_out for one extra gated-valid event) that
    // self-corrects immediately after, not a scrambled/arithmetic error.
    // Retargeting to catch this hazard live at filter 12's flat-index 61
    // (11x11 output row 5, col 6), a KNOWN-BAD pixel from that map. In
    // main_controller.c's case-5 (row,col) coordinate space (2 higher than
    // the 11x11 output grid, since the first valid window is at row=2,
    // col=2) that's c2_lb_row=7, c2_lb_col=8, which a direct simulation of
    // case 5's row/col/pixel_cnt update loop shows occurs at
    // c2_pixel_cnt==99 (post-increment) -- the 62nd valid pixel of the
    // filter (0-indexed 61, matching the flat index exactly, confirming
    // conv2's raster order matches golden's). Widened the probe to 24 bits
    // to also carry c2_pixel_cnt, so each sample is self-labeled with
    // exactly which pixel it belongs to (no more inferring position from
    // capture order alone).
    // Retargeted again: the live-caught hazard (troubleshooting_progress.md
    // Open Problem #1, "hazard caught live") showed the gate/pulse
    // mechanism is healthy but the gated VALUE equals the previous
    // pixel's golden answer. Tracing ws_conv_core_gowin's raw
    // mac_sum_dbg (this cycle's purely-combinational 4-channel MAC sum,
    // independent of any register) and partial_sum_dbg (the registered
    // accumulator the fold's 2nd pulse adds mac_sum to) directly answers
    // whether the WINDOW itself is stale for the bad pixels (mac_sum
    // would look wrong/unexpected) or the ACCUMULATOR is (partial_sum
    // would still hold an old value when the 2nd pulse fires).
    //   {c2_pixel_cnt[7:0], gated(1), accumulate_d(1), 6'b0 pad,
    //    mac_sum[31:0], partial_sum[31:0]} = 8+1+1+6+32+32 = 80 bits.
    // SUPERSEDED (2026-08-20, this session): Qwen's proposed control-plane
    // fix (main_controller.c case 5's check-before-vs-after-update
    // ordering) was tested on hardware and disproven -- bit-identical
    // mac_sum/partial_sum at every pixel_cnt label before/after the patch,
    // ruling out the C-level coordinate check. Retargeted the probe one
    // level further back, to conv2_line_buffer_wrapper's actual READ
    // ADDRESS/DATA path (troubleshooting_progress.md Open Problem #1 item
    // (j)): conv2_input_ram is a Gowin SDPB primitive with OCE tied high,
    // which typically means a 2-stage (address-register + output-register)
    // read pipeline -- if main_controller.c's shift_en pulse (fired the
    // cycle right after ram_raddr is written) assumes only 1 cycle of
    // latency, it shifts in STALE (previous-address) data every time. This
    // probe captures conv2_ram_raddr (address written this cycle),
    // ram_rdata0 (what channel 0's RAM is ACTUALLY returning this cycle),
    // conv2_shift_en (raw) and conv2_shift_en_d (the delayed copy that
    // actually drives the line buffer), and lb2_newest0 (buffer A/channel
    // 0's own newest-shifted-pixel tap, window_out[2][2]) -- together
    // these let the host directly measure the RAM's true read latency
    // (from when raddr changes to when rdata catches up) and check whether
    // shift_en_d fires before or after that catch-up point.
    //   {c2_pixel_cnt[7:0], shift_en(1), shift_en_d(1), 6'b0 pad,
    //    conv2_ram_raddr[7:0], ram_rdata0[7:0], lb2_newest0[7:0]} = 40 bits.
    // SUPERSEDED (2026-08-20, this session, continued): the RAM read path
    // is now proven correct -- raddr->rdata0 settles in exactly 1 cycle
    // with 20-25+ cycles of margin before shift_en_d fires, and the
    // captured (raddr,rdata0) pairs matched golden_benchmark.py's own
    // maxpool1 channel-0 output bit-for-bit, 9/9 (see
    // troubleshooting_progress.md Open Problem #1 item (j)). Retargeting
    // to the fold's OTHER operand: conv2_param_rom's bias read (which
    // seeds partial_sum_reg on COMPUTE_0, `current_acc = bias_in +
    // mac_sum` when accumulate=0) and the filter_idx/chunk_sel_d signals
    // that select it and mux the weight channels. conv2_param_rom does a
    // SYNCHRONOUS (1-cycle-latency) read of both weight_mem and bias_mem,
    // gated by weight_en/bias_en -- both hardwired 1'b1 in this file, so
    // the read fires every cycle regardless, tracking filter_idx_w with a
    // clean 1-cycle lag. filter_idx_w should be perfectly stable for the
    // whole ~121-pixel filter (only main_controller.c's case 7 changes
    // c2_filter_cnt, once per filter boundary), so if the traced bias
    // value is anything other than rock-stable across this known-bad
    // cluster, that's the smoking gun; if it's stable, this operand is
    // exonerated too and the remaining candidate narrows further.
    //   {c2_pixel_cnt[7:0], accumulate_d(1), chunk_sel_d(1),
    //    filter_idx_w[3:0], 2'b0 pad, bias_read_data[31:0] signed} = 48 bits.
    // SUPERSEDED (2026-08-20, this session, continued further): the bias
    // path is now ALSO proven correct (rock-stable 442, exact match vs.
    // golden), which -- combined with the window (item (j)) and the
    // gating mechanism (proven in an earlier session) all independently
    // checking out -- creates a genuine paradox (troubleshooting_progress.md
    // Open Problem #1 item (k)): every individual fold input is correct,
    // yet the output is still off by one position. Every measurement so
    // far has come from SEPARATE capture runs pieced together across
    // sessions, not one simultaneous capture. This probe combines the
    // window-address trace and the fold-arithmetic trace into ONE capture
    // (c2_pixel_cnt, accumulate_d, conv2_ram_raddr, mac_sum_dbg,
    // partial_sum_dbg), and retargets from the filter's TAIL (where every
    // previous capture landed, via wraparound) to its FIRST ~40 pixels
    // instead -- to check whether the one-position shift is already
    // present at the very first valid compute, or only emerges partway
    // through. mac_sum/partial_sum truncated 32->24 bits (signed): the
    // observed magnitudes this whole investigation have topped out
    // around +-8000, nowhere near a 24-bit signed range's +-8,388,608
    // limit, so this is a wide-margin truncation, not a real constraint
    // (kept 32-bit in earlier probes only because there was BSRAM budget
    // to spare; freed up here to make room for the extra raddr field).
    //   {c2_pixel_cnt[7:0], accumulate_d(1), 7'b0 pad, conv2_ram_raddr[7:0],
    //    mac_sum[23:0] signed, partial_sum[23:0] signed} = 72 bits.
    // SUPERSEDED 2026-08-21 (this session): the filter-5-first-computes
    // probe above (72-bit, c2_pixel_cnt+accumulate_d+conv2_ram_raddr+
    // mac_sum+partial_sum) did its job -- confirmed the re-derived Qwen
    // fix on silicon, 12/12 exact vs golden at the head of filter 5,
    // including col 12 (the position the old check never computed) and
    // the row-wrap skip landing exactly on flat[11]. But end-to-end
    // classification on the same build regressed against every baseline
    // on record, and none of those baselines are a trustworthy same-build
    // A/B (recorded at different commits; troubleshooting_progress.md
    // already flags pre-fix classification numbers as suspect). Per
    // advisor review: re-run item 1c's ORIGINAL discriminator instead --
    // conv2's raw (pre-pool) output vs golden's `conv2_shifted`, across
    // ALL 16 filters, same methodology that produced the 1461/1935
    // (~75.5%) baseline earlier this investigation (npu_out self-labeled
    // by c2_filter_cnt). That capture predates this file's local git
    // history of probe swaps, so it's rebuilt fresh here rather than
    // uncommented.
    //
    // Probe, v2 (2026-08-21, same session): v1 used the on-chip registered
    // `npu_out` directly, gated on `accumulate_d` -- reasoning said that
    // should read the freshly-folded value, but filters 5/8/9/12/13 came
    // back with small, garbled, clearly-wrong magnitudes (0% exact vs
    // golden) while the SAME filter 5, captured minutes earlier by the
    // dedicated filter-5 probe using raw `mac_sum`/`partial_sum` with the
    // ReLU/shift computed OFF-CHIP in Python, matched golden 12/12 exactly.
    // Rather than chase a second probe's own timing bug, reuse the
    // ALREADY-PROVEN method and just widen it to all 16 filters instead of
    // debugging npu_out's on-chip timing further.
    //   {4'b0 pad, c2_filter_cnt[3:0], c2_pixel_cnt[7:0],
    //    mac_sum[23:0] signed, partial_sum[23:0] signed} = 64 bits (8
    //   bytes, a clean multiple of 8 with no extra padding needed).
    // Still gated on real accumulate_d pulses only (one_shot, genuine
    // 1-cycle pulse), not free-running, so all 16*121=1936 real fold
    // events fit in one capture well under the 2048-deep buffer.
    // Probe, v3 (2026-08-21, same session): v2 proved conv2's own
    // arithmetic is now bit-exact (1823/1823 vs golden). But the ACTUAL
    // classifier consumes `npu_out` -> pool2, not the off-chip-reconstructed
    // mac_sum/partial_sum -- and a direct read of npu_out (v1) came back
    // garbled for the nonzero filters. A candidate mechanism (tdm_npu_router's
    // `mux_accumulate` reading a stale/delayed signal) was proposed here and
    // then ELIMINATED by direct inspection: `mux_compute_en` is ALSO fed the
    // delayed `conv2_compute_en_d` from the same instantiation, so
    // `mux_accumulate`/`mux_compute_en` are shifted together, self-
    // consistently -- not a bug. v3 (pool2 probe, `read_pool2.py`'s format)
    // then confirmed pool2 itself is wrong (210/400 vs golden) and ruled out
    // a simple 1-sample relabeling via a shift test (213/399, 207/399 -- no
    // jump toward 400). See troubleshooting_progress.md item (n).
    //
    // Probe, v4: a SINGLE combined capture with `npu_out` alongside
    // `mac_sum`/`partial_sum` on the SAME cycle, across all 16 filters --
    // "measure everything at once", same methodology as item (l)'s root
    // cause. Led to item (p)'s root cause (conv2_valid_out_gated samples
    // one cycle early) via a probe-only experiment (an extra delay
    // register, local to this file only, used to gate this SAME v4 probe
    // -- not shown here any more, superseded).
    //
    // Probe, v5 (this probe, 2026-08-21): the REAL fix (item (p)) is now
    // implemented in the datapath itself (npu_top_hotstate.sv's
    // conv2_accumulate_dd + tdm_npu_router.sv's new conv2_accumulate_gate
    // port) -- so the diagnostic double-delay scaffolding that used to
    // live here is no longer needed; the fix lives in the real gate now,
    // not in a probe-side workaround. Verifying via the most DIRECT
    // possible test instead: reused the pre-existing pool2 probe
    // (documented in `read_pool2.py`, this example dir), reading the REAL
    // `pool2_out`/`pool2_valid` -- i.e. testing the actual production path
    // (conv2_valid_out_gated -> maxpool2x2 -> pool2_out) end to end, not a
    // diagnostic reconstruction.
    //   ila_probe   = {4'b0, c2_filter_cnt[3:0], pool2_out[7:0]} (16 bits)
    //   capture_en  = pool2_valid (one sample per pooled pixel)
    //   stop_trigger= (layer_phase == 9) (FC1 start -- pool2 long done)
    //   ADDR_WIDTH  = 9 -> 512 slots (400 real: 16 filters x 25)
    // Probe, v6 (2026-08-21): v5 confirmed the gate fix on the real
    // production path (210/400 -> 326/399, 8/16 filters now exact) but
    // left 8 filters still corrupted, in a "values present but reordered
    // within the filter" pattern -- not random garbage. Advisor-flagged
    // hypothesis: `conv2_channel_done_pulse` (maxpool2x2's per-filter
    // reset, npu_top_hotstate.sv `.rst(rst | conv2_channel_done_pulse)`)
    // is derived combinationally from RAW (undelayed) layer_phase/
    // c2_pixel_cnt and edge-detected off THAT -- so it fires at the FIRST
    // cycle of the last pixel's case-7 pass, several cycles BEFORE that
    // same pass's own compute_en/accumulate pair even runs, let alone
    // before the one-cycle-LATER conv2_valid_out_gated pulse the v5 fix
    // now produces. Before the v5 fix this reset already fired "too
    // early" relative to the gated pulse, but which SIDE of the reset the
    // last real pulse landed on may have shifted when the gate moved one
    // cycle later -- which would exactly explain "filter N's first pooled
    // output contaminated by a stray sample from filter N-1" for some
    // filters and not others (plateau-masking, same as the original shift
    // bug). This probe directly measures the ordering: capture one sample
    // per event on EITHER conv2_channel_done_pulse OR pool2_valid, so the
    // per-filter boundary shows up as an interleaved sequence and the
    // reset pulse's position relative to the filter's last pool2_valid is
    // directly readable.
    //   ila_probe   = {6'b0, c2_filter_cnt[3:0], channel_done_pulse[1],
    //                  pool2_valid[1]} (12 bits, padded to 16)
    //   capture_en  = pool2_valid | conv2_channel_done_pulse
    //   stop_trigger= (layer_phase == 9) (FC1 start -- pool2 long done)
    localparam int ILA_PROBE_WIDTH = 32;   // widened 16->32 for v10, see below
    localparam int ILA_ADDR_WIDTH  = 11;

    // v6 CONFIRMED the reset-race hypothesis FALSE (15/15 boundaries
    // clean, done_pulse always lands exactly between filter N's last and
    // filter N+1's first pool2_valid). v5's re-run with a proper
    // non-degenerate-filter breakdown (advisor-directed) found: filter 0
    // has a genuine single spurious leading pool2_valid pulse (lag1=25/25,
    // a real but separate small bug) -- but the OTHER non-degenerate
    // filters (5,6,8,9,11,12,13) show scattered-magnitude wrong values,
    // NOT a fixed-lag shift -- the signature of a partially-wrong 2x2
    // window, not a mislabeling. An isolated Verilator testbench of
    // maxpool2x2.sv (golden's own filter-5 conv2_s raster as stimulus)
    // reproduced golden's 25 pooled values EXACTLY -- maxpool2x2's own
    // windowing logic is proven correct given a clean input stream. That
    // means the corruption is upstream: either `npu_out`/
    // `conv2_npu_valid_gated` (maxpool2x2's actual inputs, confirmed by
    // direct instantiation read to be un-registered direct wires, same
    // signals the v4 probe measured 1824/1824 against) aren't as clean as
    // item (p) claimed once split by degeneracy -- item (p)'s 1824/1824
    // was never checked per-filter and may have the same degenerate-zero-
    // filter inflation this whole investigation just found in pool2's own
    // "8/16" claim (7 of 8 exact filters were all-zero gold, zero
    // discriminating power). Probe v7 tests this directly: capture
    // maxpool2x2's actual INPUT stream (npu_out gated by
    // conv2_npu_valid_gated) instead of its output, so it can be diffed
    // straight against golden's pre-pool conv2_s raster per filter.
    //   ila_probe   = {3'b0, c2_filter_cnt[3:0], npu_out[7:0]} (15 bits, padded to 16)
    //   capture_en  = conv2_npu_valid_gated (one sample per raw conv2 pixel)
    //   stop_trigger= (layer_phase == 9)
    //   ADDR_WIDTH bumped 9->11 (512->2048 slots): conv2_npu_valid_gated
    //   fires ~16*121=1936 times/inference, which wrapped the 512-slot
    //   buffer (first measurement: wr_ptr=400=1936 mod 512, only the tail
    //   from mid-filter-11 onward survived) -- 2048 comfortably covers
    //   1936 with no wrap.
    //
    // v7's own result (npu_out into maxpool2x2 bit-exact vs golden
    // conv2_s for every non-degenerate filter except filter 0's known
    // leading-pulse artifact) combined with maxpool2x2's own isolated-sim
    // correctness created a contradiction that pool2_out was still wrong.
    // Resolved (advisor-directed offset sweep, tb_maxpool2x2_boundary.sv):
    // conv2_channel_done_pulse (maxpool2x2's per-filter reset) fires
    // exactly ONE pixel early relative to the true 121-pixel boundary --
    // reproduced hardware's exact filter-5 corruption bit-for-bit by
    // injecting the reset after pixel 120 instead of 121. Real fix
    // implemented: conv2_channel_done_pulse_d (one more delay register,
    // npu_top_hotstate.sv), now feeding u_maxpool2's reset. Back to v5
    // (real pool2_out values) to verify end to end.
    //   ila_probe   = {4'b0, c2_filter_cnt[3:0], pool2_out[7:0]} (16 bits)
    //   capture_en  = pool2_valid
    //   stop_trigger= (layer_phase == 9)
    //
    // Probe v8 (2026-08-21): the fresh (verified non-stale, correct
    // filter labels) re-measurement after the conv2_channel_done_pulse_d
    // (single-stage) fix STILL reproduced the pre-fix numbers byte-for-
    // byte. v8's first run (done_pulse vs done_pulse_d side by side,
    // gated on conv2_npu_valid_gated) confirmed the register survives
    // synthesis (fires one event later than raw, real hardware
    // measurement -- the earlier netlist string-match "0 occurrences"
    // was a false alarm, RTL names don't survive Gowin's renaming even
    // for known-real signals) but showed the ONE-stage delay is
    // INSUFFICIENT: one more conv2_npu_valid_gated event (filter N's
    // true last pixel) still lands between done_pulse_d and filter
    // N+1's first event, at every boundary. Depth-matching diagnosis:
    // conv2_npu_valid_gated carries TWO delay stages from the raw signal
    // (conv2_accumulate_d -> conv2_accumulate_dd) but the reset only had
    // one net stage. v8b (this probe): swapped done_pulse_d for the new
    // second stage, done_pulse_dd, to directly verify the corrected
    // depth lands the reset AFTER filter N's true last event.
    //   ila_probe   = {2'b0, c2_filter_cnt[3:0], done_pulse[1],
    //                  done_pulse_dd[1], conv2_npu_valid_gated[1]} (9 bits, padded to 16)
    //   capture_en  = done_pulse | done_pulse_dd | conv2_npu_valid_gated
    //   stop_trigger= (layer_phase == 9)
    //
    // v8c: v8b's event-sparse gating (on conv2_npu_valid_gated) gave an
    // IDENTICAL trace to the single-stage version -- ambiguous, since an
    // unchanged event-gap could mean either "the extra stage had no
    // effect" or "the extra cycle fell in a window with no
    // conv2_npu_valid_gated event to reveal it". Direct disambiguation:
    // capture ONLY the three pulse stages against each other (raw, _d,
    // _dd), independent of conv2_npu_valid_gated's own sparser timing --
    // if the register chain is real, three consecutive single-cycle-
    // apart events should appear at every boundary regardless.
    //   ila_probe   = {3'b0, c2_filter_cnt[3:0], done_pulse[1], done_pulse_d[1],
    //                  done_pulse_dd[1]} (10 bits, padded to 16)
    //   capture_en  = done_pulse | done_pulse_d | done_pulse_dd
    //
    // v8c RESULT (kept for the record): raw/d/dd fire on three
    // consecutive cycles at all 16 boundaries, every time -- the 2-stage
    // register chain survives Gowin synthesis and delays correctly. The
    // earlier v8b "still lands before filter N+1" reading was WRONG:
    // counting valid_gated events between boundary pulse pairs gives
    // exactly 121 per run (matches wr_ptr=1968=16*121+16*2 exactly) --
    // the pulse pair already sits BETWEEN filter runs, not bisecting one.
    // The "filter=0" label on the event right after the pulse pair was
    // stale (c2_filter_cnt is an undelayed microcode variable labeling a
    // now-2-stages-delayed datapath) -- same trap that made filter 0's
    // 26-sample count ambiguous earlier. Back to v5 (real pool2_out
    // values) for the actual end-to-end check.
    //   ila_probe   = {4'b0, c2_filter_cnt[3:0], pool2_out[7:0]} (16 bits)
    //   capture_en  = pool2_valid
    //
    // Probe v9 (2026-08-21, external-review-directed -- "DeepSeek",
    // relayed by the user): (2) confirmed the reset-timing fix has zero
    // measured effect on pool2's values despite two independent hardware
    // proofs the fix itself is correct -- meaning maxpool2x2's INTERNAL
    // state has never actually been observed, only inferred from
    // input/output/boundary timing (all now independently proven
    // correct). This probe captures col_count/row_parity (the
    // discriminator: clean 0/0 at a filter's first few real pixels means
    // the reset path is fine and the bug is in the window registers
    // instead; anything else means a reset/valid desync survives despite
    // the boundary-count checks) plus a direct reset&valid_in same-cycle
    // overlap flag (would silently eat a pixel via the `if(rst)...else
    // if(valid_in)` priority in maxpool2x2.sv -- untested by any prior
    // measurement this session).
    //   ila_probe   = {c2_filter_cnt[3:0], col_count[3:0] (low bits, max
    //                  value 10 fits), row_parity[1], reset_valid_overlap[1],
    //                  conv2_npu_valid_gated[1]} (11 bits, padded to 16)
    //   capture_en  = conv2_npu_valid_gated | conv2_channel_done_pulse_dd
    //                 | reset_valid_overlap
    // Probe v10 (2026-08-21, same review thread): v9's raw (unfiltered)
    // trace showed col_count/row_parity ARE clean (0,0) at every filter's
    // true first pixel -- the earlier "starts at 1" reading was the
    // already-known c2_filter_cnt label-staleness artifact, not a bug.
    // reset_valid_overlap measured zero throughout. The reset/valid_in
    // half of maxpool2x2 is now exonerated by direct observation, not
    // just boundary-event counting. Remaining suspect: the WINDOW
    // registers (top_left/bottom_left) that actually get maxed -- never
    // observed on hardware. This probe captures both directly, gated on
    // every real pixel, for comparison against golden's raw conv2_s
    // pixel-by-pixel.
    //   ila_probe   = {c2_filter_cnt[3:0], top_left[7:0], bottom_left[7:0],
    //                  conv2_npu_valid_gated[1]} (20 bits, padded to 32)
    //   capture_en  = conv2_npu_valid_gated
    //   PROBE_WIDTH bumped 16->32 (localparam above): top_left+bottom_left
    //   alone don't fit in 16 bits alongside the filter label.
    //
    // Probe v11 (2026-08-21, advisor-directed correction): v10's own
    // "operands all correct" reading turned out to be phase-invariant --
    // a whole-raster shift is absorbed by the relative lag check and
    // wouldn't show up. The actual smoking gun was already in v9's raw
    // dump: the last conv2_npu_valid_gated event before a reset always
    // read col_count=9, never the expected 10 (IN_WIDTH-1) -- meaning the
    // true 121st pixel of every filter was being consumed AFTER the
    // reset, not before it. The 1-2 cycle delay tuning (conv2_channel_
    // done_pulse_d/_dd) could never fix this: real conv2 pixels arrive
    // ~30 npu_clk cycles apart, so a couple cycles of delay only moves
    // the reset within the SAME idle gap, never across into the next
    // pixel. Real fix (npu_top_hotstate.sv): conv2_filter_reset_pulse,
    // derived by counting conv2_npu_valid_gated pulses directly (not
    // microcode timing) and firing exactly one cycle after the 121st.
    // This probe re-runs the v9-style col_count/row_parity check against
    // THIS new reset source, to verify col_count now genuinely reaches
    // 10 before the boundary.
    //   ila_probe   = {c2_filter_cnt[3:0], col_count[3:0], row_parity[1],
    //                  reset_valid_overlap[1], conv2_npu_valid_gated[1]}
    //   capture_en  = conv2_npu_valid_gated | conv2_filter_reset_pulse
    //                 | reset_valid_overlap
    // v11 CONFIRMED the counter-based fix: col_count now genuinely
    // reaches 10 (the true last pixel of an 11-wide row) before the
    // reset fires, at every boundary checked -- structurally correct,
    // not tuned. Back to v5 (real pool2_out values) for the decisive
    // end-to-end check.
    //   ila_probe   = {4'b0, c2_filter_cnt[3:0], pool2_out[7:0]} (16 bits, padded to 32)
    //   capture_en  = pool2_valid
    logic [ILA_PROBE_WIDTH-1:0] ila_probe;
    assign ila_probe = { 20'b0, trace_c2_filter_cnt, trace_pool2_out };

    logic [ILA_ADDR_WIDTH-1:0] ila_wr_ptr;
    logic ila_captured;
    logic [ILA_ADDR_WIDTH-1:0] ila_rd_addr;
    logic [ILA_PROBE_WIDTH-1:0] ila_rd_data;
    logic tx_busy; // shared uart_tx status, declared here so it's in scope for u_ila_dump below

    logic ila_stop_trigger;
    assign ila_stop_trigger = (trace_layer_phase == 5'd9);   // FC1 start -- pool2 long done

    ila_capture #(
        .PROBE_WIDTH(ILA_PROBE_WIDTH), .ADDR_WIDTH(ILA_ADDR_WIDTH)
    ) u_ila_capture (
        .clk(system_clk), .rst(npu_software_rst),
        .probe(ila_probe), .stop_trigger(ila_stop_trigger),
        .capture_en(trace_pool2_valid),
        .rd_addr(ila_rd_addr), .rd_data(ila_rd_data),
        .wr_ptr(ila_wr_ptr), .captured(ila_captured)
    );

    // 'D' (0x44) on the UART RX line requests a trace dump.
    // BUG (fixed): originally fired on ANY 0x44 byte on rx_data, with no
    // regard for whether the system was mid-image-load -- since raw
    // BloodMNIST pixel bytes span the full 0-255 range, some test images
    // (confirmed: index 100, 4 occurrences; index 26, 0) contain a 0x44
    // byte somewhere in their 2352-byte stream, spuriously firing a dump
    // request while soc_controller was still loading the image and
    // corrupting that run (empty/garbled classification byte, truncated
    // trace dump -- reproduced deterministically twice). Originally gated
    // on npu_done alone, on the assumption "npu_done is low for the
    // entire image-load window" -- true only for the very first load after
    // power-on. npu_done is a plain (non-one_shot) bool that stays HIGH
    // from the end of one inference until the next 'S' command's reset
    // pulse, which happens AFTER the next image's bytes are already
    // streamed in via 'L' -- so every load after the first still has
    // npu_done stuck high the whole time, and a stray 0x44 pixel byte in
    // THAT image spuriously fires a dump mid-load (confirmed on real
    // hardware: image 0's load flooded 162 bytes of a stale ILA dump
    // header+payload before the real classification byte). Fixed by also
    // requiring soc_controller's own state to genuinely be IDLE (not
    // mid-load), via the new `loading` output port.
    logic ila_start_dump;
    always_ff @(posedge system_clk or posedge rst) begin
        if (rst) ila_start_dump <= 1'b0;
        else     ila_start_dump <= rx_valid && (rx_data == 8'h44) && npu_done && !soc_loading;
    end

    logic ila_dumping;
    logic ila_tx_start;
    logic [7:0] ila_tx_data;

    ila_dump #(
        .PROBE_WIDTH(ILA_PROBE_WIDTH), .ADDR_WIDTH(ILA_ADDR_WIDTH)
    ) u_ila_dump (
        .clk(system_clk), .rst(rst),
        .start_dump(ila_start_dump), .captured(ila_captured), .wr_ptr(ila_wr_ptr),
        .rd_addr(ila_rd_addr), .rd_data(ila_rd_data),
        .tx_start(ila_tx_start), .tx_data(ila_tx_data), .tx_busy(tx_busy),
        .dumping(ila_dumping)
    );
`endif

    assign led = ~{2'b00, class_result};

`ifdef ILA_ENABLE
    // Shared uart_tx, arbitrated between the existing class-result byte
    // and the ILA dump. In practice these never overlap: the host script
    // always waits for the class-result byte before sending 'D', so a
    // simple fixed-priority mux (class byte wins ties) is sufficient --
    // no need for a stateful arbiter.
    logic tx_start;
    logic [7:0] tx_data;
    assign tx_start = class_tx_start | ila_tx_start;
    assign tx_data  = class_tx_start ? class_tx_data : ila_tx_data;

    uart_tx #(.CLK_FREQ(`SYS_CLK_HZ)) u_uart_tx (
        .clk(system_clk),
        .rst(rst),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_out(tx_out),
        .tx_busy(tx_busy)
    );
`else
    uart_tx #(.CLK_FREQ(`SYS_CLK_HZ)) u_uart_tx (
        .clk(system_clk),
        .rst(rst),
        .tx_start(class_tx_start),
        .tx_data(class_tx_data),
        .tx_out(tx_out),
        .tx_busy()
    );
`endif

    always_ff @(posedge system_clk or posedge rst) begin
        if(rst) begin
            class_tx_start <= 1'b0;
            class_tx_data  <= 8'd0;
            class_sent     <= 1'b0;
        end else begin
            class_tx_start <= 1'b0;

            // Clear the flag when the NPU starts a new inference
            if (!npu_done) begin
                class_sent <= 1'b0;
            end
            else if(!class_sent & npu_done) begin
                class_tx_start <= 1'b1;
                class_tx_data  <= {5'b00000, class_result} + 8'h30;
                class_sent     <= 1'b1;
            end
        end
    end
endmodule