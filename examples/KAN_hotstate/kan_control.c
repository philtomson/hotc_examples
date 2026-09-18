// kan_control.c — sequencer for the KAN_hotstate MNIST classifier.
//
// Replaces KAN_LUT's nano20k_top.sv FSM *and* kan_generic_core.sv /
// mnist_generic_top.sv entirely: this machine owns the whole algorithm
// (weight load, per-neuron dot-product accumulation, saturate/round,
// argmax), not just I/O sequencing. The original design's lane_cache /
// CHUNKS / PARALLELISM=4 structure existed only to let 4 SDRAM-cached
// weights be read in the same clock cycle; hotc can't do that (confirmed
// by direct test: independent array reads serialize into separate
// NOP+capture pairs, not a parallel read), but the cost of accepting that
// serialization here is ~23k cycles (~427us @ 54MHz) against a ~3.4s
// UART weight-load time -- negligible, so this collapses the original
// two-phase PREFETCH-then-pipelined-RUN into one straight
// fetch-and-accumulate loop per neuron. See plans/kan_hotstate.md for the
// full design rationale and the exact numbers behind that decision.
//
// Per-layer constants below are copied from KAN_LUT's
// examples/MNIST/FPGA/mnist_generic_top.sv (kan_generic_core instance
// parameters + the layer-2 weight offset comment in its memory mux) --
// verified against that source, not re-derived.
//
// Weight layout in SDRAM (verified against KAN_LUT's test_nano20k.py):
// 6,750,208 bytes total = layer1 (64*196*256 entries) then layer2
// (10*64*256 entries), each entry a little-endian 16-bit value, no
// framing. Layer 2's weights start at WORD offset 3,211,264 (= byte
// offset 6,422,528) -- i.e. immediately after layer 1's.
//
// SDRAM reads are done ONE BYTE AT A TIME (two transactions per 16-bit
// weight, assembled here), not as a 16-bit bus -- an earlier version of
// this file exposed a 16-bit sdram_rd_data input and hit hotc's vardata
// generation limit: total live external input bits (sdram_busy + a wide
// sdram_rd_data + rx_done + rx_byte + tx_busy) came to 27, over the 2^25
// row cap, because hotc's value-producing-expression mechanism (not just
// branch comparators) scales with the combined width of ALL live inputs
// across the whole machine. Reading a byte at a time keeps every external
// input at <=8 bits (matching sdram.v's own native byte-wide `dout` port
// directly, so the shim needs no 32-bit assembly/bit-selection logic
// either) -- total live input bits: 1+8+1+8+1 = 19, comfortably clear.

// ---- SDRAM peripheral (see kan_sdram_shim.v) ------------------------------
// Hold-until-ack handshake, same idiom tm_uart_loader.c uses for
// tx_start/tx_busy (adopted there after a real cross-machine pulse-race
// bug -- see plans/bugs.md item 9): assert the request and hold it until
// sdram_busy rises (accepted), then drop it and wait for sdram_busy to
// fall again (operation complete) before touching the interface again.
// One shared byte-addressed request: sdram_wr_req write, sdram_rd_req
// read, never both asserted at once (guaranteed by program order, not by
// the shim).
bool sdram_wr_req = 0;
bool sdram_rd_req = 0;
unsigned _BitInt(23) sdram_addr = 0;   // byte address, 0..6750207 (shared
                                        // by both read and write)
_BitInt(8) sdram_wr_data = 0;

bool sdram_busy;           // from shim: sdram op in flight (write or read)
unsigned _BitInt(8) sdram_rd_byte;  // from shim: valid once sdram_busy has
                                     // fallen after a read (shim latches it
                                     // off sdram.v's own data_ready pulse --
                                     // see kan_sdram_shim.v). Unsigned: this
                                     // is a raw byte, not to be sign-extended
                                     // when assembled into a wider word.

// ---- UART peripherals -----------------------------------------------------
bool rx_done;
_BitInt(8) rx_byte;

bool tx_start = 0;
_BitInt(8) tx_data = 0;
bool tx_busy;

// ---- Activations ------------------------------------------------------
// Small on-chip arrays -- plain hotc writable arrays, no custom
// peripheral needed (same idiom as Tsetlin_hotstate_uart's img[] array).
static _BitInt(8) in_mem[196];
static _BitInt(8) layer1_out[64];

// ---- Working state ----------------------------------------------------
unsigned _BitInt(23) byte_idx = 0;     // weight-load loop counter (needs
                                        // >=23 bits: 2^23 > 6,750,208)
_BitInt(9) p = 0;                      // input-dimension index (max 196)
_BitInt(8) q = 0;                      // neuron index (max 64) -- needs 8
                                        // bits: a signed _BitInt(7)'s max
                                        // representable value is 63, so a
                                        // `q < 64` loop bound would never
                                        // be reachable/false in 7 bits
                                        // (caught by clang's tautological-
                                        // compare warning on the .c file)
_BitInt(24) acc = 0;                   // accumulator (layer1 needs >=22
                                        // bits: DATA_WIDTH=14+clog2(196)=8;
                                        // layer2 needs >=19: 13+6 -- 24 bits
                                        // covers both with margin)
unsigned _BitInt(23) rd_addr = 0;      // byte address of a weight's LOW
                                        // byte (high byte is rd_addr+1)
