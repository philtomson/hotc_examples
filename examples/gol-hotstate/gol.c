// gol.c — Conway's Game of Life (B3/S23) as a cellular automaton on the
// Hotstate machine, rendered to the 1.14" ST7789 SPI LCD. See README.md.
//
// Algorithm:
//   * Two double-buffered writable BRAMs (grid0/grid1), 32x32 bool cells each,
//     flattened 1D as r*GRID_COLS + c. One buffer is read as "src" while the
//     other is written as "dst"; roles swap every generation so no cell ever
//     suffers an in-place read-modify-write (see docs §11.5).
//   * Next state = const-ROM lookup rule[alive][live_neighbor_count 0..8].
//   * Toroidal edges: gliders wrap both axes and travel indefinitely.
//   * After each generation, diff src vs dst and blit only changed cells as
//     CELL_SIZE x CELL_SIZE pixel blocks (gliders on a mostly-empty field ->
//     few SPI writes/gen).
//
// Shared ST7789/SPI driver lives in lcd_driver.c (compiled alongside this file
// via hotc's multi-file merge; gol.c is passed FIRST so generated names take
// "gol"). See lcd_driver.h for the shared variables.

#include "lcd_driver.h"

// -- Grid / display config --------------------------------------------------
#define GRID_COLS   32
#define GRID_ROWS   32
// CELL_SIZE: pixel width/height of one drawn cell. NOTE: lcd_driver.c's
// blit_cell() hardcodes a matching +3 offset (CELL_SIZE-1) since macros
// aren't shared across hotc's multi-file merge (only variables, via
// lcd_driver.h) -- keep the two in sync if this ever changes again.
#define CELL_SIZE   4
#define GRID_OFF_X  ((240 - GRID_COLS * CELL_SIZE) / 2)   // center 128px field: 56
#define GRID_OFF_Y  ((135 - GRID_ROWS * CELL_SIZE) / 2)   // center 128px field: 3
#define ON_COLOR    0x07E0   // green  (RGB565)
#define BG_COLOR    0x000F   // dark blue (RGB565)
#define FRAME_DELAY 450000   // throttle per generation (~sprite_bounce)

// -- Double-buffered writable BRAM (1D, flattened r*GRID_COLS + c) ----------
// Initialized with the starting pattern: grid0 carries four gliders in four
// travel directions; grid1 starts empty. Initializing here (rather than
// runtime-seeding) keeps each array to a single unified write expression
// during generation, per docs §11.5. Writable + initialized is allowed
// (sprite_bounce's dirR[] does the same).
// __bram (on grid0/grid1 below): hint real block RAM instead of distributed
// LUTRAM -- at 1024 entries x2 (grid0+grid1), the default inference exhausts
// the Tang Nano 9K's small distributed-RAM budget (259/270 RAM16SDP4) and
// fails to place; __bram routes it to BSRAM instead (otherwise only 34%
// used). No timing change: writable arrays already read through a
// registered path regardless of this qualifier.
// Confirmed on real hardware (2026-08-26): a single-glider diagnostic seed
// translates diagonally forever without settling, ruling out the __bram/
// BSRAM change and confirming the rule table is correct end-to-end. The
// multi-pattern seed below reaching a steady state after some generations
// is therefore genuine B3/S23 behavior of this specific seed, not a bug.
__bram static bool grid0[1024] = {   // 1024 = GRID_COLS * GRID_ROWS
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,0,
    0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,
};

// Second buffer starts empty.
__bram static bool grid1[1024] = {0};   // 1024 = GRID_COLS * GRID_ROWS
static bool sR[32] = {0};   // LHS-write by r forces r SOFTWARE (non-substitutable)
static bool sC[32] = {0};   // LHS-write by c forces c SOFTWARE
// -- Next-state rule ROM: [cell_is_alive][live_neighbor_count 0..8] ---------
// B3/S23: an alive cell survives at 2 or 3 neighbors; a dead cell births at
// exactly 3. Native 2D const-ROM lookup (docs §11.3), combinatorial LUT read.
static const bool rule[2][9] = {
    /* dead  */ { 0, 0, 0, 1, 0, 0, 0, 0, 0 },   // birth at exactly 3
    /* alive */ { 0, 0, 1, 1, 0, 0, 0, 0, 0 },   // survive at 2 or 3
};

