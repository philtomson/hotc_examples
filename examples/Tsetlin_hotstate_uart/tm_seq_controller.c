// tm_seq_controller.c - Hotstate clause sequencer for 10-class TM inference
//
// Sequencing:
//   1. Wait for go
//   2. Pulse vote_rst to clear accumulators in tm_core_v2
//   3. For 200 clauses:
//        pulse start_clause, wait clause_done,
//        if fire && strength >= threshold: dispatch vN_up/vN_dn
//   4. Sequential argmax over v_out_0..v_out_9 (signed 11-bit votes from core)
//   5. Assert done, handshake go deassert
//
// Compile:
//   ../../../bin/hotc tm_seq_controller.c --microcode-hs-opt --opt --comparator-bypass --all-hdl

// ── Inputs from tm_core_v2 ────────────────────────────────────────────────
bool fire;          // 1 = clause fired (viol < LF)
bool is_pos;        // 1 = positive clause
bool clause_done;   // pulse: tm_core_v2 finished one clause, outputs stable

// Weighted clause score: LF - violations (0-LF=75), stable at clause_done.
// Only meaningful when fire=1. Weak clauses (score near 1) contribute little
// signal; suppressing them reduces noise. Comparator wire: __cmp_0.
_BitInt(7) clause_strength;

#define MIN_CLAUSE_STRENGTH 5   // skip clauses with score < 5 (viol > LF-5)

extern _BitInt(4) class_idx;  // which of 10 classes (0..9); switch only

// ── Vote outputs from tm_core_v2 (signed 11-bit, stable after clause loop) ─
_BitInt(11) v_out_0;
_BitInt(11) v_out_1;
_BitInt(11) v_out_2;
_BitInt(11) v_out_3;
_BitInt(11) v_out_4;
_BitInt(11) v_out_5;
_BitInt(11) v_out_6;
_BitInt(11) v_out_7;
_BitInt(11) v_out_8;
_BitInt(11) v_out_9;

// ── Handshake input ───────────────────────────────────────────────────────
bool go;

// ── Control outputs to tm_core_v2 ────────────────────────────────────────
bool start_clause = 0;  // pulse: begin processing next clause
bool vote_rst     = 0;  // pulse: reset all vote accumulators

// ── Enable pulse outputs (one per class × direction) ─────────────────────
bool v0_up = 0;  bool v0_dn = 0;
bool v1_up = 0;  bool v1_dn = 0;
bool v2_up = 0;  bool v2_dn = 0;
bool v3_up = 0;  bool v3_dn = 0;
bool v4_up = 0;  bool v4_dn = 0;
bool v5_up = 0;  bool v5_dn = 0;
bool v6_up = 0;  bool v6_dn = 0;
bool v7_up = 0;  bool v7_dn = 0;
bool v8_up = 0;  bool v8_dn = 0;
bool v9_up = 0;  bool v9_dn = 0;

// ── Handshake output ──────────────────────────────────────────────────────
bool done = 0;

// ── Argmax accumulators (state variables) ────────────────────────────────
_BitInt(11) current_max = 0;   // running maximum vote
_BitInt(4)  winner_out  = 0;   // index of winning class

void main() {
    unsigned char clause_cnt;

    while (1) {
        while (!go) {}
        done = 0, vote_rst = 1;
        vote_rst = 0;

        for (clause_cnt = 0; clause_cnt < 200; clause_cnt++) {
            start_clause = 1;
            start_clause = 0;

            while (!clause_done) {}

            // The outer `if (fire)` check is redundant and has been removed:
            // tm_core_v2.v computes clause_output (clause_strength's source)
            // as `(viol_total < LF) ? (LF - viol_total) : 0` -- clause_strength
            // is hard-wired to 0 whenever fire is 0, and MIN_CLAUSE_STRENGTH=5
            // is never <= 0, so `clause_strength >= MIN_CLAUSE_STRENGTH` alone
            // already implies fire=1. One fewer branch per clause dispatch.
            if (clause_strength >= MIN_CLAUSE_STRENGTH) {
                if (is_pos) {
                    switch (class_idx) {
                        case 0: v0_up = 1; v0_up = 0; break;
                        case 1: v1_up = 1; v1_up = 0; break;
                        case 2: v2_up = 1; v2_up = 0; break;
                        case 3: v3_up = 1; v3_up = 0; break;
                        case 4: v4_up = 1; v4_up = 0; break;
                        case 5: v5_up = 1; v5_up = 0; break;
                        case 6: v6_up = 1; v6_up = 0; break;
                        case 7: v7_up = 1; v7_up = 0; break;
                        case 8: v8_up = 1; v8_up = 0; break;
                        case 9: v9_up = 1; v9_up = 0; break;
                    }
                } else {
                    switch (class_idx) {
                        case 0: v0_dn = 1; v0_dn = 0; break;
                        case 1: v1_dn = 1; v1_dn = 0; break;
                        case 2: v2_dn = 1; v2_dn = 0; break;
                        case 3: v3_dn = 1; v3_dn = 0; break;
                        case 4: v4_dn = 1; v4_dn = 0; break;
                        case 5: v5_dn = 1; v5_dn = 0; break;
                        case 6: v6_dn = 1; v6_dn = 0; break;
                        case 7: v7_dn = 1; v7_dn = 0; break;
                        case 8: v8_dn = 1; v8_dn = 0; break;
                        case 9: v9_dn = 1; v9_dn = 0; break;
                    }
                }
            }
        }

        // Sequential argmax: start with class 0 as candidate, scan classes 1-9.
        // Strict > preserves lowest-index-wins tie-breaking (matches Julia argmax).
        // Serial statements: comma groups encode literal values only, so
        // `current_max = v_out_N, winner_out = K` silently wrote 0 into
        // current_max (every comparison ran against 0 - winner_out was
        // "last class with votes > 0", not the argmax). Now a compile error.
        current_max = v_out_0;
        winner_out = 0;
        if (v_out_1 > current_max) { current_max = v_out_1; winner_out = 1; }
        if (v_out_2 > current_max) { current_max = v_out_2; winner_out = 2; }
        if (v_out_3 > current_max) { current_max = v_out_3; winner_out = 3; }
        if (v_out_4 > current_max) { current_max = v_out_4; winner_out = 4; }
        if (v_out_5 > current_max) { current_max = v_out_5; winner_out = 5; }
        if (v_out_6 > current_max) { current_max = v_out_6; winner_out = 6; }
        if (v_out_7 > current_max) { current_max = v_out_7; winner_out = 7; }
        if (v_out_8 > current_max) { current_max = v_out_8; winner_out = 8; }
        if (v_out_9 > current_max) { current_max = v_out_9; winner_out = 9; }

        done = 1;
        while (go) {}
        done = 0;
    }
}
