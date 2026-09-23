// Tang Nano 20K (GW2A): FC2 activation buffer for fc2_buffer_ram.sv.
// Same organisation as gowin_sdpb_fc1.v, smaller: 32 bytes written one at a
// time, read back as 4 x 64-bit words (byte k of word w = write address
// {w, k}); low nibbles in one SDPB, high nibbles in the other.
module gowin_sdpb_fc2 (
    output [63:0] dout,
    input         clka, cea, reseta,
    input         clkb, ceb, resetb, oce,
    input  [4:0]  ada,
    input  [7:0]  din,
    input  [1:0]  adb
);
    wire [31:0] lo, hi;

    genvar k;
    generate for (k = 0; k < 8; k = k + 1) begin : g_byte
        assign dout[8*k +: 8] = {hi[4*k +: 4], lo[4*k +: 4]};
    end endgenerate

    SDPB #(.READ_MODE(1'b0), .BIT_WIDTH_0(4), .BIT_WIDTH_1(32),
           .BLK_SEL_0(3'b000), .BLK_SEL_1(3'b000), .RESET_MODE("SYNC")) u_lo (
        .DO(lo), .DI({28'd0, din[3:0]}),
        .ADA({7'd0, ada, 2'b00}), .ADB({7'd0, adb, 5'b00000}),
        .CLKA(clka), .CEA(cea), .RESETA(reseta),
        .CLKB(clkb), .CEB(ceb), .RESETB(resetb), .OCE(oce),
        .BLKSELA(3'b000), .BLKSELB(3'b000)
    );

    SDPB #(.READ_MODE(1'b0), .BIT_WIDTH_0(4), .BIT_WIDTH_1(32),
           .BLK_SEL_0(3'b000), .BLK_SEL_1(3'b000), .RESET_MODE("SYNC")) u_hi (
        .DO(hi), .DI({28'd0, din[7:4]}),
        .ADA({7'd0, ada, 2'b00}), .ADB({7'd0, adb, 5'b00000}),
        .CLKA(clka), .CEA(cea), .RESETA(reseta),
        .CLKB(clkb), .CEB(ceb), .RESETB(resetb), .OCE(oce),
        .BLKSELA(3'b000), .BLKSELB(3'b000)
    );
endmodule
