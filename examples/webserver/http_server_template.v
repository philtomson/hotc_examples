// Auto-generated Verilog module for http_server
// Generated from CFG with hotstate microcode

`timescale 1ns / 1ps

module http_server (
    input wire clk,
    input wire rst,
    input wire rx_done,
    input wire [7:0] rx_byte,
    input wire tx_busy,
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

wire [7:0] crlf;

wire [1:0] variables_bus;
wire [10:0] states_bus;

assign tx_start = states_bus[0];
assign led0 = states_bus[1];
assign led1 = states_bus[2];
assign active_route = states_bus[10:3];
assign states_out = states_bus;

wire __cmp_0 = ($signed(rx_byte) != 71);
wire __cmp_1 = ($signed(rx_byte) != 69);
wire __cmp_2 = ($signed(rx_byte) != 84);
wire __cmp_3 = ($signed(rx_byte) != 32);
wire __cmp_4 = ($signed(rx_byte) != 47);
wire __cmp_5 = ($signed(rx_byte) == 115);
wire __cmp_6 = ($signed(rx_byte) == 48);
wire __cmp_7 = ($signed(rx_byte) == 49);
wire __cmp_8 = ($signed(rx_byte) == 32);
wire __cmp_9 = ($signed(rx_byte) == 13);
wire __cmp_10 = (__cmp_8 || __cmp_9);
wire __cmp_11 = ($signed(rx_byte) == 10);
wire __cmp_12 = (__cmp_10 || __cmp_11);
wire __cmp_13 = (__cmp_9 || __cmp_11);

assign variables_bus = {tx_busy, rx_done};

wire [31:0] timer_ex_data_bus;
assign timer_ex_data_bus = 32'b0;

hotstate #(
    .NUM_STATES(11),
    .NUM_VARS(2),
    .NUM_VARS_ADDR_BITS(2),
    .NUM_ADR_BITS(6),
    .NUM_WORDS(64),
    .NUM_VARSEL_BITS(5),
    .NUM_TIMERS(1),
    .NUM_SWITCHES(0),
    .TIM_MEM_WORDS(2),
    .TIM_EX_WORDS(1),
    .SWITCH_MEM_WORDS(1),
    .SWITCH_OFFSET_BITS(12),
    .NUM_SWITCH_BITS(0),
    .MCFILENAME("./http_server_smdata.mem"),
    .VRFILENAME("./http_server_vardata.mem"),
    .TIFILENAME("./http_server_timdata.mem"),
    .SWFILENAME("./http_server_switchdata.mem"),
    .STACK_DEPTH(4),
    .STANDALONE(1),
    .DUAL_BANK(0),
    .COMPILER_MODE(0),
    .NUM_COMPARATORS(14),
    .CMP_VARSEL_BASE(4),
    .EXPR_SEL_BITS(0),
    .NUM_EXPRS(0),
    .DATA_STACK_WIDTH(0),
    .RESET_VALUES(11'h000)
) hotstate_inst (
    .clk(clk),
    .rst(rst),
    .hlt(1'b0),
    .comparators({__cmp_13, __cmp_12, __cmp_11, __cmp_10, __cmp_9, __cmp_8, __cmp_7, __cmp_6, __cmp_5, __cmp_4, __cmp_3, __cmp_2, __cmp_1, __cmp_0}),
    .interrupt(1'b0),
    .interrupt_address(6'b0),
    .variables(variables_bus),
    .states(states_bus),
    .debug_adr(debug_adr),
    .ready(ready),
    .vd_tvalid(1'b0),
    .vd_tdata({32{1'b0}}),
    .vd_load_init(1'b0),
    .sm_tvalid(1'b0),
    .sm_tdata({43{1'b0}}),
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
    .expr_results_flat(1'b0),
    .count_out()
);


assign lhs_out = hotstate_inst.lhs;
assign jmp_flag_out = hotstate_inst.jmp_enb;
assign jmp_bus_out = hotstate_inst.jmp_adr;
assign br_out = hotstate_inst.branch;
assign fj_out = hotstate_inst.forced_jmp;
assign next_pc = hotstate_inst.address;
assign state_capture = hotstate_inst.state_capture;

endmodule
