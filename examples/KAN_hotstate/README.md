# KAN_hotstate — MNIST classification on a Tang Nano 20K, sequenced in hotc C

A **Kolmogorov–Arnold Network** (KAN) MNIST classifier running on a Sipeed Tang
Nano 20K, where the entire control and compute-sequencing layer is written as
hotc C (`kan_control.c`) rather than hand-written Verilog.

**Verified: 100/100 in simulation and 100/100 on real hardware** against
KAN_LUT's golden batch, at 29.9 ms/sample.

## What a KAN is

A Kolmogorov–Arnold Network replaces the fixed activation functions that sit on
the *nodes* of a multi-layer perceptron with **learnable univariate functions on
the edges**. There are no linear weight matrices at all: every weight is itself
a small function of one variable.

That reformulation is what makes this design possible on a small FPGA. Once each
edge function is discretised, it becomes a plain **lookup table** — so inference
is nothing but table lookups plus an integer adder tree. No multipliers, no
floating point, no transcendental functions. This design uses **zero DSP
blocks**; the arithmetic is a few adders and some saturation logic.

- Original paper: [KAN: Kolmogorov–Arnold Networks](https://arxiv.org/abs/2404.19756)
  (Liu et al., 2024)
- Reference implementation used here: [`KAN_LUT`](https://github.com/philtomson/KAN_LUT) —
  the Julia framework that trains the network, quantises it to 8-bit LUTs, and
  generates the golden test vectors this example is checked against.

## The network

Two layers, both pure LUT lookups, weights held in the Tang Nano 20K's
in-package SDRAM:

| Layer | Inputs | Outputs | LUT entries | Weight width |
|-------|--------|---------|-------------|--------------|
| 1 | 196 (14×14 image) | 64 | 64 × 196 × 256 | 14-bit signed |
| 2 | 64 | 10 (digit classes) | 10 × 64 × 256 | 13-bit signed |

**6,750,208 bytes of weights total**, streamed into SDRAM over UART at boot.
Each layer accumulates its lookups, rounds with `(acc + 8) >> 4`, and saturates
to 0..255; layer 2's argmax is the predicted digit.

## What is hotc C and what is hand-written Verilog

The point of this example: `kan_control.c` replaces what KAN_LUT's own FPGA
demo does in hand-written Verilog (`kan_generic_core.sv` + `mnist_generic_top.sv`).
Both layers' loops, the address arithmetic, the accumulate/round/saturate, the
argmax and the UART sequencing are all ordinary C compiled to hotstate microcode.

| File | Kind |
|---|---|
| `kan_control.c` | **hotc C** — all control and compute sequencing |
| `uart_rx.c`, `uart_tx.c` | **hotc C** — 8N1 UART machines (from `examples/webserver`) |
| `kan_sdram_shim.v` | hand-written Verilog — thin request/ack wrapper around `sdram.v` |
| `sdram.v` | hand-written Verilog — KAN_LUT's controller, **unmodified** |
| `top.v` | hand-written Verilog — PLL, reset, pin wiring, LED result display |

## Building without hotc

The `*_template.v`, `*.mem` and `*.vh` files here are **hotc's output, checked
in as-is** — this repo does not ship the hotc compiler, so there is no
`generate` step and nothing rebuilds them. The `.c` sources beside them
(`kan_control.c`, `uart_rx.c`, `uart_tx.c`) are included for reading; editing
them has no effect here without hotc.

The checked-in UART machines in `build_tang20k/` are built for **54 MHz /
2 Mbaud**. Changing the baud requires hotc.

Verified: the bitstream this produces is **byte-identical** to the one tested
100/100 on hardware.

## Running it

`weights.bin` (6.5 MB) is **checked in**, because it cannot practically be
recreated. [KAN_LUT](https://github.com/philtomson/KAN_LUT) does not track its
trained LUT JSONs — its `.gitignore` excludes `*.json` — so they only exist
after running `demo.jl`, a full Julia/Flux training run. And retraining would
produce *different* weights from a fresh random init, which would invalidate the
`tb_data.txt` golden vectors here: those were generated from these exact
weights.

`pack_weights.py` is included for the case where you *do* have a KAN_LUT
checkout with trained JSONs and want to repack (or have retrained and will
regenerate `tb_data.txt` to match):

```bash
KAN_LUT_MNIST=<path-to-KAN_LUT>/examples/MNIST python3 pack_weights.py
```

Build and flash (2 Mbaud, result shown on the LEDs — see below):

```bash
make -f Makefile.synth_tang20k pack
make -f Makefile.synth_tang20k prog
```

Classify the golden batch, reading answers off the board:

```bash
python3 send_batch.py /dev/ttyUSB1 --baud 2000000 --leds
```

Or draw your own digit:

```bash
python3 draw_digit_kan.py --port /dev/ttyUSB1
```

The weight load takes **~34 seconds** at 2 Mbaud and happens once per power-up.
Until it finishes, the board ignores images — it is still inside
`load_weights()`.

## The answer comes out on the LEDs

The classified digit is displayed in **binary on `led[3:0]`**, not returned over
UART:

| LED | Meaning |
|---|---|
| `led[3:0]` | the predicted digit, in binary (0–9) |
| `led[4]` | **toggles** on every classification — flips each time you classify |
| `led[5]` | heartbeat (~1.6 Hz) — clock/PLL/reset sanity |

LEDs on this board are **active low**.

This is deliberate. On the unit used for bring-up, the on-board BL616 bridge is
reliable **host→FPGA** but *intermittent* **FPGA→host** (see *Known issues*).
Putting the result on the LEDs removes any dependence on the unreliable
direction — and because nothing has to come back, the fast baud rate is usable
again, cutting the weight load from ~10 minutes to ~34 seconds.

`led[4]` toggles rather than latching on purpose: a sticky "a result exists"
flag lights once and then tells you nothing, whereas a toggle visibly flips each
time a new answer lands.

If you would rather have the result byte returned over UART, drop `--leds`;
`kan_control` transmits it regardless.

## Testing

Everything below runs without a board:

```bash
make ack_probe     # every completed SDRAM handshake really issues a write
make rw_probe      # bytes written through the shim read back as written
make fastload      # full inference vs tb_data.txt, with a built-in golden model
```

`make fastload` streams all 6,750,208 weight bytes into a simulated SDRAM and
classifies samples from `tb_data.txt` (checked in here), checking **all 64 layer-1 neurons**
against a software golden model on every sample — so a wrong answer is localised
to a layer and a neuron rather than just "wrong class".

Each probe was **mutation-tested against the broken version** it was written to
catch. That matters: `rw_probe` originally passed against a model it should have
failed, because a dense readback never leaves SDRAM bank 0 and a test pattern
that ignores the high address bits cannot see aliasing at all.

## Resource usage (GW2AR-18C, yosys + nextpnr-himbaechel, `-noalu`)

| Resource | Count |
|---|---|
| LUTs (all sizes) | 2,077 |
| Flip-flops (all DFF variants) | 555 |
| ALU cells | **0** (see below) |
| DSP / multipliers | **0** |

`-noalu` is required, not a tuning knob: yosys's inferred ALU carry cells
miscompute on the GW2A-18C (YosysHQ/apicula#514). It costs
essentially nothing here.

## Known issues

**The on-board BL616 USB-serial bridge is intermittent in the FPGA→host
direction** on the unit used for bring-up. Over one session it went dead for
hours, then worked, then died again and stayed dead across a power cycle.
Host→FPGA has been reliable throughout (400,000 bytes, zero loss).

The design itself is not implicated — `uart_rx`, `uart_tx`, `kan_control`
throughput, the SDRAM read/write paths, placement (two seeds) and synthesis
(both yosys/nextpnr **and** the proprietary Gowin toolchain) were each checked
independently and are clean. Showing the result on the LEDs sidesteps it.

If you hit it and want the result byte back, `kan_tang20k_extuart.cst` routes
the UART to free header pins 73/74 for an external 3.3 V USB-TTL adapter; that
path is verified 100/100 but caps at 115200 with a PL2303, which is why the
weight load takes ~10 minutes there.

**`s1` is deliberately not used as a reset.** Pin 88 is the MODE0 configuration
strap as well as the S1 button and reads low on this board, so including it in
the reset term held the entire design in permanent reset. `top.v` uses the
power-on stretch alone.

## Board notes

- Tang Nano 20K only — the design needs the GW2AR-18's **in-package 64 Mbit SDR
  SDRAM** for the 6.75 MB of weights. The Tang Primer 25K has no DRAM, and the
  Tang Nano 9K's in-package memory is a different type.
- The in-package SDRAM works through the open-source flow **with no explicit pin
  constraints**.
- Every pin needs an explicit `IO_TYPE`. Without it Gowin defaults a pin to
  LVCMOS18, which fights the 3.3 V bank voltage of its neighbours. `gw_sh`
  rejects that (CT1136); yosys/nextpnr/apycula builds it silently. Running a new
  `.cst` through the Gowin toolchain is a cheap way to audit it.
