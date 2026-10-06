// User stimulus file for dlut_uart_loader
// GENERATED AUTOMATICALLY. DO NOT EDIT DIRECTLY IF USING .stim FLOW.
// To update this file, edit ./dlut_uart_loader.stim and run:
// python3 ../../scripts/generate_verilog_stimulus.py ./dlut_uart_loader.stim ./user_tb.v
//
// ---------------------------------------------------------------------
// Signals visible to this file (it is `include`d inside module dlut_uart_loader_tb):
//
//   Drive these (reg, yours to assign):
//     reg       rx_done
//     reg [7:0] rx_byte
//     reg       tx_busy
//     reg [3:0] digit
//
//   Read these (wire, driven by the DUT):
//     wire       busy
//     wire [9:0] img_waddr
//     wire [7:0] img_wdata
//     wire       img_wen
//     wire       tx_start
//     wire [7:0] tx_data
//     wire [5:0] debug_adr      (program counter)
//     wire [28:0] states_out     (all state bits, packed)
//     wire       ready
//     wire       lhs_out
//     wire       jmp_flag_out
//     wire [5:0] jmp_bus_out
//     wire       br_out
//     wire       fj_out
//     wire [5:0] next_pc
//     wire       state_capture
//
//   Driven by the testbench itself -- do not assign:
//     clk   (toggles every 10ns)
//     rst   (released at 40ns)
//     hlt   (declared, but the DUT is instantiated with .hlt(1'b0))
//
//   Not visible here: 2 timer(s) (byte_idx, w) live inside the
//   hotstate instance and have no testbench-scope wire.
// ---------------------------------------------------------------------

initial begin
    // Initial values from .stim file will go here
    rx_done = 0;
    rx_byte = 0;
    tx_busy = 0;
    digit = 0;
end
