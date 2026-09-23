// Tang Nano 20K (GW2A): Gowin_MULT for spatial_3x3_mac_gowin.sv.
// A combinational signed 9x9 multiply on one MULT9X9 hard block, every
// register bypassed. b is an 8-bit signed operand, sign-extended to 9 bits.
module Gowin_MULT (
    output [16:0] dout,
    input  [8:0]  a,
    input  [7:0]  b
);
    wire [17:0] p;

    MULT9X9 #(
        .AREG(1'b0), .BREG(1'b0), .OUT_REG(1'b0), .PIPE_REG(1'b0),
        .ASIGN_REG(1'b0), .BSIGN_REG(1'b0), .SOA_REG(1'b0),
        .MULT_RESET_MODE("SYNC")
    ) u_mult (
        .DOUT(p),
        .SOA(), .SOB(),
        .A(a),
        .B({b[7], b}),
        .ASIGN(1'b1), .BSIGN(1'b1),
        .SIA(9'd0), .SIB(9'd0),
        .CE(1'b0), .CLK(1'b0), .RESET(1'b0),
        .ASEL(1'b0), .BSEL(1'b0)
    );

    assign dout = p[16:0];
endmodule
