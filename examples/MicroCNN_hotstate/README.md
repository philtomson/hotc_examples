# MicroCNN_hotstate — a CNN whose control plane is one hotstate machine

A small convolutional neural network that classifies
[BloodMNIST](https://medmnist.com/) blood-cell images (28×28 RGB, 8
classes) on a **Tang Primer 25K**. The datapath — MAC arrays, line buffers,
weight ROMs, max-pooling, argmax — is ordinary hand-written SystemVerilog.
Everything that *sequences* it, the part that would normally be a
hierarchy of hand-written FSMs, is a single hotc-compiled C program:
[`main_controller.c`](main_controller.c).

**Verified on real hardware:** 52 of 52 BloodMNIST test images classified
identically to the quantized Python reference model
(`golden_benchmark.py`), test-set indices 0–49, 100 and 200.

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

Requirements beyond the repo-wide ones in the top-level README:

- **yosys with the slang plugin** (`read_slang`). The datapath uses
  SystemVerilog unpacked-array ports that yosys's own frontend cannot
  parse. The OSS CAD Suite yosys includes slang; a distro or hand-built
  yosys often does not, and the Makefile stops with a clear message if so.
  Point `YOSYS_SLANG` at one that does; it also works from the environment,
  e.g. `YOSYS_SLANG=/path/to/oss-cad-suite/bin/yosys ./scripts/check_fresh_clone.sh --synth`.
- For the host scripts: `pyserial`, `numpy`, `torch` and `medmnist`
  (`pip install pyserial numpy torch medmnist`). The first run downloads
  the BloodMNIST dataset.

```bash
cd examples/MicroCNN_hotstate

# Either load the checked-in, hardware-verified bitstream...
make -f Makefile.synth_primer25k prog_verified

# ...or build your own (about 2 minutes) and load it
make -f Makefile.synth_primer25k prog
#   (add YOSYS_SLANG=/path/to/oss-cad-suite/bin/yosys if the yosys on your
#    PATH has no slang plugin -- a separate variable, so YOSYS for the other
#    examples is left alone)

# Classify a test image on the FPGA, and through the Python reference model
make hw-infer  IDX=26 PORT=/dev/ttyUSB1
make sw-golden IDX=26
```

`hw-infer` prints the true label, the FPGA's prediction, and a latency
figure (about 60 ms). That figure is timed on the host from when its writes
return, so it includes serial-link buffering; it is not the accelerator's
compute time. `PORT` defaults to `/dev/ttyUSB1`: the dock's single USB-C
connection enumerates as two serial ports, JTAG first and then the UART.

### Wire protocol

Plain 8N1 UART at 115200 baud: send `L`, then the 2,352 image bytes
(28×28 pixels × RGB), then `S`. The FPGA replies with one byte, the
predicted class as ASCII `'0'`..`'7'`.

## How it maps onto the Tang Primer 25K

- **Clock:** the dock's 50 MHz oscillator drives everything directly.
  Timing closes with margin (P&R reports about 78–100 MHz).
- **Pins** (`primer25k.cst`): UART on B3/C3, button **S1** is reset. The
  dock has no user LEDs on general I/O, so the three class-result LED bits
  go to spare header pins H8/H7/G7 — the UART reply is the real output.
- **Multipliers:** the 36 conv-layer multipliers use the GW5A's hard
  `MULT12X12` blocks (`lib/gw5a/gowin_mult.v`). The 8 accumulating FC
  multipliers are behavioral RTL in logic (`lib/gw5a/dsp_multalu_accum.v`).
- **Resources:** about 7,300 LUT4 (31%), 5,500 DFF (24%), 32 of 56 block
  RAMs, 36 of 56 `MULT12X12`.

`lib/gw5a/` exists because the original design targets the Tang Nano 20K
(GW2A) and instantiates that family's DSP and block-RAM primitives by hand.
Those modules are replaced here by versions with the same names and ports
that map onto GW5A — so the datapath files themselves are unchanged.

## Files

| File | Role |
|---|---|
| `main_controller.c` | The hotc C program — the complete control plane |
| `main_controller_*` | hotc-generated: Verilog template, microcode `.mem` files, params, symbols, testbench |
| `top_hotstate.sv`, `npu_top_hotstate.sv` | Wiring between the hotstate machine and the datapath |
| `top_primer25k.sv`, `primer25k.cst` | Tang Primer 25K board wrapper and pins |
| `lib/` | Datapath RTL from MicroCNN-TangNano20k; `lib/gw5a/` holds the GW5A primitive mappings |
| `hardware_roms/` | Quantized weights and biases, loaded by `$readmemh` |
| `uart_medmnist_loader.py` | Sends one BloodMNIST image to the board and reads back the class |
| `golden_benchmark.py`, `micro_cnn_blood.pth` | Quantized Python reference model and its trained weights |
| `verified_bitstreams/` | A bitstream verified 52/52 on real hardware |
| `sim_main.cpp`, `verilator_sim.h`, `user_tb.v` | hotc-generated simulation scaffolding for the controller alone; `*.stim` are its input stimulus files |

## Origin

The network, its training, the datapath RTL in `lib/`, the weight ROMs,
`micro_cnn_blood.pth`, `golden_benchmark.py` and `uart_medmnist_loader.py`
come from
[SweiryDev/MicroCNN-TangNano20k](https://github.com/SweiryDev/MicroCNN-TangNano20k).
Local changes to those files: the four `*_param_rom.sv` load their ROMs
from a relative path instead of an absolute one, `maxpool2x2.sv` and
`tdm_npu_router.sv` carry fixes and debug taps made while bringing up the
hotstate controller, and `ws_conv_core_gowin.sv` exposes two debug taps.
The hotstate controller (`main_controller.c` and everything generated
from it), the top-level wiring, the Tang Primer 25K port and `lib/gw5a/`
are new.
