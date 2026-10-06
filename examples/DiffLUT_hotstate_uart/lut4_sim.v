// behavioral LUT4 model for simulation only (yosys/synthesis know the
// LUT4 primitive natively; include this file with iverilog)
module LUT4 #(parameter [15:0] INIT = 16'h0)
             (output F, input I0, input I1, input I2, input I3);
    assign F = INIT[{I3, I2, I1, I0}];
endmodule
