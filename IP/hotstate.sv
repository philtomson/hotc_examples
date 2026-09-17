//////////////////////////////////////////////////////////////////////////////////
// Company: Hotwright Inc.
// Copyright (c) 2022
// All Rights Reserved 
// Engineer: Steve Casselman
// 
// Create Date: 06/20/2020 02:51:51 PM
// Design Name: 
// Module Name: hotstate
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: This is the hot algorithmic state machine. The goal is to create a single cycle 
// algorithmic state machine for control of a data flow grapic  
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created 6/24/2020
// Additional Comments: By Steve Casselman
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 10ns / 1ns

module hotstate #(
    parameter NUM_STATES = 8,
    parameter NUM_VARSEL = 3,  
    parameter NUM_VARSEL_BITS = 4,  
    parameter NUM_VARS = 10,
    parameter NUM_VARS_ADDR_BITS = NUM_VARS, // vardata truth-table address width; see variable.sv
    parameter NUM_TIMERS = 1,
    parameter NUM_SWITCHES = 1,
    parameter SWITCH_OFFSET_BITS = 8,
    parameter SWITCH_MEM_WORDS = 8,
    parameter NUM_SWITCH_BITS = 2,
    parameter NUM_ADR_BITS = 5,
    parameter NUM_WORDS = 128,
    parameter TIM_WIDTH = 32,
    parameter TIM_MEM_WORDS = 2,
    parameter TIM_EX_WORDS = 1,
    parameter EXPR_SEL_BITS = 0,  // 0 = no expression circuits
    parameter NUM_EXPRS     = 0,  // number of expression circuits
    parameter DATA_STACK_WIDTH = 0,  // 0 = no data stack; >0 = --hw-stack active
    parameter DATA_STACK_DEPTH = 32, // data_stack.sv DEPTH parameter
    parameter NUM_CTL_BITS = NUM_ADR_BITS+NUM_VARSEL_BITS+(2*NUM_TIMERS) + NUM_SWITCH_BITS + EXPR_SEL_BITS + 8 + (DATA_STACK_WIDTH > 0 ? 2 : 0),
    parameter SMDATA_WIDTH = (2*NUM_STATES)+NUM_CTL_BITS,
    parameter STACK_DEPTH = 4,
    parameter [NUM_ADR_BITS-1:0] RESET_ADDR = 0,
    parameter [NUM_STATES-1:0] RESET_VALUES = 0,
    parameter [NUM_STATES-1:0] ONE_SHOT_MASK = 0,
    parameter MCFILENAME = "",
    parameter VRFILENAME = "",
    parameter TIFILENAME = "",
    parameter SWFILENAME = "",
    parameter STANDALONE = 1,
    parameter DUAL_BANK = 0,  // STANDALONE=0 only: gates vardata/switchdata/timdata ping-pong hot-swap (1 = --profile active, 0 = cheap single-bank default). smdata's dual-bank stays unconditional under STANDALONE=0.
    parameter COMPILER_MODE = 0, // 0 = normal target mode, 1 = compiler mode
    parameter NUM_COMPARATORS = 0,
    parameter CMP_VARSEL_BASE = 0
)(
    input [NUM_VARS-1:0] variables,
    input [NUM_COMPARATORS > 0 ? NUM_COMPARATORS-1 : 0 : 0] comparators,
    output [NUM_STATES-1:0] states,
    output ready,
    input clk,
    input rst,
    input hlt,
    input vd_tvalid,
    input [(1 << NUM_VARSEL_BITS)-1:0] vd_tdata,
    input vd_load_init,
    input sm_tvalid,
    input [SMDATA_WIDTH-1:0] sm_tdata,
    input tim_tvalid,
    input [TIM_WIDTH-1:0] tim_tdata,
    input [NUM_ADR_BITS-1:0] switch_tdata,
    input switch_tvalid,
    input  [SWITCH_OFFSET_BITS-1:0] switch_offset,
    output [NUM_SWITCH_BITS > 0 ? NUM_SWITCH_BITS-1 : 0 : 0] switch_sel,
    output [NUM_ADR_BITS-1:0] debug_adr,
    /* verilator lint_off SYMRSVDWORD */
    input interrupt,
    /* verilator lint_on SYMRSVDWORD */
    input [TIM_EX_WORDS-1:0][TIM_WIDTH-1:0] timer_ex_data,
    input [NUM_ADR_BITS-1:0] interrupt_address,
    // COMPILER_MODE output ports: top state bit = mcode_tvalid, rest = mcode_tdata
    output mcode_tvalid,
    output [NUM_STATES > 1 ? NUM_STATES-2 : 0 : 0] mcode_tdata,
    // Stream status outputs (tied off; kept for port compatibility)
    output stream_valid,
    output stream_ready,
    // Ping-pong hot-swap ports (STANDALONE=0 only; ignored otherwise)
    input  load_init,       // pulse before streaming a new program
    input  switch_trigger,  // safe-point signal (e.g. out_valid) for bank swap
    // Expression results: flat vector of NUM_EXPRS × NUM_STATES bits.
    // Tied to 0 in the generated template when EXPR_SEL_BITS=0.
    input  [(EXPR_SEL_BITS > 0 ? NUM_EXPRS * NUM_STATES : 1) - 1 : 0] expr_results_flat,
    // Timer count outputs: flat [NUM_TIMERS*TIM_WIDTH-1:0] vector of current counts.
    // Left open in hotstate.sv; connected in the generated template when timer is count-exposed.
    output [(NUM_TIMERS > 0 ? NUM_TIMERS * TIM_WIDTH : 1) - 1 : 0] count_out
);

