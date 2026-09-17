# Known issues — Tsetlin_hotstate_uart

## Tang Nano 20K (GW2A-18C): yosys ALU-inference miscompile — FIXED, `-noalu`

**Status: root-caused (external), fixed, verified 100/100.**

On the Tang Nano 20K, yosys's inferred ALU carry cells compute the wrong
result on this specific Gowin part (GW2AR-LV18QN88C8/I7) — RTL simulation,
gate-level simulation and static timing analysis all pass, but the design
misclassifies one MNIST class per build, and *which* class tracks the P&R
placement/seed rather than any fixed piece of logic. This is not specific to
this design: [YosysHQ/apicula#514](https://github.com/YosysHQ/apicula/issues/514)
reports the same device computing wrong results on unrelated modular
arithmetic, with the same "everything passes except silicon" signature, and
the same workaround.

This design's signed comparisons (`$signed(a) > $signed(b)` in the vote
accumulators) compile to a 756-cell ALU carry chain — deep enough to hit the
bug reliably (7 of 7 default-inference placements tested were broken, scoring
74-98/100). With ALU inference disabled, 4 of 4 placements tested scored a
clean 100/100. Cost is negligible: LUT4 usage rises slightly (2348 → 2461),
DFF/BSRAM unchanged.

`Makefile.synth_tang20k` already ships with the fix
(`synth_gowin -noalu -top ... `) and a `make -f Makefile.synth_tang20k verify`
target that builds, flashes, and runs the full `batch_ref.bin` 100-sample
check, failing loudly if agreement isn't 100/100. If you change the source,
the yosys version, or the constraints on this board, re-run `verify` — a
passing build today doesn't guarantee a passing build after any of those
change, since this bug is placement-dependent, not something the source
alone determines.

## Tang Nano 9K: one unreproduced 93/100 batch result

**Status: open, not reproduced, not root-caused.**

Out of 28 `send_batch.py` runs against this design on a Tang Nano 9K (across
several separately-built bitstreams), one run reported 93/100 agreement
instead of the normal 100/100. All 7 mismatches fell among samples 0-82 (the
tail, samples 83-99, was clean), but the full per-sample log from that run
wasn't captured, so whether the failures clustered (consistent with a lost
UART byte desyncing the raw 98-byte-per-image stream — the protocol has no
framing or checksum) or scattered (consistent with a rare timing race)
isn't known.

Ruled out: a bad synthesis/P&R run. `synth_tang9k.json`, `pnr_tang9k.json`,
and the final `design_tang9k.fs` were confirmed byte-identical (sha256)
across 3 independent rebuild cycles, and that exact bitstream (hash
`9157757b2f9164f0336438fd70ed20494a7da27769e8fdfe09bdbe493b0d21ad`, shipped
in `verified_bitstreams/`) scored 93/100 once and then 100/100 on all 27
subsequent runs — including immediately after a fresh reprogram, and
deliberately repeating the exact original sequence 3 times.

Best-supported explanation, unconfirmed: a rare dropped/corrupted byte on the
USB-UART link. Occurrence rate so far is ~1/28 (~4%), too rare to catch live
without a much larger trial. `verified_bitstreams/design_tang9k_100of100.fs`
is the exact bitstream this was verified against if you'd rather flash a
known-good build than rebuild from source.
