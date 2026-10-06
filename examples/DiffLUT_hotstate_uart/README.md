# DiffLUT-Net FPGA Inference Accelerator — UART variant (Tang Primer 25K)

A trained **K=4 DiffLUT-Net** MNIST digit classifier (2000 + 1000 LUT4
neurons, **97.26% test accuracy** — the compact-top-K-router checkpoint,
see `~/devel/AI/DiffLUT-Network/julia/README.md`) running entirely in LUT
fabric on the Tang Primer 25K, with the same plain-UART front-end as
[`Tsetlin_hotstate_uart`](../Tsetlin_hotstate_uart/): send 784 binarized
image bytes, receive 1 predicted-digit byte.

The inference network (`logic_net.v`, 3,000 Gowin LUT4 primitives, one per
neuron, each with its learned 16-bit truth table as the INIT value) was
**exported from a Julia training flow** — see
`~/devel/AI/DiffLUT-Network/julia/export/README.md` for the exporter and
its verification chain. The exported net was verified bit-exact against the
Julia model over 500 MNIST test images in iverilog (0 mismatches), the
synthesized netlist was verified equal to the source Verilog on the same
500 images, and the full UART path (image in → digit out) is exercised in
Verilator (`make -f Makefile.sim sim n=500`; the run is slow — real-time
115200 baud bit-banging — spot-check 20 for a quick pass).

## Protocol

Same shape as the Tsetlin example, scaled for the image format:

1. Host sends exactly **784 binarized image bytes** (one byte per pixel;
   bit k of byte p = threshold-bit k for pixel p — produced by
   `gen_vectors.py` / `send_batch.py` from the training-side test dump).
2. Inference auto-starts after the 784th byte.
3. Host waits for 1 response byte: predicted digit (0-9) in the low nibble.
4. Repeat.

## Source files

| File | Role |
|------|------|
| `logic_net.v` | The trained network: 3,000 Gowin `LUT4` primitives (exported from Julia). |
| `lut4_sim.v` | Behavioral LUT4 model for simulation (synthesis tools know the primitive natively). |
| `image_reg.v` | 784-byte image register, byte-write port for the loader. |
| `argmax10.v` | Combinational argmax over the 10 per-class sums. |
| `dlut_uart_loader.c` | hotc source: the UART loader (784 bytes in → network settle wait → digit byte out). |
| `dlut_uart_loader_template.v` (+ params/mem) | hotc-compiled loader machine (generated with `--microcode-hs-opt --opt`). |
| `dlut_hw_top_uart.v` | Hand-written top: uart_rx + uart_tx + loader + image_reg + logic_net + argmax. |
| `tb_dlut_uart.v` + `sim_main.cpp` | Verilator end-to-end TB (UART image in, digit check). |
| `gen_vectors.py` | Packs the checkpoint's dumped test vectors into gen/ + images.bin. |
| `send_image.py` / `send_batch.py` | Host-side single-image / batch test scripts. |
| `dlut_primer25k_uart.cst` | Pin constraints (same UART pins as the Tsetlin example). |
| `Makefile.sim` / `Makefile.synth_primer25k` | Simulation and synthesis flows. |

## Building and testing

```bash
# End-to-end simulation (20 images through the full UART path):
make -f Makefile.sim clean_sim 2>/dev/null; make -f Makefile.sim sim n=20
#   → [TB] PASS: 20/20 images match the Julia model

# Synthesis + PnR + bitstream for Tang Primer 25K:
make -f Makefile.synth_primer25k pack     # design_primer25k.fs
make -f Makefile.synth_primer25k prog     # flash over openFPGALoader

# Host-side tests:
python3 send_image.py --port /dev/ttyUSB1 --image <784-byte .bin>
python3 send_batch.py --port /dev/ttyUSB1 --limit 20
```

`gen_vectors.py` regenerates `gen/` + `images.bin` from a DiffLUT-Network
checkpoint that has dumped test vectors (run
`julia/export/dump_testvectors.jl <ckpt>` first).

## FPGA resource usage (Tang Primer 25K, GW5A-25A, nextpnr)

| Resource | Used | Available | % |
|---|---|---|---|
| LUT4 | 7,271 | 23,040 | 31% |
| ALU (GroupSum carry trees) | 1,012 | 17,280 | 5% |
| DFF | 4,511 | 23,040 | 19% |
| IOB | 5 | 240 | 2% |
| BSRAM | 1 | 56 | 1% |

Fmax: **79 MHz** (nextpnr, unconstrained; the loader runs the 50 MHz UART;
inference itself settles in 4 clocks). Bitstream: `design_primer25k.fs`.

Note: the trained routing concentrates — layer 2 reads only 915 distinct
layer-1 outputs and 2094 distinct input bits, so ~1085 first-layer neurons
are logically dead. The deployed build keeps LUT4s as opaque primitives and
ships them anyway (~1085 LUT4s, ~4.7% of the board); see the exporter
README for the measurement and the options if board resources ever matter.

## Notes

- The network is **fully combinational between register stages** — the
  trained tables are the LUT INITs, the learned connections are the routing.
  Inference latency is 4 clocks; throughput is 1 image per ~68 ms
  (UART-limited at 115200 baud: 784 bytes × 10 bits / 115200 ≈ 68 ms).
- Build the bitstream with the **system yosys** (`make YOSYS=/usr/local/bin/yosys`
  or ensure PATH resolves it first): the oss-cad-suite v0.69 yosys emits
  `$buf` cells that nextpnr's GW5A backend cannot place (same caveat as the
  MicroCNN example).
- The `with_reg` export (used here) registers the layer-1 output and the
  adder-tree stages; the combinational export maps to ~12.6k LUT-sites
  (the GroupSum carry trees double in LUT count without the pipeline
  registers) and does not fit the Tang Nano 9K.
- K is a training-time parameter (`--lut_inputs 4`); K=6 would need
  64-entry tables (8× the LUT4s per neuron) and would not fit this board.
