# hotc examples

Real, hardware-verified example designs built with **hotc**, a C-to-FPGA
compiler that targets a small microcoded control engine called
**hotstate** — plus the hand-written Verilog, board constraints, and host
tooling each example needs to actually build and run.

`hotc` itself isn't open source yet. What's here is its *output*: the
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

hotstate is a **single-cycle microcoded state machine**: it executes one
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
  webserver/                 (coming next)
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
- **`webserver`** — coming next.
