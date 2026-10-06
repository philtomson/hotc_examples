// Hotstate microcode controller for the MicroCNN accelerator.
// Replaces the hierarchical FSM control plane (master_pipeline_fsm +
// conv1_fsm + conv2_fsm + fc1_fsm + fc2_fsm, ~850 lines of Verilog) with
// a single hotstate machine (144 microcode instructions).
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
// A recurring pattern in this file: hotc runs one statement per clock and
// a plain variable keeps its value until written again, so `x = 1;`
// followed by several unrelated statements is a multi-cycle LEVEL, not a
// pulse. Signals the datapath must see for exactly one cycle are declared
// `one_shot` (auto-cleared the cycle after each write). Writing a
// one_shot on every path of every cycle (e.g. both branches of an
// if/else in a loop) defeats it -- see case 11.
//
// accumulate: written 1 once in case 7 (COMPUTE_1, the conv2 fold) and
// must be a single-cycle pulse there; held as a level, it would keep
// ws_conv_core_gowin folding past the end of the pixel. case 6 writes 0,
// matching this initializer. The conv2 output gate that consumes it is
// documented in tdm_npu_router.sv (conv2_accumulate_gate); see case 7's
// comment for the full COMPUTE_0/COMPUTE_1 timing.
one_shot bool accumulate = 0;
bool chunk_sel = 0;
// mult_ce: the FC DSPs (dsp_multalu_accum.v -- no input registers, ACCLOAD
// tied high, see case 11) accumulate on EVERY cycle mult_ce is high, so it
// must pulse exactly once per chunk. Cases 10/15 write it once per pass,
// after the address is set.
one_shot bool mult_ce = 0;
bool mult_clear = 0;
bool param_en = 0;
// fc1_valid_out/fc2_valid_out: written 1 in cases 12/17, and on the
// loop-back path for every neuron but the last nothing clears them for
// another 11-13 statements. As levels they held fc2_buffer_ram's write
// enable for ~15-19 cycles per neuron, writing a not-yet-settled value
// into the next neuron's slot (later overwritten by that neuron's own
// write). one_shot gives exactly one write per neuron.
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
            // One instruction. weight_en/bias_en are high for exactly one
            // cycle: conv1_param_rom reads the whole filter on that edge.
            layer_state = 0, npu_sleep = 0, img_en = 0,
            weight_en = 1, bias_en = 1, filter_idx = c1_filter_cnt,
            shift_en = 0, compute_en = 0, accumulate = 0, chunk_sel = 0,
            mult_ce = 0, mult_clear = 0, param_en = 0,
            fc1_valid_out = 0, fc2_valid_out = 0, layer_phase = 2;
            break;

        // ── Phase 2: Conv1 — stream 28×28 = 784 pixels ─────────────
        case 2:
            // img_addr shares the enables' instruction, so it still lands
            // exactly one cycle before shift_en (see below).
            img_en = 1, weight_en = 0, bias_en = 0, compute_en = 1,
            accumulate = 0, chunk_sel = 0, img_addr = c1_pixel_cnt;
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
            shift_en = 1;
            shift_en = 0;
            if (c1_pixel_cnt == 783) {
                c1_pixel_cnt = 0, layer_phase = 3;
            } else {
                c1_pixel_cnt = c1_pixel_cnt + 1;
            }
            break;

        // ── Phase 3: Conv1 — drain maxpool pipeline (15 cycles) ────
        case 3:
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
            img_en = 0, weight_en = 0, bias_en = 0, shift_en = 0,
            compute_en = 1, accumulate = 0, chunk_sel = 0;
            if (c1_flush_cnt == 15) {
                c1_flush_cnt = 0, layer_phase = 4;
            } else {
                c1_flush_cnt = c1_flush_cnt + 1;
            }
            break;

        // ── Phase 4: Conv1 — next filter or move to conv2 ──────────
        case 4:
            layer_state = 0, img_en = 0, weight_en = 0, bias_en = 0,
            shift_en = 0, compute_en = 0, accumulate = 0, chunk_sel = 0;
            if (c1_filter_cnt == 7) {
                // All 8 conv1 filters done — advance to conv2
                c1_filter_cnt = 0, layer_phase = 5;
            } else {
                c1_filter_cnt = c1_filter_cnt + 1, layer_phase = 1;
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
            // Checked HERE, BEFORE the coordinate update below, so it reads
            // c2_lb_row/c2_lb_col for pixel k itself (the pixel just shifted
            // into the window above). Checking after the update would test
            // pixel k+1's position: one spurious compute at the start of each
            // filter (on an under-filled window) and the last real position
            // never computed. The total is still 121 computes, so a pulse
            // count alone doesn't catch it; the outputs are shifted by one.
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
        // may fire anywhere in the conv2 flow: every extra pulse makes the
        // core compute again, overwriting partial_sum_reg or mac_out. So
        // case 6 only re-settles filter_idx/ram_raddr (same values case 5
        // already wrote -- keeps the registered ROM/RAM outputs stable)
        // and defers BOTH compute cycles to case 7's adjacent comma-group
        // pair.
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
        // appears on npu_out the cycle AFTER edge 2. tdm_npu_router passes
        // npu_out to pool2 only on that cycle (see conv2_accumulate_gate
        // there).
        //
        // Why one_shot + comma groups: written on SEPARATE statements,
        // compute_en becomes a long level that re-writes partial_sum_reg
        // with bias+MACs(chunk 1) before the fold, and chunk_sel lands a
        // cycle ahead of accumulate. pool2 then sees only one 4-channel
        // half per pixel, which collapses FC2 to a constant argmax.
        // chunk_sel and accumulate MUST rise in the same comma group, and
        // the two compute cycles MUST be adjacent.
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
            // BOUNDARY IS 169, NOT 168: case 5's window-valid check runs
            // BEFORE the c2_pixel_cnt increment, so it tests pixel k's own
            // position and reaches here with c2_pixel_cnt already k+1. The
            // last valid k is 168 (row12,col12), hence ==169.
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
            layer_state = 1, shift_en = 0, compute_en = 0, accumulate = 0, chunk_sel = 0,
            c2_filter_cnt = 0, c2_pixel_cnt = 0, c2_lb_row = 0, c2_lb_col = 0,
            layer_phase = 9;
            break;

        // ── Phase 9: FC1 — clear NPU accumulators for new neuron ───
        case 9:
            // One instruction: mult_clear is high for exactly one cycle, until
            // case 10's first instruction clears it.
            layer_state = 1, img_en = 0, weight_en = 0, bias_en = 0, shift_en = 0,
            compute_en = 0, accumulate = 0, chunk_sel = 0, mult_clear = 1,
            mult_ce = 0, param_en = 0, fc1_valid_out = 0, fc2_valid_out = 0,
            layer_phase = 10;
            break;

        // ── Phase 10: FC1 — feed 50 chunks per neuron ──────────────
        // mult_ce (one_shot, see its declaration) fires once per chunk,
        // AFTER the addresses are set so the DSP consumes settled data.
        // A pass through this case takes ~9-11 cycles; as a level, mult_ce
        // would accumulate on every one of them. param_en deliberately
        // stays a level: it only keeps a registered ROM read enabled.
        case 10:
            // One instruction for all three addresses; mult_ce follows in the
            // next, so every synchronous read has exactly one edge to complete.
            mult_clear = 0, param_en = 1, fc1_ram_raddr = fc1_chunk_cnt,
            // weight_addr = neuron_cnt * 50 + chunk_cnt  (combinatorial)
            // A real multiply, unlike FC2's `<< 2`: FC1 has 50 chunks per
            // neuron (fc1_param_rom.sv: 32 neurons * 50 chunks), not a
            // power of 2.
            fc1_weight_raddr = (fc1_neuron_cnt * 50) + fc1_chunk_cnt,
            fc1_bias_raddr = fc1_neuron_cnt;
            mult_ce = 1;
            if (fc1_chunk_cnt == 49) {
                fc1_chunk_cnt = 0, layer_phase = 11;
            } else {
                fc1_chunk_cnt = fc1_chunk_cnt + 1;
            }
            break;

        // ── Phase 11: FC1 — drain pipeline (16 cycles) ─────────────
        // The original design's fc1_fsm.sv DRAIN_PIPELINE holds mult_ce=1
        // for exactly 3 clock cycles (OUT_REG=1/PIPE_REG=1's 2-cycle result
        // latency plus one of margin) -- 3 cycles, not 3 iterations of a
        // multi-statement loop. So this uses 3 separate one_shot pulses
        // gated on specific drain_cnt values: exactly 3 CE-high cycles
        // (on hardware: 50 feed + 3 drain = 53 pulses per neuron). Writing
        // mult_ce in both branches of an if/else every iteration would
        // defeat one_shot and hold it for whole iterations, re-feeding the
        // frozen last-chunk operand (the DSP inputs are unregistered,
        // AREG=BREG=CREG=DREG=0). The gaps between pulses are harmless:
        // case 10 has stopped advancing the addresses.
        case 11:
            mult_clear = 0, param_en = 0;
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
                fc1_drain_cnt = 0, layer_phase = 12;
            } else {
                fc1_drain_cnt = fc1_drain_cnt + 1;
            }
            break;

        // ── Phase 12: FC1 — latch neuron result into fc2_buffer_ram ─
        case 12:
            mult_clear = 0, mult_ce = 0, param_en = 0, fc1_valid_out = 1;
            if (fc1_neuron_cnt == 31) {
                fc1_neuron_cnt = 0, layer_phase = 13;
            } else {
                fc1_neuron_cnt = fc1_neuron_cnt + 1, layer_phase = 9;
            }
            break;

        // ── Phase 13: FC1 done — move to FC2 ───────────────────────
        case 13:
            fc1_valid_out = 0, fc1_neuron_cnt = 0, layer_phase = 14;
            break;

        // ── Phase 14: FC2 — clear NPU accumulators for new neuron ──
        case 14:
            // One instruction: mult_clear is high for exactly one cycle (see case 9).
            mult_clear = 1, mult_ce = 0, param_en = 0, fc2_valid_out = 0,
            layer_phase = 15;
            break;

        // ── Phase 15: FC2 — feed 4 chunks per neuron ───────────────
        // mult_ce pulses once per chunk, as in case 10.
        case 15:
            // As in case 10: addresses in one instruction, mult_ce in the next.
            mult_clear = 0, param_en = 1, fc2_ram_raddr = fc2_chunk_cnt,
            // weight_addr = {neuron_cnt[2:0], chunk_cnt[1:0]}  (6 bits)
            fc2_weight_raddr = (fc2_neuron_cnt << 2) + fc2_chunk_cnt,
            fc2_bias_raddr = fc2_neuron_cnt;
            mult_ce = 1;
            if (fc2_chunk_cnt == 3) {
                fc2_chunk_cnt = 0, layer_phase = 16;
            } else {
                fc2_chunk_cnt = fc2_chunk_cnt + 1;
            }
            break;

        // ── Phase 16: FC2 — drain pipeline (16 cycles) ─────────────
        // Exactly 3 one_shot mult_ce pulses, as in case 11.
        case 16:
            mult_clear = 0, param_en = 0;
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
                fc2_flush_cnt = 0, layer_phase = 17;
            } else {
                fc2_flush_cnt = fc2_flush_cnt + 1;
            }
            break;

        // ── Phase 17: FC2 — latch neuron result, advance or done ───
        case 17:
            mult_clear = 0, mult_ce = 0, param_en = 0, fc2_valid_out = 1;
            if (fc2_neuron_cnt == 7) {
                fc2_neuron_cnt = 0, layer_phase = 18;
            } else {
                fc2_neuron_cnt = fc2_neuron_cnt + 1, layer_phase = 14;
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
