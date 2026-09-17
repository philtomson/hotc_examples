// Auto-generated testbench for http_server
`timescale 1ns / 1ps

module http_server_tb (
    output reg clk,
    output reg rst,
    output reg hlt,
    // Output signals as ports (for C++ harness visibility)
    output wire tx_start,
    output wire led0,
    output wire led1,
    output wire [7:0] active_route,
    output wire [5:0] debug_adr,
    output wire [10:0] states_out,
    output wire ready,
    output wire lhs_out,
    output wire jmp_flag_out,
    output wire [5:0] jmp_bus_out,
    output wire br_out,
    output wire fj_out,
    output wire [5:0] next_pc,
    output wire state_capture
);

    initial begin
        clk = 0;
        rst = 1;
        hlt = 0;
        #40 rst = 0;
    end

    always #10 clk = ~clk;

    reg rx_done;
    reg [7:0] rx_byte;
    reg tx_busy;

// Device Under Test
http_server dut (
    .clk(clk),
    .rst(rst),
    .rx_done(rx_done),
    .rx_byte(rx_byte),
    .tx_busy(tx_busy),
    .tx_start(tx_start),
    .led0(led0),
    .led1(led1),
    .active_route(active_route),
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
