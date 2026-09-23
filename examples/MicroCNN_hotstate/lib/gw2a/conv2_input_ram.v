// Tang Nano 20K (GW2A): one conv2 input bank for npu_top_hotstate.sv.
// 256 x 8 simple dual-port RAM on one SDPB (8-bit write / 8-bit read),
// read mode 0 (bypass): one-cycle registered read.
module conv2_input_ram (
    output [7:0] dout,
    input        clka, cea, reseta,
    input        clkb, ceb, resetb, oce,
    input  [7:0] ada,
    input  [7:0] din,
    input  [7:0] adb
);
    wire [31:0] q;

    SDPB #(.READ_MODE(1'b0), .BIT_WIDTH_0(8), .BIT_WIDTH_1(8),
           .BLK_SEL_0(3'b000), .BLK_SEL_1(3'b000), .RESET_MODE("SYNC")) u_ram (
        .DO(q), .DI({24'd0, din}),
        .ADA({3'b000, ada, 3'b000}), .ADB({3'b000, adb, 3'b000}),
        .CLKA(clka), .CEA(cea), .RESETA(reseta),
        .CLKB(clkb), .CEB(ceb), .RESETB(resetb), .OCE(oce),
        .BLKSELA(3'b000), .BLKSELB(3'b000)
    );

    assign dout = q[7:0];
endmodule
