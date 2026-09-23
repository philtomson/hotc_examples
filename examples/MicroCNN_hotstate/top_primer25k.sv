`timescale 1ns/1ps

// Tang Primer 25K (GW5A-25A) board wrapper around `top` (top_hotstate.sv).
// Build with -D NO_RPLL -D SYS_CLK_HZ=50_000_000: this family has no rPLL, so
// the design runs straight off the dock's 50 MHz oscillator. The dock's user
// button S1 is active-low with a pull-up, while `top`'s rst is active-high.
//
// The dock has no user LEDs on general FPGA IO, so class_result's three LED
// bits go to spare header pins (see primer25k.cst); the real output is the
// class byte on UART TX, which uart_medmnist_loader.py reads.
module top_primer25k (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       uart_rxd,
    output logic       uart_txd,
    output logic [2:0] led
);
    logic [5:0] led_all;

    top u_top (
        .clk(clk),
        .rst(~rst_n),
        .led(led_all),
        .rx_in(uart_rxd),
        .tx_out(uart_txd)
    );

    assign led = led_all[2:0];
endmodule
