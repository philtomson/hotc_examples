# gol-hotstate — Conway's Game of Life on the Hotstate Machine

Conway's Game of Life (rule B3/S23), running entirely as compiled Hotstate
microcode, rendered live to a 1.14" ST7789 SPI LCD. Verified end-to-end
against a canonical B3/S23 software oracle and flashed to a real
**Sipeed Tang Nano 9K**.

## What it does

A 32×32 toroidal grid of cells lives in two double-buffered writable BRAMs.
Each generation, every cell's 8 Moore neighbors are summed (wrapping at the
edges), the next state is looked up in a 2×9 const-ROM (`rule[alive][count]`),
and only the cells that actually changed are blitted to the LCD as 4×4 pixel
blocks — so a mostly-empty field with a few gliders costs only a handful of
SPI writes per generation, not a full-screen redraw.

A physical button (S2, board pin 3) toggles between two seed patterns —
a single glider (glides forever, useful as a "is this actually running"
sanity check) and a four-glider pattern (settles into a mix of still lifes
and oscillators after some generations, which is genuine B3/S23 behavior of
that seed, not a bug) — wiping the screen and restarting the CA on each
press.

## Building and running

The `gol_template.v`/`.mem`/`.vh`/`.toml` files in this directory are hotc's
compiled OUTPUT from `gol.c` + `lcd_driver.c` (`gol.c` passed first on the
hotc command line, since hotc names the generated module/files after the
first input file's basename — `gol`, not `lcd_driver`), checked in as-is.
This repo doesn't ship hotc itself, so there's no `generate` step — the
commands below just build and flash what's here:

```bash
# Verilator RTL simulation (free-running trace capture, not self-checking)
make hw_sim

# Synthesize + place-and-route + pack a bitstream for the Tang Nano 9K
make synth pnr pack

# Program a connected Tang Nano 9K over USB
make prog
```

## Hardware target

Sipeed Tang Nano 9K (Gowin GW1NR-LV9QN88PC6/I5), pinned out in `lcd114.cst`:

| Signal | Direction | Pin | Notes |
|--------|-----------|-----|-------|
| `clk` | in | 52 | onboard 27 MHz oscillator |
| `resetn` | in | 4 | board reset button, active-low |
| `mode_btn_n` | in | 3 | seed-toggle button, active-low |
| `lcd_clk` | out | 76 | SPI clock (MOSI) |
| `lcd_data` | out | 77 | SPI MOSI data |
| `lcd_cs` | out | 48 | active-low chip select |
| `lcd_rs` | out | 49 | data/command select |
| `lcd_resetn` | out | 47 | panel hardware reset |

`top.v` inverts both active-low board inputs (`rst = ~resetn`,
`mode_btn = ~mode_btn_n`) before wiring them into the `gol` hotstate
instance; everything else (`sclk`, `mosi`, `cs_n`, `dc`, `lcd_resetn`) maps
straight through to the ST7789 panel.

## Algorithm (`gol.c`)

* **Grid:** two double-buffered writable BRAMs, `grid0[1024]`/`grid1[1024]`
  (32×32 flattened as `r*32+c`). One buffer is always read as `SRC` while the
  other is written as `DST`; the roles swap every generation (`flip`) so no
  cell is ever read and written in the same pass — see
  `docs/hotc_programming.md` §11.5.
* **`__bram` on both grids:** at 1024 entries × 2 grids, the default
  distributed-LUT-RAM inference exhausted the Tang Nano 9K's small
  `RAM16SDP4` budget (259/270, 96%) and failed to place. Annotating both
  arrays `__bram` routes them to real block RAM (BSRAM) instead — a
  synthesis-only hint with zero instruction-timing change, since writable
  arrays already read through a registered path either way. See
  `docs/hotc_programming.md` §11.5 for the general mechanism.
* **Rule:** `static const bool rule[2][9]` — `rule[cell_is_alive][live_neighbor_count]`.
  `rule[0]` (dead) births at exactly 3 neighbors; `rule[1]` (alive) survives
  at 2 or 3. A native 2D const-ROM, combinatorial LUT read.
* **Edges:** toroidal — neighbor row/col indices wrap both axes, so a lone
  glider travels indefinitely instead of running off the field.
* **Neighbor accumulation / step / diff-blit: parameterized macros.** `NB`,
  `STEP_CELL`, and `DIFF_CELL` are real `#define NAME(params) ...`
  function-like macros (including `STEP_CELL`'s body invoking `NB` — nested
  macro expansion works via hotc's depth-capped re-scan) — hotc's
  preprocessor supports parameterized macros.
* **Seed toggle:** `mode_btn` is edge-detected once per generation
  (`if (mode_btn && !btn_prev)`) rather than polled continuously — a human
  button press spans many generations, so per-generation resolution is
  ample. Both grids have exactly one write site each in the whole program,
  routed through a shared staging variable `cell_wr_val`, because hotc's
  writable-array codegen requires every write to a given array use an
  identical address/data expression (§11.5) — the reseed sweep and the
  normal per-generation write share that same expression shape.
* **Render throttle:** a `delay_cnt` busy-wait loop (`FRAME_DELAY = 450000`
  cycles) after each generation makes glider motion visible to the eye
  instead of a blur.

## Verification

* **Software oracle:** generations 1–3 compared cell-by-cell against an
  independently computed canonical B3/S23 reference, from the same
  hardware-recorded `self`/`neigh`/write values (decoded correctly via
  `gol_symbols.toml`'s per-signal bit widths — not the raw CSV column, which
  only carries bit 0 of a multi-bit state). **0 mismatches** across all
  three generations.
* **Real hardware:** flashed to a Tang Nano 9K. A single-glider seed was
  used as a live sanity check — it glides indefinitely without settling,
  confirming the whole chain (rule table, `__bram`/BSRAM routing, synthesis,
  place-and-route) end-to-end on real silicon. The four-glider seed reaching
  a steady state after some generations was confirmed to be genuine B3/S23
  behavior of that particular seed, not a hang.
* Full project regression suite stays clean with this example's build
  flags and generated artifacts.


## Files

| File | Purpose |
|------|---------|
| `gol.c` | Main hotstate program: grid state, rule ROM, generation loop, seed toggle |
| `lcd_driver.c` / `lcd_driver.h` | Shared ST7789 SPI driver (`init_display`, `fill_screen`, `blit_cell`) — same driver pattern used by hotc's other SPI-LCD examples |
| `top.v` | Top-level Verilog wiring the `gol` hotstate instance to board pins |
| `lcd114.cst` | Gowin pin-constraint file for the Tang Nano 9K + 1.14" LCD |
| `Makefile` | `hw_sim` / `synth` / `pnr` / `pack` / `prog` targets |
