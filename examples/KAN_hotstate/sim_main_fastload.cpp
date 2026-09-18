// sim_main_fastload.cpp -- fast functional test for kan_fastload_dut.v.
// Streams all 6,750,208 weight bytes into SDRAM, then classifies N samples
// from KAN_LUT's tb_data.txt and checks each against the reference scores.
//
// clk/clk_sdram are toggled directly from C++ rather than by Verilog
// #delay/@(posedge) under Verilator's --timing scheduler: the --timing
// version was far too slow to finish a multi-million-byte load (it didn't
// clear 2000 bytes in a minute of wall time). Same pattern as
// examples/hdmi_gpu/sim_main.cpp.
//
// Usage: Vkan_fastload_dut [num_samples] [expected_weight_bytes]
//   num_samples           tb_data.txt lines to classify (default 20)
//   expected_weight_bytes size of weights.bin to expect (default 6750208).
//                         Any other value selects LIVENESS mode: SDRAM holds
//                         only a prefix of the real weights, so the class is
//                         meaningless and only "did we get a result at all"
//                         is asserted. Used to iterate on handshake pacing
//                         without paying the ~7-minute full weight load.
//
// HANDSHAKE PACING -- the reason this file is fussier than it looks.
// kan_control.c polls `while (!rx_done) {}` (kan_control.c:175, :182): a
// plain level poll with NO ack handshake. On real hardware a UART byte at
// 2 Mbaud arrives every ~270 cycles against a ~15-cycle per-byte code path,
// so the poll cannot be missed. This harness has no such margin, so a
// naive one-tick rx_done pulse races kan_control's loop overhead and is
// silently dropped -- the machine then parks in the poll forever and the
// run hangs with no output. Both paths below are paced deliberately:
//   - weights: rx_done is HELD until sdram_wr_req rises (self-synchronizing,
//     costs no extra ticks, and cannot be double-consumed because
//     kan_control only returns to the poll after the write completes).
//   - images: rx_done is HELD until kan_control's in_mem write-enable pulses
//     (the per-byte ack), for the same reason.
// Every spin-wait below is bounded and reports where it stalled, so a hang
// is diagnosed in seconds instead of looking like a slow run.

#include <verilated.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include "Vkan_fastload_dut.h"

// ---- Software golden model -------------------------------------------------
// Bit-exact reimplementation of what kan_control.c computes, over the same
// weights.bin. Verified independently against KAN_LUT's tb_data.txt reference
// scores (exact match on all 10 checked samples), so a disagreement between
// this and the hardware is a hardware/compilation problem, not a difference of
// opinion about the algorithm. Having layer 1 checked separately is what makes
// a wrong answer localisable instead of just "wrong class".
static std::vector<uint16_t> g_weights;      // 16-bit LUT entries
static const long L2_BASE = 3211264;         // layer-2 base, in WORDS

static int sext(uint16_t raw, int bits) {
    int v = raw & ((1 << bits) - 1);
    return (v & (1 << (bits - 1))) ? v - (1 << bits) : v;
}
static int clamp_round(long acc) {           // (acc + 8) >> 4, then clamp 0..255
    long sh = (acc + 8) >> 4;
    return sh < 0 ? 0 : (sh > 255 ? 255 : (int)sh);
}
static void golden(const uint8_t *img, int *l1_out, int *scores) {
    for (int q = 0; q < 64; q++) {
        long acc = 0;
        for (int p = 0; p < 196; p++)
            acc += sext(g_weights[(long)(q * 196 + p) * 256 + img[p]], 14);
        l1_out[q] = clamp_round(acc);
    }
    for (int q = 0; q < 10; q++) {
        long acc = 0;
        for (int p = 0; p < 64; p++)
            acc += sext(g_weights[L2_BASE + (long)(q * 64 + p) * 256 + l1_out[p]], 13);
        scores[q] = clamp_round(acc);
    }
}

static Vkan_fastload_dut *dut;
static VerilatedContext *ctxp;
static long refresh_ticks = 0;

static int  hw_l1[64];
static bool hw_l1_seen[64];
static int  hw_l1_writes = 0;
static bool capture_l1 = false;

