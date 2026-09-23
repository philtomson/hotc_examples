# MicroCNN_hotstate — a CNN whose control plane is one hotstate machine

A small convolutional neural network that classifies
[BloodMNIST](https://medmnist.com/) blood-cell images (28×28 RGB, 8
classes) on a **Tang Primer 25K** or a **Tang Nano 20K**. The datapath — MAC arrays, line buffers,
weight ROMs, max-pooling, argmax — is ordinary hand-written SystemVerilog.
Everything that *sequences* it, the part that would normally be a
hierarchy of hand-written FSMs, is a single hotc-compiled C program:
[`main_controller.c`](main_controller.c).

**Verified on real hardware** against the quantized Python reference
model (`golden_benchmark.py`):

| Board | Toolchain | Result |
|---|---|---|
| Tang Primer 25K (GW5A-25A) | open-source: yosys + slang, nextpnr-himbaechel, apycula | 52/52 test images match |
| Tang Nano 20K (GW2AR-18C) | Gowin's `gw_sh` (Gowin EDA IDE) | 52/52 test images match |

The two boards need different toolchains. On the 20K the open-source flow
builds this design and meets timing, but the bitstream misclassifies — the
fault is in open-source place-and-route/packing for that chip, not in the
design — so the 20K build uses Gowin's tools, as the original design did.

## What this example shows

| | Original design (hand-written FSMs) | This version |
|---|---|---|
| Control logic | 6 Verilog modules, ~850 lines | 1 C file, ~320 lines of code (plus comments) |
| Control state | registers spread across each FSM | hotstate state bits |
| Datapath | — | unchanged |

