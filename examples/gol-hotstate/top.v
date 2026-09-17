`timescale 1ns / 1ps

// Top-level module for Game of Life on the ST7789 1.14" SPI LCD, Tang Nano 9K
module top (
    input  wire clk,         // Onboard 27 MHz oscillator (Pin 52)
    input  wire resetn,      // Board active-low reset button (Pin 4)
    input  wire mode_btn_n,  // Board active-low second button (Pin 3)
    output wire lcd_clk,     // SPI Clock (Pin 76)
    output wire lcd_data,    // SPI MOSI Data (Pin 77)
    output wire lcd_cs,      // Active-low Chip Select (Pin 48)
    output wire lcd_rs,      // Data / Command select (Pin 49)
    output wire lcd_resetn   // Panel Hardware Reset (Pin 47)
);

    // Active-high reset for hotstate IP core
    wire rst = ~resetn;
    // Active-high "pressed" for the seed-toggle button, same inversion
    // treatment as rst above -- gol.c's `mode_btn` input reads 1 when
    // physically pressed.
    wire mode_btn = ~mode_btn_n;

    // Instantiate hotstate-generated microcode engine (module name "gol"
    // because gol.c is passed first on the hotc command line). Only the LCD
    // SPI signals and mode_btn are wired to top-level pins; the many
    // internal state outputs (r, c, base, self, sum, nb, neigh, flip, ...)
    // are left unconnected here — they exist for simulation/debug
    // visibility only.
    gol inst_gol (
        .clk(clk),
        .rst(rst),
        .mode_btn(mode_btn),
        .sclk(lcd_clk),
        .mosi(lcd_data),
        .cs_n(lcd_cs),
        .dc(lcd_rs),
        .lcd_resetn(lcd_resetn)
    );

endmodule