wire  [(2*NUM_STATES)-1:0] statedata;
wire  [NUM_CTL_BITS-1:0] ctldata;
wire  lhs;
wire forced_jmp;
wire [NUM_ADR_BITS-1:0] address;
assign debug_adr = address;
wire [NUM_ADR_BITS-1:0] returnadr;
wire [NUM_ADR_BITS-1:0] jmp_adr;
wire [NUM_ADR_BITS -1:0] switch_adr; 
wire sub_push;
wire sub_pop;
wire [NUM_VARSEL_BITS-1:0] varSel;
// Clamp to 1 so wires are never [-1:0] when NUM_TIMERS=0
localparam TIMER_BITS = (NUM_TIMERS > 0) ? NUM_TIMERS : 1;
wire [TIMER_BITS-1:0] timer_done;
wire [TIMER_BITS-1:0] timer_sel;
wire [TIMER_BITS-1:0] timerLd;
wire var_or_timer;
wire jmp_enb;
wire sub;
wire rtn;
wire branch; 
wire external;
wire state_capture;
wire switch_active;
wire fired;
// Hardware data stack signals (DATA_STACK_WIDTH > 0 only)
wire push_en_w, pop_en_w;
wire [(DATA_STACK_WIDTH > 0 ? DATA_STACK_WIDTH : 1)-1:0] push_data_w;
wire [(DATA_STACK_WIDTH > 0 ? DATA_STACK_WIDTH : 1)-1:0] top_data_w;
wire code_ready, uberLUT_ready, tim_ready, switch_ready;

assign statedata = sm_tdata[2*NUM_STATES-1:0];

assign ctldata = sm_tdata[SMDATA_WIDTH-1:2*NUM_STATES];

if(STANDALONE == 0) begin : genblk_not_standalone1
   assign ready = STANDALONE?1: code_ready & (uberLUT_ready | NUM_VARS == 0) & (tim_ready | NUM_TIMERS == 0) & (switch_ready | NUM_SWITCHES == 0);
end
else begin : genblk_standalone1
   assign ready = 1;
end
wire lhs_raw;

