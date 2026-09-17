# Known issues — webserver

## Tang Nano 20K (GW2A-18C): yosys ALU-inference miscompile — preventively fixed, `-noalu`

**Status: preventive fix in place; not directly observed on this design, but the underlying bug is confirmed elsewhere.**

`Makefile.synth_tang20k` passes `synth_gowin -noalu`. This is the same
fix documented in `examples/Tsetlin_hotstate_uart/KNOWN_ISSUES.md`: yosys's
inferred ALU carry cells compute the wrong result on this specific Gowin
part (GW2AR-LV18QN88C8/I7) — RTL simulation, gate-level simulation and
static timing analysis all pass, but real silicon doesn't. Not specific to
any one design: [YosysHQ/apicula#514](https://github.com/YosysHQ/apicula/issues/514)
reports the same device computing wrong results on unrelated modular
arithmetic, with the same "everything passes except silicon" signature.

This webserver design uses 436 ALU cells (fewer than Tsetlin_hotstate_uart's
756) and has not been directly observed to fail with ALU inference enabled
— but the fault is placement-dependent (which placement breaks is a
function of where the ALU chains land, not the design itself), so "hasn't
failed in the placements tried" is not the same as "immune." The flag is
applied preventively rather than only after a failure is reproduced here.

If you remove `-noalu` for any reason, re-verify against real hardware
(both routes, `/s` and at least one LED toggle) rather than trusting
simulation or static timing — neither would have caught this bug.

## Real bugs found and fixed while bringing this example up

Both already fixed in what's checked in here; documented for context since
they're the kind of thing worth checking first if something *else* in a
similar hotstate design goes silently wrong later.

- **`response_streamer.v`'s hand-written FSM (`state` register)**: yosys's
  automatic FSM extraction/re-encoding pass (run by default inside
  `synth_gowin`) mis-handled it — design simulated correctly in Verilator
  but was completely silent on real hardware (`http_server` correctly
  parsed requests and pulsed `tx_start`, but `response_streamer`'s FSM
  never left `IDLE`). Fixed with `(* fsm_encoding = "none" *)` on the
  `state` declaration, opting it out of that pass. If you see a "sim is
  clean but hardware is silent" symptom on a hand-written FSM elsewhere,
  check this first.
- **`bridge.py` truncating/corrupting real (multi-header) browser
  requests**, reproducibly around a ~68-OK/~84-corrupt byte threshold —
  not an FPGA bug. Root cause: the FTDI USB-serial chip's onboard TX
  buffer overflowing on a single fast unpaced `ser.write()` of a long
  request; pacing writes 2ms apart made it disappear. Fixed by chunking
  `bridge.py`'s request write into small paced pieces (see its own
  comment) instead of one big write. Short hand-crafted test requests
  never hit the threshold, which is why this went unnoticed until a real
  multi-header browser request was tried — a lesson for testing any UART
  host bridge: test with realistic payload sizes, not just short synthetic
  ones.
