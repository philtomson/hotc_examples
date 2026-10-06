// On-chip logic analyzer: disabled. `ILA_ENABLE` stays undefined, which
// compiles out the debug-capture code in top_hotstate.sv and
// npu_top_hotstate.sv (its ila_capture/ila_dump modules are not included
// in this repository).
