`timescale 1ns / 1ps
// kan_ack_probe.v -- isolates ONE question: does kan_control's
// "assert req; while(!busy){}; drop req; while(busy){}" handshake ever
// complete WITHOUT the shim actually issuing a write to the SDRAM?
//
// The synthetic requester below reproduces kan_control.c's
// sdram_write_byte() handshake exactly (see kan_control.c:115-122).
// Two counters are exposed: handshakes the requester believes it
// completed, and real CMD_Write commands seen on the SDRAM pins.
// Equal => handshake sound. Divergent => acks are false.
module kan_ack_probe (
    input  wire clk,
    input  wire clk_sdram,
    input  wire resetn,
    input  wire [15:0] idle_gap,          // idle cycles between requests
    input  wire        req_enable,         // drop to quiesce the requester before sampling
    output wire        req_idle,            // requester parked, nothing in flight
    output reg  [31:0] handshakes_done,
    output reg  [31:0] writes_issued,
    output reg  [31:0] refreshes_issued
);
    wire rst = ~resetn;

    reg         wr_req;
    reg  [22:0] addr;
    wire        busy;
    wire [7:0]  rd_byte;

    wire O_sdram_clk, O_sdram_cke, O_sdram_cs_n, O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n;
    wire [31:0] IO_sdram_dq;
    wire [10:0] O_sdram_addr;
    wire [1:0]  O_sdram_ba;
    wire [3:0]  O_sdram_dqm;

    kan_sdram_shim #(.FREQ(54_000_000)) u_shim (
        .clk(clk), .clk_sdram(clk_sdram), .resetn(resetn),
        .sdram_wr_req(wr_req), .sdram_rd_req(1'b0),
        .sdram_addr(addr), .sdram_wr_data(addr[7:0]),
        .sdram_busy(busy), .sdram_rd_byte(rd_byte),
        .O_sdram_clk(O_sdram_clk), .O_sdram_cke(O_sdram_cke),
        .O_sdram_cs_n(O_sdram_cs_n), .O_sdram_cas_n(O_sdram_cas_n),
        .O_sdram_ras_n(O_sdram_ras_n), .O_sdram_wen_n(O_sdram_wen_n),
        .IO_sdram_dq(IO_sdram_dq), .O_sdram_addr(O_sdram_addr),
        .O_sdram_ba(O_sdram_ba), .O_sdram_dqm(O_sdram_dqm)
    );

    sim_only_sdram_model #(.SIZE_WORDS(65536)) u_sdram_model (
        .SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba),
        .SDRAM_nCS(O_sdram_cs_n), .SDRAM_nWE(O_sdram_wen_n),
        .SDRAM_nRAS(O_sdram_ras_n), .SDRAM_nCAS(O_sdram_cas_n),
        .SDRAM_CLK(O_sdram_clk), .SDRAM_CKE(O_sdram_cke), .SDRAM_DQM(O_sdram_dqm)
    );

    // Command decode on the pins (encodings from sdram.v:101-107)
    wire sel = !O_sdram_cs_n;
    wire cmd_write   = sel && ({O_sdram_ras_n,O_sdram_cas_n,O_sdram_wen_n} == 3'b100);
    wire cmd_refresh = sel && ({O_sdram_ras_n,O_sdram_cas_n,O_sdram_wen_n} == 3'b001);

    // Synthetic requester: a literal transcription of sdram_write_byte()
    localparam S_REQ = 2'd0, S_WAITBUSY = 2'd1, S_WAITDONE = 2'd2, S_GAP = 2'd3;
    reg [1:0]  st;
    reg [15:0] gap_ctr;

    assign req_idle = (st == S_GAP) && !wr_req && !busy;

    always @(posedge clk) begin
        if (rst) begin
            st <= S_GAP; wr_req <= 0; addr <= 0; gap_ctr <= 0;
            handshakes_done <= 0; writes_issued <= 0; refreshes_issued <= 0;
        end else begin
            if (cmd_write)   writes_issued    <= writes_issued + 1;
            if (cmd_refresh) refreshes_issued <= refreshes_issued + 1;

            case (st)
                S_REQ:      begin wr_req <= 1'b1; st <= S_WAITBUSY; end
                S_WAITBUSY: if (busy) begin wr_req <= 1'b0; st <= S_WAITDONE; end
                S_WAITDONE: if (!busy) begin
                                handshakes_done <= handshakes_done + 1;
                                addr <= addr + 1;
                                gap_ctr <= 0;
                                st <= S_GAP;
                            end
                S_GAP:      if (req_enable && gap_ctr >= idle_gap) st <= S_REQ;
                            else gap_ctr <= gap_ctr + 1;
            endcase
        end
    end
endmodule