static void tick() {
    dut->clk = 0; dut->clk_sdram = 1; dut->eval(); ctxp->timeInc(1);

    // Sample the layer1_out store in the LOW phase, before the rising edge.
    // kan_control_template.v latches
    //     if (states_bus[236]) layer1_out_bram[states_bus[81:74]] <= states_bus[220:212];
    // so the values the BRAM captures are the ones standing BEFORE the edge.
    // Reading these taps after the posedge eval() instead returns states_bus's
    // NEW value -- a one-cycle skew that made a correct layer 1 look like
    // garbage (runs of 0 and 255) and sent this chase off after arithmetic
    // bugs that were never there.
    if (capture_l1 && dut->l1_wr_en) {
        int a = dut->l1_wr_addr & 0x7f;
        if (a < 64) {
            if (!hw_l1_seen[a]) hw_l1_writes++;
            hw_l1[a] = dut->l1_wr_data & 0x1ff;
            hw_l1_seen[a] = true;
        }
    }

    dut->clk = 1; dut->clk_sdram = 0; dut->eval(); ctxp->timeInc(1);
    if (dut->refresh_active) refresh_ticks++;
}

// Per-byte handshakes settle in a few cycles, so a tight bound catches a
// stuck handshake fast. A full inference is a different order of magnitude:
// layer 1 alone is 64*196 = 12,544 weight reads, each two SDRAM byte-reads
// plus address arithmetic, so millions of cycles is NORMAL, not a hang.
// (A 200k bound here previously reported a healthy run as a stall.)
static const long SPIN_LIMIT        = 200000;
static const long SPIN_LIMIT_RESULT = 200000000;

// Bounded spin. Returns false (after reporting) instead of hanging forever.
#define SPIN_UNTIL_N(cond, what, ctx, limit)                                 \
    do {                                                                     \
        long _n = 0;                                                         \
        while (!(cond)) {                                                    \
            tick();                                                          \
            if (++_n % 20000000 == 0)                                        \
                std::cout << "[TB]   ... " << _n << " cycles waiting for "   \
                          << (what) << "\n";                                 \
            if (_n > (limit)) {                                              \
                std::cout << "[TB] FAIL: stalled " << (limit)                \
                          << " cycles waiting for " << (what)                \
                          << " (" << ctx << ")"                              \
                          << "  wr_req=" << (int)dut->sdram_wr_req           \
                          << " rd_req=" << (int)dut->sdram_rd_req            \
                          << " busy="   << (int)dut->sdram_busy              \
                          << " tx_start=" << (int)dut->tx_start << "\n";     \
                return false;                                                \
            }                                                                \
        }                                                                    \
    } while (0)

#define SPIN_UNTIL(cond, what, ctx) SPIN_UNTIL_N(cond, what, ctx, SPIN_LIMIT)

static bool send_weight_byte(uint8_t b, long idx) {
    dut->rx_byte = b;
    dut->rx_done = 1;                       // HELD, not pulsed
    SPIN_UNTIL(dut->sdram_wr_req, "sdram_wr_req after rx_done", "weight byte " << idx);
    dut->rx_done = 0;                       // consumed; safe to drop
    SPIN_UNTIL(dut->sdram_busy, "write ack (sdram_busy)", "weight byte " << idx);
    SPIN_UNTIL(!dut->sdram_busy, "write completion", "weight byte " << idx);
    return true;
}

// The image path gets the same hold-until-acked treatment as the weight
// path, using kan_control's in_mem write-enable as the per-byte ack. This is
// deterministic: a 1-cycle rx_done pulse is missed outright (the engine's
// fetch is pipelined, so a polling loop need not evaluate its condition every
// cycle, and kan_control then parks in load_image() forever -- measured), and
// a fixed longer hold risks the byte being consumed twice. Holding until the
// BRAM store actually fires has neither failure mode.
static bool send_image_byte(uint8_t b, int p) {
    dut->rx_byte = b;
    dut->rx_done = 1;
    SPIN_UNTIL(dut->in_mem_wr_en, "in_mem write-enable (image byte accepted)", "image byte " << p);
    dut->rx_done = 0;
    SPIN_UNTIL(!dut->in_mem_wr_en, "in_mem write-enable to clear", "image byte " << p);
    return true;
}

