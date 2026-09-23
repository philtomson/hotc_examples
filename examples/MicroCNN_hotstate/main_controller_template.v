// Auto-generated Verilog module for main_controller
// Generated from CFG with hotstate microcode

`timescale 1ns / 1ps

module main_controller (
    input wire clk,
    input wire rst,
    input wire conv1_layer_done,
    input wire conv2_layer_done,
    input wire fc1_layer_done,
    input wire fc2_layer_done,
    input wire conv1_start,
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

wire [5:0] variables_bus;
wire [138:0] states_bus;

assign layer_phase = states_bus[4:0];
assign c1_pixel_cnt = states_bus[14:5];
assign c1_filter_cnt = states_bus[17:15];
assign c1_flush_cnt = states_bus[22:18];
assign c2_pixel_cnt = states_bus[30:23];
assign c2_filter_cnt = states_bus[34:31];
assign c2_lb_row = states_bus[39:35];
assign c2_lb_col = states_bus[44:40];
assign fc1_chunk_cnt = states_bus[50:45];
assign fc1_neuron_cnt = states_bus[55:51];
assign fc1_drain_cnt = states_bus[59:56];
assign fc2_chunk_cnt = states_bus[61:60];
assign fc2_neuron_cnt = states_bus[64:62];
assign fc2_flush_cnt = states_bus[68:65];
assign conv1_start_latched = states_bus[69];
assign img_en = states_bus[70];
assign weight_en = states_bus[71];
assign bias_en = states_bus[72];
assign shift_en = states_bus[73];
assign compute_en = states_bus[74];
assign accumulate = states_bus[75];
assign chunk_sel = states_bus[76];
assign mult_ce = states_bus[77];
assign mult_clear = states_bus[78];
assign param_en = states_bus[79];
assign fc1_valid_out = states_bus[80];
assign fc2_valid_out = states_bus[81];
assign img_addr = states_bus[91:82];
assign filter_idx = states_bus[95:92];
assign ram_raddr = states_bus[103:96];
assign fc1_ram_raddr = states_bus[109:104];
assign fc1_weight_raddr = states_bus[120:110];
assign fc1_bias_raddr = states_bus[125:121];
assign fc2_ram_raddr = states_bus[127:126];
assign fc2_weight_raddr = states_bus[132:128];
assign fc2_bias_raddr = states_bus[135:133];
assign layer_state = states_bus[136];
assign npu_sleep = states_bus[137];
assign npu_done = states_bus[138];
assign states_out = states_bus;
wire [4:0] layer_phase_fb;
assign layer_phase_fb = states_bus[4:0];
wire [9:0] c1_pixel_cnt_fb;
assign c1_pixel_cnt_fb = states_bus[14:5];
wire [2:0] c1_filter_cnt_fb;
assign c1_filter_cnt_fb = states_bus[17:15];
wire [4:0] c1_flush_cnt_fb;
assign c1_flush_cnt_fb = states_bus[22:18];
wire [7:0] c2_pixel_cnt_fb;
assign c2_pixel_cnt_fb = states_bus[30:23];
wire [3:0] c2_filter_cnt_fb;
assign c2_filter_cnt_fb = states_bus[34:31];
wire [4:0] c2_lb_row_fb;
assign c2_lb_row_fb = states_bus[39:35];
wire [4:0] c2_lb_col_fb;
assign c2_lb_col_fb = states_bus[44:40];
wire [5:0] fc1_chunk_cnt_fb;
assign fc1_chunk_cnt_fb = states_bus[50:45];
wire [4:0] fc1_neuron_cnt_fb;
assign fc1_neuron_cnt_fb = states_bus[55:51];
wire [3:0] fc1_drain_cnt_fb;
assign fc1_drain_cnt_fb = states_bus[59:56];
wire [1:0] fc2_chunk_cnt_fb;
assign fc2_chunk_cnt_fb = states_bus[61:60];
wire [2:0] fc2_neuron_cnt_fb;
assign fc2_neuron_cnt_fb = states_bus[64:62];
wire [3:0] fc2_flush_cnt_fb;
assign fc2_flush_cnt_fb = states_bus[68:65];
wire conv1_start_latched_fb;
assign conv1_start_latched_fb = states_bus[69];

wire __cmp_0 = (c1_pixel_cnt_fb == 783);
wire __cmp_1 = (c1_flush_cnt_fb == 15);
wire __cmp_2 = (c1_filter_cnt_fb == 7);
wire __cmp_3 = (c2_lb_row_fb >= 2);
wire __cmp_4 = (c2_lb_col_fb >= 2);
wire __cmp_5 = (__cmp_3 && __cmp_4);
wire __cmp_6 = (c2_lb_col_fb == 12);
wire __cmp_7 = (c2_pixel_cnt_fb == 169);
wire __cmp_8 = (c2_filter_cnt_fb == 15);
wire __cmp_9 = (fc1_chunk_cnt_fb == 49);
wire __cmp_10 = (fc1_drain_cnt_fb == 0);
wire __cmp_11 = (fc1_drain_cnt_fb == 1);
wire __cmp_12 = (fc1_drain_cnt_fb == 2);
wire __cmp_13 = (fc1_drain_cnt_fb == 15);
wire __cmp_14 = (fc1_neuron_cnt_fb == 31);
wire __cmp_15 = (fc2_chunk_cnt_fb == 3);
wire __cmp_16 = (fc2_flush_cnt_fb == 0);
wire __cmp_17 = (fc2_flush_cnt_fb == 1);
wire __cmp_18 = (fc2_flush_cnt_fb == 2);
wire __cmp_19 = (fc2_flush_cnt_fb == 15);
wire __cmp_20 = (fc2_neuron_cnt_fb == 7);

assign variables_bus = {conv1_start_latched_fb, layer_phase_fb};

wire [0:0] switch_sel_wire;
wire [10:0] switch_offset_mult;
assign switch_offset_mult = 
    (switch_sel_wire == 0) ? layer_phase : 
    11'b0;

wire [159:0] timer_ex_data_bus;
assign timer_ex_data_bus[31:0] = {{(32-1){1'b0}}, conv1_layer_done};
assign timer_ex_data_bus[63:32] = {{(32-1){1'b0}}, conv2_layer_done};
assign timer_ex_data_bus[95:64] = {{(32-1){1'b0}}, fc1_layer_done};
assign timer_ex_data_bus[127:96] = {{(32-1){1'b0}}, fc2_layer_done};
assign timer_ex_data_bus[159:128] = {{(32-1){1'b0}}, conv1_start};

// _BitInt combinatorial expression circuits
wire [0:0] expr_1_raw = conv1_start;
wire [138:0] expr_1_vec = {{69{1'b0}}, expr_1_raw, {69{1'b0}}};
wire [3:0] expr_2_raw = states_bus[17:15];
wire [138:0] expr_2_vec = {{43{1'b0}}, expr_2_raw, {92{1'b0}}};
wire [9:0] expr_3_raw = states_bus[14:5];
wire [138:0] expr_3_vec = {{47{1'b0}}, expr_3_raw, {82{1'b0}}};
wire [9:0] expr_4_raw = (states_bus[14:5]) + (10'd1);
wire [138:0] expr_4_vec = {{124{1'b0}}, expr_4_raw, {5{1'b0}}};
wire [4:0] expr_5_raw = (states_bus[22:18]) + (5'd1);
wire [138:0] expr_5_vec = {{116{1'b0}}, expr_5_raw, {18{1'b0}}};
wire [2:0] expr_6_raw = (states_bus[17:15]) + (3'd1);
wire [138:0] expr_6_vec = {{121{1'b0}}, expr_6_raw, {15{1'b0}}};
wire [3:0] expr_7_raw = states_bus[34:31];
wire [138:0] expr_7_vec = {{43{1'b0}}, expr_7_raw, {92{1'b0}}};
wire [7:0] expr_8_raw = states_bus[30:23];
wire [138:0] expr_8_vec = {{35{1'b0}}, expr_8_raw, {96{1'b0}}};
wire [4:0] expr_9_raw = (states_bus[39:35]) + (5'd1);
wire [138:0] expr_9_vec = {{99{1'b0}}, expr_9_raw, {35{1'b0}}};
wire [4:0] expr_10_raw = (states_bus[44:40]) + (5'd1);
wire [138:0] expr_10_vec = {{94{1'b0}}, expr_10_raw, {40{1'b0}}};
wire [7:0] expr_11_raw = (states_bus[30:23]) + (8'd1);
wire [138:0] expr_11_vec = {{108{1'b0}}, expr_11_raw, {23{1'b0}}};
wire [3:0] expr_12_raw = (states_bus[34:31]) + (4'd1);
wire [138:0] expr_12_vec = {{104{1'b0}}, expr_12_raw, {31{1'b0}}};
wire [5:0] expr_13_raw = states_bus[50:45];
wire [138:0] expr_13_vec = {{29{1'b0}}, expr_13_raw, {104{1'b0}}};
wire [10:0] expr_14_raw = ((states_bus[55:51]) * (11'd50)) + (states_bus[50:45]);
wire [138:0] expr_14_vec = {{18{1'b0}}, expr_14_raw, {110{1'b0}}};
wire [4:0] expr_15_raw = states_bus[55:51];
wire [138:0] expr_15_vec = {{13{1'b0}}, expr_15_raw, {121{1'b0}}};
wire [5:0] expr_16_raw = (states_bus[50:45]) + (6'd1);
wire [138:0] expr_16_vec = {{88{1'b0}}, expr_16_raw, {45{1'b0}}};
wire [3:0] expr_17_raw = (states_bus[59:56]) + (4'd1);
wire [138:0] expr_17_vec = {{79{1'b0}}, expr_17_raw, {56{1'b0}}};
wire [4:0] expr_18_raw = (states_bus[55:51]) + (5'd1);
wire [138:0] expr_18_vec = {{83{1'b0}}, expr_18_raw, {51{1'b0}}};
wire [1:0] expr_19_raw = states_bus[61:60];
wire [138:0] expr_19_vec = {{11{1'b0}}, expr_19_raw, {126{1'b0}}};
wire [4:0] expr_20_raw = ((states_bus[64:62]) << (2)) + (states_bus[61:60]);
wire [138:0] expr_20_vec = {{6{1'b0}}, expr_20_raw, {128{1'b0}}};
wire [2:0] expr_21_raw = states_bus[64:62];
wire [138:0] expr_21_vec = {{3{1'b0}}, expr_21_raw, {133{1'b0}}};
wire [1:0] expr_22_raw = (states_bus[61:60]) + (2'd1);
wire [138:0] expr_22_vec = {{77{1'b0}}, expr_22_raw, {60{1'b0}}};
wire [3:0] expr_23_raw = (states_bus[68:65]) + (4'd1);
wire [138:0] expr_23_vec = {{70{1'b0}}, expr_23_raw, {65{1'b0}}};
wire [2:0] expr_24_raw = (states_bus[64:62]) + (3'd1);
wire [138:0] expr_24_vec = {{74{1'b0}}, expr_24_raw, {62{1'b0}}};
wire [3335:0] expr_results_flat = {expr_24_vec, expr_23_vec, expr_22_vec, expr_21_vec, expr_20_vec, expr_19_vec, expr_18_vec, expr_17_vec, expr_16_vec, expr_15_vec, expr_14_vec, expr_13_vec, expr_12_vec, expr_11_vec, expr_10_vec, expr_9_vec, expr_8_vec, expr_7_vec, expr_6_vec, expr_5_vec, expr_4_vec, expr_3_vec, expr_2_vec, expr_1_vec};

hotstate #(
    .NUM_STATES(139),
    .NUM_VARS(6),
    .NUM_VARS_ADDR_BITS(6),
    .NUM_ADR_BITS(8),
    .NUM_WORDS(238),
    .NUM_VARSEL_BITS(5),
    .NUM_TIMERS(0),
    .NUM_SWITCHES(1),
    .TIM_MEM_WORDS(1),
    .TIM_EX_WORDS(5),
    .SWITCH_MEM_WORDS(32),
    .SWITCH_OFFSET_BITS(5),
    .NUM_SWITCH_BITS(0),
    .MCFILENAME("./main_controller_smdata.mem"),
    .VRFILENAME("./main_controller_vardata.mem"),
    .TIFILENAME("./main_controller_timdata.mem"),
    .SWFILENAME("./main_controller_switchdata.mem"),
    .STACK_DEPTH(4),
    .STANDALONE(1),
    .DUAL_BANK(0),
    .COMPILER_MODE(0),
    .NUM_COMPARATORS(21),
    .CMP_VARSEL_BASE(3),
    .EXPR_SEL_BITS(5),
    .NUM_EXPRS(24),
    .DATA_STACK_WIDTH(0),
    .RESET_VALUES(139'h20000000000000000000000000000000000),
    .ONE_SHOT_MASK(139'h0000000000000032c000000000000000000)
) hotstate_inst (
    .clk(clk),
    .rst(rst),
    .hlt(1'b0),
    .comparators({__cmp_20, __cmp_19, __cmp_18, __cmp_17, __cmp_16, __cmp_15, __cmp_14, __cmp_13, __cmp_12, __cmp_11, __cmp_10, __cmp_9, __cmp_8, __cmp_7, __cmp_6, __cmp_5, __cmp_4, __cmp_3, __cmp_2, __cmp_1, __cmp_0}),
    .interrupt(1'b0),
    .interrupt_address(8'b0),
    .variables(variables_bus),
    .states(states_bus),
    .debug_adr(debug_adr),
    .ready(ready),
    .vd_tvalid(1'b0),
    .vd_tdata({32{1'b0}}),
    .vd_load_init(1'b0),
    .sm_tvalid(1'b0),
    .sm_tdata({304{1'b0}}),
    .load_init(1'b0),
    .switch_tdata(8'b0),
    .switch_tvalid(1'b0),
    .switch_trigger(1'b1),
    .tim_tvalid(1'b0),
    .tim_tdata(32'b0),
    .timer_ex_data(timer_ex_data_bus),
    .switch_offset(switch_offset_mult[4:0]),
    .switch_sel(switch_sel_wire),
    .mcode_tvalid(),
    .mcode_tdata(),
    .stream_valid(),
    .stream_ready(),
    .expr_results_flat(expr_results_flat),
    .count_out()
);

assign lhs_out = hotstate_inst.lhs;
assign jmp_flag_out = hotstate_inst.jmp_enb;
assign jmp_bus_out = hotstate_inst.jmp_adr;
assign br_out = hotstate_inst.branch;
assign fj_out = hotstate_inst.forced_jmp;
assign next_pc = debug_adr;
assign state_capture = hotstate_inst.state_capture;

endmodule
