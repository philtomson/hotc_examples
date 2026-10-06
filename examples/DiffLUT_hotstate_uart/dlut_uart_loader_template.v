// Auto-generated Verilog module for dlut_uart_loader
// Generated from CFG with hotstate microcode

`timescale 1ns / 1ps

module dlut_uart_loader (
    input wire clk,
    input wire rst,
    input wire rx_done,
    input wire [7:0] rx_byte,
    input wire tx_busy,
    input wire [3:0] digit,
    output wire busy,
    output wire [9:0] img_waddr,
    output wire [7:0] img_wdata,
    output wire img_wen,
    output wire tx_start,
    output wire [7:0] tx_data,
    output wire [5:0] debug_adr,
    output wire [28:0] states_out,
    output wire ready,
    output wire lhs_out,
    output wire jmp_flag_out,
    output wire [5:0] jmp_bus_out,
    output wire br_out,
    output wire fj_out,
    output wire [5:0] next_pc,
    output wire state_capture
);

wire [9:0] byte_idx;
wire [9:0] w;

wire [63:0] hotstate_count_out;

wire [5:0] variables_bus;
wire [28:0] states_bus;

assign busy = states_bus[0];
assign img_waddr = states_bus[10:1];
assign img_wdata = states_bus[18:11];
assign img_wen = states_bus[19];
assign tx_start = states_bus[20];
assign tx_data = states_bus[28:21];
assign states_out = states_bus;

assign variables_bus = {digit, tx_busy, rx_done};

wire [31:0] timer_ex_data_bus;
assign timer_ex_data_bus = 32'b0;

// _BitInt combinatorial expression circuits
wire [9:0] expr_1_raw = ((783) - byte_idx);
wire [28:0] expr_1_vec = {{18{1'b0}}, expr_1_raw, {1{1'b0}}};
wire [7:0] expr_2_raw = rx_byte;
wire [28:0] expr_2_vec = {{10{1'b0}}, expr_2_raw, {11{1'b0}}};
wire [7:0] expr_3_raw = {{4{digit[3]}}, digit};
wire [28:0] expr_3_vec = {expr_3_raw, {21{1'b0}}};
wire [86:0] expr_results_flat = {expr_3_vec, expr_2_vec, expr_1_vec};

hotstate #(
    .NUM_STATES(29),
    .NUM_VARS(6),
    .NUM_VARS_ADDR_BITS(6),
    .NUM_ADR_BITS(6),
    .NUM_WORDS(37),
    .NUM_VARSEL_BITS(4),
    .NUM_TIMERS(2),
    .NUM_SWITCHES(0),
    .TIM_MEM_WORDS(3),
    .TIM_EX_WORDS(1),
    .SWITCH_MEM_WORDS(1),
    .SWITCH_OFFSET_BITS(8),
    .NUM_SWITCH_BITS(0),
    .MCFILENAME("./dlut_uart_loader_smdata.mem"),
    .VRFILENAME("./dlut_uart_loader_vardata.mem"),
    .TIFILENAME("./dlut_uart_loader_timdata.mem"),
    .SWFILENAME("./dlut_uart_loader_switchdata.mem"),
    .STACK_DEPTH(4),
    .STANDALONE(1),
    .DUAL_BANK(0),
    .COMPILER_MODE(0),
    .NUM_COMPARATORS(0),
    .CMP_VARSEL_BASE(0),
    .EXPR_SEL_BITS(2),
    .NUM_EXPRS(3),
    .DATA_STACK_WIDTH(0),
    .RESET_VALUES(29'h00000000)
) hotstate_inst (
    .clk(clk),
    .rst(rst),
    .hlt(1'b0),
    .comparators(1'b0),
    .interrupt(1'b0),
    .interrupt_address(6'b0),
    .variables(variables_bus),
    .states(states_bus),
    .debug_adr(debug_adr),
    .ready(ready),
    .vd_tvalid(1'b0),
    .vd_tdata({16{1'b0}}),
    .vd_load_init(1'b0),
    .sm_tvalid(1'b0),
    .sm_tdata({82{1'b0}}),
    .load_init(1'b0),
    .switch_tdata(6'b0),
    .switch_tvalid(1'b0),
    .switch_trigger(1'b1),
    .tim_tvalid(1'b0),
    .tim_tdata(32'b0),
    .timer_ex_data(timer_ex_data_bus),
    .switch_offset(8'b0),
    .switch_sel(),
    .mcode_tvalid(),
    .mcode_tdata(),
    .stream_valid(),
    .stream_ready(),
    .expr_results_flat(expr_results_flat),
    .count_out(hotstate_count_out)
);

assign byte_idx = hotstate_count_out[9:0];

assign lhs_out = hotstate_inst.lhs;
assign jmp_flag_out = hotstate_inst.jmp_enb;
assign jmp_bus_out = hotstate_inst.jmp_adr;
assign br_out = hotstate_inst.branch;
assign fj_out = hotstate_inst.forced_jmp;
assign next_pc = debug_adr;
assign state_capture = hotstate_inst.state_capture;

endmodule
