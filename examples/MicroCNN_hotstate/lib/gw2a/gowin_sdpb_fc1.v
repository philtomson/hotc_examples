// Tang Nano 20K (GW2A): FC1 activation buffer for fc1_buffer_ram.sv.
// 512 bytes written one byte at a time, read back as 64 x 64-bit words
// (byte k of word w = write address {w, k}). Two SDPB blocks in 4-bit-write /
// 32-bit-read mode: block 0 holds every byte's low nibble, block 1 the high.
// Read mode 0 (bypass): one-cycle registered read.
module gowin_sdpb_fc1 (
    output [63:0] dout,
    input         clka, cea, reseta,
    input         clkb, ceb, resetb, oce,
    input  [8:0]  ada,
    input  [7:0]  din,
    input  [5:0]  adb
);
    wire [31:0] lo, hi;   // nibble k of each = low/high nibble of byte k

    genvar k;
    generate for (k = 0; k < 8; k = k + 1) begin : g_byte
        assign dout[8*k +: 8] = {hi[4*k +: 4], lo[4*k +: 4]};
    end endgenerate

    SDPB #(.READ_MODE(1'b0), .BIT_WIDTH_0(4), .BIT_WIDTH_1(32),
           .BLK_SEL_0(3'b000), .BLK_SEL_1(3'b000), .RESET_MODE("SYNC")) u_lo (
        .DO(lo), .DI({28'd0, din[3:0]}),
        .ADA({3'b000, ada, 2'b00}), .ADB({3'b000, adb, 5'b00000}),
        .CLKA(clka), .CEA(cea), .RESETA(reseta),
        .CLKB(clkb), .CEB(ceb), .RESETB(resetb), .OCE(oce),
        .BLKSELA(3'b000), .BLKSELB(3'b000)
    );

    SDPB #(.READ_MODE(1'b0), .BIT_WIDTH_0(4), .BIT_WIDTH_1(32),
           .BLK_SEL_0(3'b000), .BLK_SEL_1(3'b000), .RESET_MODE("SYNC")) u_hi (
        .DO(hi), .DI({28'd0, din[7:4]}),
        .ADA({3'b000, ada, 2'b00}), .ADB({3'b000, adb, 5'b00000}),
        .CLKA(clka), .CEA(cea), .RESETA(reseta),
        .CLKB(clkb), .CEB(ceb), .RESETB(resetb), .OCE(oce),
        .BLKSELA(3'b000), .BLKSELB(3'b000)
    );
endmodule