generate 
if (NUM_VARS != 0) begin : variable
variable #(.NUM_VARS(NUM_VARS),
           .NUM_VARS_ADDR_BITS(NUM_VARS_ADDR_BITS),
           .NUM_VARSEL(NUM_VARSEL),
           .NUM_VARSEL_BITS(NUM_VARSEL_BITS),
           .FILENAME(VRFILENAME),
           .STANDALONE (STANDALONE),
           .DUAL_BANK (DUAL_BANK)
      ) Variable (
     .variable(variables),
     .vd_tdata(vd_tdata),
     .vd_tvalid(vd_tvalid),
     .vd_load_init(vd_load_init),
     .switch_trigger(switch_trigger),
     .varSel(varSel),
     .clk(clk),
     .ready(uberLUT_ready),
     .rst(rst),
     .lhs(lhs_raw)
     );
end
else begin : gen_lhs_assign
assign lhs_raw = 1;
end
endgenerate

generate
if (NUM_COMPARATORS > 0) begin : gen_bypass
    assign lhs = ((varSel >= CMP_VARSEL_BASE) && (varSel < CMP_VARSEL_BASE + NUM_COMPARATORS)) ? 
                 comparators[varSel - CMP_VARSEL_BASE] : lhs_raw;
end else begin : gen_no_bypass
    assign lhs = lhs_raw;
end
endgenerate

next_address #(.BUS_WIDTH(NUM_ADR_BITS)) Next_addr (
     .address(address),
     .jmp_adr(jmp_adr),
     .jmp_enb(jmp_enb),
     .returnadr(returnadr),
     .switch_adr(switch_adr),
     .switch_active(switch_active),
     .ready(ready),
     .rst(rst),
     .hlt(hlt),
     .fired(fired),
     .sub_pop(sub_pop),
     .clk(clk),
     .interrupt_address(interrupt_address),
     .interrupt(interrupt),
     .nextadr(address) 
     );
      

microcode #(
       .NUM_ADDRESS_LINES(NUM_ADR_BITS),
       .NUM_STATE_BITS(NUM_STATES),
       .NUM_CONTROL_BITS(NUM_CTL_BITS),
       .NUM_VARSEL_BITS(NUM_VARSEL_BITS),
       .NUM_TIMERS(NUM_TIMERS),
       .NUM_SWITCH_BITS(NUM_SWITCH_BITS),
       .EXPR_SEL_BITS(EXPR_SEL_BITS),
       .NUM_EXPRS(NUM_EXPRS),
       .DATA_STACK_WIDTH(DATA_STACK_WIDTH),
       .NUM_WORDS(NUM_WORDS),
       .FILENAME(MCFILENAME),
       .STANDALONE (STANDALONE),
       .COMPILER_MODE(COMPILER_MODE),
       .RESET_VALUES(RESET_VALUES),
       .ONE_SHOT_MASK(ONE_SHOT_MASK)
       ) Microcode (
       .smdata_word(sm_tdata),
       .expr_results_flat(expr_results_flat),
       .top_data(top_data_w),
       .push_en(push_en_w),
       .pop_en(pop_en_w),
       .push_data(push_data_w),
       .address(address),
       .varSel(varSel),
       .timerLd(timerLd),
       .var_or_timer(var_or_timer),
       .clk(clk),
       .rst(rst),
       .hlt(hlt),
       .sub(sub),
       .forced_jmp(forced_jmp),
       .rtn(rtn),
       .branch(branch),
       .smload(sm_tvalid),
       .load_init(load_init),
       .switch_trigger(switch_trigger),
       .timerSel(timer_sel),
       .jmp_adr(jmp_adr),
       .switch_sel(switch_sel),
       .switch_active(switch_active),
       .states(states),
       .external(external),
       .ready(code_ready),
       .state_capture(state_capture),
       .stream_valid(stream_valid),
       .stream_ready(stream_ready)
       );

