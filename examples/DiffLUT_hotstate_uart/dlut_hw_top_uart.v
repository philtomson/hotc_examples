// dlut_hw_top_uart.v — DiffLUT-Net MNIST classifier with a UART front-end,
// mirroring Tsetlin_hotstate_uart's structure: uart_rx + uart_tx hotstate
// machines (reused unchanged), the hotc-compiled dlut_uart_loader, the
// trained DiffLUT network (logic_net.v, K=4, 2000+1000 LUT4 neurons), and a
// combinational argmax.
//
// Protocol: host sends 784 binarized image bytes (one byte per pixel, bit k
// of byte p = threshold-bit k for pixel p); inference auto-starts after the
// 784th byte; host receives 1 result byte (predicted digit in the low nibble).
`timescale 1ns / 1ps

module dlut_hw_top_uart (
    input  wire clk,
    input  wire rst_n,         // active-low user reset button
    input  wire uart_rxd,
    output wire uart_txd,
    output wire done_led       // lit (active-low) while idle
);
    wire sys_rst = ~rst_n;

    // ── UART receiver (115200 baud) ──
    wire [7:0] rx_data;
    wire       rx_done;
    wire       rx_busy;
    uart_rx u_rx (
        .clk(clk), .rst(sys_rst),
        .rx_in(uart_rxd),
        .rx_data(rx_data), .rx_done(rx_done), .rx_busy(rx_busy)
    );

    // ── UART transmitter (115200 baud) ──
    wire       tx_start;
    wire [7:0] tx_data;
    wire       tx_busy;
    wire       busy;
    uart_tx u_tx (
        .clk(clk), .rst(sys_rst),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx_bit(uart_txd), .tx_busy(tx_busy)
    );

    // ── Image register (784 bytes, written by the loader) ──
    wire        img_wen;
    wire [9:0]  img_waddr;
    wire [7:0]  img_wdata;
    wire [6271:0] in_vec;
    image_reg #(.IMG_BYTES(784)) u_imgreg (
        .clk(clk), .wen(img_wen), .waddr(img_waddr), .wdata(img_wdata),
        .q(in_vec)
    );

    // ── Trained DiffLUT network (combinational between register stages) ──
    wire [69:0] class_sums;
    logic_net dut (
        .clk(clk), .inp(in_vec), .out(class_sums)
    );

    // ── Argmax over the 10 per-class sums ──
    wire [3:0] digit;
    argmax10 u_argmax (.sums(class_sums), .digit(digit));

    // ── Loader FSM (hotc): UART bytes in → image_reg writes → result out ──
    dlut_uart_loader u_loader (
        .clk(clk), .rst(sys_rst),
        .rx_done(rx_done), .rx_byte(rx_data),
        .tx_busy(tx_busy),
        .tx_start(tx_start), .tx_data(tx_data),
        .img_waddr(img_waddr), .img_wdata(img_wdata), .img_wen(img_wen),
        .digit(digit),
        .busy(busy)
    );

    assign done_led = ~busy;

endmodule
