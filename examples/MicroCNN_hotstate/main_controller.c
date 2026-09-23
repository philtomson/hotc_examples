// Hotstate microcode controller for the MicroCNN accelerator.
// Replaces the hierarchical FSM control plane (master_pipeline_fsm +
// conv1_fsm + conv2_fsm + fc1_fsm + fc2_fsm, ~850 lines of Verilog) with
// a single hotstate machine (~170 microcode instructions).
//
// The soc_controller (RTL, at system_clk) handles UART image loading and
// asserts conv1_start when the 'S' command is received.  This hotstate
// machine runs at npu_clk and produces all per-layer control signals.
// On completion it asserts npu_done, which triggers result_sender to
// transmit the classification byte over UART.
//
// Network: Conv1(3→8) → ReLU → Scale(/512) → MaxPool(2×2) →
//          Conv2(8→16) → ReLU → Scale(/256) → MaxPool(2×2) → Flatten →
//          FC1(400→32) → ReLU → Scale(/512) → FC2(32→8) → Argmax

// ── Layer-phase selector (replaces master_pipeline_fsm) ───────────────
unsigned _BitInt(5) layer_phase = 0;   // 0..18 — needs 5 bits (18 > 15)
//  0 = IDLE,         wait for conv1_start
//  1 = RUN_CONV1,    load weights + stream image for one filter
//  2 = FLUSH_CONV1,  drain maxpool pipeline after each filter
//  3 = NEXT_C1_FILT, advance to next conv1 filter (or go to conv2)
//  4 = RUN_CONV2,    shift pixels + compute MACs for one filter
//  5 = NEXT_C2_FILT, advance to next conv2 filter (or go to FC1)
//  6 = INIT_FC1_N,   clear NPU accumulators for new FC1 neuron
//  7 = COMPUTE_FC1,  feed 50 chunks to the NPU array
//  8 = DRAIN_FC1,    drain pipeline after last chunk of a neuron
//  9 = WRITE_FC1,    latch reduced sum into fc2_buffer_ram
// 10 = NEXT_FC1_N,   advance to next FC1 neuron (or go to FC2)
// 11 = INIT_FC2_N,   clear NPU accumulators for new FC2 neuron
// 12 = COMPUTE_FC2,  feed 4 chunks to the NPU array
// 13 = FLUSH_FC2,    drain pipeline after last chunk of a neuron
// 14 = EMIT_FC2,     latch result (argmax will pick winner)
// 15 = DONE,         assert npu_done

// ── Conv1 counters ─────────────────────────────────────────────────────
unsigned _BitInt(10) c1_pixel_cnt = 0;    // 0..783 within a filter
unsigned _BitInt(3)  c1_filter_cnt = 0;   // 0..7
unsigned _BitInt(5)  c1_flush_cnt = 0;    // 0..15

// ── Conv2 counters ─────────────────────────────────────────────────────
unsigned _BitInt(8)  c2_pixel_cnt = 0;    // 0..168 within a filter
unsigned _BitInt(4)  c2_filter_cnt = 0;   // 0..15
unsigned _BitInt(5)  c2_lb_row = 0;       // line-buffer row coord
unsigned _BitInt(5)  c2_lb_col = 0;       // line-buffer col coord

// ── FC1 counters ───────────────────────────────────────────────────────
unsigned _BitInt(6)  fc1_chunk_cnt = 0;   // 0..49 within a neuron
unsigned _BitInt(5)  fc1_neuron_cnt = 0;  // 0..31
unsigned _BitInt(4)  fc1_drain_cnt = 0;   // 0..15 (widened, see case 11)

// ── FC2 counters ───────────────────────────────────────────────────────
unsigned _BitInt(2)  fc2_chunk_cnt = 0;   // 0..3 within a neuron
unsigned _BitInt(3)  fc2_neuron_cnt = 0;  // 0..7
unsigned _BitInt(4)  fc2_flush_cnt = 0;   // 0..15 (widened, see case 16)

// ── Inputs from datapath / soc_controller ──────────────────────────────
extern bool conv1_layer_done;
extern bool conv2_layer_done;
extern bool fc1_layer_done;
extern bool fc2_layer_done;
extern bool conv1_start;   // 1-cycle pulse from soc_controller on 'S'

// Latch external inputs into state variables so they can be used in conditions.
bool conv1_start_latched = 0;

