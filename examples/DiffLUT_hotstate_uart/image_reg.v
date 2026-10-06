// image_reg.v — 784×8 byte-wide register file holding the binarized MNIST
// image (one byte per pixel: bit k = threshold-bit k), flattened to the
// 6272-bit vector logic_net expects. Written one byte at a time by
// dlut_uart_loader as image bytes arrive over UART.
`timescale 1ns / 1ps

module image_reg #(
    parameter IMG_BYTES = 784
) (
    input  wire               clk,
    input  wire               wen,
    input  wire [9:0]         waddr,
    input  wire [7:0]         wdata,
    output wire [IMG_BYTES*8-1:0] q
);
    reg [7:0] mem [0:IMG_BYTES-1];

    always @(posedge clk) begin
        if (wen)
            mem[waddr] <= wdata;
    end

    genvar d;
    generate
        for (d = 0; d < IMG_BYTES; d = d + 1) begin: g_flat
            assign q[d*8 +: 8] = mem[d];
        end
    endgenerate
endmodule
