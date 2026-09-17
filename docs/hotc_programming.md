# hotc C Programming Guide

This guide is for engineers writing C programs for the `hotc` compiler, targeting the
Hotstate microarchitecture.  It covers the supported language subset, how C constructs
map to microcode, performance considerations, and idioms for writing effective programs.

---

## Table of Contents

1. [What is a Hotstate machine?](#1-what-is-a-hotstate-machine)
2. [Program structure](#2-program-structure)
3. [Variable types and hardware mapping](#3-variable-types-and-hardware-mapping)
4. [Control flow](#4-control-flow)
5. [Functions and subroutines](#5-functions-and-subroutines)
    - [5.3 Hardware parameter stack (`--hw-stack`)](#53-hardware-parameter-stack---hw-stack)
6. [Multi-machine systems (`--system`)](#6-multi-machine-systems---system)
    - [6.1 The `--system` flag](#61-the---system-flag)
    - [6.2 Inter-machine handshake: `__send` / `__recv`](#62-inter-machine-handshake-__send--__recv)
7. [Interrupt service routines](#7-interrupt-service-routines)
8. [Timing and cycle counts](#8-timing-and-cycle-counts)
9. [Switch statements](#9-switch-statements)
10. [For loops and timers](#10-for-loops-and-timers)
11. [Multi-bit variables (`_BitInt`)](#11-multi-bit-variables-_bitint)
    - [11.3 Static const ROM arrays](#113-static-const-rom-arrays)
    - [11.4 Synchronous ROM arrays (`__bram`)](#114-synchronous-rom-arrays-__bram)
    - [11.5 Writable BRAM arrays](#115-writable-bram-arrays)
    - [11.6 N-input reduction: `__argmax` / `__argmin`](#116-n-input-reduction-__argmax--__argmin)
    - [11.7 Multi-output computations without a builtin](#117-multi-output-computations-without-a-builtin-the-settle-then-derive-pattern)
12. [Performance guidelines](#12-performance-guidelines)
    - [12.9 Multi-bit comparisons in `if` / `while` conditions (comparator wires)](#129-multi-bit-comparisons-in-if--while-conditions-comparator-wires)
13. [Unsupported C features](#13-unsupported-c-features)
14. [Worked examples](#14-worked-examples)
    - [14.6 Multi-field opcode dispatch: if-else vs. nested switch](#146-multi-field-opcode-dispatch-if-else-vs-nested-switch)
    - [14.7 Register file using writable BRAM](#147-register-file-using-writable-bram)
    - [14.8 Multi-layer calls with `--hw-stack`](#148-multi-layer-calls-with---hw-stack)

---

## 1. What is a Hotstate machine?

A Hotstate machine is a hardware state machine engine driven by a compact microcode
ROM.  Each clock cycle the engine fetches one microcode instruction, updates state
variables (outputs), evaluates a branch condition through a combinatorial truth-table
lookup, and selects the next address.  One microcode instruction = one clock cycle.

The `hotc` compiler (also aliased as `c_parser`) takes a restricted subset of C and
produces:

- `*_smdata.mem` — the microcode program ROM
- `*_vardata.mem` — the variable/truth-table lookup ROM
- `*_switchdata.mem` — switch jump tables
- `*_timdata.mem` — timer limit pool
- `*_template.v`  — synthesizable Verilog module that instantiates the Hotstate IP
- `*_tb.v`        — simulation testbench
- `*_params.vh`   — Verilog parameter file
- `*_symbols.toml` — symbol table for the software simulator

The key mental model: **every assignment in your C program becomes one microcode
instruction, and every conditional test occupies one additional instruction.**  Writing
efficient hotc C means understanding this mapping.

---

## 2. Program structure

Every hotc program must have a `main()` function containing an infinite loop, plus
optional helper functions.  The canonical skeleton is:

```c
/* --- State outputs (initialized = start value) --- */
bool led0 = 0;
bool led1 = 0;

/* --- Inputs (no initializer) --- */
bool btn;

/* --- Helper functions --- */
void step() {
    led0 = btn;
    led1 = !btn;
}

/* --- Entry point --- */
int main() {
    while (1) {
        step();
    }
    return 0;
}
```

Rules:
- `main()` must contain a `while(1)` loop (or equivalent infinite loop).
- All variables must be declared at file scope — there are no local variables in the
  hardware sense; all state persists across iterations.
- By default, functions may not return values and take no parameters; pass data
  through file-scope state variables.  With `--hw-stack`, functions may declare
  `_BitInt(N)` parameters and return a `_BitInt(N)` value — see
  [§5.3](#53-hardware-parameter-stack---hw-stack).
- `return 0;` at the end of `main()` is accepted but irrelevant at runtime.

---

## 3. Variable types and hardware mapping

The compiler classifies every file-scope variable into one of four hardware roles based
on its type and declaration:

### 3.1 State variables (outputs)

`bool` declarations **with an initializer** become state outputs — registers that hold
their value across clock cycles and appear on the module's output ports.

```c
bool led0 = 0;   // state variable, initial value 0
bool done = 1;   // state variable, initial value 1
```

State variables can be read and written freely.  If a state variable appears in a
branch condition (`if`, `while`, `for`, `switch`), the compiler automatically adds it
to the feedback path through the truth-table address bus.

### 3.2 Input variables

`bool` declarations **without an initializer** become input ports — combinatorial
signals driven from outside the module.

```c
bool btn;        // input port
bool a0, a1;     // two input ports
```

Inputs can only be read, not written.  They feed directly into the truth-table LUT.

### 3.3 Multi-bit variables (`_BitInt(N)`)

`_BitInt(N)` variables hold N-bit values — **signed by default**, like all hotc
integer types; declare them `unsigned` for raw magnitudes (see [§11.0](#110-signedness)).
When initialized they are state outputs; without an initializer they are inputs.
See [Section 11](#11-multi-bit-variables-_bitint).

```c
_BitInt(8) count = 0;   // 8-bit state output
char sw;                 // 8-bit input (char = _BitInt(8))
```

### 3.4 Timer variables

Non-extern integer, `_BitInt(N)`, or `bool` variables become hardware timer
resources only when they are *pure `for`-loop counters in the canonical form*
`for (c = 0; c < LIMIT; c = c + 1)` (up-count; must not be value-read in the
body — Phase C territory) or `for (c = N; c > 0; c = c - 1)` (down-count; body
reads see the raw count and are fine) — and never used in a `while` condition
without the pragma. `c++`/`c--` are equally valid in the update clause: the
parser desugars both to exactly `c = c + 1`/`c = c - 1` before any of this
classification runs, so the two spellings are indistinguishable to the
compiler — use whichever reads better. Counters that fail those rules compile
as ordinary state variables with software counter loops (exact C semantics,
~2 extra cycles per iteration).  `extern` variables are **never** detected as timers by name
convention; they must be explicitly marked with `#pragma hotwright counter`.
See [Section 10](#10-for-loops-and-timers) for the full rules.

```c
_BitInt(6) i;                        // auto-detected: canonical for-loop counter
```

**`#pragma hotwright counter <name>`** forces timer classification for a counter
that auto-detection won't accept — typically a manually-incremented counter in a
`goto` loop or a `while(1)` wrapper.  The pragma works on ordinary (non-extern)
variables; for `extern` variables it is the *only* way to become a timer (externs
are never auto-detected).  The validated pattern compares the count in **`if`
conditions** (the raw count is wired into the condition machinery — "count-exposed")
and writes only `c = 0` (reset) and `c = c + 1` / `c++` (absorbed into a hardware
tick on a following instruction):

```c
#pragma hotwright counter crlf
_BitInt(8) crlf = 0;

void step() {
    crlf = 0;                  // timer reset
    while (1) {                // wrapper loop — crlf NOT in the condition
        if (crlf >= 4) {       // count-exposed compare in an if: OK
            break;
        }
        while (!rx_done) {}
        if (rx_byte == '\r' || rx_byte == '\n') {
            crlf++;            // hardware tick
        } else {
            crlf = 0;          // reset
        }
    }
}
```

(See `examples/webserver/http_server.c` and `examples/goto_timer_test/` for the
two validated shapes — `while(1)`+`if`+`break` and `goto` loop respectively.)

**`#pragma hotwright switch_prefetch <switch_var> <prefetch_var>`** enables
CLEAR+SWITCH pipelining for **`while(1)` or `do-while(true)` + `switch`** patterns
when compiling with `--microcode-hs-opt --opt`.  Declares that `<prefetch_var>` holds
the precomputed (prefetched) value of `<switch_var>` for the *next* iteration —
typically a combinational lookahead from the datapath.  When the compiler detects
this pragma and `--microcode-hs-opt` is active, simple case bodies (no `if`/`while`/`for`)
fuse their `continue` statement with the preceding CLEAR instruction's switch
dispatch, reducing the steady-state loop from **3 cycles to 2 cycles** per
instruction.  Requires RTL prefetch wiring in the top-level module (combinational
IMEM read at the next PC, decode logic on the prefetched IR).

Non‑simple case bodies (containing `if`, `while`, or `for`) safely fall back to
the original 3‑cycle pattern, avoiding branch hazards from a stale prefetch.

```c
// In main_controller.c:
unsigned _BitInt(11) decode_key;          // switch variable (current instruction)
unsigned _BitInt(11) decode_key_next;     // prefetched value (PC+4 / jump target)
#pragma hotwright switch_prefetch decode_key decode_key_next

void main() {
    while (1) {
        switch (decode_key) {
        case KEY_ADDI: {
            alu_add=1, use_imm=1, reg_write_en=1, pc_update_en=1, fetch_en=1;
            alu_add=0, use_imm=0, reg_write_en=0, pc_update_en=0, fetch_en=0;
            continue;   // ← fused into CLEAR as switch dispatch (saves 1 cycle)
        }
        case KEY_BNE: {
            // Non-simple (contains `if`): falls back to 3-cycle pattern
            is_branch = 1;
            if (branch_taken) { pc_sel = 1; }
            pc_update_en = 1, fetch_en = 1;
            is_branch = 0, pc_sel = 0, pc_update_en = 0, fetch_en = 0;
            continue;
        }
        }
    }
}
```

(Working example: `examples/RV32IM_hotstate/main_controller/main_controller.c`.
See `examples/RV32IM_hotstate/README.md` §"switch_prefetch Pipelining" and
`examples/RV32IM_hotstate/RV32IM_Instr_cycles.md` for cycle‑count results.)

**`#pragma hotwright intrinsic <name>(<param>:<width>, ...) -> <width> = <expr>`**
declares a **reusable expression template**, callable like an ordinary function
from anywhere in the file:

```c
#pragma hotwright intrinsic __avg2(a:8, b:8) -> 8 = (a >> 1) + (b >> 1)

_BitInt(8) sensor_a, sensor_b, sensor_c, sensor_d;
_BitInt(8) avg_ab = 0, avg_cd = 0;

void main() {
    while (1) {
        avg_ab = __avg2(sensor_a, sensor_b);
        avg_cd = __avg2(sensor_c, sensor_d);   // same template, different arguments
    }
}
```

Unlike an ordinary hotc function (which consumes hardware call-stack depth and
needs `--hw-stack` for parameters/return values), an intrinsic call compiles to
a plain combinational expression circuit at each call site — `avg_ab` and
`avg_cd` above become two independent Verilog wires, each substituted with its
own arguments. There's no shared runtime state or control transfer involved.

The body (`(a >> 1) + (b >> 1)` above) is parsed with the same expression
grammar `.hasm`'s `.expr = <expr>` and `.intrinsic` directives use — see
`docs/microassembly.md` §2.3 and §2.5 for the full grammar reference
(arithmetic, bitwise, comparison, ternary, bit-select/slice) and design notes
that apply identically here: template bodies can only reference their own
formal parameters (never a global variable), argument widths aren't enforced
against the declared parameter widths (matching this codebase's existing
implicit-width-promotion convention for `_BitInt` arithmetic generally), and a
call can't yet be composed with other operators or nested inside another
intrinsic call — capture an intermediate result into a state variable first if
you need to chain two calls.

(Working example: `examples/pragma_intrinsic_demo/`. Design rationale:
`plans/user_defined_intrinsics.md`.)

**Down-count while-loop counters (pragma-forced timers):** the canonical shape

```c
#pragma hotwright counter wait_count
unsigned _BitInt(3) wait_count = 5;   // initializer → timer LOAD at entry

while (wait_count > 0) {     // top-tested comparator on the raw count
    out_val = wait_count;    // body reads see the raw count (5,4,3,2,1)
    wait_count--;            // timer TICK instruction
}
```

maps natively onto the down-counting timer — the counter consumes **zero state
bits**.  The contract (anything else is a compile error): every while condition
naming the counter is `> 0` or `!= 0`, and every write is a literal assignment
(load) or `c = c - 1` (tick).  Declare the counter `unsigned` (the hardware
count is an unsigned down-counter; see §11.0).  Validated by
`test/test_while_pragma_timer.c` — software simulation and RTL lockstep.

**Pragma counter pitfalls (verified against the current compiler):**
- **Up-count while counters are not timers** — `while (c < 3) { ...; c = c + 1; }`
  with a pragma is a compile error (the exposed count runs DOWNWARD; the
  elapsed-count conversion is docs/timer_bugs.md Phase C).  Drop the pragma: a plain
  state-variable counter compiles as a software loop with full C semantics.
- **The extern down-count idiom is not supported** — `#pragma hotwright counter
  wait_cnt; extern _BitInt(16) wait_cnt;` with a decrement loop: an extern
  timer's count is only loaded by a for-loop header.  Use a non-extern pragma
  counter loaded from a literal, or a plain state variable initialized from an
  extern input.

### 3.5 Extern variables

`extern` declarations that are not timers represent external data inputs delivered
on a side-channel bus (e.g. register file read data, memory output).

```c
extern _BitInt(6) ex_num0, ex_num1;  // external loop-limit inputs
```

Supported uses: a `for`-loop numeric bound (as above), or reading the value via
a plain assignment (`result = ex_num0;`).

**`extern` is not a general-purpose control/status signal.** Unlike a plain
uninitialized `bool`/`_BitInt` ([§3.2](#32-input-variables)), an `extern`
variable is not part of the condition truth table the compiler builds for
`if`/`while`, so it **cannot be used directly as a branch condition** — `if
(ex_flag)` / `while (!ex_flag) {}` is a compile error. If you need to branch
on an external signal, declare it as a plain input instead
(`bool ex_flag;`), or — if it must specifically be `extern` — latch it into a
plain state variable first and branch on that:

```c
extern bool x;          // side-channel input
bool x_latched = 0;

void step() {
    x_latched = x;       // OK: plain assignment
    if (x_latched) { ... }  // OK: branching on the state variable, not x directly
}
```

### 3.6 Enumeration constants

`enum` declarations are fully supported.  Enumerators are substituted as integer
constants at parse time and have no hardware cost.

```c
enum { IDLE = 0, FETCH = 1, EXECUTE = 2 } state;
```

---

## 4. Control flow

### 4.1 `if` / `else`

Each `if` compiles to one branch instruction (one cycle) plus the body instructions.
An `else` branch adds a forced-jump at the end of the `if` body.

```c
if (btn) {
    led0 = 1;   // 1 cycle
} else {
    led0 = 0;   // 1 cycle
}
// Total: 1 (branch) + 1 (then) + 1 (forced jump) + 1 (else) = 4 cycles worst-case
```

Keep `if` bodies short.  Deeply nested conditions accumulate cycle counts linearly.

### 4.2 `while`

```c
while (condition) {
    body;
}
```

Compiles to: branch-back instruction, body, forced-jump back to branch.
`while(1)` with no condition is recognized and the NOP at the top is elided (with `--microcode-hs-opt`).

### 4.3 `do`-`while`

```c
do {
    body;
} while (condition);
```

Body executes first unconditionally, then the condition is checked each subsequent
iteration.

### 4.4 `for` loops

`for` loops in the canonical form `for (c = 0; c < LIMIT; c = c + 1)` (`c++`
is equally valid — the parser desugars it identically, see §3.4) (with a
constant or extern bound) are lowered to hardware timers — no compare/increment
instructions per iteration.  Any other shape (computed bound, nonzero init,
step ≠ 1, `<=`) compiles as a software counter loop with exact C
semantics — except the down-count form `for (c = N; c > 0; c = c - 1)` /
`for (c = N; c > 0; c--)`, which is also a canonical hardware-timer form
(§3.4).  See [Section 10](#10-for-loops-and-timers).

### 4.5 `switch` / `case`

Switch on a `char` or `_BitInt(N)` variable uses a hardware jump table.  Each `case`
compiles to one jump-table entry; the switch variable indexes into the table directly.
See [Section 9](#9-switch-statements).

### 4.6 `goto` and labels

`goto` is supported for forward and backward jumps.  It is useful for writing loops
that do not map cleanly to `while`/`for`.

```c
loop_start:
    led0 = !led0;
    if (count < limit) goto loop_start;
```

### 4.7 `break` and `continue`

`break` and `continue` work as in standard C, inside `while`, `do`-`while`, `for`,
and `switch` statements.

---

### 4.8 The comma operator — parallel vs. serial assignment

In hotc, **how you separate assignments determines how many clock cycles they consume**:

| Separator | Meaning | Cycles |
|-----------|---------|--------|
| Semicolon `;` | Serial — each assignment is a separate microcode instruction | 1 per assignment |
| Comma `,` | Parallel — all assignments share the **same** microcode instruction | 1 total |

```c
// Serial: 2 cycles — LED1 turns on one cycle before LED0 turns off
LED0 = 0;
LED1 = 1;

// Parallel: 1 cycle — both change on the same clock edge
LED0 = 0, LED1 = 1;
```

This is the primary use of the C comma operator in hotc.  In standard C the comma
operator evaluates left-to-right and discards intermediate values; in hotc it signals
to the compiler that a group of assignments should be packed into a single microcode
word so the hardware applies them simultaneously.

#### Rules

- Every assignment in a comma group is either a **literal assignment**
  (`var = <number>`, including bit-slice writes like `nst[1] = 0`) or an
  **independent expression assignment** (`var = a + b`, `var = a << 1`,
  `var = sel ? a : b`, ...) — see "Fusing expression assignments" below for
  the latter.  Mixing both kinds in one group is fine.  A variable copy or
  expression that the compiler can't turn into a hardware circuit at all is a
  **compile error** naming the reason (it used to silently write 0 for any
  non-literal RHS).
- **Every assignment's destination bit range must be disjoint from every
  other assignment's in the same group** — two different values can't both
  land on the same bit in one instruction.  This is checked for expression
  assignments (a hard compile error on overlap); the older literal-only path
  has no such check (e.g. `a = b, b = a` is formally a swap, but the result
  depends on which microcode bit the compiler assigns to each — write an
  explicit temporary instead).
- **All leaves in a group read the same pre-group state.**  A leaf's RHS
  cannot depend on another leaf's newly-written value within the same group
  — `max_val = ..., max_idx = ... max_val ...;` would read the *old* `max_val`
  for `max_idx`'s computation, not the value the first leaf just computed.
  Use semicolons when one output depends on another.
- Control flow, function calls with real call/return semantics (a `#pragma
  hotwright intrinsic` call is fine — it expands to a plain combinational
  expression, not a call), and BRAM/ROM reads (their 1-cycle registered
  latency doesn't fit inside one instruction) are not supported as an
  expression assignment's RHS — place those on their own line. A combined
  expression assignment spanning more than 64 bits is also rejected.
- Comma groups can appear anywhere a single statement can: inside `if` bodies,
  `for` loop bodies, `while` bodies, and `switch` cases.

#### Example — 8-LED parallel update

```c
bool LED0=0, LED1=0, LED2=0, LED3=0;
bool LED4=0, LED5=0, LED6=0, LED7=0;

void main() {
    while (1) {
        // Turn on LEDs 0-3 AND turn off LEDs 4-7 in one cycle:
        LED0 = 1, LED1 = 1, LED2 = 1, LED3 = 1,
        LED4 = 0, LED5 = 0, LED6 = 0, LED7 = 0;

        // One cycle later, reverse them:
        LED0 = 0, LED1 = 0, LED2 = 0, LED3 = 0,
        LED4 = 1, LED5 = 1, LED6 = 1, LED7 = 1;
    }
}
```

The entire eight-LED assignment compiles to **one** microcode instruction.  With
semicolons it would be eight instructions.

#### Parallel clear with comma, one-cycle pulse with semicolons

The two patterns complement each other:

```c
// Assert two flags in the same cycle (comma):
req = 1, ack = 0;

// Generate a two-signal handshake over two consecutive cycles (semicolons):
req = 1;   // cycle N:   req high
req = 0;   // cycle N+1: req low  (one-cycle pulse — see §12.8, or §4.9 to
                                  // drop the deassert instruction entirely)
```

#### Fusing expression assignments

A comma group isn't limited to literals — it can also fuse **independent**
expression assignments into the same instruction. Each expression still
compiles to its own combinational circuit (§12.6); the comma operator just
tells the compiler to capture several of them (and any literal assignments
in the same group) on the same clock edge instead of one per cycle:

```c
_BitInt(8) out_add = 0;
_BitInt(8) out_sub = 0;
_BitInt(8) out_mul = 0;
bool done = 0;

_BitInt(8) a;
_BitInt(8) b;

void step() {
    // 1 cycle instead of 4 -- three independent arithmetic results plus a
    // literal, all captured on the same clock edge:
    out_add = a + b, out_sub = a - b, out_mul = a * b, done = 1;
}
```

Exactly **one** non-literal leaf is a "free win" — its circuit is already
built for it regardless of comma-group membership, so fusing it with
surrounding literals costs nothing extra to register. **Two or more**
non-literal leaves make the compiler synthesize one additional composite
circuit (a bitwise OR of the leaves' own expressions, each shifted to its
own bit offset) and select it with a single `expr_sel` value — this is what
makes disjoint destination ranges a hard requirement: `expr_sel` picks
exactly one circuit per instruction, so two different expressions can't both
apply to the same bit. See `examples/bitint_arith/` for a worked example
(six arithmetic/shift/ternary results plus a literal, fused from 7 cycles
down to 1) including its generated Verilog.

### 4.9 `one_shot` — auto-clearing pulse signals

A `one_shot`-qualified state variable **auto-clears to its initializer every
cycle it isn't explicitly written** — the hardware does it, not your program:

```c
one_shot bool strobe = 0;   // must have an initializer (its "at rest" value)

void main() {
    while (1) {
        strobe = 1;    // asserted for exactly one cycle
        // no deassert needed -- strobe is already 0 on the next cycle
        ...
    }
}
```

Without `one_shot`, a one-cycle pulse costs two instructions (§12.8):
`strobe = 1; strobe = 0;`. With `one_shot`, the same pulse costs **one**
instruction — the deassert simply isn't written, because the hardware
forces the bit back to its initializer on any cycle your program doesn't
assign it. This is exactly the lever that cut `examples/hdmi_gpu`'s render
loop from 7 to 6 microcode instructions per pixel (`wr_en`'s deassert was
one of them).

#### Rules

- Requires an initializer (`one_shot bool x = 0;`, not `one_shot bool x;`)
  — auto-clear needs a value to clear *to*, so `one_shot` only applies to
  state (output) variables, never inputs. Declaring it on a variable with
  no initializer is a compile error.
- Writing an explicit deassert anyway (`strobe = 1; strobe = 0;`) is not
  wrong, just redundant — the second instruction still compiles, it just
  duplicates what the hardware already does.
- Works the same on both compilation paths (`--microcode-hs` and
  `--microcode-ssa`) and in both the RTL (`IP/microcode.sv`'s
  `ONE_SHOT_MASK`) and the software simulator (`sim/`), so `compare_c`-style
  validation sees identical behavior either way.
- Can combine with `reg` (`reg one_shot bool x = 0;`) if the variable also
  needs to be condition-testable, though this is an unusual combination —
  a signal that both auto-clears and feeds back into a branch condition on
  the same cycle needs care about which value the branch actually sees.

---

## 5. Functions and subroutines

Functions are compiled as subroutines with a hardware call/return stack.  The default
stack depth is **4** (configurable with `--stack-size N`).  The compiler performs a
static call-graph analysis: it warns when the estimated call depth from `main()`
exceeds half the configured depth and errors out when it would exceed the full depth.

```c
void helper() {
    led0 = 1;
    led0 = 0;
}

int main() {
    while (1) {
        helper();   // call instruction (1 cycle) + body + return (1 cycle)
    }
}
```

**Key restrictions:**
- By default, functions may not take parameters.  Pass data through file-scope state
  variables.  With `--hw-stack`, functions may declare one or more `_BitInt(N)` parameters
  and return a `_BitInt(N)` value — see §5.3.
- By default, functions may not return values.  With `--hw-stack`, `_BitInt(N)` return
  values are supported via the data stack.
- Recursion is supported when structured as tail calls (see §5.1); non-tail recursion
  consumes stack depth and is limited to `--stack-size` levels.

### 5.1 Tail-call optimization (TCO)

When a function call is the last action before `return` — a tail call — the compiler
replaces the call+return pair with a direct jump, consuming no stack:

```c
void seq() {
    if (!led0) { led0 = 1; seq(); return; }  // tail call → jump
    if (!led1) { led1 = 1; seq(); return; }  // tail call → jump
    done = 1;
}
```

Write tail-recursive logic to stay within the stack limit on deeply chained dispatch.

### 5.2 Call depth analysis

`hotc` performs static call-graph analysis against the configured stack size
(`--stack-size N`, default 4): it prints a warning when the estimated maximum
call depth from `main()` exceeds **half** the stack size and errors out when it
exceeds the **full** stack size (the error message names the `--stack-size`
value needed).  Recursive programs get a note instead — static analysis cannot
bound their depth.  Structure your code so the main loop is shallow, with
helpers called only one or two levels deep.

### 5.3 Hardware parameter stack (`--hw-stack`)

By default, hotc functions share data through file-scope state variables (§5).  The
`--hw-stack` flag activates an additional hardware data stack inside the Hotstate IP,
enabling functions to declare **`_BitInt(N)` parameters and return `_BitInt(N)` values**.
Arguments are pushed before the call and popped into parameter variables at callee entry;
the return value (if any) is pushed before `return` and popped by the caller.

#### Enabling the feature

```bash
hotc input.c --microcode-hs --all-hdl --hw-stack
# Optional: set data stack depth (default 32)
hotc input.c --microcode-hs --all-hdl --hw-stack --data-stack-depth 16
```

`--hw-stack` is a **zero-overhead invariant** when not used: the `push_en`/`pop_en`
instruction bits are only added to the instruction word width when `--hw-stack` is
active.  Programs compiled without the flag have exactly the same instruction encoding
as before.

#### Writing parameterized functions

Parameters may be `_BitInt(N)`, `char`, `int`, or `bool` (see the type table
below); return types may be any of those **except `bool`**.  Parameter
variables act as internal state variables inside the callee — they are not visible as
external ports.  State variables may be passed as arguments.

```c
bool trigger;
bool done   = 0;
_BitInt(8) result = 0;

/* Two-parameter function: both args received via the data stack */
_BitInt(8) add(_BitInt(8) a, _BitInt(8) b) {
    return a + b;   /* return value pushed onto stack before return */
}

void main() {
    while (!trigger) {}
    result = add(3, 4);   /* push 3, push 4, call add; pop return value into result */
    done = 1;
    while (1) {}
}
```

Compile with:

```bash
hotc hw_stack.c --microcode-hs --all-hdl --hw-stack
```

#### Calling convention

1. The **caller** emits one `push` microcode instruction per argument, right-to-left
   (last argument pushed first), immediately before the `sub` (call) instruction.
   If the return value is needed, the caller emits a `pop` instruction after the call
   to capture it (e.g., `result = fn(5)` becomes push, call, pop into `result`).
2. The **callee** emits one `pop → __retval` + `copy __retval → param` pair per
   parameter in left-to-right declaration order, immediately after the function entry NOP.
   Before `return`, the callee emits one `push` of the return expression (if the
   function has a non-`void` return type).
3. A `push` writes the value into the stack; the top-of-stack is visible from the
   **next** clock cycle (registered output).
4. A `pop` reads the top-of-stack in two instructions: first `pop → __retval`, then
   `copy __retval → destination` via the `expr_sel` circuit.

Cycle cost:
- 1 push instruction per argument (before the call)
- 2 instructions per parameter at callee entry (pop → __retval, copy → param)
- 1 push instruction before return (if returning a value)
- 2 instructions at call site to capture a return value (pop → __retval, copy → dest)

#### Variant B: direct-write calling convention (automatic optimization)

The compiler automatically switches to a faster **direct-write** (Variant B) calling
convention when all call sites of a function pass only literal constants or simple
identifier arguments.

**Unique parameter names:** under `--hw-stack` the compiler internally renames every
function's parameters to the globally unique form `fn__param` (e.g. `add`'s `a` becomes
`add__a`), rewriting all references inside the function body. Each function's parameters
therefore occupy their own state variable bits — a caller's local named `a` is a different
state variable from `add__a`. This eliminates the read-after-write hazard that previously
blocked Variant B for call sites like `add(b, a)`, and prevents a callee's argument writes
from clobbering same-named variables in the caller. The mangled names are what appear in
generated ports, `*_symbols.toml`, and simulation CSV columns.

If a call site passes a complex expression argument (not a literal or identifier), the
function stays on the push path.

**Cycle cost comparison (`add(a, b)` — 2 parameters):**

| Calling convention | Cost |
|-------------------|------|
| Push path (fallback) | ~9 cycles (2 push + call + 4 pop/copy + push ret + pop ret) |
| Variant B — all const args | **1 cycle** (constants packed into call instruction) |
| Variant B — identifier args | **2 cycles** (last copy fused with the call: N cycles for N args) |

**How Variant B works:**
- *Constant args*: all argument values are packed into the call instruction's `state_value`
  field at the parameter bit positions, with `state_capture=1, sub=1, forced_jmp=1`.
  Parameters are written and the jump taken simultaneously in one instruction.
- *Identifier args*: one `expr_sel`-based copy instruction is emitted per variable argument
  (writing the source variable bits into the destination parameter's bit position). The
  **last copy is fused with the call instruction** (`sub=1, forced_jmp=1, branch=1` on the
  copy), so N variable arguments cost N cycles total.
- *Mixed const + identifier args*: the constants ride in the call instruction's
  `state_value`/mask, so the call cannot also carry an `expr_sel` copy (the hardware
  substitutes the expr result for the entire `state_value` when `expr_sel != 0`).
  Cost: N copies + 1 const-carrying call = N+1 cycles.
- The **callee prologue skips the pop sequence** entirely — parameters are already written
  before the first callee instruction executes.

**Example — `add(n, n)` with Variant B (inside `double_val`, whose param `n` is
`double_val__n`):**

```
; Caller (double_val):
  N   varb: double_val__n → add__a;   expr_sel=copy_circuit, mask(add__a), state_capture=1
  N+1 varb: double_val__n → add__b; call add() [fused];  sub=1, branch=1, forced_jmp=1

; Callee (add) — NO pop prologue:
  add_entry:
  ...body...
  push_en=1, expr_sel=a+b   ; push return value
  rtn
```

Compare to `add(3, 4)` (all constant) with Variant B:

```
  N   varb call add(); state={add__a=3,add__b=4}, mask(add__a,add__b), state_capture=1, sub=1, forced_jmp=1
```

One instruction for the entire call setup.

#### Generated microcode (push-path example — `result = add(3, 4)` with push path)

```
Addr  Instruction                         Comment
  4   push_en=1 state=0x04                push arg[1]=4  (right-to-left)
  5   push_en=1 state=0x03                push arg[0]=3
  6   sub → add                           call add
  7   pop_en=1                             pop __retval (return value)
  8   result = __retval                   copy __retval → result
  ...
  A   nop                                 add entry NOP
  B   pop_en=1                             pop → __retval
  C   add__a = __retval                   copy __retval → add__a  (first param)
  D   pop_en=1                             pop → __retval
  E   add__b = __retval                   copy __retval → add__b  (second param)
  F   push_en=1, expr_sel=a+b             push return value
  10  implicit return
```

#### Hardware parameters emitted

The compiler sets `DATA_STACK_WIDTH` to the maximum parameter bit width used across
all functions, and instantiates `IP/data_stack.sv` in the generated Verilog.

In `*_params.vh`:
```verilog
parameter DATA_STACK_WIDTH = 8;   // max _BitInt(N) param width found
parameter DATA_STACK_DEPTH = 32;  // configurable via --data-stack-depth
```

In `*_template.v` (hotstate instantiation):
```verilog
hotstate #(
    ...
    .DATA_STACK_WIDTH(8),
    .DATA_STACK_DEPTH(32)
) hs_inst (...);
```

#### Symbol table (`*_symbols.toml`)

Parameter state variables appear in the symbol table with `is_internal = true`,
indicating they are internal to the function and not exposed as top-level output ports:

```toml
[states]
"0" = { name = "n", type = "output", initial_value = 0, is_internal = true }
```

#### Supported parameter types

| Type | Width | Notes |
|------|-------|-------|
| `_BitInt(N)` | N | Recommended; exact width control |
| `char` / `unsigned char` | 8 | Identical to `_BitInt(8)` under the hood |
| `bool` | 1 | Supported; `DATA_STACK_WIDTH` stays narrow |
| `int` / `unsigned int` | 32 | Supported; inflates `DATA_STACK_WIDTH` to 32 — prefer `_BitInt(N)` for FPGA area efficiency |

#### Limitations

- **`bool` return types are not supported**: the return type must be `_BitInt(N)`, `char`,
  `int`, or `void`.  Return a boolean result as `_BitInt(8)` (0/255 or 0/1) instead.
- **Software simulator**: `sim/bin/hotstate_sim` models push/pop for single-assignment
  capture patterns but complex multi-parameter call chains should be validated with
  hardware simulation (Verilator).

See `examples/hw_stack/` for a complete runnable example with 3-layer calls and a
two-parameter function (`add(a, b)`) — `compute(5) = 11` validated by the `sim` target.
See `examples/hw_stack_types/` for `char`, `bool`, and `int` parameter type validation.

---

## 6. Multi-machine systems (`--system`)

Real designs often require several cooperating hotstate machines — a UART receiver,
a tokenizer, and a command interpreter, for example.  Each machine is compiled
independently from its own C file; `--system` then wires them together automatically
into a single top-level Verilog module.

### 6.1 The `--system` flag

#### What it generates

When you pass `--system` together with two or more C source files, hotc:

1. Compiles each file into its own `*_template.v`, `*_smdata.mem`, etc. as usual.
2. Inspects every machine's input and output ports.
3. **Signal matching**: if an output of machine A has the same name as an input of
   machine B, the two are wired together as an **internal wire** in the system module.
4. **Unmatched signals**: any input or output that does not appear on the other side of
   any machine boundary becomes a **top-level port** of the system module.
   - Port names are prefixed with `{machinename}_` when the same signal name exists on
     more than one machine (e.g. `sender_start`, `receiver_result`).
   - Unambiguous names (unique across all machines) are exposed without a prefix.
5. Writes one combined `{first_file}_system.v` module that instantiates all machines
   and connects them.

#### Compile command

```bash
# Two machines: produces sender_template.v, receiver_template.v, sender_system.v
hotc sender.c receiver.c --microcode-hs-opt --opt --all-hdl --system

# Five machines: produces word_lexer_system.v wiring all 5 machines
hotc word_lexer.c outer_interpreter.c inner_interpreter.c \
     uart_rx.c uart_tx.c \
     --microcode-hs-opt --opt --all-hdl --system
```

The generated module is always named `{first_machine}_system` and placed in the
directory of the first source file.

#### Plain wire example (`system_demo`)

When matched signals are ordinary level-sensitive wires (no pulse-reliability
requirement), `--system` needs no special annotations — just make sure the C variable
names match:

```c
/* sender.c */
bool start;    // input: external trigger  → unmatched, becomes top-level port
bool ack;      // input: matched from receiver.ack

bool go = 0;   // output: matched to receiver.go

void main() {
    while (1) {
        while (!start) {}
        go = 1; go = 0;      // one-cycle pulse (plain wire)
        while (!ack) {}
    }
}
```

```c
/* receiver.c */
bool go;            // input: matched from sender.go

bool ack    = 0;    // output: matched back to sender.ack
bool result = 0;    // output: unmatched → top-level port

void main() {
    while (1) {
        while (!go) {}
        result = 1; result = 0;
        ack = 1; ack = 0;
    }
}
```

```bash
hotc sender.c receiver.c --microcode-hs-opt --opt --all-hdl --system
```

Generated `sender_system.v`:

```verilog
module sender_system (
    input  wire clk,
    input  wire rst,
    input  wire sender_start,      // unmatched → top-level port
    output wire receiver_result    // unmatched → top-level port
);
// Internal wires: signals matched between machines
wire go;
wire ack;

sender   sender_inst   (.clk(clk), .rst(rst), .start(sender_start),
                        .ack(ack), .go(go), ...);
receiver receiver_inst (.clk(clk), .rst(rst), .go(go),
                        .ack(ack), .result(receiver_result), ...);
endmodule
```

This is sufficient when the receiver is always polling at its `while (!go) {}` line
when the sender fires the pulse.  For designs where the receiver may be temporarily
busy, use `__send`/`__recv` (§6.2) instead.

See `examples/system_demo/` for the complete runnable version.

#### Multi-machine example — Forth machine (5 machines)

```bash
hotc word_lexer/word_lexer.c \
     outer_interpreter/outer_interpreter.c \
     inner_interpreter/inner_interpreter.c \
     uart_rx/uart_rx.c \
     uart_tx/uart_tx.c \
     --microcode-hs-opt --opt --all-hdl --system
# → generates word_lexer/word_lexer_system.v
```

The 5-machine Forth system has these automatically matched inter-machine wires:

| Signal | From | To |
|--------|------|----|
| `word_ready` | `word_lexer` output | `outer_interpreter` input |
| `lex_start` | `outer_interpreter` output | `word_lexer` input |
| `call_en` | `outer_interpreter` output | `inner_interpreter` input |
| `inner_done` | `inner_interpreter` output | `outer_interpreter` input |
| `rx_done` | `uart_rx` output | `word_lexer` input |

All remaining ports (UART `rx_in`, `tx_bit`, datapath enable signals) are unmatched
and appear as top-level ports of `word_lexer_system`.

See `examples/forth_machine/` and its `generate_system` make target for the full example.

---

### 6.2 Inter-machine handshake: `__send` / `__recv`

When multiple hotstate machines are connected via the `--system` generator, signals
flow between them as plain Verilog wires by default.  A plain wire works fine for
level-sensitive signals but fails for one-cycle pulses: if machine A fires a 1-cycle
pulse while machine B is mid-subroutine and not yet polling its input, the pulse is
missed.

`__send` and `__recv` solve this with a **compiler-expanded handshake** that generates
a registered latch circuit in the system module, guaranteeing the pulse is captured
even if the receiver is temporarily busy.

### 6.2.1 Expansion semantics

`__send` and `__recv` look like function calls to the C programmer but are expanded
inline by the compiler at microcode-generation time — they have no runtime call
overhead and do not consume stack:

```
__send(sig)  →  sig = 1;               (fire one-cycle pulse)
                sig = 0;               (de-assert)

__recv(sig)  →  while (!sig) {}        (busy-wait until latch is set)
                sig_ack = 1;           (acknowledge: clear the latch)
                sig_ack = 0;
```

`sig_ack` is an **auto-generated output** added to the receiving machine's template
by the compiler — you never declare it in your C source.

### 6.2.2 System-level latch circuit

When `hotc --system` processes files whose machines have a matched `__send(x)` /
`__recv(x)` pair, it emits a registered set/clear latch in `*_system.v` instead of a
plain wire:

```verilog
// set-latch for 'go': set by sender pulse, cleared by receiver ack
reg go_latch = 0;
always @(posedge clk) begin
    if (sender_go)     go_latch <= 1;   // sender fires __send(go)
    if (go_ack)        go_latch <= 0;   // receiver fires ack after __recv(go)
end
assign receiver_go = go_latch;          // receiver sees level-high until it acks
```

The latch holds the signal high until the receiver explicitly acknowledges it,
so even if the receiver polls infrequently the pulse is never missed.

### 6.2.3 Requirements and restrictions

| Role | What to declare | Signal direction |
|------|-----------------|------------------|
| Sender | `bool sig = 0;` (initialized → state output) | output from sender |
| Receiver | `bool sig;` (no initializer → input) | input to receiver |

- `__send(sig)` may only be called on a **declared `bool` output** (`bool sig = 0;`).
  The compiler errors if `sig` is an input or undeclared.
- `__recv(sig)` may only be called on a **declared `bool` input** (`bool sig;`).
  The compiler errors if `sig` is an output or undeclared.
- The auto-generated `sig_ack` output must not collide with any explicitly declared
  variable in the receiving machine.
- The `__recv` busy-wait (`while (!sig) {}`) uses a truth-table branch, so `sig`
  counts as one input bit in `variables_bus`.

### 6.2.4 Usage example

```c
/* sender.c */
bool start;      // input: external trigger
bool ack;        // input: matched from receiver via latch

bool go = 0;     // output: matched to receiver via latch

void main() {
    while (1) {
        while (!start) {}   // wait for external trigger
        __send(go);         // fire handshake → sets go_latch in system
        __recv(ack);        // wait for receiver to confirm
    }
}
```

```c
/* receiver.c */
bool go;            // input: matched from sender via latch

bool ack    = 0;    // output: matched back to sender
bool result = 0;    // output: unmatched → becomes system port

void main() {
    while (1) {
        __recv(go);            // wait for go_latch to be set, then ack it
        result = 1; result = 0; // one-cycle pulse on result
        __send(ack);           // confirm to sender
    }
}
```

### 6.2.5 Compile command

```bash
# Compile both machines and generate the system module
hotc sender.c receiver.c --microcode-hs-opt --all-hdl --system
# → produces sender_template.v, receiver_template.v, sender_system.v
```

The `--system` flag is required for latch generation.  Without it, the two machines
compile independently and `__send`/`__recv` expand to plain pulse-and-poll sequences
without the latch circuit.

### 6.2.6 Unmatched signals

Signals that appear on only one side of the boundary (declared in one machine but not
referenced by the other) become **top-level ports** of the system module.  In the
example above, `start` and `result` are unmatched — they become `input wire start`
and `output wire result` on `sender_system.v`.

### 6.2.7 Comparison with plain pulse-and-poll

| Mechanism | Missed pulse possible? | Extra Verilog | Boilerplate |
|-----------|------------------------|---------------|-------------|
| Plain `sig = 1; sig = 0;` + `while(!sig){}` | Yes — if receiver is busy | None | Yes |
| `__send(sig)` / `__recv(sig)` | No — latch holds until ack | Set/clear FF per pair | None |

Use `__send`/`__recv` any time the sender and receiver may not be simultaneously at
their handshake points.  Use plain pulses only when both machines are tightly
synchronized and you can guarantee the receiver is polling at the moment the pulse
fires.

---

## 7. Interrupt service routines

The Hotstate hardware supports a single hardware interrupt input.  When the `interrupt`
port sees a rising edge, the engine automatically pushes the current program counter
onto the return stack and jumps to a fixed address — the ISR entry point.

### 7.1 Declaring an ISR

Mark a function with `__attribute__((interrupt))` to designate it as the ISR:

```c
bool irq_count = 0;
bool irq_flag  = 0;

__attribute__((interrupt))
void isr() {
    irq_flag  = 1;   // pulse for one hotstate step
    irq_flag  = 0;
    irq_count = !irq_count;
}
```

The compiler:
1. Records the ISR's start address as `INTERRUPT_ADDR` in `*_params.vh` and
   `*_symbols.toml`.
2. Adds `input wire interrupt` to the generated Verilog module port list.
3. Wires `.interrupt_address(N'd<addr>)` in the hotstate instantiation instead of
   tying the interrupt address to zero.
4. The generated testbench declares `reg interrupt` and connects it to the DUT.

Only one function may be marked `__attribute__((interrupt))` per compilation unit.
The ISR is compiled like a normal subroutine and returns via the implicit `rtn`
instruction at the end of the function body.

### 7.2 Hardware interrupt timing

The hardware detects the **rising edge** of the `interrupt` input:

```
fired = interrupt && !interrupt_r
```

When `fired` is true, the return address is pushed onto the stack and execution
jumps to `INTERRUPT_ADDR`.  The ISR runs to completion, then the `rtn`
instruction pops the return address and resumes the main program.

**Important:** interrupts are not masked while the ISR is running.  A second rising
edge during the ISR will re-enter it, consuming another stack level.  If re-entrancy
is undesirable, keep the ISR short.

### 7.3 Interrupt latency

Interrupt latency is **one clock cycle** — the hardware detects the rising edge and
redirects execution in the very next cycle.  This makes the Hotstate ISR mechanism
suitable for tight real-time response.

### 7.4 Multi-edge ISR design

When the `interrupt` input is driven by an edge detector that fires on
transitions of **multiple** signals (e.g., both SCLK and CS_N edges), the ISR
must disambiguate which edge fired by reading the current signal values.

**Pitfall:** On a CS_N falling edge, other signals may be at their idle levels.
For example, in SPI Mode 0, SCLK is idle-low.  If the ISR uses `if (sclk_in)`
to distinguish rising vs. falling SCLK edges, a CS_N falling edge will
spuriously enter the `!sclk_in` (falling-edge) path because `sclk_in` is 0.

**Recommended pattern:** Process signal edges **before** protocol-edge setup.
Use a state flag (e.g., `xfer_active`) to gate signal processing so that the
first protocol edge (CS_N assertion) sets up the flag without accidentally
processing idle-level signals:

```c
bool xfer_active = 0;

__attribute__((interrupt))
void on_edge() {
    // Signal processing — gated by xfer_active.
    // On CS_N falling edge, xfer_active is still 0, so this is skipped.
    if (xfer_active) {
        if (sclk_in) {
            // rising SCLK: sample data
        } else {
            // falling SCLK: prepare next bit
        }
    }

    // Protocol edge processing — runs regardless.
    if (!cs_n_in) {
        if (!xfer_active) {
            xfer_active = 1;   // start transfer
        }
    } else {
        if (xfer_active) {
            xfer_active = 0;   // end transfer
        }
    }
}

void main() {
    while (1) {}
}
```

### 7.5 Avoiding tight polling loops with ISRs

In `.stim` files the `interrupt` signal is a named keyword, just like any other input:

```
# Pulse interrupt high for one cycle at cycle 10
10 interrupt=1
11 interrupt=0
```

The `generate_verilog_stimulus.py` script handles `interrupt` automatically — it
appears in the generated `user_tb.v` alongside ordinary inputs.

### 7.6 Timing recommendation — hold, don't pulse

The Hotstate polling loop checks a signal approximately every 2 cycles (branch +
loop-back).  A 1-cycle pulse on `interrupt` is guaranteed to be caught because the
hardware detects the edge in hardware, not by polling.  However, if you are driving
the `interrupt` input from another piece of logic that uses a 1-cycle pulse, the
rising edge must be **stable for at least one full clock period** to be reliably
captured.

### 7.7 Complete ISR example

```c
/* state outputs */
bool led0      = 0;
bool irq_count = 0;
bool irq_flag  = 0;

/* normal input */
bool btn;

/* ISR — called by hardware on rising edge of 'interrupt' input */
__attribute__((interrupt))
void isr() {
    irq_flag  = 1;    /* 1-step pulse visible on output */
    irq_flag  = 0;
    irq_count = !irq_count;   /* toggles on every interrupt */
}

void step() {
    led0 = 1;
    led0 = 0;
}

int main() {
    while (1) { step(); }
    return 0;
}
```

---

## 8. Timing and cycle counts

Each hotc C statement maps to a fixed number of microcode instructions (clock cycles):

| C construct | Cycles (approx.) |
|---|---|
| Simple assignment `x = y;` | 1 |
| Comma-separated assignments `a = 1, b = 0;` | 1 (all packed into one instruction — see §4.8) |
| Conditional `if (cond)` | 1 (branch instruction) |
| `else` branch | +1 (forced jump at end of then-body) |
| Function call | 1 (call) + body + 1 (return) |
| `while (cond)` header | 1 (branch) + 1 (forced jump back) |
| `switch` dispatch | 1 (index into jump table; +1 when a range guard is emitted — see §9) |
| `for` loop, canonical timer form | timer overhead only (body cycles + 1 backedge per iteration) |
| `for` loop, non-canonical (software) | + ~2 cycles per iteration (condition branch + update) |
| Interrupt entry | 1 (redirect on rising edge, zero overhead to ISR) |
| ISR return (`rtn`) | 1 |

**The `while(1)` main loop adds 0 cycles overhead** when compiled with
`--microcode-hs-opt` (the NOP at the loop header is elided).

### 8.1 Counting cycles for a function

```c
void step() {       // addr N:
    led0 = 1;       //   N+0: state assignment (1 cycle)
    led0 = 0;       //   N+1: state assignment (1 cycle)
}                   //   N+2: implicit rtn (1 cycle)
                    // call site: 1 cycle for the call instruction
                    // Total round-trip: 5 cycles
```

### 8.2 State variables in branch conditions

When a state variable appears in a branch condition, it must be included in the
truth-table address bus.  The compiler does this automatically, but each additional
feedback variable doubles the LUT size.  With N feedback state variables and M input
bits, the LUT has `2^(N+M)` rows.

Keep the number of state variables used in conditions small for manageable LUT sizes.
Multi-bit relational comparisons (`<`, `>`, `<=`, `>=`, `==`, `!=`) are automatically
lowered to Verilog comparator wires and contribute only 1 bit each to the truth-table —
see [Section 12.9](#129-multi-bit-comparisons-in-if--while-conditions-comparator-wires).

---

## 9. Switch statements

`switch` on a `char` or `_BitInt(N)` variable uses the hardware jump table.  The
switch variable value is used as a direct index into the table, so dispatch to any
case costs exactly 1 cycle regardless of how many cases exist.

```c
char opcode;   /* input: 8-bit opcode */

void decode() {
    switch (opcode) {
    case 0x10: { is_load  = 1; break; }
    case 0x20: { is_store = 1; break; }
    case 0x30: { is_alu   = 1; break; }
    default:   { break; }
    }
}
```

**Switch table size** is determined automatically from the **largest case label**
across all switches in the program (one global table size): labels up to 0x33
produce a 64-entry table, regardless of whether the switch variable is 8 or 32
bits wide.  Use `--switch-bits N` to override; setting it below what the largest
case label needs is a compile error (the label could not be routed).

**Range guard:** when the switch variable is wider than the table, the compiler
emits an unsigned bounds check (`var < table_size`) before the dispatch, routing
out-of-range runtime values to `default` — the hardware truncates the index at
the port, so without the guard such values would alias into a case.  The guard
costs one extra cycle on every dispatch of that switch.

**Fall-through** (`case` without `break`) is supported.

**Case fusion (`--microcode-hs-opt`):** a case body of exactly
`var = <literal>; break;` is fused into a single instruction (assignment and
jump together).  Bodies with a non-literal right-hand side (`result = result +
5; break;`), multiple statements, or fall-through emit through the regular path.

---

## 10. For loops and timers

`for` loops in the canonical form — with a compile-time-constant or extern-input
limit — are compiled to hardware timer resources, not software counter logic.
The timer counts in hardware: no compare or increment instructions per iteration.

```c
_BitInt(6) i;     // loop variable — becomes a timer

void step() {
    for (i = 0; i < 10; i++) {
        LED0 = 1;
    }
    LED0 = 0;
}
```

The timer fires when the count reaches the limit; the compiler emits a timer-load
instruction followed by a branch that checks the done signal.

**Timer variable detection:** a variable becomes a **hardware timer** only when it
is a *pure counter*:
- It is a non-extern integer, `_BitInt(N)`, or `bool` that appears in a `for`
  loop condition **and** is written to (i.e. acts as a counter), **and**
- it is **never** used in a `while`/`do-while` condition (without the pragma —
  see the down-count while pattern in §3.4), **and**
- every `for` loop it controls is in one of the two **canonical timer forms**
  (never mixed on one counter, and the body never writes the counter):

  ```c
  for (c = 0; c < LIMIT; c = c + 1)   // UP:   LIMIT literal or extern input
  for (c = N; c > 0;     c = c - 1)   // DOWN: N a non-negative literal
  ```

  `c++`/`c--` are equally valid in the update clause of either form — the
  parser desugars both to exactly `c = c + 1`/`c = c - 1` before this
  classification runs, so the two spellings are indistinguishable to the
  compiler.

  **Up-form counters may be read in their own loop body** in assignment-RHS
  positions (`sum = sum + i`): the expression circuit substitutes the elapsed
  count (`LOADED − count`), so the body sees 0..N−1 exactly — including
  nested counters (`sum += x * y`).  Reads in conditions, array indices, or
  after the loop still demote the counter to a software state variable (a
  post-loop read needs the value N, but the count sits at 0).
  **Down-form counters may be read freely** — the raw down-count IS the C
  value, wired into comparator and expression circuits ("count-exposed");
  the loop header is a top-tested comparator on the count, so the body sees
  N..1 exactly and zero-trip (`N = 0`) works.

  Count-exposed counters appear as synthetic entries in the input listing
  (`i -> input4 (timer0 count, wire-only)`): the live count rides a
  dedicated wire consumed by comparator and expression circuits.  It is
  **not** part of `variables_bus` — even 32-bit `int` counters add zero
  vardata rows (`test/test_for_int_counter.c`) — and it **cannot be driven
  from the testbench or stimulus**: the machine drives it; or
- It is explicitly marked with `#pragma hotwright counter <name>` — this works
  on ordinary variables as well as `extern` ones (for externs it is the only
  route to timer classification; name conventions such as "timer" or "delay"
  are **not** checked).  See §3.4 for the validated pragma usage patterns,
  including the down-count while-loop counter.

The reason for the restrictions: the hardware timer counts **down** from the
loaded value and ticks by 1 — so an up-count body read, a stepped/`<=` loop, or
a loop whose bound is computed at runtime cannot be a timer.  Non-canonical
loops (`for (k = 0; k < 8; k = k + 2)`, `for (i = 0; i < computed_bound; i++)`,
...) compile as software counter loops with exact C semantics
(`test/test_computed_bound.c` locks the trip counts in;
`test/test_for_downcount.c` locks the down-form values in).

**Software counter loops:** any counter that fails the rules above compiles to an
ordinary **state variable** instead: the loop condition is re-checked each
iteration (through a hardware comparator or the condition truth table), the update
is a real expression-circuit instruction, and the value reads correctly everywhere.
This costs ~2 extra cycles per iteration compared to a hardware timer loop, and it
is what `while`-loop counters always use:

```c
_BitInt(5) i = 0;          // state variable (used in a while condition)
while (i < 8) {
    sum = sum + i;          // value read: works — i is a state variable
    i = i + 1;              // real increment instruction
}
```

**Reading a hardware timer's value is a compile error.**  An expression that reads
a pragma-marked extern timer (e.g. `x = x + tick;`) is rejected — the count is not
reachable from expression circuits.  Non-pragma counters never hit this: a
value-read makes them state variables automatically.  In particular, a `__bram`
array indexed by a loop counter (`weights[i]`) reads in correct ASCENDING order:
the index read turns the counter into a state variable, and the access takes the
state-variable BRAM path (`test/test_bram_timer_idx.c` locks the order in).

**Pragma counters compare against the RAW down-count.**  A `#pragma hotwright
counter` extern timer that appears in a comparison inside a loop body is
"count-exposed": the hardware's `count_out` is wired into the condition
machinery directly, and the timer counts DOWN from its externally loaded value.
`if (tick == N)` therefore matches when the remaining count equals N, not when
N ticks have elapsed.

**Timer reuse:** the same variable can serve as the induction variable in multiple
`for` loops.  The hardware timer is reconfigured at each loop entry.

**Extern loop limits:** use `extern _BitInt(N) ex_name` to feed a loop limit from
outside the module at runtime:

```c
extern _BitInt(6) ex_num0;
_BitInt(6) i;

void step() {
    for (i = 0; i < ex_num0; i++) {
        LED0 = 1;
    }
}
```

> **External-bound contract (raw load):** the external bound is loaded RAW into
> the down-counting timer, while compile-time-constant bounds store `limit-1` in
> the timer pool. A constant bound of N runs the body exactly N times, but an
> **external bound of N runs the body N+1 times**, and timer loops are minimum
> one-trip (a bound of 0 still runs once — the header loads the timer, the body
> executes, and only the backedge checks timer-done). Existing designs
> (e.g. `examples/systolic_array_spi`) are calibrated to this convention; drive
> `N-1` from the testbench when you need exactly N iterations.
> `test/test_ctrl_matrix.c` segment S7 encodes this contract as a regression.

---

## 11. Multi-bit variables (`_BitInt`)

`_BitInt(N)` holds an N-bit value.  `char` is a convenient alias for `_BitInt(8)`.

```c
_BitInt(4)  nibble = 0;   // 4-bit state output
_BitInt(16) wide   = 0;   // 16-bit state output
char        byte;         // 8-bit input
```

### 11.0 Signedness

Multi-bit types are **signed by default** (matching C): comparisons are emitted
with `$signed()` in the generated Verilog, so a width-N variable holding the
all-ones bit pattern is **−1**, not `2^N − 1`.  This is the classic trap:

```c
_BitInt(4) x;          // signed: range −8 .. 7
if (x == 15) { ... }   // NEVER fires — the 1111 pattern is −1, not 15
if (x > 7)   { ... }   // NEVER fires — no signed 4-bit value exceeds 7
```

Declare counters, indices, and full-scale quantities `unsigned` when you mean
raw magnitudes:

```c
unsigned _BitInt(4) u; // unsigned: range 0 .. 15
if (u == 15) { ... }   // fires at full scale
unsigned char level;   // 0 .. 255
if (level > 200) { ... }
```

`unsigned` is accepted on `char`, `int`, and `_BitInt(N)` for state variables,
inputs, extern inputs, and function parameters.  A comparison is **unsigned when
either operand is unsigned** (mirroring C's usual arithmetic conversions at equal
rank).

**Negative literals** are supported (unary minus on a numeric literal only):

```c
_BitInt(8) w = -3;       // negative initializer (stores the 0xFD pattern)
if (v < 0)   { ... }     // the sign test
if (s == -1) { ... }     // sentinel compare
```

Negation of *variables* is not supported — write `0 - x` (the ordinary
subtractor circuit).  Negatives are rejected where they are meaningless:
comparisons against unsigned operands, for-loop bounds, `case` labels, and bit
indices are all compile errors.

Arithmetic (`+`, `-`, `*`, `<<`) operates on raw bit patterns and wraps at the
declared width, giving identical results for signed and unsigned operands —
the *value* those bits represent only diverges once an operation looks past
the raw pattern: right-shift (fill direction) and division/modulo (rounding
direction). Both are sign-aware: `>>` on a signed operand emits an arithmetic
(sign-filling) shift, and `/`/`%` truncate toward zero with the remainder
taking the dividend's sign (C semantics, not floor division) — see §11.2 for
the compiled Verilog form (`>>>`, `$signed()`-wrapped operands). Comparisons
(`< <= > >= == !=`), whether in a branch condition or a plain assignment
(`bool ok = a < b;`), are also sign-aware when at least one identifier
operand is signed.

The one caveat that still applies uniformly: mixing a signed and an unsigned
identifier directly in the *same* operator (e.g. `signed_var + unsigned_var`)
resolves that operator as unsigned as a whole — matching C's own "usual
arithmetic conversions" ambiguity and Verilog's own any-unsigned-operand-
taints-the-whole-expression rule (IEEE 1800 §11.8.1) — rather than promoting
the unsigned operand to signed. If you need a genuinely signed result from
mixed-signedness inputs, assign the unsigned operand to a signed intermediate
of the same width first.

`test/test_unsigned.c` encodes the branch-condition comparator semantics as a
regression; `test/test_signed_arith.c`, `test/test_division_signed.c`, and
`test/test_signed_cmp.c` cover signed arithmetic, division, and RHS-expression
comparisons respectively.

### 11.1 Bit indexing

Individual bits of a `_BitInt` variable can be read and written using array-index
notation:

```c
_BitInt(8) data = 0;

data[0] = 1;           // set bit 0
data[7] = 0;           // clear bit 7
bool b = data[3];      // read bit 3
```

### 11.2 Expressions

Bitwise operations between `_BitInt` variables generate dedicated combinatorial
expression circuits in the template:

```c
_BitInt(8) a;          // input
_BitInt(8) b;          // input
_BitInt(8) result = 0; // output

result = a & b;        // AND circuit
result = a | b;        // OR circuit
result = a ^ b;        // XOR circuit
```

**Width truncation matches real hardware.** Arithmetic/shift results are truncated to
the width of whatever they're ultimately assigned to (Verilog's context-determined size
propagation), not to the operands' own width:

```c
_BitInt(8) a, b;                // 8-bit inputs
_BitInt(8)  narrow = 0;
_BitInt(16) wide   = 0;

narrow = (a + b) >> 1;  // (a+b) truncates to 8 bits BEFORE the shift: a=b=255 -> 127
wide   = (a + b) >> 1;  // no truncation (16-bit target has headroom): a=b=255 -> 255
```

If you need headroom for an intermediate sum, widen the *assignment target*, not just
the operands — `hotstate_sim` reproduces this truncation exactly (matching real
Verilator-synthesized hardware), so `compare_c`-style validation will catch a
mismatch if you get the width wrong.

If the *final* result must stay narrow but an intermediate step needs more headroom
(e.g. averaging three 8-bit values needs up to 10 bits for the sum, even though the
average always fits in 8), plain C has no cast syntax for this — declare an
intermediate wider `_BitInt` variable instead:

```c
unsigned _BitInt(10) sum10 = 0;
unsigned _BitInt(8)  avg3  = 0;

sum10 = a + b + c;   // computed at 10 bits (sum10's own declared width)
avg3  = sum10 / 3;   // narrows back down, correctly
```

The `.hasm`/`#pragma hotwright intrinsic` expression grammar has an equivalent
single-line form, `zext(<expr>, <width>)` — see `docs/microassembly.md` §2.3. It is
not available in plain C expressions; use the intermediate-variable idiom above there.

**Saturating arithmetic (`--saturate`).** By default `+`, `-`, and `*` wrap on
overflow (two's-complement truncation, as shown above). Passing `--saturate` on the
command line changes this: instead of wrapping, `+`/`-`/`*` clamp to the destination
type's representable range (`0..2^N-1` for `unsigned _BitInt(N)`, `-2^(N-1)..2^(N-1)-1`
for signed) — e.g. `unsigned _BitInt(8) x = 200 + 100;` gives `255`, not the wrapped
`44`. It's a global flag (like `--opt`), not a per-variable qualifier, but its effect
is scoped to plain scalar assignment RHS only (`x = a + b;`): it does **not** apply to
array/BRAM writes, function return values (`--hw-stack`), intrinsic call arguments, or
the condition of a `? :` — those keep wrapping regardless. Not supported on a
`_BitInt` wider than 32 bits (rejected at compile time). See `test/test_saturate.c`
for a worked example of every combination.

**Fixed-point math** is not a distinct hotc feature — it's the same
intermediate-variable idiom applied to a Q-format multiply. `hotc` has no
built-in notion of a fixed-point *type* or a `typedef` to build one with; the
binary point is purely a convention in how you interpret a plain `_BitInt`'s
bits, same as in C. `#define`, which hotc's preprocessor does support, is
enough to document that convention in the type name itself — the `Q(m,n)`
suffix on both the macro and the variable names below — rather than only in
a comment. Multiplying two Q(m,n) values produces a Q(2m,2n) product before
rescaling:

```c
#define Q0_8  unsigned _BitInt(8)    // Q(0,8): 8-bit fraction, value = raw/256.0
#define Q0_16 unsigned _BitInt(16)   // Q(0,16), same convention, doubled width

Q0_8  a_q0_8     = 200;   // 0.78125
Q0_8  b_q0_8     = 230;   // 0.89844
Q0_16 prod_q0_16 = 0;     // full 16-bit product, nothing lost
Q0_8  result_q0_8 = 0;    // Q(0,8) again after rescaling

prod_q0_16  = a_q0_8 * b_q0_8;    // computed at 16 bits (prod's own declared
                                   // width): 200*230=46000
result_q0_8 = prod_q0_16 >> 8;    // rescale back to Q(0,8): divide by 256 -> 179
```

This is pure naming convention — hotc does not check that a `Q0_8` value is
only ever combined with another `Q0_8` value; get the scaling wrong and it
silently computes a wrong-but-plausible number, same as any other C-like
language without a real fixed-point type. Pick one consistent scheme per
project; the macro name and variable-name suffix both carrying the format
means a reader (or a `grep`) can see which values share a scale without
tracing back to a declaration comment.

The narrower single-line form `result_q0_8 = (a_q0_8 * b_q0_8) >> 8;` is
**not** a fixed-point-specific hazard — it's exactly the same width-truncation
rule demonstrated above for `+`: if `result_q0_8`'s own declared width is too
narrow to hold the full product *before* the shift (e.g. this were assigned
to another 8-bit variable directly, not to the 16-bit `prod_q0_16` above),
the product truncates first and the shift operates on already-lost bits.
Route through a wide-enough intermediate variable, exactly as with the
`sum10`/`avg3` example above.

**Rounding.** Plain `>>` truncates (rounds toward zero for unsigned, toward
negative infinity for signed — see §11.0). Round-to-nearest needs no new
feature, just the standard bias-before-shift idiom, expressed with an
intermediate variable the same way:

```c
unsigned _BitInt(17) biased = 0;
Q0_8 rounded_q0_8 = 0;

biased        = prod_q0_16 + 128;   // + (1 << (n-1)) for n=8: half an LSB of bias
rounded_q0_8  = biased >> 8;        // round-to-nearest instead of truncate:
                                      // 179 -> 180 (frac byte 176/256 >= half)
```

A `--saturate` compiler flag for saturating (clamp-on-overflow) arithmetic
instead of wraparound is tracked as future work, not available today. It
does not change what's expressible now — the intermediate-wider-variable
idiom above already avoids the overflow it would guard against, at the cost
of writing the headroom explicitly rather than having the compiler clamp for
you.

**Division and modulo (`/`, `%`).** Both operators are supported between
`_BitInt`/`char`/`int` operands, signed or unsigned. A signed `/`/`%` (either
operand signed, `_BitInt` is signed by default) truncates toward zero with the
remainder taking the dividend's sign, matching C — not Python-style floor
division:

```c
unsigned _BitInt(8) a, b;       // inputs
unsigned _BitInt(8) q = 0;

q = a / b;    // unsigned: ordinary magnitude division
q = a % 10;   // literal operands don't affect unsigned-ness

_BitInt(8) s = -17;
_BitInt(8) t = 5;
_BitInt(8) sq = s / t;  // -17 / 5 = -3 (truncate toward zero, not -4)
_BitInt(8) sr = s % t;  // -17 % 5 = -2 (remainder takes s's sign)
```

Mixing a signed and an unsigned operand directly in the *same* `/`/`%`
resolves that operation as unsigned as a whole (see the general
signed/unsigned-mixing caveat in §11.0) — it does not reject the program, but
it does mean the signed operand's raw bit pattern is used as an unsigned
magnitude, not its negative value.

Two caveats to know about:
- **Divide-by-zero diverges between software and hardware.** `hotstate_sim`
  defines `x / 0` and `x % 0` as `0`. Real Verilog `/`/`%` by zero evaluates to
  `'x` (unknown) — most simulators resolve `'x` to a fixed bit pattern, but it
  is not guaranteed to be `0`. If a divisor can legitimately be zero at
  runtime, guard it explicitly (`result = (b == 0) ? 0 : a / b;`) rather than
  relying on either tool's default.
- **Wide combinational division is a real synthesis-timing risk.** Every `/`/`%`
  here compiles to a single-cycle combinational divider circuit. This codebase
  has never shipped a wide combinational divider anywhere else — the existing
  precedent (`examples/RV32IM_hotstate/divider/`) is a 32-cycle *sequenced*
  division state machine specifically to avoid that risk. For operand widths
  much beyond 16 bits, prefer a multi-cycle sequenced divider (following that
  example's pattern) over a single combinational `/`.

### 11.3 Static const ROM arrays

Constant lookup tables can be declared as `static const _BitInt(N)` arrays.  The
compiler embeds them as ROM in the generated Verilog, and the row is selected
combinatorially at runtime:

```c
static const _BitInt(15) programs[4][14] = {
    { 0x0001, 0x0002, ... },   // program 0
    { 0x0010, 0x0020, ... },   // program 1
    ...
};

_BitInt(2) shader_program;    // runtime row selector (input)
_BitInt(15) word0 = 0;        // state: loaded from ROM

word0 = programs[shader_program][0];   // column 0 selected at compile time
```

Both the row and column indices may be runtime variables.  The compiler flattens
2D arrays into 1D ROMs and computes the index as `{row, col}` (concatenation,
equivalent to `row * stride + col`):

```c
word0 = programs[shader_program][word_idx];  // both indices runtime variables
```

### 11.4 Synchronous ROM arrays (`__bram`)

By default, a `static const _BitInt(N)` array is implemented as a distributed LUT
(asynchronous combinatorial read).  For large tables this wastes LUT fabric.  Adding
the `__bram` qualifier switches to a **synchronous registered read**, which synthesis
tools automatically map to block RAM:

```c
// Without __bram: distributed LUT, combinatorial (async) read
static const _BitInt(8) palette[256];

// With __bram: registered read, synthesis infers BRAM
__bram static const _BitInt(8) palette[256];
```

The C programmer writes `result = palette[idx]` identically in both cases.
The only change is the qualifier — the compiler handles all timing automatically.

#### 1-cycle address-to-data latency

Block RAM has a registered output: the data corresponding to address `idx` does not
appear until the clock edge **after** `idx` is presented.  The compiler inserts a
transparent latency NOP between the address write and the result capture:

```c
/* After __bram: compiler emits 2 microcode instructions per read */
result = palette[idx];
//  Instruction N  : NOP (state_capture=0) — address idx held in states_bus
//  Instruction N+1: capture (state_capture=1, exprSel=K) — result captured from BRAM output
```

The programmer never sees or manages this NOP.  Writing `result = palette[idx]` is all
that is required.

#### When the index is a state variable

If `idx` is a state variable (set in a prior statement), the compiler reads the address
directly from `states_bus`, which is a registered output and therefore already stable
for the duration of the NOP cycle:

```c
__bram static const _BitInt(8) weights[64];
_BitInt(6) addr = 0;     // state variable
_BitInt(8) val  = 0;     // state variable

void step() {
    addr = addr_in;        // latch address (states_bus updated this cycle)
    val  = weights[addr];  // NOP + capture; states_bus[addr] stays stable
}
```

If `idx` is an `extern` input variable, the address is taken directly from the input
bus:

```c
__bram static const _BitInt(8) lut[256];
extern _BitInt(8) idx_in;
_BitInt(8) out = 0;

void step() {
    out = lut[idx_in];   // NOP + capture; idx_in is stable external input
}
```

#### Generated Verilog

```verilog
// Without __bram (default) — combinatorial, synthesis uses LUTs
reg [7:0] palette_rom [0:255];
assign expr_1_raw = palette_rom[idx];

// With __bram — registered, synthesis infers BRAM
reg [7:0] palette_rom [0:255];
always @(posedge clk) expr_1_raw <= palette_rom[idx];
```

#### When to use `__bram`

| Table size | Recommendation |
|---|---|
| ≤ 64 entries | Default (LUT) is fine — no qualifier needed |
| 64–512 entries | Consider `__bram` to reduce LUT pressure |
| > 512 entries | Use `__bram`; distributed LUT would be impractical |

For neural-network weight tables (hundreds to thousands of entries) `__bram` is
almost always the right choice.

#### Optimizer compatibility

Both `--opt` and `--microcode-hs-opt` are `__bram`-aware and will not collapse or
fuse the mandatory NOP cycle away.

---

### 11.5 Writable BRAM arrays

A `static _BitInt(N)` array **without `const` and without an initializer** declares
a **dual-port synchronous BRAM** — an array whose contents can be written and read
at runtime:

```c
static _BitInt(8) regfile[8];   // 8-entry × 8-bit dual-port BRAM
```

The compiler auto-generates a write-enable state variable (`regfile__wr_en`) and
emits the appropriate Verilog; you never declare or manage `wr_en` yourself.

#### Write operation

An indexed assignment writes a value into the BRAM:

```c
regfile[wr_addr] = wr_data;   // 2 microcode instructions
//  Instruction N  : wr_en = 1 — BRAM sees address + data on states_bus
//  Instruction N+1: wr_en = 0 — BRAM write commits at this clock edge
```

The write takes exactly **2 clock cycles**.  The BRAM write commits at the clock edge
that clears `wr_en` (when both `wr_addr` and `wr_data` are stable in `states_bus`).

**Computed write addresses are supported.**  The write index and data can be any
expression the compiler can render — identifiers, literals, and arithmetic on
state/extern variables:

```c
mem[a * 4 + b] = 77;          // computed address, literal data
mem[x] = y + 1;               // simple address, computed data
```

The compiler renders the address and data expressions into the generated Verilog
write port (e.g., `mem_bram[((states_bus[1:0]) * (4)) + (states_bus[3:2])] <= 8'd77;`).
The combinational address/data are stable during the `wr_en` pulse because they derive
from registered state bits — same timing argument as the read port.

**Multiple write sites to the same array** must use identical address and data
expressions.  If two sites write to different computed indices (e.g.,
`mem[a * 4 + b] = 77` and `mem[x] = 99`), the compiler produces a hard error:

```
Error: writable array 'mem' has conflicting write address expressions:
  '((states_bus[1:0]) * (4'd4)) + (states_bus[3:2])' vs 'states_bus[5:4]'.
  Use a staging state variable to unify.
```

To fix: write the computed index into a state variable first, then use that
variable at all write sites:

```c
_BitInt(6) staging_idx = 0;
_BitInt(8) staging_val = 0;

void step() {
    if (cond) {
        staging_idx = a * 4 + b;
        staging_val = 77;
        mem[staging_idx] = staging_val;
    } else {
        staging_idx = x;
        staging_val = 99;
        mem[staging_idx] = staging_val;
    }
}
```

> [!NOTE]
> **Optimizer Safety**: The compiler's AST and SSA optimizer passes are aware of BRAM indexing variables and will not fold/inline `staging_idx` or `staging_val` back into the write sites if doing so would re-create conflicting write expressions.

#### Emulating 2D Writable Arrays

While constant ROMs (`static const`) support multi-dimensional indices natively, writable BRAM arrays must be declared as 1D arrays. However, because computed write addresses are fully supported, you can easily emulate a 2D writable array by manually flattening it:

```c
static _BitInt(8) ram_2d[64]; // Emulates an 8x8 2D BRAM

void step() {
    _BitInt(3) row = row_in;
    _BitInt(3) col = col_in;
    
    // Write value using computed 2D-to-1D index
    ram_2d[row * 8 + col] = data_in;
}
```

#### Read operation

An indexed read returns a value from the BRAM:

```c
rd_result = regfile[rd_addr];  // 2 microcode instructions
//  Instruction N  : NOP (state_capture=0) — address rd_addr held in states_bus
//  Instruction N+1: capture — rd_result captured from BRAM registered output
```

This is identical to a `__bram` const-ROM read: NOP then capture, 1-cycle latency,
transparent to the programmer.

#### Write-first semantics

When `wr_addr == rd_addr` within the same `step()` call, the **read sees the newly
written value** — not the old one.  The NOP after `wr_en = 0` gives the BRAM time to
update before the read capture fires:

```c
static _BitInt(8) mem[8];
_BitInt(3) addr = 0;
_BitInt(8) val  = 0;

void step() {
    mem[addr] = 99;       // write 99 to slot addr (wr_en=1, wr_en=0)
    val = mem[addr];      // read slot addr → val == 99 (write-first)
}
```

In hardware: write commits at clock edge C, NOP at D lets the BRAM output settle,
capture at E reads the updated value.

#### Full example — 8-entry register file

```c
// regfile.c — simple dual-port register file
static _BitInt(8) regfile[8];    // 8 × 8-bit BRAM

_BitInt(3) wr_addr = 0;          // write address (state)
_BitInt(8) wr_data = 0;          // write data (state)
_BitInt(3) rd_addr = 0;          // read address (state)
_BitInt(8) rd_result = 0;        // read result (state output)

extern _BitInt(3) wr_addr_in;    // write address input
extern _BitInt(8) wr_data_in;    // write data input
extern _BitInt(3) rd_addr_in;    // read address input

void step() {
    // Latch inputs into state variables
    wr_addr = wr_addr_in;
    wr_data = wr_data_in;
    rd_addr = rd_addr_in;

    // Write phase: store wr_data at wr_addr (2 instructions)
    regfile[wr_addr] = wr_data;

    // Read phase: read rd_addr (NOP + capture; write-first if same addr)
    rd_result = regfile[rd_addr];
}

void main() {
    while (1) { step(); }
}
```

Compile with:

```bash
hotc regfile.c --microcode-hs --all-hdl
```

Generated Verilog in `*_template.v` (key sections):

```verilog
// Auto-generated dual-port BRAM
reg [7:0] regfile_bram [0:7];

// Write port: fires when wr_en state bit is high
always @(posedge clk) begin
    if (states_bus[22])                          // regfile__wr_en
        regfile_bram[states_bus[2:0]] <= states_bus[10:3];  // wr_addr, wr_data
end

// Read port: registered (1-cycle latency)
always @(posedge clk)
    expr_4_raw <= regfile_bram[states_bus[13:11]];          // rd_addr → rd_result
```

The state-bit ranges (`[22]`, `[2:0]`, `[10:3]`, `[13:11]`) are determined
automatically by the compiler from the order variables are assigned state numbers.

#### Limitations

- **No read-modify-write in a single step**: `arr[i] = arr[i] + 1` does not work
  because the read NOP and write sequence cannot be overlapped.  Use a separate
  state variable as a staging register:
  ```c
  _BitInt(8) tmp = 0;
  tmp    = arr[i];       // NOP + capture into tmp
  tmp    = tmp + 1;      // modify in register (combinatorial expression)
  arr[i] = tmp;          // write back (wr_en=1, wr_en=0)
  ```
  This takes 4 instructions per read-modify-write cycle.

- **One active write per step**: only one writable array write per step() call is
  supported in a single sequential flow.  Writing the same array twice in one step
  is fine (the second write overwrites the first); writing two different arrays in
  one step works — each gets its own `wr_en` state bit.

- **Separate read and write ports**: this is a **dual-port** BRAM.  Read and write
  happen simultaneously with independent addresses.  There is no single-port mode.

#### `__bram` on writable arrays (synthesis hint, no timing change)

The `__bram` qualifier (§11.4) also works on writable arrays, as a pure
**synthesis hint**:

```c
__bram static _BitInt(8) grid[1024];   // request real block RAM over distributed LUTRAM
```

Unlike const ROM arrays, a writable array's read port is *already* a registered
`always @(posedge clk) ... <= arr[addr];` regardless of `__bram` — the NOP+capture
read sequence (§ above) is unconditional for every writable array. So `__bram` here
changes **no instruction timing at all**; it only adds a `(* ram_style = "block" *)`
attribute to the generated Verilog declaration, steering synthesis toward real block
RAM (BSRAM) instead of the default distributed-LUT RAM inference.

This matters for **large writable arrays** (hundreds to thousands of entries, or
several such arrays in one design): default inference maps each one to small
distributed-RAM primitives (e.g. Gowin's `RAM16SDP4`), and a design with a couple of
1024-entry writable arrays can exhaust that scarce resource on a small FPGA even
though the LUT budget and block-RAM budget both have plenty of headroom (found via
`examples/gol-hotstate`'s two 1024-entry grid buffers on a Tang Nano 9K: two
unmarked arrays needed 259/270 of the device's `RAM16SDP4` primitives and failed to
place; marking them `__bram` dropped that to 3/270, with block RAM usage rising from
9/26 to 13/26).

Same size guidance as §11.4's table applies. Leave small/default writable arrays
unmarked — forcing a tiny array into a whole block-RAM primitive just wastes it.

### 11.6 N-input reduction: `__argmax` / `__argmin`

`__argmax(idx_out, val_out, v0, v1, ..., vN)` and `__argmin(idx_out, val_out, v0,
..., vN)` compute the index and value of the winning candidate among N `_BitInt`
expressions in one call, via a combinational balanced-tournament comparator tree
(not a sequential scan — one settled result per cycle):

```c
_BitInt(6) v0, v1, v2, v3;
_BitInt(2) max_idx = 0;
_BitInt(6) max_val = 0;

__argmax(max_idx, max_val, v0, v1, v2, v3);   // max_idx/max_val settle combinationally
```

Like `__send`/`__recv`, these look like function calls but are recognized by name
and expanded by the compiler — they are not routed through user-defined
`.intrinsic`/`#pragma hotwright intrinsic` templates (see
`plans/argmax_argmin_intrinsics_plan.md`'s "Status: shipped" section for why: the
mechanism needs two output parameters plus internal storage-aliasing that the
single-return-value `.intrinsic` model has no way to express).

**Tie-breaking**: the first (lowest-index) candidate wins on an exact tie, matching
a naive left-to-right sequential `>`/`<` scan. Verified against a naive-reference
differential test across N ∈ {2, 3, 4, 5} with random inputs and deliberate ties
(174/174 trials passed) — see the plan doc for details.

**Known limitation — keep total candidate bits under 32.** `IP/variable.sv` has a
pre-existing sizing bug at exactly 32 total raw input bits (unrelated to
`__argmax`/`__argmin`, not fixed). Four 8-bit candidates (the most natural first
choice) lands exactly on this boundary and will fail with an opaque `$readmem`
out-of-bounds error. Use narrower candidate widths (`examples/argmax_demo/` uses
6-bit candidates for 4 inputs) or fewer candidates if you need full 8-bit range.

**Gate-count caveat**: the emitted Verilog *text* duplicates each tournament
level's comparison condition (once to select the index, once to select the value),
so it is not literally an N-1-comparator circuit as written — the true
N-1-comparator hardware realization depends on synthesis common-subexpression
elimination collapsing the duplicated (textually identical) conditions, which
mainstream synthesis tools do but this compiler does not do itself.

See `examples/argmax_demo/` for a complete worked example.

### 11.7 Multi-output computations without a builtin: the "settle, then derive" pattern

`__argmax`/`__argmin` (§11.6) are compiler builtins because they pack two outputs
into one clock cycle — which requires the compiler-internal packed-state-variable/
aliasing mechanism described in `plans/argmax_argmin_intrinsics_plan.md`. **If you
don't need the 1-cycle guarantee, you don't need a builtin at all**: any
"compute several related outputs from the same inputs" problem can be written in
plain, already-supported C by settling one output per statement, where each
statement after the first is a pure function of already-settled state:

```c
_BitInt(6) v0, v1, v2, v3;
_BitInt(6) max_val = 0;
_BitInt(2) max_idx = 0;

void main() {
    while (1) {
        // Statement 1: settle the value (a plain nested-ternary tournament
        // expression — arbitrary N, one cycle, no builtin involved).
        max_val = ((v0>=v1)?v0:v1) >= ((v2>=v3)?v2:v3)
                ? ((v0>=v1)?v0:v1) : ((v2>=v3)?v2:v3);

        // Statement 2: derive the index from the now-settled value, via an
        // equality-based priority encode. The first (lowest-index) match
        // naturally wins ties -- no tree/index-tracking needed.
        max_idx = (v0==max_val) ? 0 : (v1==max_val) ? 1 : (v2==max_val) ? 2 : 3;
    }
}
```

This is not a special case of `__argmax` — it's the general technique, and
`__argmax`'s tie-breaking behavior is a consequence of it, not something
hand-coded on top of it. It generalizes to any number of derived outputs: settle
whatever the "primary" result is first, then write each additional output as its
own single-expression statement referencing that already-settled state (and
whatever other inputs it needs).

**The tradeoff is cycles, not expressiveness.** Each statement here is one
microcode instruction, so N outputs cost N cycles. §4.8's comma operator can
now fuse independent *expression* assignments too (not just literals), but
that doesn't help *this specific* pattern: every leaf in a fused comma group
reads the same pre-group state, so `max_idx`'s expression would see the
*old* `max_val`, not the value Statement 1 just settled — the two statements
have a genuine same-cycle data dependency, which is exactly what comma
fusion excludes by design (§4.8's rules). Statements whose outputs are
independent of each other's *new* values (like `bitint_arith.c`'s six
arithmetic results) can fuse; this settle-then-derive pattern's whole point
is that Statement 2 depends on Statement 1's result, so it can't. Verified
directly (`hotstate_sim`, no `__argmax`/`__argmin` call anywhere) against a
naive sequential reference on both a tie case and a random case — bit-exact
in both, 2 cycles instead of `__argmax`'s 1.

**When to reach for this instead of a builtin (or a future `.intrinsic`
extension)**: whenever a new multi-output need comes up (e.g. "min and max
together," "value and a running count") and a 1-cycle fused result isn't required
— this pattern needs zero new compiler support, works today, and is usually the
right first thing to try before proposing a new hardcoded primitive.

---

## 12. Performance guidelines

### 12.1 Minimize state variables used in conditions

Every state variable that appears in a branch condition is added to the truth-table
address bus.  The LUT size is `2^(feedback_bits + input_bits)`.  Fewer feedback
variables → smaller LUT → faster synthesis and smaller area.

**Good:**
```c
bool a = 0;   // used only as output, never in if()/while()
```

**Costs LUT space:**
```c
bool a = 0;
if (a) { ... }    // a is now a feedback input: LUT doubles
```

The compiler automatically adds only the variables that are actually used in
conditions — you do not need to annotate anything.

### 12.2 Use `void step()` + `while(1)` structure

Factor the main logic into `step()` and call it from a `while(1)` loop.  This
separates the main-loop overhead (one forced-jump per iteration) from the step
logic, and makes cycle-counting straightforward.

### 12.3 Keep ISRs short

The ISR borrows stack space and delays the main loop for its duration.  Keep it to
a small number of assignments — set flags, toggle counters — and do heavier work in
the main loop on those flags.

```c
/* Good: ISR only sets a flag */
__attribute__((interrupt))
void isr() {
    irq_pending = 1;
}

/* Main loop handles the work */
int main() {
    while (1) {
        if (irq_pending) {
            irq_pending = 0;
            do_irq_work();
        }
        step();
    }
}
```

### 12.4 Prefer `switch` over long `if`-`else` chains

A `switch` dispatches in **one cycle** regardless of the number of cases.  An
`if`-`else if` chain costs one branch instruction per tested condition — O(N) in
the number of cases.

**Cycle count comparison — 4-case opcode dispatcher:**

```c
/* ── if-else version ──────────────────────────────── */
if      (op == LOAD)   { is_load   = 1; }
else if (op == STORE)  { is_store  = 1; }
else if (op == OP_IMM) { is_imm    = 1; }
else                   { is_r_type = 1; }
```

Microcode trace (each line = one clock cycle):

```
branch(op != LOAD,   → else-if1)    ; 1 cycle always
is_load = 1                          ; reached only if LOAD
forced_jmp to end                    ; 1 cycle if LOAD taken
branch(op != STORE,  → else-if2)    ; 1 cycle if STORE or later
is_store = 1
forced_jmp to end
branch(op != OP_IMM, → else)        ; 1 cycle if OP_IMM or later
is_imm = 1
forced_jmp to end
is_r_type = 1                        ; else — no branch needed
```

| Matched case | Cycles |
|---|---|
| LOAD (1st test) | 3 |
| STORE (2nd test) | 4 |
| OP\_IMM (3rd test) | 5 |
| OP (else) | 4 |
| **Average** | **4** |

```c
/* ── switch version ───────────────────────────────── */
switch (op) {
case LOAD:   { is_load   = 1; break; }
case STORE:  { is_store  = 1; break; }
case OP_IMM: { is_imm    = 1; break; }
default:     { is_r_type = 1; break; }
}
```

Microcode trace:

```
SWITCH(op)       ; 1 cycle — hardware jump table, any case
is_load = 1      ; 1 cycle (whichever case body is hit)
break            ; 1 cycle — forced_jmp to end
```

| Any case | Cycles |
|---|---|
| **Always** | **3** |

**For N cases:** if-else averages roughly N/2 + 2 cycles; switch is always 3 cycles
(dispatch + body + break) — 2 with `--microcode-hs-opt` when the body is a single
literal assignment (case fusion, see §9), +1 when a range guard is present.
At N = 8 (e.g., a 3-bit funct3 field) the if-else average is ~6 cycles vs.
switch's 3 — a 2× speedup.

### 12.5 Use nested `switch` for multi-field dispatch

When two fields jointly determine the operation (e.g., opcode + funct3 in RISC-V),
nest a `switch` on the inner field inside each outer `case`.  This keeps the total
dispatch cost at **2 cycles** regardless of how many outer or inner cases exist.

```c
/* ── Two-level if-else (slow) ─────────────────────── */
if (op == OP) {
    if (funct3 == 0) { alu_add = 1; }
    else if (funct3 == 1) { alu_sll = 1; }
    else if (funct3 == 2) { alu_slt = 1; }
    // … 8 cases …
} else if (op == OP_IMM) {
    if (funct3 == 0) { alu_add = 1; is_imm = 1; }
    // …
}
```

Worst-case cycles (last outer case, last inner case):
```
  9 outer branches  +  8 inner branches  +  1 body  =  18 cycles
```

```c
/* ── Nested switch (fast) ─────────────────────────── */
switch (op) {
case OP: {
    switch (funct3) {
    case 0: { alu_add = 1; break; }
    case 1: { alu_sll = 1; break; }
    // …
    }
    break;
}
case OP_IMM: {
    switch (funct3) {
    case 0: { alu_add = 1; is_imm = 1; break; }
    // …
    }
    break;
}
}
```

Any combination of (op, funct3):
```
  SWITCH(op)      ; 1 cycle
  SWITCH(funct3)  ; 1 cycle
  body            ; 1 cycle
  break           ; 1 cycle
  Total: 4 cycles (or 3 with --microcode-hs-opt fusing break)
```

The hardware allocates one jump table per `switch`; each table lookup costs exactly
one cycle (plus one for the range guard when the variable is wider than the
table — see §9).  All tables share one global size, computed automatically from
the largest case label anywhere in the program — for this decoder, label 0x33
gives 64-entry tables with no flags needed.  `--switch-bits N` overrides the
global size; it cannot be set below what the largest case label requires.

**Decode timing warning:** when a hotstate machine is used as a "decode-then-freeze"
unit (another controller drives `hlt` low only while decoding), every cycle shaved
from the decode path reduces the margin between `decode_done` firing and the next
`step()` call clearing all outputs.  If the outer controller needs N cycles to assert
`hlt` after it sees `decode_done`, the decode function must not return to its clearing
preamble in fewer than N+1 cycles after setting `decode_done`.  If `--opt` or further
optimizations reduce the path below that margin, the decoder outputs will be erased
before the controller can sample them.  See the decode-then-freeze warning under
[worked example 14.6](#146-multi-field-opcode-dispatch-if-else-vs-nested-switch)
for a concrete illustration.

### 12.6 Use `_BitInt` bit-indexing instead of masking

Direct bit indexing (`data[3] = 1`) generates a single assignment instruction.
Computing a mask and OR-ing it in would require multiple instructions.

### 12.7 Tail calls avoid stack consumption

When a function ends with a recursive or chained call, write it as a tail call so the
compiler can replace the call+return with a direct jump:

```c
void dispatch_b();

void dispatch_a() {
    ...
    dispatch_b();   // tail call — no work after this
    return;
}
```

### 12.9 Multi-bit comparisons in `if` / `while` conditions (comparator wires)

The compiler automatically lifts multi-bit relational comparisons in branch conditions
to dedicated Verilog `wire` expressions, so **`<`, `>`, `<=`, `>=`, `==`, `!=`
comparisons on `_BitInt(N)` variables are safe to use in `if` and `while` guards.**

#### How it works

When the compiler detects a relational expression whose operands are wider than 1 bit,
it generates a 1-bit comparator wire in `*_template.v` and adds that wire — not the
raw operand bits — to `variables_bus`:

```c
_BitInt(8) counter = 0;
_BitInt(8) sensor_a;    // 8-bit input
_BitInt(8) sensor_b;    // 8-bit input

void main() {
    while (1) {
        if (counter < sensor_a) out_a = 1; else out_a = 0;
        if (counter < sensor_b) out_b = 1; else out_b = 0;
        if (counter < sensor_a) out_c = 1; else out_c = 0;  // duplicate — reuses __cmp_0
        if (counter == 0)       done  = 1; else done  = 0;
        counter = counter + 1;
    }
}
```

Generated Verilog (excerpt from `*_template.v`):

```verilog
input wire [7:0] sensor_a,
input wire [7:0] sensor_b,
...
wire [7:0] counter_fb;
assign counter_fb = states_bus[7:0];

wire __cmp_0 = ($signed(counter_fb) < $signed(sensor_a));
wire __cmp_1 = ($signed(counter_fb) < $signed(sensor_b));
wire __cmp_2 = ($signed(counter_fb) == 0);

assign variables_bus = {__cmp_2, __cmp_1, __cmp_0};
```

`variables_bus` is only 3 bits wide (one bit per unique comparison), so
`*_vardata.mem` has 8 rows regardless of operand widths.

| Conditions | Without comparator wires | With comparator wires |
|---|---|---|
| `counter < sensor_a` (8+8 bits) | 65,536 rows | 2 rows |
| `counter < sensor_a && counter < sensor_b` | 65,536 rows | 4 rows |
| 3 distinct comparisons on 8-bit vars | 16,777,216 rows | 8 rows |

#### Supported operators

`<`, `>`, `<=`, `>=`, `==`, `!=`

Both operands may be `_BitInt(N)` input variables, `_BitInt(N)` state variables
(the compiler uses the existing `_fb` feedback wire), or integer constants on the
right-hand side.

#### Deduplication

When the same comparison appears multiple times, the compiler generates only one
wire and reuses it.  In the example above, `counter < sensor_a` appears twice but
produces only `__cmp_0`.

#### Remaining limitations

The following patterns are **not** handled by comparator wires and still cause
`variables_bus` to grow:

- **Raw multi-bit variable as the sole condition** — `if (counter)` where `counter`
  is `_BitInt(8)` adds all 8 bits.  Write `if (counter != 0)` instead.
- **Arithmetic in comparator operands** — `if (a + b < c)` is not supported;
  operands must be bare variable names or constants.
- **Mixed boolean + comparator in `--comparator-bypass` mode** — `if (flag && counter < limit)`
  in a single expression is not supported in bypass mode; split into a separate `if` or
  an intermediate `bool`.  (In the default mode the UberLUT handles mixed expressions
  naturally.)

#### When to use a hardware timer instead

For loops that count from 0 to a fixed or runtime limit, a hardware timer is still
the best choice — it costs **zero** `variables_bus` bits and the loop induction
variable never appears in the truth table at all.  Use comparator-wire comparisons for
non-loop conditional checks where the full relational expression is needed at an
arbitrary point in the program:

```c
// Loop to a constant — use a timer (zero vardata cost)
_BitInt(8) i;
for (i = 0; i < 100; i++) { do_work(); }

// Conditional check mid-loop — comparator wire (1 vardata bit)
if (counter < threshold) { alarm = 1; }
```

#### Software simulator note

The software simulator (`hotstate_sim`) evaluates comparator wires: comparator
definitions are emitted into the `[comparators]` section of `*_symbols.toml`
and the sim drives the synthetic `__cmp_N` input bits from them every cycle
(in both default and `--comparator-bypass` modes).  Hardware lockstep
validation is still available via the `hw_check` make target — the
`multibit_cmp` example runs both and compares settled state.

#### Bypassing the truth table entirely (`--comparator-bypass`)

By default, every unique comparator wire consumes **one bit** in `variables_bus`.
With many comparisons the bus still grows and the truth table scales as 2^(bus width):

| Comparators | `variables_bus` bits | vardata rows |
|---|---|---|
| 1 | 1 | 2 |
| 4 | 4 | 16 |
| 10 | 10 | 1,024 |
| 14 | 14 | 16,384 |

> **The 2^25 truth-table limit:** `vardata.mem` is addressed by the full
> (compacted) input bus, so it has `2^bits` rows and generation is clamped at
> **2^25**. The compiler prints a loud warning when a design exceeds the clamp:
> a clamped table evaluates conditions correctly **only while the inputs beyond
> bit 25 stay 0 at runtime** — combinations indexing past the clamp read
> garbage. Comparator-heavy designs hit this quickly (each comparator is one
> bus bit, plus any raw feedback bits); when the warning appears, either reduce
> condition inputs or compile with `--comparator-bypass`, which removes
> comparator bits from the bus entirely.

When the `--comparator-bypass` flag is added, each `__cmp_N` wire is connected
directly to a dedicated `comparators` port on the `hotstate` IP core.  A bypass mux
inside the IP selects the correct comparator result before the truth-table look-up,
so `variables_bus` carries **only the non-comparator inputs**.  For a design with
only comparator-derived conditions, the truth table collapses to a single row.

```bash
# Enable bypass mode (compatible with --microcode-hs, --microcode-hs-opt, --opt)
hotc input.c --microcode-hs-opt --comparator-bypass --all-hdl
```

**Measured impact on Tang Nano 9K (Tsetlin Clause Sequencer, 10 comparators):**

| Metric | Default (Path A) | `--comparator-bypass` (Path B) | Delta |
|---|---|---|---|
| `variables_bus` bits | 14 | 4 | −10 |
| vardata rows | 16,384 | 16 | −1,024× |
| **Total LUTs** | **984** | **869** | **−115 (−11.7%)** |
| SPX9 BRAM | 21 | 21 | 0 |

> **Note on BRAM:** The `variable` module reads its truth table using a
> combinational `assign` statement, which synthesis tools cannot map to block RAM
> (block RAM requires synchronous reads).  BRAM count is therefore zero regardless
> of table size; **all savings are LUT-only**.

**Compound conditions in bypass mode:**  `||`, `&&`, and `!` applied to comparator
wires are supported.  The compiler generates dedicated compound wires:

```verilog
wire __cmp_0 = ($signed(counter_fb) < $signed(threshold_a));
wire __cmp_1 = ($signed(counter_fb) < $signed(threshold_b));
wire __cmp_2 = (__cmp_0 || __cmp_1);   // compound OR — also on the bypass port
```

**Restriction in bypass mode:**  mixing a `bool` variable directly with a comparator
result in a single condition (e.g. `if (flag && counter < limit)`) is not supported.
Split it into nested `if`s or an intermediate `bool`.  See `examples/comparator_bypass_demo/`
for a worked demonstration including `make compare_sizes` compaction statistics.

`--comparator-bypass` is **not** compatible with `--microcode-ssa` (CFG/SSA path).

---

### 12.8 One-cycle signal pulses

To generate a single-cycle pulse on an output, write the asserted value then the
de-asserted value in consecutive statements:

```c
irq_flag = 1;   // asserted for exactly one clock cycle
irq_flag = 0;   // de-asserted the following cycle
```

If the signal's "at rest" value is its initializer (the common case), declaring
it `one_shot` (§4.9) drops the deassert instruction entirely — the hardware
auto-clears it every cycle it isn't explicitly written, so `irq_flag = 1;` alone
produces the same one-cycle pulse in one instruction instead of two.

---

## 13. Unsupported C features

The following standard C features are **not** supported by `hotc`:

| Feature | Notes |
|---|---|
| `float` / `double` | No floating-point hardware |
| Pointers (`*`, `&`) | No indirection in microcode |
| Structs / unions | Not supported |
| Arrays of variables | `static const _BitInt(N) arr[D]` → ROM (§11.3/11.4); `static _BitInt(N) arr[D]` (non-const) → writable BRAM (§11.5); dynamic/automatic arrays not supported |
| Function parameters (default) | Pass data through file-scope variables; `_BitInt(N)` params supported with `--hw-stack` (§5.3) |
| Function return values (default) | Write results to file-scope variables; `_BitInt(N)` return values supported with `--hw-stack` (§5.3) |
| `#include` of standard headers | `#include` of local `.h` files is supported |
| Dynamic memory (`malloc`) | No heap |
| Multiple compilation units sharing state | Supported via explicit `#include` of a shared header |
| Reserved port names | User variables may not be named after generated ports/wires (`clk`, `rst`, `hlt`, `ready`, `interrupt`, `states_out`, `states_bus`, `variables_bus`, ...) — compile error; the generated Verilog would have a duplicate pin |

The compiler rejects programs that use unsupported features with a clear error message.

---

## 14. Worked examples

### 14.1 Simple LED blinker

```c
bool led0 = 0;
bool btn;

void step() {
    led0 = btn;
}

int main() {
    while (1) { step(); }
    return 0;
}
```

Microcode: 3 instructions per iteration — `led0=btn` (1), loop-back (1), wait-for-rtn (1).

### 14.2 Conditional toggle

```c
bool led0 = 0;
bool go;

void step() {
    if (go) {
        led0 = !led0;
    }
}

int main() {
    while (1) { step(); }
    return 0;
}
```

Note: `led0 = !led0` feeds back through the truth table.  The compiler automatically
adds `led0` as a feedback input because it appears as a RHS operand in a branch
context.

### 14.3 Counted delay with for loop

```c
bool LED0 = 0;
_BitInt(6) i;    // timer variable

void step() {
    for (i = 0; i < 10; i++) {
        LED0 = 1;
    }
    LED0 = 0;
}

int main() {
    while (1) { step(); }
    return 0;
}
```

The `for` loop is in the canonical timer form, so it uses a hardware timer — the
body executes exactly 10 times with no compare/increment instructions (just the
body plus the timer-ticking backedge each iteration).

### 14.4 Opcode decoder with switch

```c
char opcode;   /* 8-bit input */

bool is_load  = 0;
bool is_store = 0;
bool is_alu   = 0;

void decode() {
    switch (opcode) {
    case 0x03: { is_load  = 1; is_store = 0; is_alu = 0; break; }
    case 0x23: { is_store = 1; is_load  = 0; is_alu = 0; break; }
    case 0x33: { is_alu   = 1; is_load  = 0; is_store = 0; break; }
    default:   { is_load  = 0; is_store = 0; is_alu = 0; break; }
    }
}

int main() {
    while (1) { decode(); }
    return 0;
}
```

### 14.5 ISR-driven event counter

```c
bool led0      = 0;
bool irq_count = 0;   /* toggles on each interrupt */
bool irq_flag  = 0;   /* 1-cycle pulse on interrupt */
bool btn;

__attribute__((interrupt))
void isr() {
    irq_flag  = 1;
    irq_flag  = 0;
    irq_count = !irq_count;
}

void step() {
    led0 = 1;
    led0 = 0;
}

int main() {
    while (1) { step(); }
    return 0;
}
```

The hardware interrupt fires on the rising edge of the `interrupt` input port.
The ISR runs in 3 cycles (`irq_flag=1`, `irq_flag=0`, `irq_count=!irq_count`) plus
one cycle for the return.  The main loop is not disrupted beyond those 4 cycles.

### 14.6 Multi-field opcode dispatch: if-else vs. nested switch

This example uses a simplified RISC-V-style instruction set to show the cycle
savings from replacing if-else chains with nested switch statements.

**Problem:** decode a 7-bit opcode and a 3-bit funct3 field into one-hot ALU
select signals.  There are 4 outer opcodes and up to 8 inner funct3 variants.

#### if-else version

```c
char opcode_in;         // 7-bit opcode (declared as char = 8-bit, upper bit 0)
_BitInt(3) funct3;      // 3-bit sub-field

bool alu_add = 0, alu_sub = 0, alu_and = 0, alu_or = 0;
bool alu_xor = 0, alu_sll = 0, alu_srl = 0, alu_sra = 0;
bool is_imm = 0, is_load = 0, is_store = 0;
bool decode_done = 0;

void step() {
    // clear all
    alu_add=0, alu_sub=0, alu_and=0, alu_or=0,
    alu_xor=0, alu_sll=0, alu_srl=0, alu_sra=0,
    is_imm=0, is_load=0, is_store=0, decode_done=0;

    if (opcode_in == 0x33) {           // OP (R-type)
        if      (funct3 == 0) { alu_add = 1; }
        else if (funct3 == 1) { alu_sll = 1; }
        else if (funct3 == 4) { alu_xor = 1; }
        else if (funct3 == 5) { alu_srl = 1; }
        else if (funct3 == 6) { alu_or  = 1; }
        else if (funct3 == 7) { alu_and = 1; }
        decode_done = 1;
    } else if (opcode_in == 0x13) {    // OP_IMM (I-type)
        is_imm = 1;
        if      (funct3 == 0) { alu_add = 1; }
        else if (funct3 == 4) { alu_xor = 1; }
        else if (funct3 == 6) { alu_or  = 1; }
        else if (funct3 == 7) { alu_and = 1; }
        decode_done = 1;
    } else if (opcode_in == 0x03) {    // LOAD
        is_load = 1;
        decode_done = 1;
    } else if (opcode_in == 0x23) {    // STORE
        is_store = 1;
        decode_done = 1;
    }
}
```

**Cycle counts per instruction (with `--microcode-hs-opt`):**

| Instruction type | Outer branches | Inner branches | Total dispatch cycles |
|---|---|---|---|
| OP (1st outer test) | 1 | 1–6 | **2–7** |
| OP_IMM (2nd outer) | 2 | 1–4 | **3–6** |
| LOAD (3rd outer) | 3 | — | **3** |
| STORE (4th outer) | 4 | — | **4** |
| **Worst case** | | | **~11** |
| **Average** | | | **~5–6** |

#### switch version

```c
void step() {
    // clear all (same 1-cycle parallel clear as above)
    alu_add=0, alu_sub=0, alu_and=0, alu_or=0,
    alu_xor=0, alu_sll=0, alu_srl=0, alu_sra=0,
    is_imm=0, is_load=0, is_store=0, decode_done=0;

    switch (opcode_in) {

    case 0x33: {    // OP (R-type)
        switch (funct3) {
        case 0: { alu_add = 1; break; }
        case 1: { alu_sll = 1; break; }
        case 4: { alu_xor = 1; break; }
        case 5: { alu_srl = 1; break; }
        case 6: { alu_or  = 1; break; }
        case 7: { alu_and = 1; break; }
        }
        decode_done = 1;
        break;
    }

    case 0x13: {    // OP_IMM (I-type)
        is_imm = 1;
        switch (funct3) {
        case 0: { alu_add = 1; break; }
        case 4: { alu_xor = 1; break; }
        case 6: { alu_or  = 1; break; }
        case 7: { alu_and = 1; break; }
        }
        decode_done = 1;
        break;
    }

    case 0x03: { is_load  = 1, decode_done = 1; break; }
    case 0x23: { is_store = 1, decode_done = 1; break; }
    }
}
```

**Cycle counts per instruction (with `--microcode-hs-opt`):**

| Instruction type | Outer dispatch | Inner dispatch | body | Total |
|---|---|---|---|---|
| Any OP with funct3 | 1 | 1 | 1 | **3** |
| Any OP_IMM with funct3 | 1 | 1+1 (is_imm) | 1 | **4** |
| LOAD or STORE | 1 | — | 1 | **2** |
| **Worst case** | | | | **4** |
| **Always** | | | | **2–4** |

The switch version is **2–5× faster** than the if-else version depending on opcode
and funct3 values.  With a 9-case outer switch (like the full RV32IM opcode set),
the if-else worst case climbs to ~18 cycles while the nested switch stays at 4.
(One adjustment: the 8-bit `opcode_in` is wider than the 64-entry table sized
from label 0x33, so a range guard adds +1 cycle to each outer dispatch — see §9.
The inner `_BitInt(3) funct3` fits its table and needs no guard.)

#### Compile command

```bash
# Table size is automatic: the largest case label (0x33) gives 64-entry tables.
# The 8-bit opcode_in is wider than the 6-bit table, so the compiler emits a
# range guard routing opcodes ≥ 64 to default (+1 cycle on that dispatch).
hotc decoder.c --microcode-hs-opt --all-hdl
```

#### Decode-then-freeze timing warning

If the hotstate decoder is controlled by an external "freeze" signal (`hlt`) that
another controller drives low only while decoding is needed, **do not add `--opt`**
to the compile flags.  The `--opt` pass (Pattern A) fuses `decode_done + break` into
one instruction and eliminates the `}}` NOP, reducing the gap between `decode_done`
firing and the next `step()` re-executing the clear.  If the controlling machine
needs 3 cycles to assert `hlt` after seeing `decode_done`, and `--opt` leaves only
3 cycles of margin, the clear will race the freeze — erasing the decoded signals
before they are sampled.  Use `--microcode-hs-opt` alone (without `--opt`) for
decode-then-freeze decoders.

### 14.7 Register file using writable BRAM

This example builds a minimal 8-entry × 8-bit register file: one write port and one
read port, with simultaneous read-after-write in the same `step()` call.  It
demonstrates the complete writable-BRAM workflow from C source through generated
Verilog.

#### Goal

Each clock iteration (`step()` call) the machine:
1. Writes `wr_data` to `regfile[wr_addr]`.
2. Reads `regfile[rd_addr]` into `rd_result`.

When `wr_addr == rd_addr`, `rd_result` receives the value just written (write-first).

#### C source (`regfile.c`)

```c
// regfile.c — 8-entry × 8-bit dual-port register file
//
// Every call to step():
//   Write: regfile[wr_addr] = wr_data
//   Read:  rd_result = regfile[rd_addr]
// Write-first: if wr_addr == rd_addr, rd_result sees the new value.

static _BitInt(8) regfile[8];     // 8 × 8-bit dual-port BRAM

// State variables (outputs): hold their values between steps
_BitInt(3) wr_addr  = 0;
_BitInt(8) wr_data  = 0;
_BitInt(3) rd_addr  = 0;
_BitInt(8) rd_result = 0;

// Extern inputs: driven from outside the module each clock
extern _BitInt(3) wr_addr_in;
extern _BitInt(8) wr_data_in;
extern _BitInt(3) rd_addr_in;

void step() {
    // 1. Latch inputs — 3 cycles (one assignment each)
    wr_addr = wr_addr_in;
    wr_data = wr_data_in;
    rd_addr = rd_addr_in;

    // 2. Write — 2 cycles (wr_en=1, wr_en=0)
    //    BRAM write commits at the wr_en=0 clock edge.
    regfile[wr_addr] = wr_data;

    // 3. Read — 2 cycles (NOP + capture)
    //    NOP allows BRAM output to settle; capture loads rd_result.
    //    If rd_addr == wr_addr, rd_result gets the freshly written value.
    rd_result = regfile[rd_addr];
}

void main() {
    while (1) {
        step();
    }
}
```

**Cycle budget per iteration** (with `--microcode-hs`):

| Phase | Instructions | Description |
|---|---|---|
| Call `step()` | 1 | subroutine call |
| Latch inputs | 3 | `wr_addr=`, `wr_data=`, `rd_addr=` |
| Write BRAM | 2 | `wr_en=1`, `wr_en=0` |
| Read BRAM | 2 | NOP + capture |
| Return | 1 | implicit return |
| Loop-back | 1 | `while(1)` forced jump |
| **Total** | **10** | **per step** |

#### Compilation

```bash
hotc regfile.c --microcode-hs --all-hdl
```

The compiler emits (abbreviated) microcode — use `hotc regfile.c --microcode-hs` to
see the full table:

```
Addr  Label
  8   wr_addr = expr[1]        ; latch wr_addr_in
  9   wr_data = expr[2]        ; latch wr_data_in
  A   rd_addr = expr[3]        ; latch rd_addr_in
  B   regfile[...]=...;(wr_en=1)
  C   regfile[...]=...;(wr_en=0)
  D   // bram_latency_nop      ; rd_addr stable in states_bus
  E   rd_result = expr[4]      ; capture BRAM[rd_addr]
  F   implicit_return
```

#### Key sections of generated `regfile_template.v`

```verilog
// Dual-port BRAM storage
reg [7:0] regfile_bram [0:7];

// Write port: fires on every clock where wr_en (states_bus[22]) is high
always @(posedge clk) begin
    if (states_bus[22])                             // regfile__wr_en
        regfile_bram[states_bus[2:0]] <= states_bus[10:3]; // wr_addr, wr_data
end

// Read port: registered address, 1-cycle latency
always @(posedge clk)
    expr_4_raw <= regfile_bram[states_bus[13:11]];  // rd_addr → rd_result
wire [22:0] expr_4_vec = {{1{1'b0}}, expr_4_raw, {14{1'b0}}};
```

The state-bit positions (`[22]`, `[2:0]`, `[10:3]`, `[13:11]`) come from the
sequential assignment of state numbers: `wr_addr` occupies bits 0–2, `wr_data`
3–10, `rd_addr` 11–13, `rd_result` 14–21, and the auto-generated `regfile__wr_en`
lands at bit 22 (the first free bit after all programmer-declared state variables).

#### Write-first trace

| Step | wr_addr_in | wr_data_in | rd_addr_in | rd_result |
|---|---|---|---|---|
| 0 | 3 | 0xAB | 3 | 0xAB (write-first: same address) |
| 1 | 5 | 0x42 | 3 | 0xAB (slot 3 unchanged) |
| 2 | 5 | 0x42 | 5 | 0x42 (slot 5 was written in step 1) |
| 3 | 0 | 0xFF | 5 | 0x42 (slot 5 unchanged) |

At step 0 `wr_addr == rd_addr == 3`, so `rd_result` gets `0xAB` even though the
write and read happen in the same step — write-first semantics confirmed.

#### Validation

The example in `examples/bram_rw_array/` exercises this exact pattern with an 8-entry
array, sweep of all slots, and write-first checks.  Run:

```bash
cd examples/bram_rw_array
make -f Makefile compare_c
```

This compiles the C golden reference, runs the software simulator, and checks that
`rd_result` matches at every sync point (31 points including all write-first cases).

### 14.8 Multi-layer calls with `--hw-stack`

This example validates the hardware parameter stack at its full depth: a 3-layer call
chain with a two-parameter innermost function and return values propagated at every level.
The expected result is `compute(5) = 11`.

#### C source (`examples/hw_stack/hw_stack.c`)

```c
// Call chain: main → compute(5) → double_val(n) → add(a, b)
// add(5,5)=10; double_val(5)=10; compute(5)=10+1=11

bool trigger;
bool done   = 0;
_BitInt(8) result = 0;

/* Innermost: two parameters, returns their sum */
_BitInt(8) add(_BitInt(8) a, _BitInt(8) b) {
    return a + b;
}

/* Middle layer: doubles n by calling add(n, n), returns the result */
_BitInt(8) double_val(_BitInt(8) n) {
    _BitInt(8) r = add(n, n);   /* state var n passed as both args */
    return r;
}

/* Outer layer: calls double_val, adds 1, returns */
_BitInt(8) compute(_BitInt(8) x) {
    _BitInt(8) d = double_val(x);
    return d + 1;
}

void main() {
    while (!trigger) {}
    result = compute(5);   /* expects 11 */
    done = 1;
    while (1) {}
}
```

#### Compilation

```bash
hotc hw_stack.c --microcode-hs --all-hdl --hw-stack
# Also compatible with optimization flags:
hotc hw_stack.c --microcode-hs-opt --all-hdl --hw-stack
hotc hw_stack.c --microcode-hs --opt --all-hdl --hw-stack
```

The compiler:
1. Sets `DATA_STACK_WIDTH = 8` (widest `_BitInt` found across all params and return types).
2. Allocates internal state variables for each parameter (`a`, `b`, `n`, `x`, `r`, `d`);
   these are marked `is_internal = true` in `*_symbols.toml`.
3. For each call site: pushes arguments right-to-left before `sub`; pops the return value
   after `sub` (two instructions: pop → `__retval`, copy `__retval` → destination).
4. For each function entry: pops each parameter in declaration order (two instructions per
   parameter: pop → `__retval`, copy `__retval` → param variable).
5. Before each `return` in a non-void function: pushes the return expression.

#### Key observations

- **Chained returns**: `double_val` calls `add`, captures its return value into `r`, then
  pushes `r` before its own return.  `compute` does the same with `d`.  The stack depth
  never exceeds 2 items at once because each level pops before pushing its own return.
- **State-variable arguments**: `add(n, n)` passes state variable `n` as both arguments.
  The compiler registers a push circuit for `n` mapping `states_bus[n_hi:n_lo]` to
  `[DATA_STACK_WIDTH-1:0]` so the push instruction can use `expr_sel`.
- **`--microcode-hs-opt` and `--opt` compatible**: parameter pops are emitted regardless
  of the optimize flag; only the entry NOP is suppressed in optimize mode.
- **Zero-overhead when unused**: without `--hw-stack`, instruction word width is unchanged.

#### Validation

```bash
cd examples/hw_stack
make -f Makefile sim     # software sim — checks result==11
make -f Makefile hw_sim  # Verilator hardware sim
```

The `sim` target runs the software simulator and confirms `done=1, result=11` at the
end of the trace.  The `hw_sim` target runs full Verilator RTL simulation including
`IP/data_stack.sv`.

---

## Compiler invocation reference

```bash
# Standard compilation (AST path, all outputs)
hotc input.c --microcode-hs --all-hdl

# With microcode-level optimization (recommended for production)
hotc input.c --microcode-hs-opt --all-hdl

# With AST expression simplification
hotc input.c --microcode-hs --opt --all-hdl

# Control switch table size (default: auto)
hotc input.c --microcode-hs --switch-bits 7 --all-hdl

# Multi-file compilation (functions split across files, shared declarations)
hotc main.c lib.c --microcode-hs --all-hdl

# Multi-machine system: compile N machines and generate a wiring top module
hotc machine_a.c machine_b.c machine_c.c --microcode-hs-opt --opt --all-hdl --system
# → machine_a_system.v wires all three machines; matched signals become internal
#   wires, unmatched signals become top-level ports.

# Hardware parameter stack: enable _BitInt(N) function parameters and return values
hotc input.c --microcode-hs --all-hdl --hw-stack
hotc input.c --microcode-hs --all-hdl --hw-stack --data-stack-depth 16

# Rewrite AST back to C for inspection
hotc input.c --rewrite-c
```

Key flags:

| Flag | Effect |
|---|---|
| `--microcode-hs` | AST path → CompactMicrocode (recommended) |
| `--microcode-hs-opt` | AST path with microcode-level optimization |
| `--microcode-ssa` | CFG/SSA path (alternative) |
| `--all-hdl` | Generate all output files |
| `--opt` | Enable AST expression simplification |
| `--system` | Multi-machine mode: generate `{first}_system.v` wiring all machines (see §6) |
| `--switch-bits N` | Override switch table width |
| `--stack-size N` | Hardware call-stack depth (default 4; increase for deep call chains) |
| `--comparator-bypass` | Route multi-bit comparator wires via dedicated bypass port (Path B; see §12.9) |
| `--data-width N` | Override I/O bit width (default: auto-detect) |
| `--runtime-load` | Generate runtime-swappable microcode template + loader |
| `--hw-stack` | Enable hardware parameter stack; allows `_BitInt(N)` function parameters and return values (see §5.3) |
| `--data-stack-depth N` | Data stack depth when `--hw-stack` is active (default 32; range 2–1024) |
| `--hardware` | Print hardware analysis summary |
| `--dot` | Emit CFG DOT graph |
| `--debug` | Verbose compiler debug output |
