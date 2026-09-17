# Tsetlin Machine FPGA Inference Accelerator — UART variant

A 200-clause Tsetlin Machine MNIST digit classifier, running entirely on
the hotstate engine (see the [repo-level README](../../README.md) for what
that is), with a plain UART front-end — no extra hardware beyond a Tang
Nano 9K/20K or Tang Primer 25K's existing USB-serial bridge.

The inference engine itself (`tm_core_v2.v`'s clause evaluation and vote
accumulators, `tm_seq_controller.c`'s hotstate clause sequencer, and the
trained clause-mask ROMs in `gen/`) is hand-designed/trained Verilog and
hotc C, not something this README will re-derive — what's documented here
is the UART front-end wired around it and how to build, flash, and talk to
the result.

## Protocol

The design auto-starts inference right after the 98th image byte arrives —
no separate trigger, a natural fit for UART's byte-stream model:

1. Host sends exactly 98 raw image bytes over UART (no framing needed).
2. The design immediately starts inference (no separate trigger).
3. Host waits for 1 response byte: the predicted digit (0-9) in the low
   nibble.
4. Repeat — the design loops forever, one image in, one result byte out.

```
  Host (send_image.py)
      │  98 raw bytes (MNIST image, 1 bit/pixel packed to bytes)
      ▼
  uart_rx (hotstate)
      │  rx_done/rx_byte, one pulse per byte
      ▼
  tm_uart_loader (hotstate)
      │  writes img_waddr/img_wdata/img_wen (98x), then go=1
      ▼
  tm_top (tm_seq_controller + tm_core_v2)
      │  200-clause evaluation + sequential argmax -> done, winner[3:0]
      ▼
  tm_uart_loader
      │  tx_data = winner, tx_start (held until tx_busy)
      ▼
  uart_tx (hotstate)
      │  1 byte out
      ▼
  Host
```

## Source Files

| File | Role |
|------|------|
| `tm_core_v2.v` | Hand-written: clause evaluation + vote accumulators. Carries `(* fsm_encoding = "none" *)` on its hand-written `state` register as a preventive fix for a yosys FSM-re-encoding issue seen elsewhere on this hardware. |
| `tm_top.v` | Hand-written: fully I/O-agnostic (`go`/`done`/`img_waddr`/`img_wdata`/`img_wen`/`result` ports only). |
| `tm_seq_controller.c` | hotc source: the hotstate clause sequencer (200-clause evaluation + argmax). |
| `gen/` | Trained clause-mask ROMs (`clause_meta.hex`, `include_mask.hex`, `include_inv_mask.hex`) + `tm_config.vh`. Training itself isn't part of this repo. |
| `uart_rx.c` / `uart_tx.c` | hotc source: general-purpose UART receive/transmit hotstate machines. |
| `tm_uart_loader.c` | hotc source: receives the 98-byte image over UART, drives `img_waddr`/`img_wdata`/`img_wen`, runs the `go`/`done` handshake with `tm_seq_controller`, and sends the result byte back. |
| `tm_hw_top_uart.v` | Hand-written: top-level wrapper wiring `uart_rx` + `uart_tx` + `tm_uart_loader` + `tm_top` together. |
| `tm_hw_top_uart_tb.v` | Verilator testbench — sends a real MNIST test image (`sample0.hex`) over simulated UART and checks the result against the expected prediction for that sample (digit 7). |
| `sample0.hex` | Fixture for the testbench above — sample 0's 98 image bytes, as a `$readmemh`-compatible hex dump. |
| `batch_ref.bin` | 100 real labeled MNIST samples + reference predictions, used by `send_batch.py` below. |
| `tm_{tang9k,tang20k,primer25k}_uart.cst` | Pin constraints per board. |
| `Makefile.synth_{tang9k,tang20k,primer25k}` | Per-board synthesis/PNR/pack/program flow (yosys + nextpnr-himbaechel + gowin_pack + openFPGALoader). |
| `send_image.py` | Host-side test script — sends a single 98-byte image (default: all-zero) and prints the returned digit. |
| `send_batch.py` | Host-side batch test script — sends all 100 `batch_ref.bin` samples and reports agreement against the reference predictions and true labels. **Use this, not a single test image, to judge whether a build actually works** — see "Known limitations" below for why. |
| `draw_digit_uart.py` | Interactive host-side GUI (Tk + pyserial) — draw a digit on a 28×28 canvas with the mouse and classify it on real hardware over the same UART protocol as `send_image.py`. |
| `verified_bitstreams/` | Known-good pre-built bitstream(s), if you'd rather flash directly than synthesize. See its contents for which board/hash. |

