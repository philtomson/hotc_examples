// Auto-generated Verilog module for uart_rx
// Generated from CFG with hotstate microcode

`timescale 1ns / 1ps

module uart_rx (
    input wire clk,
    input wire rst,
    input wire rx_in,
    output wire [7:0] rx_data,
    output wire rx_done,
    output wire rx_busy,
    output wire [6:0] debug_adr,
    output wire [9:0] states_out,
    output wire ready,
    output wire lhs_out,
    output wire jmp_flag_out,
    output wire [6:0] jmp_bus_out,
    output wire br_out,
    output wire fj_out,
    output wire [6:0] next_pc,
    output wire state_capture
);

wire [31:0] bit_delay;

wire [0:0] variables_bus;
wire [9:0] states_bus;

assign rx_data = states_bus[7:0];
assign rx_done = states_bus[8];
assign rx_busy = states_bus[9];
assign states_out = states_bus;

assign variables_bus = {rx_in};

wire [31:0] timer_ex_data_bus;
assign timer_ex_data_bus = 32'b0;

hotstate #(
    .NUM_STATES(10),
    .NUM_VARS(1),
    .NUM_VARS_ADDR_BITS(1),
    .NUM_ADR_BITS(7),
    .NUM_WORDS(66),
    .NUM_VARSEL_BITS(1),
    .NUM_TIMERS(1),
    .NUM_SWITCHES(0),
    .TIM_MEM_WORDS(3),
    .TIM_EX_WORDS(1),
    .SWITCH_MEM_WORDS(1),
    .SWITCH_OFFSET_BITS(8),
    .NUM_SWITCH_BITS(0),
    .MCFILENAME("build_primer25k/uart_rx_smdata.mem"),
    .VRFILENAME("build_primer25k/uart_rx_vardata.mem"),
    .TIFILENAME("build_primer25k/uart_rx_timdata.mem"),
    .SWFILENAME("build_primer25k/uart_rx_switchdata.mem"),
    .STACK_DEPTH(4),
    .STANDALONE(1),
    .DUAL_BANK(0),
    .COMPILER_MODE(0),
    .NUM_COMPARATORS(0),
    .CMP_VARSEL_BASE(-1),
    .EXPR_SEL_BITS(0),
    .NUM_EXPRS(0),
    .DATA_STACK_WIDTH(0),
    .RESET_VALUES(10'h000)
) hotstate_inst (
    .clk(clk),
    .rst(rst),
    .hlt(1'b0),
    .comparators(1'b0),
    .interrupt(1'b0),
    .interrupt_address(7'b0),
    .variables(variables_bus),
    .states(states_bus),
    .debug_adr(debug_adr),
    .ready(ready),
    .vd_tvalid(1'b0),
    .vd_tdata({2{1'b0}}),
    .vd_load_init(1'b0),
    .sm_tvalid(1'b0),
    .sm_tdata({38{1'b0}}),
    .load_init(1'b0),
    .switch_tdata(7'b0),
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
assign next_pc = debug_adr;
assign state_capture = hotstate_inst.state_capture;

endmodule
