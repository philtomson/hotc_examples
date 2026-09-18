// Auto-generated Verilog module for kan_control
// Generated from CFG with hotstate microcode

`timescale 1ns / 1ps

module kan_control (
    input wire clk,
    input wire rst,
    input wire sdram_busy,
    input wire [7:0] sdram_rd_byte,
    input wire rx_done,
    input wire [7:0] rx_byte,
    input wire tx_busy,
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

wire [10:0] variables_bus;
wire [252:0] states_bus;

assign sdram_wr_req = states_bus[0];
assign sdram_rd_req = states_bus[1];
assign sdram_addr = states_bus[24:2];
assign sdram_wr_data = states_bus[32:25];
assign tx_start = states_bus[33];
assign tx_data = states_bus[41:34];
assign byte_idx = states_bus[64:42];
assign p = states_bus[73:65];
assign q = states_bus[81:74];
assign acc = states_bus[105:82];
assign rd_addr = states_bus[128:106];
assign byte_lo = states_bus[136:129];
assign byte_hi = states_bus[144:137];
assign combined = states_bus[160:145];
assign weight14 = states_bus[174:161];
assign weight13 = states_bus[187:175];
assign shifted = states_bus[211:188];
assign val = states_bus[220:212];
assign best_class = states_bus[225:221];
assign max_score = states_bus[234:226];
assign in_mem__wr_en = states_bus[235];
assign layer1_out__wr_en = states_bus[236];
assign __arrtmp0 = states_bus[244:237];
assign __arrtmp1 = states_bus[252:245];
assign states_out = states_bus;
wire [22:0] byte_idx_fb;
assign byte_idx_fb = states_bus[64:42];
wire [8:0] p_fb;
assign p_fb = states_bus[73:65];
wire [7:0] q_fb;
assign q_fb = states_bus[81:74];
wire [23:0] shifted_fb;
assign shifted_fb = states_bus[211:188];
wire [8:0] val_fb;
assign val_fb = states_bus[220:212];
wire [8:0] max_score_fb;
assign max_score_fb = states_bus[234:226];

wire __cmp_0 = (byte_idx_fb < 6750208);
wire __cmp_1 = ($signed(p_fb) < 196);
wire __cmp_2 = ($signed(q_fb) < 64);
wire __cmp_3 = ($signed(shifted_fb) > 255);
wire __cmp_4 = ($signed(shifted_fb) < 0);
wire __cmp_5 = ($signed(q_fb) < 10);
wire __cmp_6 = ($signed(p_fb) < 64);
wire __cmp_7 = ($signed(q_fb) == 0);
wire __cmp_8 = ($signed(val_fb) > $signed(max_score_fb));

assign variables_bus = {tx_busy, rx_byte, rx_done, sdram_busy};

wire [31:0] timer_ex_data_bus;
assign timer_ex_data_bus = 32'b0;

// Writable BRAM arrays (Direction 4b)
reg [7:0] in_mem_bram [0:195];
always @(posedge clk) begin
    if (states_bus[235])
        in_mem_bram[states_bus[73:65]] <= rx_byte;
end
reg [7:0] layer1_out_bram [0:63];
always @(posedge clk) begin
    if (states_bus[236])
        layer1_out_bram[states_bus[81:74]] <= states_bus[220:212];
end

// _BitInt combinatorial expression circuits
wire [22:0] expr_1_raw = states_bus[64:42];
wire [252:0] expr_1_vec = {{228{1'b0}}, expr_1_raw, {2{1'b0}}};
wire [7:0] expr_2_raw = rx_byte;
wire [252:0] expr_2_vec = {{220{1'b0}}, expr_2_raw, {25{1'b0}}};
wire [22:0] expr_3_raw = states_bus[128:106];
wire [252:0] expr_3_vec = {{228{1'b0}}, expr_3_raw, {2{1'b0}}};
wire [7:0] expr_4_raw = sdram_rd_byte;
wire [252:0] expr_4_vec = {{116{1'b0}}, expr_4_raw, {129{1'b0}}};
wire [22:0] expr_5_raw = (states_bus[128:106]) + (23'd1);
wire [252:0] expr_5_vec = {{228{1'b0}}, expr_5_raw, {2{1'b0}}};
wire [7:0] expr_6_raw = sdram_rd_byte;
wire [252:0] expr_6_vec = {{108{1'b0}}, expr_6_raw, {137{1'b0}}};
wire [15:0] expr_7_raw = states_bus[144:137];
wire [252:0] expr_7_vec = {{92{1'b0}}, expr_7_raw, {145{1'b0}}};
wire [15:0] expr_8_raw = (states_bus[160:145]) << (8);
wire [252:0] expr_8_vec = {{92{1'b0}}, expr_8_raw, {145{1'b0}}};
wire [15:0] expr_9_raw = (states_bus[160:145]) + (states_bus[136:129]);
wire [252:0] expr_9_vec = {{92{1'b0}}, expr_9_raw, {145{1'b0}}};
wire [22:0] expr_10_raw = states_bus[81:74];
wire [252:0] expr_10_vec = {{124{1'b0}}, expr_10_raw, {106{1'b0}}};
wire [22:0] expr_11_raw = (states_bus[128:106]) * (23'd196);
wire [252:0] expr_11_vec = {{124{1'b0}}, expr_11_raw, {106{1'b0}}};
wire [22:0] expr_12_raw = (states_bus[128:106]) + (states_bus[73:65]);
wire [252:0] expr_12_vec = {{124{1'b0}}, expr_12_raw, {106{1'b0}}};
wire [22:0] expr_13_raw = (states_bus[128:106]) * (23'd256);
wire [252:0] expr_13_vec = {{124{1'b0}}, expr_13_raw, {106{1'b0}}};
reg [7:0] expr_14_raw;
always @(posedge clk) expr_14_raw <= in_mem_bram[states_bus[73:65]];
wire [252:0] expr_14_vec = {{8{1'b0}}, expr_14_raw, {237{1'b0}}};
wire [22:0] expr_15_raw = (states_bus[128:106]) + (states_bus[244:237]);
wire [252:0] expr_15_vec = {{124{1'b0}}, expr_15_raw, {106{1'b0}}};
wire [22:0] expr_16_raw = (states_bus[128:106]) * (23'd2);
wire [252:0] expr_16_vec = {{124{1'b0}}, expr_16_raw, {106{1'b0}}};
wire [22:0] expr_17_raw = (states_bus[128:106]) * (23'd64);
wire [252:0] expr_17_vec = {{124{1'b0}}, expr_17_raw, {106{1'b0}}};
reg [7:0] expr_18_raw;
always @(posedge clk) expr_18_raw <= layer1_out_bram[states_bus[73:65]];
wire [252:0] expr_18_vec = {expr_18_raw, {245{1'b0}}};
wire [22:0] expr_19_raw = (states_bus[128:106]) + (states_bus[252:245]);
wire [252:0] expr_19_vec = {{124{1'b0}}, expr_19_raw, {106{1'b0}}};
wire [22:0] expr_20_raw = (states_bus[128:106]) + (23'd3211264);
wire [252:0] expr_20_vec = {{124{1'b0}}, expr_20_raw, {106{1'b0}}};
wire [22:0] expr_21_raw = (states_bus[64:42]) + (23'd1);
wire [252:0] expr_21_vec = {{188{1'b0}}, expr_21_raw, {42{1'b0}}};
wire [8:0] expr_22_raw = ($signed(states_bus[73:65])) + (9'sd1);
wire [252:0] expr_22_vec = {{179{1'b0}}, expr_22_raw, {65{1'b0}}};
wire [7:0] expr_23_raw = ($signed(states_bus[81:74])) + (8'sd1);
wire [252:0] expr_23_vec = {{171{1'b0}}, expr_23_raw, {74{1'b0}}};
wire [13:0] expr_24_raw = states_bus[160:145];
wire [252:0] expr_24_vec = {{78{1'b0}}, expr_24_raw, {161{1'b0}}};
wire [23:0] expr_25_raw = ($signed(states_bus[105:82])) + ($signed(states_bus[174:161]));
wire [252:0] expr_25_vec = {{147{1'b0}}, expr_25_raw, {82{1'b0}}};
wire [23:0] expr_26_raw = (($signed(states_bus[105:82])) + (24'sd8)) >>> (4);
wire [252:0] expr_26_vec = {{41{1'b0}}, expr_26_raw, {188{1'b0}}};
wire [8:0] expr_27_raw = states_bus[211:188];
wire [252:0] expr_27_vec = {{32{1'b0}}, expr_27_raw, {212{1'b0}}};
wire [12:0] expr_28_raw = states_bus[160:145];
wire [252:0] expr_28_vec = {{65{1'b0}}, expr_28_raw, {175{1'b0}}};
wire [23:0] expr_29_raw = ($signed(states_bus[105:82])) + ($signed(states_bus[187:175]));
wire [252:0] expr_29_vec = {{147{1'b0}}, expr_29_raw, {82{1'b0}}};
wire [8:0] expr_30_raw = states_bus[220:212];
wire [252:0] expr_30_vec = {{18{1'b0}}, expr_30_raw, {226{1'b0}}};
wire [4:0] expr_31_raw = states_bus[81:74];
wire [252:0] expr_31_vec = {{27{1'b0}}, expr_31_raw, {221{1'b0}}};
wire [7:0] expr_32_raw = states_bus[225:221];
wire [252:0] expr_32_vec = {{211{1'b0}}, expr_32_raw, {34{1'b0}}};
wire [8095:0] expr_results_flat = {expr_32_vec, expr_31_vec, expr_30_vec, expr_29_vec, expr_28_vec, expr_27_vec, expr_26_vec, expr_25_vec, expr_24_vec, expr_23_vec, expr_22_vec, expr_21_vec, expr_20_vec, expr_19_vec, expr_18_vec, expr_17_vec, expr_16_vec, expr_15_vec, expr_14_vec, expr_13_vec, expr_12_vec, expr_11_vec, expr_10_vec, expr_9_vec, expr_8_vec, expr_7_vec, expr_6_vec, expr_5_vec, expr_4_vec, expr_3_vec, expr_2_vec, expr_1_vec};

hotstate #(
    .NUM_STATES(253),
    .NUM_VARS(11),
    .NUM_VARS_ADDR_BITS(11),
    .NUM_ADR_BITS(8),
    .NUM_WORDS(131),
    .NUM_VARSEL_BITS(5),
    .NUM_TIMERS(0),
    .NUM_SWITCHES(0),
    .TIM_MEM_WORDS(1),
    .TIM_EX_WORDS(1),
    .SWITCH_MEM_WORDS(1),
    .SWITCH_OFFSET_BITS(8),
    .NUM_SWITCH_BITS(0),
    .MCFILENAME("./kan_control_smdata.mem"),
    .VRFILENAME("./kan_control_vardata.mem"),
    .TIFILENAME("./kan_control_timdata.mem"),
    .SWFILENAME("./kan_control_switchdata.mem"),
    .STACK_DEPTH(4),
    .STANDALONE(1),
    .DUAL_BANK(0),
    .COMPILER_MODE(0),
    .NUM_COMPARATORS(9),
    .CMP_VARSEL_BASE(6),
    .EXPR_SEL_BITS(6),
    .NUM_EXPRS(32),
    .DATA_STACK_WIDTH(0),
    .RESET_VALUES(253'h0000000000000000000000000000000000000000000000000000000000000000)
) hotstate_inst (
    .clk(clk),
    .rst(rst),
    .hlt(1'b0),
    .comparators({__cmp_8, __cmp_7, __cmp_6, __cmp_5, __cmp_4, __cmp_3, __cmp_2, __cmp_1, __cmp_0}),
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
    .sm_tdata({533{1'b0}}),
    .load_init(1'b0),
    .switch_tdata(8'b0),
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