unsigned _BitInt(8) byte_lo = 0;
unsigned _BitInt(8) byte_hi = 0;
unsigned _BitInt(16) combined = 0;     // {byte_hi, byte_lo}, unsigned/raw
                                        // (zero-extended assembly; the
                                        // final narrowing copy below into
                                        // a signed weightN variable is what
                                        // reinterprets the low DATA_WIDTH
                                        // bits as signed -- matching the
                                        // original's mem_rdata[N-1:0] slice
                                        // then signed lane_cache storage)
_BitInt(14) weight14 = 0;              // layer 1: DATA_WIDTH=14 signed
_BitInt(13) weight13 = 0;              // layer 2: DATA_WIDTH=13 signed
_BitInt(24) shifted = 0;               // (acc + round) >> FRACTIONAL_BITS,
                                        // pre-saturation, same width as acc
_BitInt(9) val = 0;                    // post-saturate/round activation,
                                        // 0..255 -- needs 9 bits since
                                        // _BitInt(8) signed only reaches 127
_BitInt(5) best_class = 0;             // 0..9 -- needs 5 bits (signed
                                        // _BitInt(4) only reaches 7)
_BitInt(9) max_score = 0;

void sdram_write_byte() {
    sdram_addr = byte_idx;
    sdram_wr_data = rx_byte;
    sdram_wr_req = 1;
    while (!sdram_busy) {}
    sdram_wr_req = 0;
    while (sdram_busy) {}
}

// Reads sdram_addr's byte into byte_lo, then sdram_addr+1's byte into
// byte_hi, and assembles them (little-endian) into `combined`.
void read_weight_raw() {
    sdram_addr = rd_addr;
    sdram_rd_req = 1;
    while (!sdram_busy) {}
    sdram_rd_req = 0;
    while (sdram_busy) {}
    byte_lo = sdram_rd_byte;

    sdram_addr = rd_addr + 1;
    sdram_rd_req = 1;
    while (!sdram_busy) {}
    sdram_rd_req = 0;
    while (sdram_busy) {}
    byte_hi = sdram_rd_byte;

    combined = byte_hi;
    combined = combined << 8;
    combined = combined + byte_lo;
}

// rd_addr is computed incrementally, entirely in rd_addr's own already-
// wide (23-bit) precision -- q and p are only 8/9 bits (sized for their
// loop-counter role), and it's not documented/verified whether hotc widens
// an intermediate product like `q * 196` to fit an eventual wide assignment
// target, or truncates at each operand's own declared width. Rather than
// trust that either way, every step below both reads and writes rd_addr
// itself, so no operation ever combines two different narrower-than-needed
// operands before the running value is already at full precision.
void addr_from_qp() {
    rd_addr = q;
    rd_addr = rd_addr * 196;
    rd_addr = rd_addr + p;
    rd_addr = rd_addr * 256;
    rd_addr = rd_addr + in_mem[p];
    rd_addr = rd_addr * 2;    // word index -> byte address of the low byte
}

void addr_from_qp_layer2() {
    rd_addr = q;
    rd_addr = rd_addr * 64;
    rd_addr = rd_addr + p;
    rd_addr = rd_addr * 256;
    rd_addr = rd_addr + layer1_out[p];
    rd_addr = rd_addr + 3211264;
    rd_addr = rd_addr * 2;
}

void load_weights() {
    for (byte_idx = 0; byte_idx < 6750208; byte_idx = byte_idx + 1) {
        while (!rx_done) {}
        sdram_write_byte();
    }
}

void load_image() {
    for (p = 0; p < 196; p = p + 1) {
        while (!rx_done) {}
        in_mem[p] = rx_byte;
    }
}

// Layer 1: 196 -> 64, DATA_WIDTH=14, FRACTIONAL_BITS=4, weight base word 0.
void run_layer1() {
    for (q = 0; q < 64; q = q + 1) {
        acc = 0;
        for (p = 0; p < 196; p = p + 1) {
            addr_from_qp();
            read_weight_raw();
            weight14 = combined;   // narrowing copy: low 14 bits, reinterpreted signed
            acc = acc + weight14;
        }
        shifted = (acc + 8) >> 4;   // round: +(1<<(FRACTIONAL_BITS-1)), >>FRACTIONAL_BITS (arithmetic shift, signed)
        if (shifted > 255) { val = 255; } else if (shifted < 0) { val = 0; } else { val = shifted; }
        layer1_out[q] = val;
    }
}

// Layer 2: 64 -> 10, DATA_WIDTH=13, FRACTIONAL_BITS=4, weight base word
// 3,211,264 (immediately after layer 1's weights).
void run_layer2() {
    for (q = 0; q < 10; q = q + 1) {
        acc = 0;
        for (p = 0; p < 64; p = p + 1) {
            addr_from_qp_layer2();
            read_weight_raw();
            weight13 = combined;   // narrowing copy: low 13 bits, reinterpreted signed
            acc = acc + weight13;
        }
        shifted = (acc + 8) >> 4;
        if (shifted > 255) { val = 255; } else if (shifted < 0) { val = 0; } else { val = shifted; }
        if (q == 0) {
            max_score = val;
            best_class = 0;
        } else if (val > max_score) {
            max_score = val;
            best_class = q;
        }
    }
}

void send_result() {
    tx_data = best_class;
    tx_start = 1;
    while (!tx_busy) {}
    tx_start = 0;
    while (tx_busy) {}
}

void step() {
    load_image();
    run_layer1();
    run_layer2();
    send_result();
}

void main() {
    load_weights();
    while (1) {
        step();
    }
}
