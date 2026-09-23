// Behavioral stand-ins for the three gowin_sdpb/*.v SDPB wrappers on GW5A,
// same module names and ports. All model SDPB with READ_MODE=0 (bypass): a
// 1-cycle registered read on CLKB/CEB, sync RESETB clearing the output
// register, a write on CLKA/CEA.
//
// fc1/fc2 are mixed-width on the GW2A (8-bit write, 64-bit read). Byte k of
// read word w is write address {w, k} -- lower address, lower bits, per the
// wrappers' DO wiring. They are deliberately NOT written as one 64-bit memory
// with byte writes: yosys either splits that into many narrow blocks or
// re-merges it into a mixed-width port. fc1 is eight independent 64x8 byte
// lanes (eight plain symmetric block RAMs); fc2 is 32 bytes, so flip-flops.

module fc1_lane (output reg [7:0] q, input clk, input we, input [5:0] wa, input [7:0] d,
                 input re, input rst, input [5:0] ra);
(* ram_style = "block" *) reg [7:0] mem [0:63];
always @(posedge clk) if (we) mem[wa] <= d;
always @(posedge clk) if (rst) q <= 8'd0; else if (re) q <= mem[ra];
endmodule

module gowin_sdpb_fc1 (dout, clka, cea, reseta, clkb, ceb, resetb, oce, ada, din, adb);
output [63:0] dout;
input clka, cea, reseta, clkb, ceb, resetb, oce;
input [8:0] ada;
input [7:0] din;
input [5:0] adb;
genvar k;
generate for (k = 0; k < 8; k = k + 1) begin : lane
    fc1_lane u (.q(dout[k*8 +: 8]), .clk(clka), .we(cea && ada[2:0] == k), .wa(ada[8:3]), .d(din),
                .re(ceb), .rst(resetb), .ra(adb));
end endgenerate
endmodule

module gowin_sdpb_fc2 (dout, clka, cea, reseta, clkb, ceb, resetb, oce, ada, din, adb);
output reg [63:0] dout;
input clka, cea, reseta, clkb, ceb, resetb, oce;
input [4:0] ada;
input [7:0] din;
input [1:0] adb;
(* ram_style = "logic" *) reg [63:0] mem [0:3];
always @(posedge clka) if (cea) mem[ada[4:3]][ada[2:0]*8 +: 8] <= din;
always @(posedge clkb) if (resetb) dout <= 64'd0; else if (ceb) dout <= mem[adb];
endmodule

module conv2_input_ram (dout, clka, cea, reseta, clkb, ceb, resetb, oce, ada, din, adb);
output reg [7:0] dout;
input clka, cea, reseta, clkb, ceb, resetb, oce;
input [7:0] ada;
input [7:0] din;
input [7:0] adb;
(* ram_style = "block" *) reg [7:0] mem [0:255];
always @(posedge clka) if (cea) mem[ada] <= din;
always @(posedge clkb) if (resetb) dout <= 8'd0; else if (ceb) dout <= mem[adb];
endmodule
