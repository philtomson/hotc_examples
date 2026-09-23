// GW5A (Tang Primer 25K) stand-in for gowin_mult/gowin_mult.v: same module
// name and ports, so spatial_3x3_mac_gowin.sv is unchanged. GW5A has no
// MULT9X9; its MULT12X12 is a signed 12x12 -> 24-bit multiply (Gowin
// prim_sim.v: both inputs sign-extended, DOUT = A*B), combinational with every
// register BYPASSed. The GW2A wrapper's MULT9X9 is a signed 9x9 (B
// sign-extended from 8 bits), so sign-extending a and b to 12 bits and keeping
// the low 17 product bits is exact.
//
// Hard DSP rather than a behavioral `*` on purpose: yosys infers no DSPs for
// gw5a, and a LUT-built 9x8 multiply costs ~400 LUT4 there -- 36 of them do
// not fit the part.
module Gowin_MULT (dout, a, b);
output [16:0] dout;
input  [8:0] a;
input  [7:0] b;
wire [23:0] p;
MULT12X12 #(
    .AREG_CLK("BYPASS"), .BREG_CLK("BYPASS"),
    .PREG_CLK("BYPASS"), .OREG_CLK("BYPASS"),
    .MULT_RESET_MODE("SYNC")
) mult12x12_inst (
    .DOUT(p),
    .A({{3{a[8]}}, a}),
    .B({{4{b[7]}}, b}),
    .CLK(2'b00), .CE(2'b00), .RESET(2'b00)
);
assign dout = p[16:0];
endmodule