// COMPILER_MODE: expose top state bit as mcode_tvalid, rest as mcode_tdata
generate
    if (COMPILER_MODE == 1) begin : gen_compiler_out
        assign mcode_tvalid = states[NUM_STATES-1];
        assign mcode_tdata  = states[NUM_STATES-2:0];
    end else begin : gen_no_compiler_out
        assign mcode_tvalid = 1'b0;
        assign mcode_tdata  = {(NUM_STATES > 1 ? NUM_STATES-1 : 1){1'b0}};
    end
endgenerate

generate
if (STACK_DEPTH != 0) begin: stack
stack #(.DEPTH(STACK_DEPTH),.WIDTH(NUM_ADR_BITS)) Stack (
     .push_adr(address),
     .pop_adr(returnadr),
     .sub_push(sub_push),
     .sub_pop(sub_pop),
     .hlt(hlt),
     .fired(fired),
     .clk(clk),
     .rst(rst)
     );
end
endgenerate

// Hardware data stack (Direction A: --hw-stack).
// Instantiated only when DATA_STACK_WIDTH > 0.
generate
if (DATA_STACK_WIDTH > 0) begin : gen_data_stack
    data_stack #(
        .DEPTH(DATA_STACK_DEPTH),
        .WIDTH(DATA_STACK_WIDTH)
    ) DataStack (
        .push_data(push_data_w),
        .push_en(push_en_w),
        .pop_en(pop_en_w),
        .hlt(hlt),
        .clk(clk),
        .rst(rst),
        .top_data(top_data_w),
        .empty(),
        .full()
    );
end else begin : gen_no_data_stack
    assign top_data_w = 1'b0;
end
endgenerate

control #(.NUM_TIMERS(NUM_TIMERS)) Control (
     .varible(lhs),
     .var_or_timer(var_or_timer),
     .timer_done(timer_done),
     .timer_sel(timer_sel),
     .sub(sub),
     .forced_jmp(forced_jmp),
     .rtn(rtn),
     .branch(branch),
     .jmp_enb(jmp_enb),
     .clk(clk),
     .rst(rst),
     .fired(fired),
     .interrupt(interrupt),
     .sub_push(sub_push),
     .sub_pop(sub_pop)
     ); 
 generate
 if (NUM_TIMERS != 0) begin : timer
timer #(.NUM_TIMERS(NUM_TIMERS),
       .TIMER_WIDTH(TIM_WIDTH),
       .TIM_MEM_WORDS(TIM_MEM_WORDS),
       .TIM_MEM_ADR_WIDTH(NUM_ADR_BITS),
       .TIM_EX_WORDS(TIM_EX_WORDS),
       .FILENAME(TIFILENAME),
       .STANDALONE (STANDALONE),
       .DUAL_BANK (DUAL_BANK)
     ) Timers (
     .timer_data(tim_tdata),
     .timer_ex_data(timer_ex_data),
     .timer_ld(timerLd),
     .timer_sel(timer_sel),
     .timer_mem_adr(jmp_adr),
     .external(external),
     .tim_tvalid(tim_tvalid),
     .load_init(load_init),
     .switch_trigger(switch_trigger),
     .clk(clk),
     .rst(rst),
     .ready(tim_ready),
     .timer_done(timer_done),
     .count_out(count_out)
     );
 end else begin : no_timer
     assign count_out = 1'b0;
 end
endgenerate
 
generate
if(NUM_SWITCHES != 0) begin : switch
switch #(.ADR_BUS_WIDTH(NUM_ADR_BITS),
         .SWITCH_MEM_BITS(SWITCH_OFFSET_BITS),
         .SWITCH_MEM_WORDS(SWITCH_MEM_WORDS),
         .FILENAME(SWFILENAME),
         .STANDALONE (STANDALONE),
         .DUAL_BANK (DUAL_BANK)
         ) Switch (
.switch_tvalid (switch_tvalid),
.switch_tdata(switch_tdata),
.load_init(load_init),
.switch_trigger(switch_trigger),
.jmp_adr(jmp_adr),
.switch_offset_adr(switch_offset),
.switch_active(switch_active),
.switch_adr(switch_adr),
.clk (clk),
.rst (rst),
.ready(switch_ready)
);
end
endgenerate


     
endmodule
