// Auto-generated testbench for main_controller
`timescale 1ns / 1ps

module main_controller_tb (
    output reg clk,
    output reg rst,
    output reg hlt,
    // Output signals as ports (for C++ harness visibility)
    output wire [4:0] layer_phase,
    output wire [9:0] c1_pixel_cnt,
    output wire [2:0] c1_filter_cnt,
    output wire [4:0] c1_flush_cnt,
    output wire [7:0] c2_pixel_cnt,
    output wire [3:0] c2_filter_cnt,
    output wire [4:0] c2_lb_row,
    output wire [4:0] c2_lb_col,
    output wire [5:0] fc1_chunk_cnt,
    output wire [4:0] fc1_neuron_cnt,
    output wire [3:0] fc1_drain_cnt,
    output wire [1:0] fc2_chunk_cnt,
    output wire [2:0] fc2_neuron_cnt,
    output wire [3:0] fc2_flush_cnt,
    output wire conv1_start_latched,
    output wire img_en,
    output wire weight_en,
    output wire bias_en,
    output wire shift_en,
    output wire compute_en,
    output wire accumulate,
    output wire chunk_sel,
    output wire mult_ce,
    output wire mult_clear,
    output wire param_en,
    output wire fc1_valid_out,
    output wire fc2_valid_out,
    output wire [9:0] img_addr,
    output wire [3:0] filter_idx,
    output wire [7:0] ram_raddr,
    output wire [5:0] fc1_ram_raddr,
    output wire [10:0] fc1_weight_raddr,
    output wire [4:0] fc1_bias_raddr,
    output wire [1:0] fc2_ram_raddr,
    output wire [4:0] fc2_weight_raddr,
    output wire [2:0] fc2_bias_raddr,
    output wire layer_state,
    output wire npu_sleep,
    output wire npu_done,
    output wire [7:0] debug_adr,
    output wire [138:0] states_out,
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

    reg conv1_layer_done;
    reg conv2_layer_done;
    reg fc1_layer_done;
    reg fc2_layer_done;
    reg conv1_start;

// Device Under Test
main_controller dut (
    .clk(clk),
    .rst(rst),
    .conv1_layer_done(conv1_layer_done),
    .conv2_layer_done(conv2_layer_done),
    .fc1_layer_done(fc1_layer_done),
    .fc2_layer_done(fc2_layer_done),
    .conv1_start(conv1_start),
    .layer_phase(layer_phase),
    .c1_pixel_cnt(c1_pixel_cnt),
    .c1_filter_cnt(c1_filter_cnt),
    .c1_flush_cnt(c1_flush_cnt),
    .c2_pixel_cnt(c2_pixel_cnt),
    .c2_filter_cnt(c2_filter_cnt),
    .c2_lb_row(c2_lb_row),
    .c2_lb_col(c2_lb_col),
    .fc1_chunk_cnt(fc1_chunk_cnt),
    .fc1_neuron_cnt(fc1_neuron_cnt),
    .fc1_drain_cnt(fc1_drain_cnt),
    .fc2_chunk_cnt(fc2_chunk_cnt),
    .fc2_neuron_cnt(fc2_neuron_cnt),
    .fc2_flush_cnt(fc2_flush_cnt),
    .conv1_start_latched(conv1_start_latched),
    .img_en(img_en),
    .weight_en(weight_en),
    .bias_en(bias_en),
    .shift_en(shift_en),
    .compute_en(compute_en),
    .accumulate(accumulate),
    .chunk_sel(chunk_sel),
    .mult_ce(mult_ce),
    .mult_clear(mult_clear),
    .param_en(param_en),
    .fc1_valid_out(fc1_valid_out),
    .fc2_valid_out(fc2_valid_out),
    .img_addr(img_addr),
    .filter_idx(filter_idx),
    .ram_raddr(ram_raddr),
    .fc1_ram_raddr(fc1_ram_raddr),
    .fc1_weight_raddr(fc1_weight_raddr),
    .fc1_bias_raddr(fc1_bias_raddr),
    .fc2_ram_raddr(fc2_ram_raddr),
    .fc2_weight_raddr(fc2_weight_raddr),
    .fc2_bias_raddr(fc2_bias_raddr),
    .layer_state(layer_state),
    .npu_sleep(npu_sleep),
    .npu_done(npu_done),
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
