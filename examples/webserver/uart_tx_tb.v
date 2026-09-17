// Auto-generated testbench for uart_tx
`timescale 1ns / 1ps

module uart_tx_tb (
    output reg clk,
    output reg rst,
    output reg hlt,
    // Output signals as ports (for C++ harness visibility)
    output wire tx_bit,
    output wire tx_busy,
    output wire [6:0] debug_adr,
    output wire [1:0] states_out,
    output wire ready,
    output wire lhs_out,
    output wire jmp_flag_out,
    output wire [6:0] jmp_bus_out,
    output wire br_out,
    output wire fj_out,
    output wire [6:0] next_pc,
    output wire state_capture
);

    initial begin
        clk = 0;
        rst = 1;
        hlt = 0;
        #40 rst = 0;
    end

    always #10 clk = ~clk;

    reg tx_start;
    reg [7:0] tx_data;

// Device Under Test
uart_tx dut (
    .clk(clk),
    .rst(rst),
    .tx_start(tx_start),
    .tx_data(tx_data),
    .tx_bit(tx_bit),
    .tx_busy(tx_busy),
    .debug_adr(debug_adr),
    .states_out(states_out),
    .ready(ready),
    .lhs_out(lhs_out),
    .jmp_flag_out(jmp_flag_out),
    .jmp_bus_out(jmp_bus_out),
    .br_out(br_out),
    .fj_out(fj_out),
    .next_pc(next_pc),
    .state_capture(state_capture)
);

// Include user stimulus
`include "user_tb.v"

endmodule
