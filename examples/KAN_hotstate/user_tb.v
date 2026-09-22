// User stimulus file for kan_control
// GENERATED AUTOMATICALLY. DO NOT EDIT DIRECTLY IF USING .stim FLOW.
// To update this file, edit ./kan_control.stim and run:
// python3 ../../scripts/generate_verilog_stimulus.py ./kan_control.stim ./user_tb.v
//
// ---------------------------------------------------------------------
// Signals visible to this file (it is `include`d inside module kan_control_tb):
//
//   Drive these (reg, yours to assign):
//     reg       sdram_busy
//     reg [7:0] sdram_rd_byte
//     reg       rx_done
//     reg [7:0] rx_byte
//     reg       tx_busy
//
//   Read these (wire, driven by the DUT):
//     wire       sdram_wr_req
//     wire       sdram_rd_req
//     wire [22:0] sdram_addr
//     wire [7:0] sdram_wr_data
//     wire       tx_start
//     wire [7:0] tx_data
//     wire [22:0] byte_idx
//     wire [8:0] p
//     wire [7:0] q
//     wire [23:0] acc
//     wire [22:0] rd_addr
//     wire [7:0] byte_lo
//     wire [7:0] byte_hi
//     wire [15:0] combined
//     wire [13:0] weight14
//     wire [12:0] weight13
//     wire [23:0] shifted
//     wire [8:0] val
//     wire [4:0] best_class
//     wire [8:0] max_score
//     wire       in_mem__wr_en
//     wire       layer1_out__wr_en
//     wire [7:0] __arrtmp0
//     wire [7:0] __arrtmp1
//     wire [7:0] debug_adr      (program counter)
//     wire [252:0] states_out     (all state bits, packed)
//     wire       ready
//     wire       lhs_out
//     wire       jmp_flag_out
//     wire [7:0] jmp_bus_out
//     wire       br_out
//     wire       fj_out
//     wire [7:0] next_pc
//     wire       state_capture
//
//   Driven by the testbench itself -- do not assign:
//     clk   (toggles every 10ns)
//     rst   (released at 40ns)
//     hlt   (declared, but the DUT is instantiated with .hlt(1'b0))
// ---------------------------------------------------------------------

initial begin
    // Initial values from .stim file will go here
    sdram_busy = 0;
    sdram_rd_byte = 0;
    rx_done = 0;
    rx_byte = 0;
    tx_busy = 0;
end
