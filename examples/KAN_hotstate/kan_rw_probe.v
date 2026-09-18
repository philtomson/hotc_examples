`timescale 1ns / 1ps
// kan_rw_probe.v -- does a byte written through kan_sdram_shim read back as
// the same byte?
//
// kan_ack_probe.v proves writes are ISSUED; it says nothing about whether
// they LAND, nor about the read path at all (it ties sdram_rd_req low). This
// probe closes that gap: it writes a known pattern through the exact
// handshake kan_control.c's sdram_write_byte() uses, then reads every byte
// back through the exact handshake read_weight_raw() uses, and compares.
//
// The read direction is the least-exercised seam in the stack: sdram.v's
// 8-bit `dout` port (with its `off` byte-lane select) is not what KAN_LUT's
// own design used -- that read `dout32` -- so nothing upstream has ever
// depended on it being right.
module kan_rw_probe (
    input  wire clk,
    input  wire clk_sdram,
    input  wire resetn,
    input  wire [22:0] num_bytes,
    input  wire [22:0] addr_stride,   // byte step between probed addresses
    output reg  [31:0] writes_done,
    output reg  [31:0] reads_done,
    output reg  [31:0] mismatches,
    output reg  [22:0] first_bad_addr,
    output reg  [7:0]  first_bad_exp,
    output reg  [7:0]  first_bad_got,
    output reg         finished
);
    wire rst = ~resetn;

    reg         wr_req, rd_req;
    reg  [22:0] addr;
    reg  [7:0]  wdata;
    wire        busy;
    wire [7:0]  rd_byte;

    wire O_sdram_clk, O_sdram_cke, O_sdram_cs_n, O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n;
    wire [31:0] IO_sdram_dq;
    wire [10:0] O_sdram_addr;
    wire [1:0]  O_sdram_ba;
    wire [3:0]  O_sdram_dqm;

    kan_sdram_shim #(.FREQ(54_000_000)) u_shim (
        .clk(clk), .clk_sdram(clk_sdram), .resetn(resetn),
        .sdram_wr_req(wr_req), .sdram_rd_req(rd_req),
        .sdram_addr(addr), .sdram_wr_data(wdata),
        .sdram_busy(busy), .sdram_rd_byte(rd_byte),
        .O_sdram_clk(O_sdram_clk), .O_sdram_cke(O_sdram_cke),
        .O_sdram_cs_n(O_sdram_cs_n), .O_sdram_cas_n(O_sdram_cas_n),
        .O_sdram_ras_n(O_sdram_ras_n), .O_sdram_wen_n(O_sdram_wen_n),
        .IO_sdram_dq(IO_sdram_dq), .O_sdram_addr(O_sdram_addr),
        .O_sdram_ba(O_sdram_ba), .O_sdram_dqm(O_sdram_dqm)
    );

    sim_only_sdram_model #(.SIZE_WORDS(1687552)) u_sdram_model (
        .SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba),
        .SDRAM_nCS(O_sdram_cs_n), .SDRAM_nWE(O_sdram_wen_n),
        .SDRAM_nRAS(O_sdram_ras_n), .SDRAM_nCAS(O_sdram_cas_n),
        .SDRAM_CLK(O_sdram_clk), .SDRAM_CKE(O_sdram_cke), .SDRAM_DQM(O_sdram_dqm)
    );

    // Pattern varies with the low address bits so a byte-lane select error
    // cannot be masked by every lane holding the same value.
    // Address actually probed for step i. A stride > 1 is what makes this
    // cross SDRAM bank boundaries: bank = byte_addr[22:21], so a dense
    // low-address run never leaves bank 0 and cannot see a bank-decode bug.
    wire [22:0] probe_addr = step * addr_stride;
    reg  [22:0] step;

    // The pattern MUST depend on the whole address, including bits [22:16].
    // Bank is byte_addr[22:21]; if the pattern ignored those bits, two
    // addresses that alias under a bank-decode bug would expect the SAME
    // byte and the aliasing would be invisible. (It was: an earlier version
    // keyed only on a[15:0] and passed against a model that truncated the
    // bank bits away.)
    function [7:0] pat(input [22:0] a);
        pat = {1'b0, a[22:16]} ^ a[15:8] ^ a[7:0] ^ 8'h5A;
    endfunction

    localparam W_REQ=3'd0, W_ACK=3'd1, W_DONE=3'd2,
               R_REQ=3'd3, R_ACK=3'd4, R_DONE=3'd5, DONE=3'd6;
    reg [2:0] st;

    always @(posedge clk) begin
        if (rst) begin
            st <= W_REQ; step <= 0; addr <= 0; wr_req <= 0; rd_req <= 0; wdata <= 0;
            writes_done <= 0; reads_done <= 0; mismatches <= 0; finished <= 0;
            first_bad_addr <= 0; first_bad_exp <= 0; first_bad_got <= 0;
        end else begin
            case (st)
                // ---- write phase: mirrors sdram_write_byte() --------------
                W_REQ:  begin addr <= probe_addr; wdata <= pat(probe_addr); wr_req <= 1'b1; st <= W_ACK; end
                W_ACK:  if (busy) begin wr_req <= 1'b0; st <= W_DONE; end
                W_DONE: if (!busy) begin
                            writes_done <= writes_done + 1;
                            if (step + 1 >= num_bytes) begin step <= 0; st <= R_REQ; end
                            else begin step <= step + 1; st <= W_REQ; end
                        end
                // ---- read phase: mirrors read_weight_raw()'s byte read ----
                R_REQ:  begin addr <= probe_addr; rd_req <= 1'b1; st <= R_ACK; end
                R_ACK:  if (busy) begin rd_req <= 1'b0; st <= R_DONE; end
                R_DONE: if (!busy) begin
                            reads_done <= reads_done + 1;
                            if (rd_byte !== pat(addr)) begin
                                if (mismatches == 0) begin
                                    first_bad_addr <= addr;
                                    first_bad_exp  <= pat(addr);
                                    first_bad_got  <= rd_byte;
                                end
                                mismatches <= mismatches + 1;
                            end
                            if (step + 1 >= num_bytes) begin st <= DONE; finished <= 1'b1; end
                            else begin step <= step + 1; st <= R_REQ; end
                        end
                DONE: ;
            endcase
        end
    end
endmodule