The datapath RTL comes from
[MicroCNN-TangNano20k](https://github.com/SweiryDev/MicroCNN-TangNano20k)
(see [Origin](#origin)); only the control plane is replaced. That makes it
a direct comparison: same network, same arithmetic, same memories — the
sequencing written as C instead of as state machines.

## Network

```
Input (28×28 RGB) → Conv1 (3→8) → ReLU → Scale(/512) → MaxPool 2×2
                  → Conv2 (8→16) → ReLU → Scale(/256) → MaxPool 2×2
                  → Flatten → FC1 (400→32) → ReLU → Scale(/512)
                  → FC2 (32→8) → Argmax → class 0..7
```

INT8 weights and activations, INT32 accumulation. The trained FP32
weights are in `micro_cnn_blood.pth`; the quantized ROM contents the
hardware uses are in `hardware_roms/`.

## Building and running

Pick your board. Each build has a `prog_verified` target that loads a
checked-in, hardware-verified bitstream with no toolchain beyond
`openFPGALoader`.

### Tang Primer 25K — open-source flow

Needs **yosys with the slang plugin** (`read_slang`): the datapath uses
SystemVerilog unpacked-array ports that yosys's own frontend cannot parse.
The OSS CAD Suite yosys includes slang; a distro or hand-built yosys often
does not, and the Makefile stops with a clear message if so. Point
`YOSYS_SLANG` at one that has it — a separate variable, so `YOSYS` for the
other examples is left alone. It also works from the environment, e.g.
`YOSYS_SLANG=/path/to/oss-cad-suite/bin/yosys ./scripts/check_fresh_clone.sh --synth`.

```bash
cd examples/MicroCNN_hotstate
make -f Makefile.synth_primer25k prog_verified     # load the verified bitstream, or:
make -f Makefile.synth_primer25k prog              # build (~2 min) and load
make -f Makefile.synth_primer25k prog YOSYS_SLANG=/path/to/oss-cad-suite/bin/yosys
```

### Tang Nano 20K — Gowin toolchain

Needs `gw_sh` from the [Gowin EDA IDE](https://www.gowinsemi.com/en/support/home/)
(the free Education edition is enough). It is usually not on `PATH`, so
point `GW_SH` at it, on the command line or in the repo's gitignored
`local.mk`:

```bash
cd examples/MicroCNN_hotstate
make -f Makefile.synth_tang20k_gowin prog_verified                          # verified bitstream, or:
make -f Makefile.synth_tang20k_gowin prog GW_SH=/opt/gowin/IDE/bin/gw_sh    # build (~1 min) and load
```

`gw_sh` is a Qt program even when run headless. If it exits at startup
without building anything, pass `GW_SH_ENV='QT_QPA_PLATFORM=minimal'`; on
systems whose freetype is newer than the one Gowin bundles, use
`GW_SH_ENV='LD_PRELOAD=/lib64/libfreetype.so.6 QT_QPA_PLATFORM=minimal'`.
The build script is `build_tang20k.tcl`, runnable directly as
`gw_sh build_tang20k.tcl`.

### Classifying images

For the host scripts: `pyserial`, `numpy`, `torch` and `medmnist`
(`pip install pyserial numpy torch medmnist`). The first run downloads the
BloodMNIST dataset. Same commands for either board:

```bash
make hw-infer  IDX=26 PORT=/dev/ttyUSB1   # classify test image 26 on the FPGA
make sw-golden IDX=26                     # same image through the Python reference model
```

`hw-infer` prints the true label, the FPGA's prediction, and a latency
figure (about 60 ms). That figure is timed on the host from when its writes
return, so it includes serial-link buffering; it is not the accelerator's
compute time. `PORT` defaults to `/dev/ttyUSB1`: both boards' single USB-C
connection enumerates as two serial ports, JTAG first and then the UART.

### Wire protocol

Plain 8N1 UART at 115200 baud: send `L`, then the 2,352 image bytes
(28×28 pixels × RGB), then `S`. The FPGA replies with one byte, the
predicted class as ASCII `'0'`..`'7'`.

## How it maps onto each board

**Tang Primer 25K** (`top_primer25k.sv`, `primer25k.cst`):

- **Clock:** the dock's 50 MHz oscillator drives everything directly (GW5A
  has no `rPLL`). Timing closes with margin (P&R reports about 78–100 MHz).
- **Pins:** UART on B3/C3, button **S1** is reset. The dock has no user
  LEDs on general I/O, so the three class-result LED bits go to spare
  header pins H8/H7/G7 — the UART reply is the real output.
- **Primitives:** GW5A has none of the GW2A hard blocks the original design
  instantiates by hand. `lib/gw5a/` replaces them with modules of the same
  names and ports: the 36 conv-layer multipliers use GW5A `MULT12X12` hard
  multipliers, the 8 accumulating FC multipliers are behavioral RTL in
  logic, and the FC buffers are plain RAMs.
- **Resources:** about 7,300 LUT4 (31%), 5,500 DFF (24%), 32 of 56 block
  RAMs, 36 of 56 `MULT12X12`.

**Tang Nano 20K** (`top_hotstate.sv`, `tang20k.cst`):

- **Clock:** the 27 MHz oscillator through a Gowin `rPLL` to 30 MHz.
- **Pins:** the on-board USB UART (pins 69/70), button on pin 88 as reset,
  and the class result on the on-board LEDs (active low).
- **Primitives:** the original design's Gowin IP — `MULT9X9`,
  `MULTALU18X18`, mixed-width `SDPB`, `rPLL` — in `lib/gw2a/`.
- **Resources (Gowin):** about 4,500 logic cells (22%), 1,800 registers
  (12%), 36 `MULT9X9`, 8 `MULTALU18X18`.

The datapath files in `lib/` are shared by both builds; only the
primitive modules (`lib/gw2a/` or `lib/gw5a/`) and the board top differ.

## Files

| File | Role |
|---|---|
| `main_controller.c` | The hotc C program — the complete control plane |
| `main_controller_*` | hotc-generated: Verilog template, microcode `.mem` files, params, symbols, testbench |
| `top_hotstate.sv`, `npu_top_hotstate.sv` | Wiring between the hotstate machine and the datapath |
| `top_primer25k.sv`, `primer25k.cst` | Tang Primer 25K board wrapper and pins |
| `tang20k.cst`, `build_tang20k.tcl` | Tang Nano 20K pins and Gowin build script (`top_hotstate.sv` is the 20K top) |
| `lib/` | Datapath RTL from MicroCNN-TangNano20k; `lib/gw2a/` holds its Gowin IP wrappers (20K), `lib/gw5a/` their GW5A replacements (25K) |
| `hardware_roms/` | Quantized weights and biases, loaded by `$readmemh` |
| `uart_medmnist_loader.py` | Sends one BloodMNIST image to the board and reads back the class |
| `golden_benchmark.py`, `micro_cnn_blood.pth` | Quantized Python reference model and its trained weights |
| `verified_bitstreams/` | Hardware-verified bitstreams for each board |
| `sim_main.cpp`, `verilator_sim.h`, `user_tb.v` | hotc-generated simulation scaffolding for the controller alone; `*.stim` are its input stimulus files |

## Origin

The network, its training, the datapath RTL in `lib/`, the weight ROMs,
`micro_cnn_blood.pth`, `golden_benchmark.py` and `uart_medmnist_loader.py`
come from
[SweiryDev/MicroCNN-TangNano20k](https://github.com/SweiryDev/MicroCNN-TangNano20k).
Local changes to those files: the four `*_param_rom.sv` load their ROMs
from a relative path instead of an absolute one, `maxpool2x2.sv` and
`tdm_npu_router.sv` carry fixes and debug taps made while bringing up the
hotstate controller, `ws_conv_core_gowin.sv` exposes two debug taps, and
`lib/gw2a/gowin_rpll.v` exposes the PLL's divided output. `lib/gw2a/` is
Gowin IP Core Generator output from that repo.
The hotstate controller (`main_controller.c` and everything generated
from it), the top-level wiring, the Tang Primer 25K port and `lib/gw5a/`
are new.
