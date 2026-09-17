# HotState Machine Documentation

> **License note:** this directory is licensed under CC BY-NC-ND 4.0
> (noncommercial, no derivative redistribution) — see `LICENSE.md` in this
> directory. The rest of this repository is MIT; see the root `README.md`'s
> "License" section for the split.

## Overview

The hotstate is a **single-cycle algorithmic state machine** designed for control of data flow graphs. It executes one microcode instruction per clock cycle to orchestrate computation, making it highly efficient for embedded control applications.

## Architecture

### Core Components

#### 1. Microcode Memory (`microcode.sv`)

- Stores instructions in a memory array addressed by program counter
- Each instruction word contains:
  - **State bits** (2×NUM_STATES): current state values and transition flags
  - **Control bits**: jump address, variable selector, timer config, switch config, and control flags

#### 2. State Registers

- NUM_STATE flip-flops that hold the machine's state
- States can be updated on specific cycles when `state_capture` is asserted from the microcode

#### 3. Variable LUT (UberLUT) (`variable.sv`)

- **2D lookup table**: `code[varSel][variable]`
- `varSel` selects which truth table (operation/logic function) to use
- `variable` acts as an index into that truth table, selecting the result bit based on current input values
- Implements all conditional logic from C if-statements as truth tables

#### 4. Timer System (`timer.sv`)

- NUM_TIMERS countdown timers
- Timers are loaded from timer memory when both `timer_ld[i]` and `timer_sel[i]` are active
- Each timer decrements each cycle while selected until reaching zero
- Asserts `timer_done[i]` when the timer reaches zero

#### 5. Switch Table (`switch.sv`)

- Implements C switch/case statements
- Stores jump addresses for each case in a memory array
- Addressed by `{jmp_adr, switch_offset_adr}` to handle multiple switches with different base offsets

#### 6. Call Stack (`stack.sv`)

- Implements function call/return mechanism
- Pushes return address (current_address + 1) when `sub_push` is asserted
- Pops and returns to saved address when `sub_pop` is asserted
- Depth configurable via STACK_DEPTH parameter

#### 7. Address Generator (`next_address.sv`)

Computes the next program counter based on priority:

1. Reset or not ready → address 0
2. Halt → hold current address
3. Switch active → switch_adr (case jump)
4. Interrupt fired → interrupt_address
5. Jump enabled → jmp_adr (branch/jump instruction)
6. Subroutine return → returnadr (from stack pop)
7. Normal execution → address + 1 (sequential)

#### 8. Control Logic (`control.sv`)

- Determines when to fire (execute an instruction):
  - Checks variable conditions, timer conditions, and branch flags
- Generates control signals:
  - `jmp_enb`: enables jump to jmp_adr
  - `sub_push`: pushes return address onto stack
  - `sub_pop`: pops return address from stack

## Instruction Format

Each microcode word (64 bits typical) contains:

```
[ StateData(2*NUM_STATES) | ControlBits(NUM_CTL_BITS) ]

StateData:
  [ CurrentState(NUM_STATE_BITS) | TransitionFlags(NUM_STATE_BITS) ]

ControlBits:
  [ JMP_ADR(NUM_ADDRESS_LINES) 
    | VARSEL(NUM_VARSEL_BITS)
    | TIMERSEL(NUM_TIMERS)
    | TIMERLD(NUM_TIMERS)
    | SWITCHSEL(NUM_SWITCH_BITS)
    | FLAGS(7 bits) ]
    
FLAGS:
  bit 0: switch_active
  bit 1: state_capture
  bit 2: var_or_timer (selects variable vs timer for condition)
  bit 3: branch
  bit 4: forced_jmp
  bit 5: sub (function call)
  bit 6: rtn (function return)
```

## Execution Flow

1. **Fetch**: Read microcode word at current program counter address
2. **Decode**: Extract state values, transition flags, and control signals from the word
3. **Evaluate Conditions**: 
   - Variables evaluated through UberLUT based on varSel and input variables
   - Timers checked if selected and countdown to zero
   - Branch flag determines if conditional execution is allowed
4. **Compute Next Address**:
   - Based on jump, branch, subroutine call/return, switch case, or interrupt
5. **Update State**: 
   - If `state_capture` is high, update state registers with new values
6. **Repeat**

## Data Flow

The machine coordinates a data flow graph by:

1. Evaluating conditions (variables/timers) to determine execution path
2. Controlling when computation units fire based on available data
3. Routing data through multiplexers selected by varSel and switch_sel
4. Managing control flow with jumps, branches, and function calls

## Parameterization

The machine is highly parameterizable:

- `NUM_STATES`: Number of state bits (default 8)
- `NUM_VARSEL`: Number of variable selectors
- `NUM_VARS`: Number of input variables (defines LUT size: 2^NUM_VARS entries)
- `NUM_TIMERS`: Number of timers (0 = no timer support)
- `NUM_SWITCHES`: Number of switch tables
- `SWITCH_OFFSET_BITS`: Bits for switch offset addressing
- `STACK_DEPTH`: Call stack depth (0 = no call stack)
- `NUM_WORDS`: Microcode memory size

## Integration with C Parser

The hotc tool converts C code to hotstate microcode:

1. Parses C source file into AST
2. Transforms control flow (if/while/for/switch) into jump/branch instructions
3. Converts expressions to truth tables for the UberLUT
4. Allocates state variables and assigns them to state registers
5. Generates timer configurations if timers are used
6. Outputs microcode files in hexadecimal format for loading

The generated microcode targets the hotstate machine parameters configured during compilation.
