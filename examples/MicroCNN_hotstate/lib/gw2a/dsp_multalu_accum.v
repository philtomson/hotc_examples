// Tang Nano 20K (GW2A): dsp_multalu_accum for fc_npu_array_gowin.sv.
// One MULTALU18X18 in mode 0 (ACC/0 + A*B + C): a unsigned 8-bit, b signed
// 8-bit (sign-extended to 18), c zero-extended. Pipeline and output
// registers on, every input and ACCLOAD unregistered, synchronous reset.
module dsp_multalu_accum (
    output [53:0] dout,
    output [54:0] caso,
    input  [7:0]  a,
    input  [7:0]  b,
    input  [31:0] c,
    input         accload,
    input         ce,
    input         clk,
    input         reset
);
    MULTALU18X18 #(
        .AREG(1'b0), .BREG(1'b0), .CREG(1'b0), .DREG(1'b0),
        .OUT_REG(1'b1), .PIPE_REG(1'b1),
        .ASIGN_REG(1'b0), .BSIGN_REG(1'b0), .DSIGN_REG(1'b0),
        .ACCLOAD_REG0(1'b0), .ACCLOAD_REG1(1'b0),
        .B_ADD_SUB(1'b0), .C_ADD_SUB(1'b0),
        .MULTALU18X18_MODE(0),
        .MULT_RESET_MODE("SYNC")
    ) u_multalu (
        .DOUT(dout),
        .CASO(caso),
        .A({10'd0, a}),
        .B({{10{b[7]}}, b}),
        .C({22'd0, c}),
        .D(54'd0),
        .ASIGN(1'b0), .BSIGN(1'b1), .DSIGN(1'b1),
        .CASI(55'd0),
        .ACCLOAD(accload),
        .CE(ce), .CLK(clk), .RESET(reset)
    );
endmodule
