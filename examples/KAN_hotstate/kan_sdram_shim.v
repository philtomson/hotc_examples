// kan_sdram_shim.v — byte-addressed SDRAM peripheral for kan_control.
//
// Wraps KAN_LUT's sdram.v (copied unmodified from ~/devel/FPGA/KAN_LUT/
// hardware/sdram.v) with the hold-until-ack request/busy interface
// kan_control.c expects, plus an autonomous refresh generator. kan_control
// is the SOLE requester (no second, concurrent SDRAM client the way the
// original kan_generic_core.sv's own mem_req port was) -- weight-load
// writes and inference-time reads happen at different points in
// kan_control's own sequential program, never simultaneously, so this
// shim's arbitration is a plain priority mux, not a true concurrent-
// requester arbiter.
//
// Contract with kan_control.c: `sdram_wr_req`/`sdram_rd_req` are held
// (not pulsed) until `sdram_busy` rises (request accepted), then dropped;
// kan_control waits for `sdram_busy` to fall again (operation complete)
// before touching the interface again.
//
// `sdram_busy` is therefore an ACK for *this requester's* operation, and
// must NOT be a passthrough of sdram.v's `busy`. sdram.v raises `busy` for
// its refresh and init/config sequences too (sdram.v:176, :243), which this
// shim issues autonomously. Passing that through meant a request asserted
// while an autonomous refresh happened to be in flight saw busy=1
// immediately, concluded "accepted", and dropped the request before the
// mux below ever forwarded it -- a silently lost write/read. Measured with
// a synthetic requester driving this exact handshake: ~0.9% of operations
// lost at realistic request spacing (and 0% at one phase-lucky spacing,
// which is why a single-spacing test does not establish this is correct).
//
// So `sdram_busy` is driven from a `granted` latch that rises only when a
// kan_control request is genuinely issued to sdram.v. `granted` also gates
// the mux, so a held request is issued exactly once even if sdram.v's busy
// falls before kan_control has reacted to the ack.
//
// `sdram_rd_byte` is a direct passthrough of sdram.v's `dout` -- verified
// from sdram.v's own source: `dout_buf` latches the read result once and
// holds it (stable across subsequent writes and refreshes) until the next
// read completes, so no extra capture register is needed here.
//
// Refresh priority: this shim only ever asserts sdram.refresh when
// neither sdram_wr_req nor sdram_rd_req is currently pending AND sdram is
// idle, so there is no cycle where a kan_control request and a refresh
// are both presented to sdram.v at once -- refresh simply waits for the
// next idle gap. Given weight-load bytes arrive roughly every ~5us
// (2 Mbaud UART) against a ~15us refresh period, and inference reads take
// ~5-6 cycles each with plenty of idle time around them, refresh always
// gets a free slot well within its deadline (verify this holds under
// simulation with a full weight-load run, not just by this reasoning --
// see plans/kan_hotstate.md).

module kan_sdram_shim #(
    parameter FREQ = 54_000_000
) (
    input  wire        clk,
    input  wire        clk_sdram,
    input  wire        resetn,

    // kan_control side
    input  wire         sdram_wr_req,
    input  wire         sdram_rd_req,
    input  wire [22:0]  sdram_addr,
    input  wire [7:0]   sdram_wr_data,
    output wire         sdram_busy,
    output wire [7:0]   sdram_rd_byte,

    // Physical SDRAM pins (Tang Nano 20K embedded SDRAM)
    output wire        O_sdram_clk,
    output wire        O_sdram_cke,
    output wire        O_sdram_cs_n,
    output wire        O_sdram_cas_n,
    output wire        O_sdram_ras_n,
    output wire        O_sdram_wen_n,
    inout  wire [31:0]  IO_sdram_dq,
    output wire [10:0]  O_sdram_addr,
    output wire [1:0]   O_sdram_ba,
    output wire [3:0]   O_sdram_dqm
);

    wire        core_busy;
    wire [7:0]  core_dout;
    reg         core_rd, core_wr, core_refresh;

    sdram #(.FREQ(FREQ)) u_sdram (
        .clk(clk), .clk_sdram(clk_sdram), .resetn(resetn),
        .addr(sdram_addr), .rd(core_rd), .wr(core_wr), .refresh(core_refresh),
        .din(sdram_wr_data), .dout(core_dout), .dout32(),
        .data_ready(), .busy(core_busy),

        .SDRAM_DQ(IO_sdram_dq),
        .SDRAM_A(O_sdram_addr),
        .SDRAM_BA(O_sdram_ba),
        .SDRAM_nCS(O_sdram_cs_n),
        .SDRAM_nWE(O_sdram_wen_n),
        .SDRAM_nRAS(O_sdram_ras_n),
        .SDRAM_nCAS(O_sdram_cas_n),
        .SDRAM_CLK(O_sdram_clk),
        .SDRAM_CKE(O_sdram_cke),
        .SDRAM_DQM(O_sdram_dqm)
    );

    // ---- Grant latch: the ack kan_control actually waits on -------------
    // Rises only on the cycle a kan_control request is really issued to
    // sdram.v; falls once that operation has completed AND the requester
    // has dropped its request (so a held request can never be issued twice).
    reg granted = 1'b0;
    always @(posedge clk) begin
        if (!resetn)
            granted <= 1'b0;
        else if (!granted && !core_busy && (sdram_wr_req || sdram_rd_req))
            granted <= 1'b1;
        else if (granted && !core_busy && !sdram_wr_req && !sdram_rd_req)
            granted <= 1'b0;
    end

    assign sdram_busy   = granted;
    assign sdram_rd_byte = core_dout;

    // ---- Refresh timer: ~15us period, autonomous, invisible to kan_control ---
    localparam integer REFRESH_COUNT = FREQ / 1_000 / 1_000 * 15;  // 810 @ 54MHz
    reg [11:0] refresh_time = 0;
    reg        refresh_needed = 0;

    always @(posedge clk) begin
        if (!resetn) begin
            refresh_time   <= 0;
            refresh_needed <= 0;
        end else begin
            if (refresh_time < REFRESH_COUNT) begin
                refresh_time <= refresh_time + 1;
            end else begin
                refresh_needed <= 1;
            end
            if (core_refresh) begin
                refresh_time   <= 0;
                refresh_needed <= 0;
            end
        end
    end

    // ---- Priority mux: kan_control's request wins; refresh only in a free idle slot ---
    always @(*) begin
        core_rd      = 1'b0;
        core_wr      = 1'b0;
        core_refresh = 1'b0;
        if (!core_busy && !granted) begin
            if (sdram_wr_req) begin
                core_wr = 1'b1;
            end else if (sdram_rd_req) begin
                core_rd = 1'b1;
            end else if (refresh_needed) begin
                core_refresh = 1'b1;
            end
        end
    end

endmodule
