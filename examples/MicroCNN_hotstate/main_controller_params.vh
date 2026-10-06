`ifndef MICROCODE_PARAMS_VH
`define MICROCODE_PARAMS_VH

localparam NUM_STATES = 139;
localparam NUM_VARS = 6;
localparam NUM_VARS_ADDR_BITS = 6;
localparam NUM_INPUT_BITS = 6;
localparam NUM_INPUT_VARS = 2;
localparam NUM_WORDS = 119;
localparam NUM_ADR_BITS = 7;
localparam NUM_VARSEL_BITS = 5;
localparam VD_ROW_WIDTH = 32;
localparam NUM_TIMERS = 0;
localparam NUM_SWITCHES = 1;
localparam NUM_SWITCH_BITS = 0;
localparam SWITCH_OFFSET_BITS = 5;
localparam TIM_MEM_WORDS = 1;
localparam TIM_EX_WORDS = 5;
localparam EXPR_SEL_BITS = 5;
localparam NUM_EXPRS = 29;
localparam NUM_CONST_ARRAYS = 0;
localparam NUM_COMPARATORS = 21;
localparam CMP_VARSEL_BASE = 3;
localparam SMDATA_WIDTH = 303;

localparam STATE_WIDTH = 139;
localparam MASK_WIDTH = 139;
localparam JADR_WIDTH = 7;
localparam VARSEL_WIDTH = 5;
localparam TIMERSEL_WIDTH = 0;
localparam TIMERLD_WIDTH = 0;
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
localparam ONE_SHOT_MASK_LO = 0;
localparam ONE_SHOT_MASK_HI = 0;
localparam ONE_SHOT_MASK_2 = 207872;
localparam ONE_SHOT_MASK_3 = 0;
localparam ONE_SHOT_MASK_4 = 0;

`endif // MICROCODE_PARAMS_VH
