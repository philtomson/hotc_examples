// Auto-generated Verilog module for tm_seq_controller
// Generated from CFG with hotstate microcode

`timescale 1ns / 1ps

module tm_seq_controller (
    input wire clk,
    input wire rst,
    input wire fire,
    input wire is_pos,
    input wire clause_done,
    input wire [6:0] clause_strength,
    input wire [10:0] v_out_0,
    input wire [10:0] v_out_1,
    input wire [10:0] v_out_2,
    input wire [10:0] v_out_3,
    input wire [10:0] v_out_4,
    input wire [10:0] v_out_5,
    input wire [10:0] v_out_6,
    input wire [10:0] v_out_7,
    input wire [10:0] v_out_8,
    input wire [10:0] v_out_9,
    input wire go,
    input wire [3:0] class_idx,
    output wire start_clause,
    output wire vote_rst,
    output wire v0_up,
    output wire v0_dn,
    output wire v1_up,
    output wire v1_dn,
    output wire v2_up,
    output wire v2_dn,
    output wire v3_up,
    output wire v3_dn,
    output wire v4_up,
    output wire v4_dn,
    output wire v5_up,
    output wire v5_dn,
    output wire v6_up,
    output wire v6_dn,
    output wire v7_up,
    output wire v7_dn,
    output wire v8_up,
    output wire v8_dn,
    output wire v9_up,
    output wire v9_dn,
    output wire done,
    output wire [10:0] current_max,
    output wire [3:0] winner_out,
    output wire [6:0] debug_adr,
    output wire [37:0] states_out,
    output wire ready,
    output wire lhs_out,
    output wire jmp_flag_out,
    output wire [6:0] jmp_bus_out,
    output wire br_out,
    output wire fj_out,
    output wire [6:0] next_pc,
    output wire state_capture
);

wire [7:0] clause_cnt;

wire [2:0] variables_bus;
wire [37:0] states_bus;

assign start_clause = states_bus[0];
assign vote_rst = states_bus[1];
assign v0_up = states_bus[2];
assign v0_dn = states_bus[3];
assign v1_up = states_bus[4];
assign v1_dn = states_bus[5];
assign v2_up = states_bus[6];
assign v2_dn = states_bus[7];
assign v3_up = states_bus[8];
assign v3_dn = states_bus[9];
assign v4_up = states_bus[10];
assign v4_dn = states_bus[11];
assign v5_up = states_bus[12];
assign v5_dn = states_bus[13];
assign v6_up = states_bus[14];
assign v6_dn = states_bus[15];
assign v7_up = states_bus[16];
assign v7_dn = states_bus[17];
assign v8_up = states_bus[18];
assign v8_dn = states_bus[19];
assign v9_up = states_bus[20];
assign v9_dn = states_bus[21];
assign done = states_bus[22];
assign current_max = states_bus[33:23];
assign winner_out = states_bus[37:34];
assign states_out = states_bus;
wire [10:0] current_max_fb;
assign current_max_fb = states_bus[33:23];

wire __cmp_0 = ($signed(clause_strength) >= 5);
wire __cmp_1 = ($signed(v_out_1) > $signed(current_max_fb));
wire __cmp_2 = ($signed(v_out_2) > $signed(current_max_fb));
wire __cmp_3 = ($signed(v_out_3) > $signed(current_max_fb));
wire __cmp_4 = ($signed(v_out_4) > $signed(current_max_fb));
wire __cmp_5 = ($signed(v_out_5) > $signed(current_max_fb));
wire __cmp_6 = ($signed(v_out_6) > $signed(current_max_fb));
wire __cmp_7 = ($signed(v_out_7) > $signed(current_max_fb));
wire __cmp_8 = ($signed(v_out_8) > $signed(current_max_fb));
wire __cmp_9 = ($signed(v_out_9) > $signed(current_max_fb));

assign variables_bus = {go, clause_done, is_pos};

wire [0:0] switch_sel_wire;
wire [10:0] switch_offset_mult;
assign switch_offset_mult = 
    (switch_sel_wire == 0) ? class_idx : 
    (switch_sel_wire == 1) ? class_idx : 
    11'b0;

wire [31:0] timer_ex_data_bus;
assign timer_ex_data_bus[31:0] = {{(32-4){1'b0}}, class_idx};

// _BitInt combinatorial expression circuits
wire [10:0] expr_1_raw = v_out_0;
wire [37:0] expr_1_vec = {{4{1'b0}}, expr_1_raw, {23{1'b0}}};
wire [10:0] expr_2_raw = v_out_1;
wire [37:0] expr_2_vec = {{4{1'b0}}, expr_2_raw, {23{1'b0}}};
wire [10:0] expr_3_raw = v_out_2;
wire [37:0] expr_3_vec = {{4{1'b0}}, expr_3_raw, {23{1'b0}}};
wire [10:0] expr_4_raw = v_out_3;
wire [37:0] expr_4_vec = {{4{1'b0}}, expr_4_raw, {23{1'b0}}};
wire [10:0] expr_5_raw = v_out_4;
wire [37:0] expr_5_vec = {{4{1'b0}}, expr_5_raw, {23{1'b0}}};
wire [10:0] expr_6_raw = v_out_5;
wire [37:0] expr_6_vec = {{4{1'b0}}, expr_6_raw, {23{1'b0}}};
wire [10:0] expr_7_raw = v_out_6;
wire [37:0] expr_7_vec = {{4{1'b0}}, expr_7_raw, {23{1'b0}}};
wire [10:0] expr_8_raw = v_out_7;
wire [37:0] expr_8_vec = {{4{1'b0}}, expr_8_raw, {23{1'b0}}};
wire [10:0] expr_9_raw = v_out_8;
wire [37:0] expr_9_vec = {{4{1'b0}}, expr_9_raw, {23{1'b0}}};
wire [10:0] expr_10_raw = v_out_9;
wire [37:0] expr_10_vec = {{4{1'b0}}, expr_10_raw, {23{1'b0}}};
wire [379:0] expr_results_flat = {expr_10_vec, expr_9_vec, expr_8_vec, expr_7_vec, expr_6_vec, expr_5_vec, expr_4_vec, expr_3_vec, expr_2_vec, expr_1_vec};

hotstate #(
    .NUM_STATES(38),
    .NUM_VARS(3),
    .NUM_VARS_ADDR_BITS(3),
    .NUM_ADR_BITS(7),
    .NUM_WORDS(93),
    .NUM_VARSEL_BITS(5),
    .NUM_TIMERS(1),
    .NUM_SWITCHES(2),
    .TIM_MEM_WORDS(2),
    .TIM_EX_WORDS(1),
    .SWITCH_MEM_WORDS(32),
    .SWITCH_OFFSET_BITS(4),
    .NUM_SWITCH_BITS(1),
    .MCFILENAME("./tm_seq_controller_smdata.mem"),
    .VRFILENAME("./tm_seq_controller_vardata.mem"),
    .TIFILENAME("./tm_seq_controller_timdata.mem"),
    .SWFILENAME("./tm_seq_controller_switchdata.mem"),
    .STACK_DEPTH(4),
    .STANDALONE(1),
    .DUAL_BANK(0),
    .COMPILER_MODE(0),
    .NUM_COMPARATORS(10),
    .CMP_VARSEL_BASE(16),
    .EXPR_SEL_BITS(4),
    .NUM_EXPRS(10),
    .DATA_STACK_WIDTH(0),
    .RESET_VALUES(38'h0000000000)
) hotstate_inst (
    .clk(clk),
    .rst(rst),
    .hlt(1'b0),
    .comparators({__cmp_9, __cmp_8, __cmp_7, __cmp_6, __cmp_5, __cmp_4, __cmp_3, __cmp_2, __cmp_1, __cmp_0}),
    .interrupt(1'b0),
    .interrupt_address(7'b0),
    .variables(variables_bus),
    .states(states_bus),
    .debug_adr(debug_adr),
    .ready(ready),
    .vd_tvalid(1'b0),
    .vd_tdata({32{1'b0}}),
    .vd_load_init(1'b0),
    .sm_tvalid(1'b0),
    .sm_tdata({103{1'b0}}),
    .load_init(1'b0),
    .switch_tdata(7'b0),
    .switch_tvalid(1'b0),
    .switch_trigger(1'b1),
    .tim_tvalid(1'b0),
    .tim_tdata(32'b0),
    .timer_ex_data(timer_ex_data_bus),
    .switch_offset(switch_offset_mult[3:0]),
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
