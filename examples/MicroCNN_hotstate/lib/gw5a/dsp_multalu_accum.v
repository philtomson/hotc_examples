// Behavioral stand-in for gowin_multalu/dsp_multalu_accum.v on GW5A, which has
// no MULTALU18X18. Derived from Gowin's own prim_sim.v model of MULTALU18X18
// with the GW2A wrapper's parameters: MULTALU18X18_MODE 0, PIPE_REG=1,
// OUT_REG=1, every input and ACCLOAD unregistered, sync RESET, A unsigned
// (ASIGN=0), B signed (BSIGN=1), C zero-extended, both adds positive:
//
//   acc <= (ACCLOAD ? acc : 0) + (A*B registered one cycle earlier) + C
module dsp_multalu_accum (dout, caso, a, b, c, accload, ce, clk, reset);
output [53:0] dout;
output [54:0] caso;
input [7:0] a;
input [7:0] b;
input [31:0] c;
input accload, ce, clk, reset;
reg signed [35:0] p;
reg [54:0] acc;
always @(posedge clk)
    if (reset) begin
        p <= 36'sd0; acc <= 55'd0;
    end else if (ce) begin
        p   <= $signed({1'b0, a}) * $signed(b);
        acc <= (accload ? acc : 55'd0) + {{19{p[35]}}, p} + {23'd0, c};
    end
assign dout = acc[53:0];
assign caso = {acc[53], acc[53:0]};
endmodule