// ── Outputs to datapath (state variables — hotstate drives them directly)
bool img_en = 0;
bool weight_en = 0;
bool bias_en = 0;
bool shift_en = 0;
// one_shot so each `compute_en = 1` write (case 7's adjacent COMPUTE_0 /
// COMPUTE_1 pair) is a genuine 1-cycle pulse and the shared conv core sees
// exactly 2 compute cycles per conv2 output pixel, as in conv2_fsm.sv. The
// old plain-bool compute_en read as a ~22-cycle LEVEL spanning cases 6-7
// (one C statement per clock cycle), re-writing ws_conv_core_gowin's
// partial_sum_reg every one of those cycles -- clobbering the chunk-0
// partial sum a cycle before the fold once chunk_sel_d flipped ahead of
// accumulate_d. Conv1-era `compute_en = 1` writes (cases 2/3) are
// datapath-dead under one_shot's 1-cycle pulses: tdm_npu_router muxes
// window1_valid_synced into the shared core while layer_state==0. See
// case 7's comment for the full timing contract.
one_shot bool compute_en = 0;
// BUG (fixed): conv2's valid-gate downstream (tdm_npu_router.sv's
// conv2_valid_out_gated = npu_valid & layer_state & !conv2_accumulate_d)
// checks accumulate's PRE-fold (case 6, partial channels-0-3-only) phase,
// not its POST-fold (case 7, true 8-channel result) phase -- confirmed
// directly via cycle-by-cycle trace: the gate stayed open for ~13 cycles
// spanning case 6 into case 7, closing exactly when accumulate finally
// flipped to 1 (i.e. exactly when the correct folded result became
// available), so maxpool2/FC1 were consuming conv2's incomplete partial
// sum, never the true final one. one_shot turns accumulate=1 (written
// once in case 7) into a genuine single-cycle pulse instead of a level
// held across the rest of case 7's statements. The 2026-08-20 gate-polarity
// flip that shipped with this change (tdm_npu_router.sv,
// !conv2_accumulate -> conv2_accumulate) was itself wrong and has been
// REVERTED: mac_out is registered inside ws_conv_core_gowin, so the folded
// value appears on npu_out one cycle AFTER the accumulate_d cycle, and
// gating on `& conv2_accumulate` sampled the pre-fold partial (one 4-channel
// chunk only). See case 7's comment for the full COMPUTE_0/COMPUTE_1
// contract. case 6 already writes accumulate=0 (matching this initializer),
// so one_shot is a no-op there.
one_shot bool accumulate = 0;
bool chunk_sel = 0;
// BUG (over-accumulation confirmed, residual mismatch still open -- see
// hotc_microcnn_hotstate_classifier_bug_hunt.md): cases 10/15 (FC1/FC2
// "feed N chunks" loops) wrote mult_ce=1 exactly once per chunk-pass and
// never touched it again for that pass's remaining ~6-10 statements/
// cycles -- since hotc compiles one statement per clock cycle, mult_ce
// read as a continuous HIGH level for the whole pass, not a once-per-
// chunk pulse. The DSP (dsp_multalu_accum.v, no input registers, ACCLOAD
// tied permanently high -- see case 11's comment) performs a NEW
// accumulate on every cycle mult_ce is high, so this caused ~9-11x too
// many accumulates per neuron, non-uniformly. `one_shot` makes the
// single mult_ce=1 write in cases 10/15 (moved to fire AFTER the address
// is set) a genuine 1-cycle pulse. Cases 11/16 had the SAME bug in a
// different shape -- explicitly writing mult_ce in both branches of an
// if/else every iteration defeats one_shot (no cycle goes unwritten),
// so ce was held for ~2 whole loop iterations instead of 2 true clock
// cycles; fixed there too (see case 11's comment). On hardware, the
// case-10/15 fix alone reduced FC1 output magnitudes by roughly 10x
// (confirming the mechanism) but did not yet produce a full match
// against golden_benchmark.py; the case-11/16 fix's impact has not yet
// been verified on real hardware.
one_shot bool mult_ce = 0;
bool mult_clear = 0;
bool param_en = 0;
// CORRECTNESS FIX, CONFIRMED NOT the cause of the live classifier bug
// (see hotc_microcnn_hotstate_classifier_bug_hunt.md for the full A/B
// methodology). Both were written `=1` in cases 12/17 and not
// explicitly cleared until 11-13 statements later (case 9's 12th
// statement / case 14's 4th statement) on the loop-back path each
// takes for every neuron but the last -- the same "multi-cycle level,
// not a pulse" bug SHAPE already fixed 3x elsewhere in this file
// (shift_en x2, accumulate x1). Confirmed via a wr_ptr-header-verified,
// non-wrapping ILA capture (2048-slot buffer): pre-fix, fc1_valid_out
// read HIGH for ~15-19 consecutive cycles per neuron transition,
// uniformly across all 32 neurons, corrupting the NEXT neuron's
// fc2_buffer_ram slot with a slowly-settling stale value. `one_shot`
// on fc1_valid_out ALONE was A/B tested against this same baseline:
// wr_ptr dropped to exactly 32 (one clean pulse/neuron, confirming the
// fix works), but a "last write per neuron-label" reconstruction of
// BOTH pre- and post-fix runs gave IDENTICAL values for every neuron
// that mismatches golden_benchmark.py's fc1_shifted (e.g. neuron 6: 0
// vs golden 21; neuron 27: 44 vs golden 18) -- the neuron's own later
// real write was already overwriting the bleed either way, so this bug
// was latent/harmless for final RAM contents, not the root cause of
// the classifier bug. Kept (and extended to fc2_valid_out) as a
// legitimate correctness fix on its own terms -- the real remaining
// bug is somewhere in FC1's own compute/ROM-read datapath, not here.
one_shot bool fc1_valid_out = 0;
one_shot bool fc2_valid_out = 0;