// -- Loop counters and staging temporaries (file scope; hotc has no locals) -
// r/c MUST be unsigned: hotc's _BitInt is signed by default, and a signed
// 6-bit value can never satisfy "< 32" going false (max representable is
// +31; incrementing past it wraps to -32, which is still < 32) -- the loop
// bound 32 sits exactly on the boundary a signed N-bit type can't represent.
// Plain (signed) _BitInt(6) here is an infinite loop, confirmed via
// hotstate_sim: r frozen at 0 forever, c cycling through its full 6-bit
// range endlessly, base writes aliasing to exactly 64 distinct addresses
// (0..31 and 992..1023 -- the raw bit patterns of c's positive and wrapped
// negative halves sign-extended into base's 10 bits) instead of the 1024
// distinct cells one real pass should hit.
unsigned _BitInt(6) r = 0;   // row counter (software: value-read via base)
unsigned _BitInt(6) c = 0;   // col counter (software: value-read via base)
unsigned _BitInt(10) base = 0;   // unified write index (r*GRID_COLS + c), 0..1023
unsigned _BitInt(10) ni       = 0;   // computed neighbor index
_BitInt(7) nr       = 0;   // wrapped row (-1..32 pre-correction, signed)
_BitInt(7) nc       = 0;   // wrapped col (-1..32 pre-correction, signed)
unsigned _BitInt(4) self  = 0;   // center cell value (0/1)
unsigned _BitInt(4) sum   = 0;   // Moore-neighbor sum incl. center (0..9)
unsigned _BitInt(4) nb    = 0;   // one neighbor/cell read (0/1)
unsigned _BitInt(4) neigh = 0;   // neighbor count excluding self (0..8)
bool flip = 1;               // first generation reads seeded grid0 -> grid1
// cell_wr_val: shared staging variable for every grid0/grid1 write in the
// program (STEP_CELL's normal per-generation write AND the reseed sweep
// below). Required so every write site to a given writable array shares an
// identical data expression (docs §11.5) -- grid0 is written only ever as
// `grid0[base] = cell_wr_val;` (in gen2's STEP_CELL and in reseed), grid1
// only ever as `grid1[base] = cell_wr_val;` (gen1's STEP_CELL and reseed).
bool cell_wr_val = 0;

// -- Seed-toggle button (pin 3 / S2, see top.v) ------------------------------
bool mode_btn;                // input: 1 = pressed (top.v inverts the active-low pin)
bool btn_prev = 0;            // previous mode_btn sample, for edge detection
bool seed_mode = 0;           // 0 = multi-glider (grid0's compiled-in default), 1 = single glider

// Single-glider seed (matches the real-hardware-confirmed diagnostic pattern
// from the __bram/BSRAM verification): 5 cells, standard south-east glider.
static const bool seed_single[1024] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
};
// Multi-glider seed (identical to grid0's compiled-in initializer below --
// kept as its own ROM so reseed can restore this pattern from either mode).
static const bool seed_multi[1024] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,0,
    0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,
};

// -- Neighbor accumulate / STEP_CELL / DIFF_CELL: parameterized macros -----
// hotc's preprocessor (src/preprocessor.c) now supports real function-like
// macros with parameters (see plans/parameterized_macro_support.md) --
// these three used to be hand-expanded per call site because the
// preprocessor only ever recognized the literal zero-parameter form
// `#define NAME() body`. NB is invoked from inside STEP_CELL's own body;
// hotc's macro expander re-scans expanded text (depth-capped), so the
// nested call expands correctly with no special handling needed here.
#define NB(SRC, DR, DC) \
    nr = r + (DR); if (nr < 0) nr += GRID_ROWS; if (nr >= GRID_ROWS) nr -= GRID_ROWS; \
    nc = c + (DC); if (nc < 0) nc += GRID_COLS; if (nc >= GRID_COLS) nc -= GRID_COLS; \
    ni = nr * GRID_COLS + nc; nb = SRC[ni]; sum += nb

