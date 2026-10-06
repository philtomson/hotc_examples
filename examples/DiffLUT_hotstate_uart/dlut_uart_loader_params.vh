`ifndef MICROCODE_PARAMS_VH
`define MICROCODE_PARAMS_VH

localparam NUM_STATES = 29;
localparam NUM_VARS = 6;
localparam NUM_VARS_ADDR_BITS = 6;
localparam NUM_INPUT_BITS = 24;
localparam NUM_INPUT_VARS = 5;
localparam NUM_WORDS = 37;
localparam NUM_ADR_BITS = 6;
localparam NUM_VARSEL_BITS = 4;
localparam VD_ROW_WIDTH = 16;
localparam NUM_TIMERS = 2;
localparam NUM_SWITCHES = 0;
localparam NUM_SWITCH_BITS = 0;
localparam SWITCH_OFFSET_BITS = 8;
localparam TIM_MEM_WORDS = 3;
localparam TIM_EX_WORDS = 0;
localparam EXPR_SEL_BITS = 2;
localparam NUM_EXPRS = 3;
localparam NUM_CONST_ARRAYS = 0;
localparam NUM_COMPARATORS = 0;
localparam CMP_VARSEL_BASE = 0;
localparam SMDATA_WIDTH = 82;

localparam STATE_WIDTH = 29;
localparam MASK_WIDTH = 29;
localparam JADR_WIDTH = 6;
localparam VARSEL_WIDTH = 4;
localparam TIMERSEL_WIDTH = 2;
localparam TIMERLD_WIDTH = 2;
localparam SWITCH_SEL_WIDTH = 0;
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