unsigned _BitInt(10) img_addr = 0;
unsigned _BitInt(4)  filter_idx = 0;   // filter idx: conv1 (0..7), conv2 (0..15)
unsigned _BitInt(8)  ram_raddr = 0;    // conv2 chunk RAM read address
unsigned _BitInt(6)  fc1_ram_raddr = 0; // fc1 buffer RAM read address
unsigned _BitInt(11) fc1_weight_raddr = 0; // fc1 weight ROM address
unsigned _BitInt(5)  fc1_bias_raddr = 0;   // fc1 bias ROM address
unsigned _BitInt(2)  fc2_ram_raddr = 0;  // fc2 buffer RAM read address
unsigned _BitInt(5)  fc2_weight_raddr = 0; // fc2 weight ROM address
unsigned _BitInt(3)  fc2_bias_raddr = 0;   // fc2 bias ROM address

bool layer_state = 0;  // 0 = conv path, 1 = conv2/FC path (TDM router select)
bool npu_sleep = 1;    // gate the NPU clock via DCS when idle/done
bool npu_done = 0;     // assertion triggers result_sender UART TX

void main() {
    while (1) {
        switch (layer_phase) {

        // ── Phase 0: Idle — wait for inference start ───────────────
        case 0:
            npu_sleep = 1;
            conv1_start_latched = conv1_start;
            if (conv1_start_latched) layer_phase = 1;
            break;

        // ── Phase 1: Conv1 — load weights + bias for current filter ─
        case 1:
            layer_state = 0;
            npu_sleep = 0;   // wake the datapath clock (matches master_fsm default)
            img_en = 0;
            weight_en = 1;
            bias_en = 1;
            filter_idx = c1_filter_cnt;
            shift_en = 0;
            compute_en = 0;
            accumulate = 0;
            chunk_sel = 0;
            mult_ce = 0;
            mult_clear = 0;
            param_en = 0;
            fc1_valid_out = 0;
            fc2_valid_out = 0;
            layer_phase = 2;
            break;

        // ── Phase 2: Conv1 — stream 28×28 = 784 pixels ─────────────
        case 2:
            img_en = 1;
            weight_en = 0;
            bias_en = 0;
            compute_en = 1;
            accumulate = 0;
            chunk_sel = 0;
            // BUG (fixed): hotstate executes one C statement per clock
            // cycle, so a single pass through this case's ~9 statements
            // takes ~9 cycles -- but shift_en=1 used to be asserted early
            // and never explicitly deasserted within the case, so it (and
            // its registered copy driving unified_line_buffer) stayed
            // HIGH for the entire multi-cycle pass, shifting the SAME
            // img_rdata byte into the sliding-window line buffer ~9 times
            // per logical pixel instead of once. Confirmed directly: the
            // captured per-pixel stream showed runs of up to 9 identical
            // values (avg run length 2.8) and only 2/169 exact matches
            // against the golden maxpool1 reference. Fix: set img_addr,
            // THEN pulse shift_en high for exactly one statement/cycle
            // (immediately followed by an explicit deassert) so exactly
            // one shift happens per logical pixel, timed so img_rdata's
            // 1-cycle synchronous-read latency has already settled by the
            // time the pulse reaches the line buffer's own registered
            // shift_en_d.
            img_addr = c1_pixel_cnt;
            shift_en = 1;
            shift_en = 0;
            if (c1_pixel_cnt == 783) {
                c1_pixel_cnt = 0;
                layer_phase = 3;
            } else {
                c1_pixel_cnt = c1_pixel_cnt + 1;
            }
            break;

        // ── Phase 3: Conv1 — drain maxpool pipeline (15 cycles) ────
        case 3:
            img_en = 0;
            weight_en = 0;
            bias_en = 0;
            // BUG (fixed): shift_en was held 1 throughout this whole
            // drain phase (15 passes x this case's own multi-statement
            // duration). Since lb1_row/lb1_col are frozen at their last
            // real position (>=2,>=2) once streaming ends, every one of
            // those spurious shift_en assertions re-satisfies
            // window1_valid_combo in npu_top_hotstate.sv, re-firing
            // conv1_npu_valid/pool1_valid with the same stale repeated
            // value. conv1_to_conv2_router blindly advances its
            // pixel_cnt/ch_cnt on every pool_valid pulse with no way to
            // tell real pixels from drain spillover, so these extra
            // events desynchronize which 13x13 block lands in which of
            // its 8 channel RAMs for every channel after the first --
            // confirmed directly via a router write-event trace (169
            // clean channel-0 writes, then ~39-45 stale-value writes
            // spilling into channel 1 before filter 1's real data even
            // starts). ws_conv_core_gowin's MAC path is purely
            // combinational plus one register stage (no deep pipeline),
            // and conv1's 169 true pooled outputs are already fully
            // captured by the time streaming ends -- this drain has
            // nothing left to flush, so shift_en simply should not be
            // asserted here at all.
            shift_en = 0;
            compute_en = 1;
            accumulate = 0;
            chunk_sel = 0;
            if (c1_flush_cnt == 15) {
                c1_flush_cnt = 0;
                layer_phase = 4;
            } else {
                c1_flush_cnt = c1_flush_cnt + 1;
            }
            break;

        // ── Phase 4: Conv1 — next filter or move to conv2 ──────────
        case 4:
            layer_state = 0;
            img_en = 0;
            weight_en = 0;
            bias_en = 0;
            shift_en = 0;
            compute_en = 0;
            accumulate = 0;
            chunk_sel = 0;
            if (c1_filter_cnt == 7) {
                // All 8 conv1 filters done — advance to conv2
                c1_filter_cnt = 0;
                layer_phase = 5;
            } else {
                c1_filter_cnt = c1_filter_cnt + 1;
                layer_phase = 1;
            }
            break;

        // ── Phase 5: Conv2 — shift pixels into line buffer ─────────
        case 5:
            layer_state = 1;
            img_en = 0;
            // weight_en/bias_en asserted here (and filter_idx re-asserted
            // every cycle, not just once) so the very first weight_en
            // pulse of a new filter still reads the right filter index.
            // NOTE: conv2_param_rom's weight_en/bias_en ports are actually
            // hardwired 1'b1 in npu_top_hotstate.sv (u_conv2_params),
            // disconnected from these hotstate signals entirely -- so this
            // assignment is cosmetic/signal-discipline only, not a fix by
            // itself. The real conv2-output bug turned out to be the
            // shift_en pulse-width issue documented below.
            filter_idx = c2_filter_cnt;
            weight_en = 1;
            bias_en = 1;
            compute_en = 0;
            accumulate = 0;
            chunk_sel = 0;
            // ram_raddr hygiene: this is conv2_input_ram's read address,
            // feeding conv2_line_buffer_wrapper's data_in. It's only
            // otherwise written in phases 6/7 (compute), so without this
            // line it holds a stale value throughout every shift pass.
            // Written before c2_pixel_cnt increments, below.
            //
            // BUG (fixed): the real root cause of conv2's near-all-zero
            // raw output. hotstate executes one C statement per clock
            // cycle, so one pass through this case's statements takes
            // ~13-17 cycles -- but shift_en=1 used to be asserted once
            // and never explicitly deasserted within the case, so it (and
            // its registered copy driving unified_line_buffer) stayed
            // HIGH for the entire multi-cycle pass, shifting the SAME
            // byte into the 29-deep sliding-window line buffer ~13-17
            // times per logical pixel instead of once. This affected BOTH
            // conv1 (case 2, ~9x duplication) and conv2 (case 5, ~13-17x
            // duplication) -- confirmed directly via cycle-by-cycle RTL
            // trace: ram_raddr/img_addr each held constant for many
            // cycles while shift_en/shift_en_d stayed high the whole
            // time, and the captured 3x3 MAC window came back as 1-2
            // distinct values repeated across all 9 taps. Fix: pulse
            // shift_en high for exactly one statement/cycle (immediately
            // followed by an explicit deassert), placed right after
            // ram_raddr's write so conv2_input_ram's 1-cycle synchronous-
            // read latency has already settled by the time the pulse
            // reaches the line buffer's own registered shift_en_d.
            ram_raddr = c2_pixel_cnt;
            shift_en = 1;
            shift_en = 0;
            // Once the 3×3 window is valid, move to compute.
            // FIX (Qwen's finding, re-derived + sim/hw-verified 2026-08-20):
            // checked HERE, BEFORE the coordinate update below, so the test
            // reads c2_lb_row/c2_lb_col as left by the PREVIOUS pass -- i.e.
            // pixel k's own raster position (the pixel just shifted into the
            // window above). The old post-update ordering tested pixel
            // (k+1)'s position instead (one column ahead within a row, and
            // wrong across a row-wrap boundary), so it fired one pixel too
            // early on the first valid position of every row and never fired
            // at all on each row's true last valid column. Net effect over a
            // whole 121-pixel filter: one spurious compute at the very start
            // (using an under-populated window) and one real position never
            // computed at the very end -- a systematic one-slot content
            // shift that survived every earlier pulse-COUNT check (still
            // totals 121) and every mid-filter value check (values at a
            // shared label are identical either way -- see
            // troubleshooting_progress.md for why that comparison doesn't
            // discriminate). This mirrors the row-major count-scan pattern
            // Qwen originally described; verified directly via combined
            // mac_sum/partial_sum + pixel_cnt hardware capture that compute
            // #1 (old ordering) is genuinely spurious (no golden match) and
            // compute #2 onward matches golden shifted by one slot.
            if ((c2_lb_row >= 2) && (c2_lb_col >= 2)) {
                layer_phase = 6;
            }
            // Update 2-D line-buffer coordinates
            if (c2_lb_col == 12) {
                c2_lb_col = 0;
                c2_lb_row = c2_lb_row + 1;
            } else {
                c2_lb_col = c2_lb_col + 1;
            }
            c2_pixel_cnt = c2_pixel_cnt + 1;
            break;

        // ── Phase 6: Conv2 — settle operands (NO compute pulse) ────
        // COMPUTE_0's compute_en pulse must land on the cycle immediately
        // before COMPUTE_1's (both in case 7), and no OTHER compute_en=1
        // may fire anywhere in the conv2 flow: every extra pulse is an
        // extra npu_valid cycle, and with tdm_npu_router's !accumulate
        // gate each such cycle feeds pool2 a stale/partial mac_out. So
        // case 6 only re-settles filter_idx/ram_raddr (same values case 5
        // already wrote -- keeps the registered ROM/RAM outputs stable)
        // and defers BOTH compute cycles to case 7's adjacent comma-group
        // pair. (This case's old `compute_en = 1` was one of the two
        // sources of the former ~22-cycle compute_en level.)
        case 6:
            weight_en = 0;
            bias_en = 0;
            shift_en = 0;
            accumulate = 0;
            chunk_sel = 0;
            filter_idx = c2_filter_cnt;
            ram_raddr = c2_pixel_cnt;
            layer_phase = 7;
            break;

        // ── Phase 7: Conv2 — COMPUTE_0 + COMPUTE_1 on adjacent cycles ─
        // Mirrors conv2_fsm.sv's timing contract exactly:
        //   chunk_sel  = (state == COMPUTE_1);
        //   accumulate = (state == COMPUTE_1);
        //   compute_en = (state == COMPUTE_0) || (state == COMPUTE_1);
        // Per output pixel the core sees exactly 2 compute_en cycles, with
        // chunk_sel/accumulate rising TOGETHER on the second:
        //   edge 1 (COMPUTE_0): partial_sum_reg <= bias + MACs(chunk 0)
        //   edge 2 (COMPUTE_1): mac_out <= relu((partial + MACs(chunk 1)) >>> 8)
        // -- the folded 8-channel result, which being REGISTERED only
        // appears on npu_out the cycle AFTER edge 2. tdm_npu_router's gate
        // (npu_valid & !conv2_accumulate, as in the reference) opens for
        // exactly that one cycle, because npu_valid (valid_out <=
        // compute_en) outlasts the 1-cycle accumulate_d by one cycle.
        //
        // Why one_shot + comma groups (2026-08-20 findings A/B,
        // troubleshooting_progress.md): the old code wrote compute_en,
        // chunk_sel, accumulate on SEPARATE statements -- a ~22-cycle
        // compute_en level that re-wrote partial_sum_reg with
        // bias+MACs(chunk 1) BEFORE the fold (chunk_sel_d one cycle ahead
        // of accumulate_d), plus a router gate (since reverted) that
        // sampled mac_out DURING the fold cycle when it still held the
        // PRE-fold value. Net: pool2 was fed relu((bias + one 4-channel
        // chunk) >>> 8) every pixel -- one half of the channels, never
        // both -- which collapses FC2 to a constant argmax. chunk_sel and
        // accumulate MUST rise in the same comma group, and the two
        // compute cycles MUST be adjacent (a gap opens the !accumulate
        // gate on the fresh chunk-0 partial in between).
        case 7:
            weight_en = 0;
            bias_en = 0;
            shift_en = 0;
            filter_idx = c2_filter_cnt;
            ram_raddr = c2_pixel_cnt;
            compute_en = 1, chunk_sel = 0, accumulate = 0;
            compute_en = 1, chunk_sel = 1, accumulate = 1;
            // After computing the last valid output pixel (window at row12,
            // col12, i.e. pixel k=168), next filter or done.
            // BOUNDARY IS 169, NOT 168 (2026-08-20 re-fix, see case 5's
            // comment). Case 5's window-valid check now fires BEFORE the
            // c2_pixel_cnt increment, so it tests pixel k's own position and
            // reaches case 7 with c2_pixel_cnt already incremented to k+1.
            // The last valid k is 168 (row12,col12 -- both dimensions
            // maxed), so the transitioning pass is captured here with
            // c2_pixel_cnt==169. (An earlier same-day attempt at this fix
            // added an extra `&& c2_pixel_cnt>=29` term to case 5 instead of
            // reordering the check, and moved this boundary to 169 without
            // that reordering -- k=169 is (row13,col0), col<2, so that
            // version's ==169 could never fire and c2_pixel_cnt wrapped at
            // 255. That attempt was reverted; this is the reorder-based fix.)
            // NOTE: this constant was ALSO 168 in an earlier, unrelated
            // historical fix (pre-dates case 5's reordering) that corrected
            // a then-post-update check's own off-by-one -- see git history /
            // troubleshooting_progress.md if reconciling old commit
            // messages against this comment.
            if (c2_pixel_cnt == 169) {
                if (c2_filter_cnt == 15) {
                    layer_phase = 8;
                } else {
                    c2_filter_cnt = c2_filter_cnt + 1;
                    c2_pixel_cnt = 0;
                    c2_lb_row = 0;
                    c2_lb_col = 0;
                    layer_phase = 5;
                }
            } else {
                layer_phase = 5;
            }
            break;

        // ── Phase 8: Conv2 done — move to FC1 ──────────────────────
        case 8:
            layer_state = 1;
            shift_en = 0;
            compute_en = 0;
            accumulate = 0;
            chunk_sel = 0;
            c2_filter_cnt = 0;
            c2_pixel_cnt = 0;
            c2_lb_row = 0;
            c2_lb_col = 0;
            layer_phase = 9;
            break;

        // ── Phase 9: FC1 — clear NPU accumulators for new neuron ───
        case 9:
            layer_state = 1;
            img_en = 0;
            weight_en = 0;
            bias_en = 0;
            shift_en = 0;
            compute_en = 0;
            accumulate = 0;
            chunk_sel = 0;
            mult_clear = 1;
            mult_ce = 0;
            param_en = 0;
            fc1_valid_out = 0;
            fc2_valid_out = 0;
            layer_phase = 10;
            break;

        // ── Phase 10: FC1 — feed 50 chunks per neuron ──────────────
        // BUG (over-accumulation mechanism confirmed and reduced ~10x on
        // hardware; full match against golden_benchmark.py NOT yet
        // achieved -- see hotc_microcnn_hotstate_classifier_bug_hunt.md):
        // mult_ce was set `=1` once here and never
        // touched again for the rest of this case's ~8-statement body,
        // so on every one of the ~9-11 microcode cycles it takes to
        // get through one pass of this loop (hotc: one C statement per
        // clock cycle), mult_ce read as a continuous HIGH level, not a
        // once-per-chunk pulse. dsp_multalu_accum.v's MULTALU18X18 has
        // no input registers and ACCLOAD tied permanently high (see
        // case 11's comment), so the DSP performed a NEW multiply-
        // accumulate on every one of those cycles using whatever
        // stale/settling data was on the bus -- roughly 9-11x too many
        // accumulates per neuron, non-uniformly (branch-dependent cycle
        // counts), explaining the scrambled (not uniformly-scaled)
        // mismatches against golden_benchmark.py found via ILA (e.g.
        // neuron 6: 0 vs golden 21; neuron 20: 32 vs golden 8; neuron
        // 27: 44 vs golden 18). Fixed by moving mult_ce=1 to fire AFTER
        // the address is set (so the DSP consumes settled data, not a
        // stale address) and making it `one_shot` so it pulses for
        // exactly one cycle per chunk instead of persisting across the
        // whole ~9-11-cycle pass. param_en deliberately stays a
        // continuous level (unlike mult_ce, it just keeps a registered
        // ROM-read enable stable/idempotent, not accumulate-triggering).
        case 10:
            mult_clear = 0;
            param_en = 1;
            fc1_ram_raddr = fc1_chunk_cnt;
            // weight_addr = neuron_cnt * 50 + chunk_cnt  (combinatorial)
            // BUG (fixed): was `(fc1_neuron_cnt << 5)` (<<5 = *32), almost
            // certainly copy-pasted from FC2's analogous
            // `(fc2_neuron_cnt << 2) + fc2_chunk_cnt` -- correct there
            // since FC2 genuinely has 4=2^2 chunks/neuron, but FC1 has 50
            // chunks/neuron (fc1_param_rom.sv's own header comment: "0 to
            // 1599 (32 neurons * 50 chunks)"), not a power of 2. Neuron 0
            // happened to read correctly (0*32 == 0*50 == 0), so every
            // other neuron read a scrambled, partially-overlapping set of
            // weight rows -- confirmed by comparing this design's FC1
            // output vector against golden_benchmark.py's for the same
            // image: completely different neurons activated, not just a
            // scaling/precision difference.
            fc1_weight_raddr = (fc1_neuron_cnt * 50) + fc1_chunk_cnt;
            fc1_bias_raddr = fc1_neuron_cnt;
            mult_ce = 1;
            if (fc1_chunk_cnt == 49) {
                fc1_chunk_cnt = 0;
                layer_phase = 11;
            } else {
                fc1_chunk_cnt = fc1_chunk_cnt + 1;
            }
            break;

        // ── Phase 11: FC1 — drain pipeline (16 cycles) ─────────────
        // CORRECTNESS FIX, ZERO MEASURED VALUE IMPACT (verified on real
        // hardware via a dedicated free-running mult_ce/fc1_ram_raddr
        // probe: exactly 50 feed pulses + exactly 3 drain pulses, 53
        // total, matches the reference FSM's count precisely, correct
        // settle timing, no anomalies -- but the resulting fc2_wdata
        // vector was numerically IDENTICAL before/after this fix. So
        // this is a real, verified-correct structural change, not a
        // "fix" for the still-open classifier bug -- see
        // hotc_microcnn_hotstate_classifier_bug_hunt.md). Root cause was
        // the same over-accumulation mechanism as case 10, but
        // hiding behind a passing A/B test until case 10 was fixed. The
        // old code wrote mult_ce in BOTH if/else branches every
        // iteration ("if drain_cnt<2: ce=1 else: ce=0"), which -- same
        // as `one_shot` having no effect when a variable is explicitly
        // written on every path -- held ce=1 as a continuous level for
        // the ENTIRE body of drain_cnt's first 2 ITERATIONS (~5-6
        // statement-cycles each, ~10-12 cycles total), not the 2 cycles
        // the comment claimed. fc1_ram_raddr/fc1_weight_raddr are frozen
        // at the last chunk's address here (case 10 stops advancing them
        // once fc1_chunk_cnt==49), so those extra held cycles re-fed the
        // same frozen operand into the DSP's un-registered a/b inputs
        // (AREG=BREG=CREG=DREG=0) over and over -- the reference design's
        // fc1_fsm.sv DRAIN_PIPELINE state holds mult_ce=1 for exactly 3
        // true clock cycles ("Keep NPU pipeline moving for the final
        // chunks", matching OUT_REG=1/PIPE_REG=1's 2-cycle result
        // latency with one cycle of margin), not 3 iterations of a
        // multi-statement loop. Fixed by using 3 separate one-shot
        // pulses gated on specific drain_cnt values -- each is a single
        // microcode statement/cycle, so `mult_ce` auto-clears (one_shot)
        // immediately after, giving exactly 3 real CE-high cycles
        // total (with gaps from the surrounding statements in between,
        // which is harmless since the frozen address is unchanged
        // across the whole drain window either way).
        case 11:
            mult_clear = 0;
            param_en = 0;
            if (fc1_drain_cnt == 0) {
                mult_ce = 1;
            }
            if (fc1_drain_cnt == 1) {
                mult_ce = 1;
            }
            if (fc1_drain_cnt == 2) {
                mult_ce = 1;
            }
            if (fc1_drain_cnt == 15) {
                fc1_drain_cnt = 0;
                layer_phase = 12;
            } else {
                fc1_drain_cnt = fc1_drain_cnt + 1;
            }
            break;

        // ── Phase 12: FC1 — latch neuron result into fc2_buffer_ram ─
        case 12:
            mult_clear = 0;
            mult_ce = 0;
            param_en = 0;
            fc1_valid_out = 1;
            if (fc1_neuron_cnt == 31) {
                fc1_neuron_cnt = 0;
                layer_phase = 13;
            } else {
                fc1_neuron_cnt = fc1_neuron_cnt + 1;
                layer_phase = 9;
            }
            break;

        // ── Phase 13: FC1 done — move to FC2 ───────────────────────
        case 13:
            fc1_valid_out = 0;
            fc1_neuron_cnt = 0;
            layer_phase = 14;
            break;

        // ── Phase 14: FC2 — clear NPU accumulators for new neuron ──
        case 14:
            mult_clear = 1;
            mult_ce = 0;
            param_en = 0;
            fc2_valid_out = 0;
            layer_phase = 15;
            break;

        // ── Phase 15: FC2 — feed 4 chunks per neuron ───────────────
        // BUG (fixed): same root cause as case 10 -- mult_ce was set
        // once and left as a continuous level across this ~7-statement
        // loop body instead of pulsing once per chunk. See case 10's
        // comment for the full mechanism.
        case 15:
            mult_clear = 0;
            param_en = 1;
            fc2_ram_raddr = fc2_chunk_cnt;
            // weight_addr = {neuron_cnt[2:0], chunk_cnt[1:0]}  (6 bits)
            fc2_weight_raddr = (fc2_neuron_cnt << 2) + fc2_chunk_cnt;
            fc2_bias_raddr = fc2_neuron_cnt;
            mult_ce = 1;
            if (fc2_chunk_cnt == 3) {
                fc2_chunk_cnt = 0;
                layer_phase = 16;
            } else {
                fc2_chunk_cnt = fc2_chunk_cnt + 1;
            }
            break;

        // ── Phase 16: FC2 — drain pipeline (16 cycles) ─────────────
        // CORRECTNESS FIX, value impact not independently measured (not
        // yet re-probed for FC2 specifically, but case 11's identical
        // fix showed zero measured impact on FC1's output -- see its
        // comment). Same root cause and fix as case 11 -- mult_ce was
        // held as a continuous level across ~2 iterations (~10-12
        // cycles) instead of pulsing for exactly 3 true clock cycles.
        case 16:
            mult_clear = 0;
            param_en = 0;
            if (fc2_flush_cnt == 0) {
                mult_ce = 1;
            }
            if (fc2_flush_cnt == 1) {
                mult_ce = 1;
            }
            if (fc2_flush_cnt == 2) {
                mult_ce = 1;
            }
            if (fc2_flush_cnt == 15) {
                fc2_flush_cnt = 0;
                layer_phase = 17;
            } else {
                fc2_flush_cnt = fc2_flush_cnt + 1;
            }
            break;

        // ── Phase 17: FC2 — latch neuron result, advance or done ───
        case 17:
            mult_clear = 0;
            mult_ce = 0;
            param_en = 0;
            fc2_valid_out = 1;
            if (fc2_neuron_cnt == 7) {
                fc2_neuron_cnt = 0;
                layer_phase = 18;
            } else {
                fc2_neuron_cnt = fc2_neuron_cnt + 1;
                layer_phase = 14;
            }
            break;

        // ── Phase 18: Done — assert npu_done, sleep NPU clock ──────
        case 18:
            mult_clear = 0;
            mult_ce = 0;
            param_en = 0;
            fc1_valid_out = 0;
            fc2_valid_out = 0;
            npu_done = 1;
            npu_sleep = 1;
            layer_phase = 18;  // hold
            break;

        default:
            layer_phase = 0;
            break;
        }
    }
}