#define STEP_CELL(SRC, DST) \
    base = r * GRID_COLS + c; \
    self = SRC[base]; sum = self; \
    NB(SRC, -1, -1); \
    NB(SRC, -1, 0); \
    NB(SRC, -1, 1); \
    NB(SRC, 0, -1); \
    NB(SRC, 0, 1); \
    NB(SRC, 1, -1); \
    NB(SRC, 1, 0); \
    NB(SRC, 1, 1); \
    neigh = sum - self; \
    cell_wr_val = rule[self][neigh]; \
    DST[base] = cell_wr_val

#define DIFF_CELL(SRC, DST) \
    base = r * GRID_COLS + c; \
    self = SRC[base]; nb = DST[base]; \
    if (self != nb) { \
        blit_x = GRID_OFF_X + c * CELL_SIZE; \
        blit_y = GRID_OFF_Y + r * CELL_SIZE; \
        pixel_color = nb ? ON_COLOR : BG_COLOR; \
        blit_cell(); \
    }

// -- Main ------------------------------------------------------------------
int main() {
    init_display();

    // Full-screen dark background.
    pixel_color = BG_COLOR;
    fill_screen();

    while (1) {
        // -- Seed-toggle button (pin 3 / S2): edge-detected, checked once
        // per generation. On a press, wipe the screen, clear both grids,
        // write the other seed pattern into grid0, and restart from flip=1
        // -- mirrors exactly what power-on does (fill_screen() then a
        // seeded grid0 with grid1 empty), so a reseed behaves consistently
        // with the real boot sequence rather than introducing new behavior.
        if (mode_btn && !btn_prev) {
            // KNOWN QUIRK (kept deliberately, real-hardware confirmed
            // 2026-08-26): unlike the boot-time fill_screen() call above,
            // this one doesn't reset pixel_color = BG_COLOR first, so the
            // wipe uses whatever color the most recently blitted cell left
            // behind -- effectively a coin flip (dark-as-normal or
            // green-inverted) each press, independent of which seed_mode
            // is being switched to. Confirmed on hardware: not tied to
            // single- vs multi-glider mode, just press timing. Left as-is
            // by request -- to make it always correct, set
            // `pixel_color = BG_COLOR;` right before this fill_screen().
            fill_screen();
            seed_mode = !seed_mode;
            for (r = 0; r < GRID_ROWS; r++) {
                for (c = 0; c < GRID_COLS; c++) {
                    sR[r]=0; sC[c]=0;
                    base = r * GRID_COLS + c;
                    if (seed_mode) {
                        cell_wr_val = seed_single[base];
                    } else {
                        cell_wr_val = seed_multi[base];
                    }
                    grid0[base] = cell_wr_val;
                    cell_wr_val = 0;
                    grid1[base] = cell_wr_val;
                }
            }
            flip = 1;
        }
        btn_prev = mode_btn;

        if (flip) {
            // Generate grid0 -> grid1, then blit changed cells from grid1.
            for (r = 0; r < GRID_ROWS; r++) {
                for (c = 0; c < GRID_COLS; c++) {
                    sR[r]=0; sC[c]=0;
                    STEP_CELL(grid0, grid1);
                }
            }
            for (r = 0; r < GRID_ROWS; r++) {
                for (c = 0; c < GRID_COLS; c++) {
                    sR[r]=0; sC[c]=0;
                    DIFF_CELL(grid0, grid1)
                }
            }
        } else {
            // Generate grid1 -> grid0, then blit changed cells from grid0.
            for (r = 0; r < GRID_ROWS; r++) {
                for (c = 0; c < GRID_COLS; c++) {
                    sR[r]=0; sC[c]=0;
                    STEP_CELL(grid1, grid0);
                }
            }
            for (r = 0; r < GRID_ROWS; r++) {
                for (c = 0; c < GRID_COLS; c++) {
                    sR[r]=0; sC[c]=0;
                    DIFF_CELL(grid1, grid0)
                }
            }
        }

        flip = !flip;

        // Frame throttle: make glider motion watchable.
        for (delay_cnt = 0; delay_cnt < FRAME_DELAY; delay_cnt++) {}
    }
    return 0;
}
