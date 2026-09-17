// lcd_driver.c — Shared ST7789 SPI LCD driver code for the gol-hotstate
// example. Compiled into the single hotstate machine via hotc's multi-file
// merge (NOT --system): gol.c must be passed FIRST on the command line so the
// generated module/file names take gol's name; this file second. See
// lcd_driver.h for the small set of variables shared by name.
//
// Display: 1.14" SPI LCD (240x135 visible pixels, ST7789V controller, RGB565)
// Bit-bang SPI Mode 0, MSB first.
//
// Hardware mapping (Tang Nano 9K pins) — identical to examples/spi_lcd:
//   sclk       -> pin 76 (lcd_clk)
//   mosi       -> pin 77 (lcd_data)
//   cs_n       -> pin 48 (lcd_cs)
//   dc         -> pin 49 (lcd_rs)
//   lcd_resetn -> pin 47 (lcd_resetn)

// -- State / Outputs (initialized global variables) ------------------------
bool sclk       = 0;  // SPI Clock (idle low)
bool mosi       = 0;  // SPI MOSI
bool cs_n       = 1;  // Active-low chip select
bool dc         = 0;  // Data/Command: 0 = command, 1 = data
bool lcd_resetn = 0;  // Display hardware reset (active low)

// -- Operational Globals (private to this file's own functions) -----------
_BitInt(8)  spi_byte    = 0;
bool        spi_dc      = 0;

_BitInt(10) win_x1      = 0;
_BitInt(10) win_x2      = 0;
_BitInt(9)  win_y1      = 0;
_BitInt(9)  win_y2      = 0;

// -- Shared with gol.c (re-declared in lcd_driver.h) -----------------------
// delay_cnt reused by init_display() timing and gol.c's frame throttle.
// pixel_color set by gol.c before each fill. blit_x/blit_y hold the top-left
// of the 2x2 cell gol.c is about to paint (blit_cell reads them).
_BitInt(32) delay_cnt   = 0;
_BitInt(16) pixel_color = 0;
_BitInt(9)  blit_x      = 0;
_BitInt(9)  blit_y      = 0;

// -- Internal counters/index registers (private to this file) -------------
_BitInt(16) px_cnt    = 0;
_BitInt(8)  cmd_idx   = 0;
_BitInt(10) entry     = 0;
_BitInt(10) c_start   = 0;
_BitInt(10) c_end     = 0;
_BitInt(9)  r_start   = 0;
_BitInt(9)  r_end     = 0;
_BitInt(16) num_pixels= 0;

// -- 70-entry Init Command Table --------------------------------------------
// Bit 8: DC (0 = command, 1 = data)
// Bits 7:0: Byte payload
static const _BitInt(10) init_cmd[70] = {
    0x036, 0x170,                                                    // MADCTL = 0x70
    0x03A, 0x105,                                                    // COLMOD = 0x05 (RGB565)
    0x0B2, 0x10C, 0x10C, 0x100, 0x133, 0x133,                         // PORCTRL
    0x0B7, 0x135,                                                    // GCTRL
    0x0BB, 0x119,                                                    // VCOMS
    0x0C0, 0x12C,                                                    // LCMCTRL
    0x0C2, 0x101,                                                    // VDVVRHEN
    0x0C3, 0x112,                                                    // VRHS
    0x0C4, 0x120,                                                    // VDVS
    0x0C6, 0x10F,                                                    // FRCTRL2
    0x0D0, 0x1A4, 0x1A1,                                             // PWCTRL1
    0x0E0, 0x1D0, 0x104, 0x10D, 0x111, 0x113, 0x12B, 0x13F,
    0x154, 0x14C, 0x118, 0x10D, 0x10B, 0x11F, 0x123,                 // PVGAMCTRL
    0x0E1, 0x1D0, 0x104, 0x10C, 0x111, 0x113, 0x12C, 0x13F,
    0x144, 0x151, 0x12F, 0x11F, 0x11F, 0x120, 0x123,                 // NVGAMCTRL
    0x021,                                                           // INVON
    0x029,                                                           // DISPON
    0x02A, 0x100, 0x128, 0x101, 0x117,                               // CASET: col 40..279 (240 cols)
    0x02B, 0x100, 0x135, 0x100, 0x1BB,                               // RASET: row 53..187 (135 rows)
    0x02C                                                            // RAMWR
};

