# hotc examples

Hardware-verified example designs built with **hotc**, a C-to-FPGA
compiler that targets a small microcoded control engine called
**hotstate** — plus the hand-written Verilog, board constraints, and host
tooling each example needs to actually build and run.

The `hotc` compiler itself isn't currently open source. What's here is its *output*: the
generated Verilog and microcode `.mem` files for each example, the
hotstate engine those files run on (`IP/`), and everything else (hand-
written top-level wiring, board constraints, host-side test/demo scripts)
needed to synthesize, flash, and talk to a real board. The `.c` sources
that were compiled to produce each example are included too, so you can
see the actual programming model — just not the compiler that consumes
them. **You do not need `hotc` to build or run anything in this repo.**

These examples target Sipeed **Tang Nano 9K**, **Tang Nano 20K**, and
Tang Primer **25K** boards (all Gowin FPGAs). Some examples support a
subset of these — check the example's own README.

## What is hotstate?

hotstate is a **single-cycle microcoded state machine** 
(see: https://hotwright.com/ for more details): it executes one
instruction per clock cycle to drive a control-dominated design (an FSM,
a protocol engine, a sequencer) plus whatever narrow datapath logic hangs
off it. `hotc` compiles a restricted, hardware-mappable subset of C
directly into hotstate microcode, so "programming the FPGA" looks like
writing ordinary-looking (if constrained) C: plain assignments, `if`/
`while`/`for`/`switch`, function calls — no pointers, no dynamic memory,
no `float`. Control flow becomes jump/branch microcode; conditions become
truth tables; state variables become flip-flops.

The engine itself lives in `IP/` as a handful of small SystemVerilog
modules:

| File | Role |
|---|---|
| `IP/hotstate.sv` | Top-level: wires everything below together |
| `IP/microcode.sv` | Instruction memory + decode |
| `IP/control.sv` | Fire/branch/call/return control logic |
| `IP/next_address.sv` | Next-PC priority mux (reset/jump/call/return/sequential) |
| `IP/variable.sv` | The "UberLUT" — truth tables implementing every C condition |
| `IP/timer.sv` | Countdown timers (loop induction variables map here) |
| `IP/switch.sv` | `switch`/`case` jump tables |
| `IP/stack.sv` | Function call/return stack |

See `IP/README.md` for the instruction format and execution model in
detail, and `docs/hotc_programming.md` for the full C-subset language
reference (types, control flow, hardware-mapping rules, and the
performance pitfalls that matter when you're compiling to microcode
instead of running on a CPU) — worth reading before the `.c` sources in
each example will make much sense.

Every example's generated Verilog instantiates the same eight `IP/*.sv`
files with design-specific parameters (state count, timer count, etc.) —
there's one engine, reused and reconfigured per design, not one engine
per example.

## Repository layout

```
IP/                          hotstate engine (shared by every example)
docs/hotc_programming.md     hotc C-subset language reference
examples/
  Tsetlin_hotstate_uart/     Tsetlin Machine MNIST classifier over UART
  gol-hotstate/              Conway's Game of Life, rendered to an SPI LCD
  webserver/                 HTTP web server with browser LED control, over UART
  KAN_hotstate/              Kolmogorov-Arnold Network MNIST classifier (Tang Nano 20K)
tools.mk                     shared synthesis tool-path overrides
```

Each example directory is self-contained: its own Makefile(s), board
constraint (`.cst`) files, generated Verilog/`.mem`, and any host-side
Python scripts. Look for a README.md inside each example for specifics —
this file only covers what's common to all of them.

## Requirements

**To build and flash a design:**

| Tool | Used for | Typical source |
|---|---|---|
| [Yosys](https://github.com/YosysHQ/yosys) (`synth_gowin`) | Synthesis | [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) |
| [nextpnr-himbaechel](https://github.com/YosysHQ/nextpnr) | Place & route (Gowin backend) | OSS CAD Suite |
| `gowin_pack` (Project Apicula) | Bitstream packing | OSS CAD Suite |
| [openFPGALoader](https://github.com/trabucayre/openFPGALoader) | Flashing over USB | OSS CAD Suite, or your distro's package |

The easiest route to all four is the **OSS CAD Suite** nightly build —
it's a single tarball with everything above on `PATH`. `tools.mk`
(included by every example's `Makefile.synth_*`) lets you override any
tool's path without editing files — see the comment at its top for the
three ways to do that (command line, environment variable, or a
gitignored `local.mk`).

**To simulate a design (optional — hardware-verified designs don't require
this to just flash and run):**

- [Verilator](https://www.veripool.org/verilator/) — each example's README
  gives the exact invocation.

**To run the host-side test/demo scripts:**

- Python 3
- [`pyserial`](https://pyserial.readthedocs.io/) (`pip install pyserial`)
- `tkinter`, for examples with an interactive GUI (usually already present
  with your system Python; if not, it's a separate OS package — e.g.
  `python3-tk` on Debian/Ubuntu/Fedora)

## Building and running an example

```bash
cd examples/Tsetlin_hotstate_uart
make -f Makefile.synth_tang9k prog      # synth + PnR + pack + flash, one board
python3 send_image.py --port /dev/ttyUSB1
```

Each example's own README has the full story — expected resource usage,
the wire protocol (if it talks to the host over UART/SPI/etc.), and any
board-specific quirks. If a design ships a `KNOWN_ISSUES.md`, read it
before filing something as a bug — some of what's there (a toolchain
version regression, a board-specific errata) is unrelated to hotc itself,
already root-caused, and already worked around in the Makefile you're
using.

If a board's `.cst` doesn't match the pins on the specific dev board
revision you have, or `openFPGALoader -b <preset>` doesn't recognize your
board, check `openFPGALoader --list-boards`; presets occasionally get
renamed upstream.

## Examples

- **[`Tsetlin_hotstate_uart`](examples/Tsetlin_hotstate_uart/)** — a
  200-clause Tsetlin Machine MNIST digit classifier, driven over a plain
  UART link (no extra hardware beyond the board's USB-serial bridge).
  Verified 100/100 against 100 real labeled MNIST samples on Tang Nano 9K
  real hardware. Includes `draw_digit_uart.py`, an interactive GUI to draw
  a digit and classify it live.
- **[`gol-hotstate`](examples/gol-hotstate/)** — Conway's Game of Life
  (B3/S23), running entirely as compiled hotstate microcode, rendered live
  to a 1.14" ST7789 SPI LCD. A physical button toggles between two seed
  patterns. Tang Nano 9K only (needs the SPI LCD). Verified against a
  canonical B3/S23 software oracle and flashed to real hardware.
- **[`KAN_hotstate`](examples/KAN_hotstate/)** — a **Kolmogorov–Arnold
  Network** MNIST digit classifier. KANs put learnable univariate functions on
  the *edges* instead of fixed activations on the nodes, so once discretised
  every edge becomes a lookup table and inference is table lookups plus an
  integer adder tree — **zero DSP blocks, no floating point**. 6.75 MB of
  trained weights live in the Tang Nano 20K's in-package SDRAM, streamed in over
  UART at 2 Mbaud in ~34 s. The classified digit is displayed in binary on the
  board's LEDs. Verified 100/100 in simulation **and** 100/100 on real hardware.
  Includes `draw_digit_kan.py`, an interactive GUI to draw a digit and read the
  answer off the board. Tang Nano 20K only (needs the in-package SDRAM).
- **[`webserver`](examples/webserver/)** — a small HTTP server, served
  entirely from compiled hotstate microcode, with a browser-based dashboard
  to toggle on-board LEDs. Talks over plain UART via a host-side TCP
  bridge (`bridge.py`); a real-time Verilator bridge lets you try it with
  no board at all. Tang Nano 9K and 20K, both verified end-to-end on real
  hardware with real browser traffic.

## License

This repository is under two licenses, split by directory:

- **Everything else** (other examples, `docs/`, `tools.mk`, host scripts)
  is [MIT](LICENSE.md) — use, modify, and redistribute freely, including
  commercially.
- **[`IP/`](IP/LICENSE.md)** (the hotstate engine itself — `hotstate.sv`,
  `microcode.sv`, `control.sv`, `next_address.sv`, `timer.sv`, `variable.sv`,
  `switch.sv`, `stack.sv`) and **[`examples/Tsetlin_hotstate_uart/`](examples/Tsetlin_hotstate_uart/LICENSE.md)**
  are each CC BY-NC-ND 4.0 — noncommercial use only, no derivative/modified
  redistribution. Every example depends on `IP/` to build and run, so
  building and running an example is fine; redistributing a modified
  version of the engine (or of Tsetlin_hotstate_uart), or using either
  commercially, is not.

If you're unsure which applies to a given file, check which directory it's
in — each CC-BY-NC-ND directory's own `LICENSE.md` is the authoritative
text (`IP/LICENSE.md`, `examples/Tsetlin_hotstate_uart/LICENSE.md`).