static bool run(int num_samples, long expect_bytes, bool liveness) {

    dut->resetn = 0; dut->rx_done = 0; dut->rx_byte = 0;
    for (int i = 0; i < 64; i++) tick();
    dut->resetn = 1;
    for (int i = 0; i < 64; i++) tick();

    // ---- Stream all weight bytes -------------------------------------------
    std::ifstream wfile("weights.bin", std::ios::binary);
    if (!wfile) {
        std::cout << "[TB] FAIL: could not open weights.bin (run pack_weights.py first)\n";
        return false;
    }
    std::cout << "[TB] Streaming weights.bin ...\n";
    long i = 0;
    char byte;
    std::vector<uint8_t> raw;
    raw.reserve(6750208);
    while (wfile.get(byte)) {
        raw.push_back((uint8_t)byte);
        if (!send_weight_byte((uint8_t)byte, i)) return false;
        if (++i % 250000 == 0)
            std::cout << "[TB]   " << i << " / 6750208 weight bytes\n";
    }
    wfile.close();
    g_weights.resize(raw.size() / 2);
    for (size_t k = 0; k < g_weights.size(); k++)
        g_weights[k] = (uint16_t)(raw[2*k] | (raw[2*k+1] << 8));   // little-endian
    std::cout << "[TB] Weight load done: " << i << " bytes\n";
    if (i != expect_bytes) { std::cout << "[TB] FAIL: wrong weight byte count (got " << i << ", expected " << expect_bytes << ")\n"; return false; }

    // Refresh must actually have fired -- a dead refresh generator would
    // lose SDRAM contents over a load this long on real hardware.
    std::cout << "[TB] Refresh-active cycles during load: " << refresh_ticks << "\n";
    if (refresh_ticks == 0) {
        std::cout << "[TB] FAIL: refresh never fired during a multi-million-cycle load\n";
        return false;
    }

    // ---- Classify samples from tb_data.txt ----------------------------------
    // Format verified against generate_test_vectors.jl (NOT test_nano20k.py's
    // docstring, which is stale for this file): 196 image bytes as 2-hex-digit
    // pairs with no delimiter, a space, then 10 reference per-class score
    // bytes. Expected class = argmax of those 10 scores.
    // Golden vectors: the copy shipped beside this example, so a fresh clone
    // works with no KAN_LUT checkout. Override with the TB_DATA env var.
    const char *tb_env = getenv("TB_DATA");
    const char *tb_path = tb_env ? tb_env : "tb_data.txt";
    std::ifstream tfile(tb_path);
    if (!tfile) { std::cout << "[TB] FAIL: could not open " << tb_path
                  << " (set TB_DATA=<path> to override)\n"; return false; }

    // Refresh during INFERENCE is a separate question from refresh during the
    // load, and the more important one: the load runs once, but main() is
    // `while (1) step()`, so on hardware inference runs forever. The shim only
    // issues refresh in a slot where no request is pending and nothing is
    // granted, so a read-bound inference loop could in principle starve it.
    // This sim cannot detect the consequence -- the model treats
    // CMD_AutoRefresh as a no-op and never decays -- so a starved design would
    // pass the classification check and still corrupt SDRAM on real hardware
    // about 64ms after boot. Hence: assert refresh activity explicitly.
    long refresh_after_load = refresh_ticks;

    int correct = 0, tested = 0;
    std::string line;
    while (tested < num_samples && std::getline(tfile, line)) {
        if (line.size() < 392 + 1 + 20) continue;
        uint8_t img[196];
        for (int p = 0; p < 196; p++)
            img[p] = (uint8_t)strtol(line.substr(p * 2, 2).c_str(), nullptr, 16);
        int expected = -1, best = -1;
        for (int q = 0; q < 10; q++) {
            int v = (int)strtol(line.substr(392 + 1 + q * 2, 2).c_str(), nullptr, 16);
            if (q == 0 || v > best) { best = v; expected = q; }
        }

        for (int k = 0; k < 64; k++) { hw_l1[k] = -1; hw_l1_seen[k] = false; }
        hw_l1_writes = 0;
        capture_l1 = true;

        for (int p = 0; p < 196; p++) if (!send_image_byte(img[p], p)) return false;
        SPIN_UNTIL_N(dut->tx_start, "tx_start (classification result)",
                     "sample " << tested, SPIN_LIMIT_RESULT);
        int result = dut->tx_data;
        capture_l1 = false;

        // Compare layer 1 against the golden model -- this is what turns a
        // wrong final class into a localised "layer 1 neuron q is wrong".
        int gl1[64], gsc[10];
        int l1_bad = 0, first_bad_q = -1;
        if (!liveness) {
            golden(img, gl1, gsc);
            for (int q = 0; q < 64; q++) {
                if (!hw_l1_seen[q] || hw_l1[q] != gl1[q]) {
                    if (l1_bad == 0) first_bad_q = q;
                    l1_bad++;
                }
            }
            // Dump sample 0's full layer-1 vector and its image so competing
            // explanations for a mismatch can be tested offline, instead of
            // paying a ~7-minute weight load per hypothesis.
            if (tested == 0) {
                std::ofstream d("hw_layer1_dump.txt");
                d << "# image 196 bytes\n";
                for (int k = 0; k < 196; k++) d << (int)img[k] << (k == 195 ? '\n' : ' ');
                d << "# hw layer1_out 64\n";
                for (int k = 0; k < 64; k++) d << (hw_l1_seen[k] ? hw_l1[k] : -1) << (k == 63 ? '\n' : ' ');
                d << "# golden layer1_out 64\n";
                for (int k = 0; k < 64; k++) d << gl1[k] << (k == 63 ? '\n' : ' ');
                d.close();
                std::cout << "[TB]   wrote hw_layer1_dump.txt\n";
            }
            if (l1_bad) {
                std::cout << "[TB]   layer1 MISMATCH: " << l1_bad << "/64 neurons differ"
                          << " (writes seen=" << hw_l1_writes << ")"
                          << "  first q=" << first_bad_q
                          << " hw=" << (hw_l1_seen[first_bad_q] ? std::to_string(hw_l1[first_bad_q]) : std::string("<no write>"))
                          << " golden=" << gl1[first_bad_q] << "\n";
            } else {
                std::cout << "[TB]   layer1 OK (all 64 neurons match golden)\n";
            }
        }

        bool ok = liveness ? true : (result == expected);
        if (ok) correct++;
        std::cout << "[TB] sample " << tested << ": got " << result
                  << " expected " << expected
                  << (liveness ? "  (liveness mode: class not asserted)"
                               : (ok ? "  OK" : "  MISMATCH")) << "\n";
        tested++;

        // let kan_control finish send_result() and re-enter load_image()
        for (int k = 0; k < 500; k++) tick();
    }

    if (tested == 0) { std::cout << "[TB] FAIL: no samples read from tb_data.txt\n"; return false; }

    long refresh_during_inference = refresh_ticks - refresh_after_load;
    std::cout << "[TB] Refresh-active cycles during inference: "
              << refresh_during_inference << "\n";
    if (refresh_during_inference == 0) {
        std::cout << "[TB] FAIL: refresh never fired during inference -- the read loop"
                     " is starving the shim's refresh generator. This sim would still"
                     " classify correctly (the model never decays), but real SDRAM"
                     " would lose its contents.\n";
        return false;
    }
    std::cout << "[TB] " << correct << "/" << tested << " samples match the reference argmax\n";
    if (correct == tested) { std::cout << "[TB] PASS\n"; return true; }
    std::cout << "[TB] FAIL\n";
    return false;
}

int main(int argc, char **argv) {
    std::cout << std::unitbuf;              // never buffer progress to a file
    ctxp = new VerilatedContext;
    Verilated::commandArgs(argc, argv);
    dut = new Vkan_fastload_dut;
    int  num_samples  = (argc > 1) ? atoi(argv[1]) : 20;
    long expect_bytes = (argc > 2) ? atol(argv[2]) : 6750208;
    bool liveness     = (expect_bytes != 6750208);
    std::cout << "[TB] num_samples=" << num_samples
              << " expect_weight_bytes=" << expect_bytes
              << (liveness ? "  [LIVENESS MODE]" : "") << "\n";
    return run(num_samples, expect_bytes, liveness) ? 0 : 1;
}