// -- SPI Bit-Bang Byte Send ------------------------------------------------
void send_byte() {
    dc = spi_dc;
    cs_n = 0;

    // Unrolled 8-bit MSB-first transmission
    mosi = spi_byte[7]; sclk = 1; sclk = 0;
    mosi = spi_byte[6]; sclk = 1; sclk = 0;
    mosi = spi_byte[5]; sclk = 1; sclk = 0;
    mosi = spi_byte[4]; sclk = 1; sclk = 0;
    mosi = spi_byte[3]; sclk = 1; sclk = 0;
    mosi = spi_byte[2]; sclk = 1; sclk = 0;
    mosi = spi_byte[1]; sclk = 1; sclk = 0;
    mosi = spi_byte[0]; sclk = 1; sclk = 0;

    cs_n = 1;
}

// -- Set Window (CASET + RASET + RAMWR) ------------------------------------
void set_window() {
    c_start = win_x1 + 40;
    c_end   = win_x2 + 40;
    r_start = win_y1 + 53;
    r_end   = win_y2 + 53;

    // CASET (0x2A)
    spi_dc = 0; spi_byte = 0x2A; send_byte();
    spi_dc = 1; spi_byte = c_start >> 8; send_byte();
    spi_dc = 1; spi_byte = c_start & 0xFF; send_byte();
    spi_dc = 1; spi_byte = c_end >> 8; send_byte();
    spi_dc = 1; spi_byte = c_end & 0xFF; send_byte();

    // RASET (0x2B)
    spi_dc = 0; spi_byte = 0x2B; send_byte();
    spi_dc = 1; spi_byte = r_start >> 8; send_byte();
    spi_dc = 1; spi_byte = r_start & 0xFF; send_byte();
    spi_dc = 1; spi_byte = r_end >> 8; send_byte();
    spi_dc = 1; spi_byte = r_end & 0xFF; send_byte();

    // RAMWR (0x2C)
    spi_dc = 0; spi_byte = 0x2C; send_byte();
}

// -- Fill Window with Solid Color ------------------------------------------
void fill_current_window() {
    num_pixels = (win_x2 - win_x1 + 1) * (win_y2 - win_y1 + 1);
    set_window();
    spi_dc = 1;
    for (px_cnt = 0; px_cnt < num_pixels; px_cnt++) {
        spi_byte = pixel_color >> 8;
        send_byte();
        spi_byte = pixel_color & 0xFF;
        send_byte();
    }
}

// -- Full-screen background fill using the global pixel_color --------------
void fill_screen() {
    win_x1 = 0;   win_x2 = 239;
    win_y1 = 0;   win_y2 = 134;
    fill_current_window();
}

// -- Paint one 4x4 pixel cell at (blit_x, blit_y) using global pixel_color -
// gol.c sets blit_x/blit_y and pixel_color before calling. Reuses
// set_window()/fill_current_window() from the shared driver core.
// The "+3" below is gol.c's CELL_SIZE-1 (4-1); macros aren't shared across
// hotc's multi-file merge (only variables, via lcd_driver.h), so this is
// hand-kept in sync with gol.c's CELL_SIZE -- update both if it changes.
void blit_cell() {
    win_x1 = blit_x;   win_x2 = blit_x + 3;
    win_y1 = blit_y;   win_y2 = blit_y + 3;
    fill_current_window();
}

// -- Display Initialization ------------------------------------------------
void init_display() {
    // 1. Hardware Reset sequence
    lcd_resetn = 0;
    for (delay_cnt = 0; delay_cnt < 2700000; delay_cnt++) {} // 100ms low @ 27MHz

    lcd_resetn = 1;
    for (delay_cnt = 0; delay_cnt < 5400000; delay_cnt++) {} // 200ms high @ 27MHz

    // 2. SLPOUT (0x11)
    spi_dc = 0; spi_byte = 0x11; send_byte();
    for (delay_cnt = 0; delay_cnt < 3240000; delay_cnt++) {} // 120ms delay @ 27MHz

    // 3. Send 70-entry init command table
    for (cmd_idx = 0; cmd_idx < 70; cmd_idx++) {
        entry    = init_cmd[cmd_idx];
        spi_dc   = (entry >> 8) & 1;
        spi_byte = entry & 0xFF;
        send_byte();
    }
}