## Building and Testing

### Simulation

```bash
IP_DIR=../../IP
verilator --timing --cc -Wno-fatal -Wno-WIDTHTRUNC --exe --build -j 4 \
  -I. -I$IP_DIR -Igen \
  sim_main.cpp tm_hw_top_uart_tb.v tm_hw_top_uart.v tm_top.v tm_core_v2.v \
  tm_seq_controller_template.v tm_uart_loader_template.v uart_tx_template.v uart_rx_template.v \
  $IP_DIR/hotstate.sv $IP_DIR/microcode.sv $IP_DIR/control.sv $IP_DIR/next_address.sv \
  $IP_DIR/timer.sv $IP_DIR/variable.sv $IP_DIR/switch.sv $IP_DIR/stack.sv \
  --top tm_hw_top_uart_tb
./obj_dir/Vtm_hw_top_uart_tb
```
Expected: `[TB] PASS: result=7 (expected 7, matches the reference prediction for this sample)`.

### Hardware

```bash
make -f Makefile.synth_tang9k prog                 # or Makefile.synth_tang20k / _primer25k
python3 send_image.py --port /dev/ttyUSB1          # all-zero test image
python3 send_image.py --port /dev/ttyUSB1 --image path/to/98-byte-image.bin
python3 send_batch.py --port /dev/ttyUSB1          # all 100 batch_ref.bin samples
python3 draw_digit_uart.py --port /dev/ttyUSB1     # draw a digit, classify interactively
```

Use `udevadm info -a -n /dev/ttyUSBn | grep bInterfaceNumber` to find the
right port if `/dev/ttyUSB1` isn't correct on your machine — interface `00`
is the JTAG debug interface, interface `01` is the UART.

**Verified on real Tang Nano 9K hardware** against the full 100-sample
`batch_ref.bin` batch: **100/100 (100.0%) agreement** with both the
reference predictions and the true labels (see `verified_bitstreams/` for
that exact build). See "Known limitations" below for one open, rare,
unreproduced result and what's known about it.

## FPGA Resource Usage (Tang Nano 9K, nextpnr-himbaechel device utilisation)

| Resource | Used | Available | % |
|---|---|---|---|
| LUT4 | 2,485 | 8,640 | 28% |
| DFF | 629 | 6,480 | 9% |
| ALU | 742 | 6,480 | 11% |
| BSRAM | 22 | 26 | 84% |
| IOB | 5 | 276 | 1% |

BSRAM is dominated by the 200-clause mask ROMs; LUT/DFF usage is mostly the
four hotstate machines' control logic (loader + two UART engines + the
clause sequencer) plus the clause evaluation datapath itself.

## Tang Nano 20K: build with `-noalu`

This design builds for the Tang Nano 20K (`Makefile.synth_tang20k`). It
passes `synth_gowin -noalu`, and **that flag is required for correctness
on this part** — it is not a tuning knob. See `KNOWN_ISSUES.md` for the
full story (a yosys ALU-carry-cell miscompile on GW2A-18C, corroborated
upstream at YosysHQ/apicula#514, not specific to this design). Verify
after any change to the sources, to yosys, or to the constraints:

```bash
make -f Makefile.synth_tang20k verify     # build, flash, run all 100 samples
```
and require 100/100.

## Known limitations

- **Batch-test, don't single-image-test, when judging correctness.** An
  all-zero image written to `input_bram[0]` on every iteration is
  indistinguishable from one correctly advancing through the image, so a
  single all-zero test can pass even with a stuck write address. Use
  `send_batch.py` against real labeled data to actually validate a build.
- See `KNOWN_ISSUES.md` for two hardware/toolchain findings worth knowing
  about before you build: the Tang Nano 20K `-noalu` requirement above,
  and one rare, unreproduced 93/100 batch result on the Tang Nano 9K
  (root cause not confirmed, most likely a UART link glitch — the
  protocol has no framing or checksum to guard against one).
