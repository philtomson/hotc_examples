// Auto-generated testbench for kan_control
`timescale 1ns / 1ps

module kan_control_tb (
    output reg clk,
    output reg rst,
    output reg hlt,
    // Output signals as ports (for C++ harness visibility)
    output wire sdram_wr_req,
    output wire sdram_rd_req,
    output wire [22:0] sdram_addr,
    output wire [7:0] sdram_wr_data,
    output wire tx_start,
    output wire [7:0] tx_data,
    output wire [22:0] byte_idx,
    output wire [8:0] p,
    output wire [7:0] q,
    output wire [23:0] acc,
    output wire [22:0] rd_addr,
    output wire [7:0] byte_lo,
    output wire [7:0] byte_hi,
    output wire [15:0] combined,
    output wire [13:0] weight14,
    output wire [12:0] weight13,
    output wire [23:0] shifted,
    output wire [8:0] val,
    output wire [4:0] best_class,
    output wire [8:0] max_score,
    output wire in_mem__wr_en,
    output wire layer1_out__wr_en,
    output wire [7:0] __arrtmp0,
    output wire [7:0] __arrtmp1,
    output wire [7:0] debug_adr,
    output wire [252:0] states_out,
    output wire ready,
    output wire lhs_out,
    output wire jmp_flag_out,
    output wire [7:0] jmp_bus_out,
    output wire br_out,
    output wire fj_out,
    output wire [7:0] next_pc,
    output wire state_capture
);

    initial begin
        clk = 0;
        rst = 1;
        hlt = 0;
        #40 rst = 0;
    end

    always #10 clk = ~clk;

    reg sdram_busy;
    reg [7:0] sdram_rd_byte;
    reg rx_done;
    reg [7:0] rx_byte;
    reg tx_busy;

// Device Under Test
kan_control dut (
    .clk(clk),
    .rst(rst),
    .sdram_busy(sdram_busy),
    .sdram_rd_byte(sdram_rd_byte),
    .rx_done(rx_done),
    .rx_byte(rx_byte),
    .tx_busy(tx_busy),
    .sdram_wr_req(sdram_wr_req),
    .sdram_rd_req(sdram_rd_req),
    .sdram_addr(sdram_addr),
    .sdram_wr_data(sdram_wr_data),
    .tx_start(tx_start),
    .tx_data(tx_data),
    .byte_idx(byte_idx),
    .p(p),
    .q(q),
    .acc(acc),
    .rd_addr(rd_addr),
    .byte_lo(byte_lo),
    .byte_hi(byte_hi),
    .combined(combined),
    .weight14(weight14),
    .weight13(weight13),
    .shifted(shifted),
    .val(val),
    .best_class(best_class),
    .max_score(max_score),
    .in_mem__wr_en(in_mem__wr_en),
    .layer1_out__wr_en(layer1_out__wr_en),
    .__arrtmp0(__arrtmp0),
    .__arrtmp1(__arrtmp1),
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
