`ifndef MICROCODE_PARAMS_VH
`define MICROCODE_PARAMS_VH

localparam NUM_STATES = 38;
localparam NUM_VARS = 3;
localparam NUM_VARS_ADDR_BITS = 3;
localparam NUM_INPUT_BITS = 121;
localparam NUM_INPUT_VARS = 15;
localparam NUM_WORDS = 93;
localparam NUM_ADR_BITS = 7;
localparam NUM_VARSEL_BITS = 5;
localparam VD_ROW_WIDTH = 32;
localparam NUM_TIMERS = 1;
localparam NUM_SWITCHES = 2;
localparam NUM_SWITCH_BITS = 1;
localparam SWITCH_OFFSET_BITS = 4;
localparam TIM_MEM_WORDS = 2;
localparam TIM_EX_WORDS = 1;
localparam EXPR_SEL_BITS = 4;
localparam NUM_EXPRS = 10;
localparam NUM_CONST_ARRAYS = 0;
localparam NUM_COMPARATORS = 10;
localparam CMP_VARSEL_BASE = 16;
localparam SMDATA_WIDTH = 103;

localparam STATE_WIDTH = 38;
localparam MASK_WIDTH = 38;
localparam JADR_WIDTH = 7;
localparam VARSEL_WIDTH = 5;
localparam TIMERSEL_WIDTH = 1;
localparam TIMERLD_WIDTH = 1;
localparam SWITCH_SEL_WIDTH = 1;
localparam SWITCH_ADR_WIDTH = 1;
localparam STATE_CAPTURE_WIDTH = 1;
localparam VAR_OR_TIMER_WIDTH = 1;
localparam BRANCH_WIDTH = 1;
localparam FORCED_JMP_WIDTH = 1;
localparam SUB_WIDTH = 1;
localparam RTN_WIDTH = 1;
localparam EXTERNAL_WIDTH = 1;

localparam INSTR_WIDTH = STATE_WIDTH + MASK_WIDTH + JADR_WIDTH + VARSEL_WIDTH + 
                         TIMERSEL_WIDTH + TIMERLD_WIDTH + SWITCH_SEL_WIDTH + SWITCH_ADR_WIDTH + 
                         STATE_CAPTURE_WIDTH + VAR_OR_TIMER_WIDTH + BRANCH_WIDTH + FORCED_JMP_WIDTH + 
                         SUB_WIDTH + RTN_WIDTH + EXTERNAL_WIDTH;

`endif // MICROCODE_PARAMS_VH
