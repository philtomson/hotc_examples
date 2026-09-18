# KAN_hotstate — TODO

## Retry the UART result path on a replacement Tang Nano 20K

The board used for bring-up has an **intermittent FPGA→host** direction on its
on-board BL616 bridge (host→FPGA has been reliable throughout). The example
currently sidesteps this by showing the classified digit on `led[3:0]` instead
of returning a result byte — see README.md.

**Everything needed to retry is already in the tree.** `kan_control` transmits
the result byte regardless of the LED display, and `send_batch.py` **without**
`--leds` waits for it:

```bash
python3 pack_weights.py
make -f Makefile.synth_tang20k pack BAUD=2000000
make -f Makefile.synth_tang20k prog
python3 send_batch.py /dev/ttyUSB1 --baud 2000000      # no --leds
```

Expect `100/100` and ~34 s for the weight load. If instead it streams the
weights at full line rate and then times out waiting for sample 0, that is the
same failure seen on the original board.

### Why this is worth doing rather than assuming

Every software-side cause was eliminated on the original board, each by direct
experiment rather than argument:

| Ruled out | How |
|---|---|
| `uart_rx` framing | Clean at 115200–2 Mbaud in simulation, back-to-back |
| `uart_tx` timing | 469 vs 468.75 clocks/bit (0.16% error), clean idle, no glitch |
| `kan_control` throughput | 300,000 back-to-back bytes at 2 Mbaud, zero loss |
| Dropped weight bytes | `sdram_rd_req` fires, so `load_weights()` completes |
| SDRAM read/write | `make rw_probe`, plus 100/100 via the external adapter |
| Placement | Seeds 1 and 12345 behave identically |
| Synthesis | yosys/nextpnr **and** the proprietary Gowin toolchain agree |
| Host side | A Tang Primer 25K on the same PC/baud/script works, 3/3 |
| ModemManager | Stopped; no change |
| Debugger firmware | Updated 2023030621 → 2025030317; no change |

So a new board either confirms the fault was that unit, or points somewhere
nobody has looked yet. Both outcomes are informative.

### Dead ends — do not redo these

- **FTDI latency timer.** `ttyUSB1` reports `latency_timer=0`, which looks like
  a smoking gun. Setting it to 16 changed nothing, and the value resets on
  re-enumeration.
- **"Isolated bytes are dropped, continuous streams get through."** This looked
  like a clean characterisation and it was an **artifact of testing at moments
  when the path happened to be alive versus dead**. It collapsed as soon as the
  continuous-stream control was re-run: the same bitstream that had just
  delivered 128/128 went to 0 bytes.
- **Chasing a burst-size threshold.** Followed from the above and is void for
  the same reason.

The honest characterisation is simply **intermittent, cause unknown**. It was
dead for hours, then worked, then died again and stayed dead across a power
cycle.

## Smaller follow-ups

- **Refresh scheduling under sustained reads is unverified.** The shim issues a
  refresh only when nothing is pending and nothing is granted, so a back-to-back
  read loop (which is exactly what `run_layer1`/`run_layer2` do) can defer it.
  Simulation cannot catch the *consequence* — `sim_only_sdram_model.v` treats
  `CMD_AutoRefresh` as a no-op and never decays, so a starved design still
  passes — but it **can** measure the schedule. The instrumentation belongs in
  `kan_ack_probe.v`, which already decodes SDRAM commands (`kan_rw_probe.v` does
  not). Assert the worst gap beats 64 ms/4096 = 15.625 µs (843 clocks at 54 MHz),
  and make sure the check fails when refresh never fires at all rather than
  passing vacuously.
- **`draw_digit_kan.py` centering is untested on real handwriting.** The
  canvas/brush/centering came from `Tsetlin_hotstate_uart`, which fed a
  *thresholded 1-bit* image; KAN takes 8-bit grayscale, so stroke intensity now
  matters in a way it did not there. The `tb_data.txt` samples bypass this path
  entirely — they are already centred and downsampled.
- **2 Mbaud + `--leds` is verified; 2 Mbaud + result-byte is not.** The fast
  rate has only ever been exercised with the result on the LEDs.
