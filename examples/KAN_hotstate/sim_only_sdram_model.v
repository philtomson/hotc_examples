// sim_only_sdram_model.v — behavioral SDRAM chip model, SIMULATION ONLY,
// never synthesized. Neither KAN_LUT nor this project ships a Verilator
// model for the Tang Nano 20K's embedded SDRAM chip (only the CONTROLLER,
// sdram.v, exists as RTL -- the memory array itself is a real hardened
// chip on real hardware, absent from simulation entirely unless something
// stands in for it). This is that stand-in, so kan_sdram_shim + sdram.v's
// real read/write/refresh protocol and timing can be exercised under
// simulation, not just kan_control's own control-flow logic.
//
// Command timing/encoding below is read directly from sdram.v's source
// (default parameters: CAS=2, T_RCD=1), not re-derived -- specifically
// the {SDRAM_nRAS,SDRAM_nCAS,SDRAM_nWE} command encoding and the
// cycle-relative offsets at which sdram.v issues Activate, Read/Write,
// and drives/samples SDRAM_DQ:
//   - Read: CMD_Read is issued at controller-relative cycle T_RCD (the
//     first cycle of its READ state); data must be valid on SDRAM_DQ
//     CAS cycles after that (controller cycle T_RCD+CAS, when it sets
//     data_ready and samples dq_in combinationally).
//   - Write: CMD_Write is issued at controller-relative cycle T_RCD;
//     sdram.v drives its own write data onto SDRAM_DQ for exactly the
//     ONE cycle immediately after that (dq_oen/dq_out are registered
//     during the CMD_Write cycle, so they take effect the following
//     cycle, and are reverted the cycle after that) -- so this model
//     samples SDRAM_DQ/SDRAM_DQM exactly 1 cycle after detecting
//     CMD_Write.
// Implemented as small fixed-depth delay-register chains (not a general
// shift-register pipe) sized exactly to CAS/T_RCD, since both are small
// fixed constants here -- easier to verify each stage's timing by
// inspection than a parameterized pipeline.
//
// sdram.v always uses auto-precharge and always issues Activate
// immediately before every Read/Write (see its own IDLE-state logic), so
// this model doesn't need to track open-row/bank state-machine legality
// at all -- it just needs to remember the most recent Activate's
// {bank,row} and combine it with the following Read/Write's column to
// reconstruct the full word address, exactly as sdram.v itself derives
// those fields FROM one address in the first place (bank=addr[22:21],
// row=addr[20:10], col=addr[9:2], byte-offset=addr[1:0] -- verified these
// partition addr[22:0] exactly: 2+11+8=21 address bits plus 2 low bits
// this model handles via DQM byte-lane masking instead of a separate
// "off" field, matching how DQM is actually transmitted to real SDRAM).
//
// SIZE_WORDS defaults to exactly this design's weight blob
// (6,750,208 bytes = 1,687,552 32-bit words) -- big enough for the real
// weight-load test, not a generic full-address-space model.

module sim_only_sdram_model #(
    parameter integer SIZE_WORDS = 1687552
) (
    inout  wire [31:0] SDRAM_DQ,
    input  wire [10:0] SDRAM_A,
    input  wire [1:0]  SDRAM_BA,
    input  wire        SDRAM_nCS,
    input  wire        SDRAM_nWE,
    input  wire        SDRAM_nRAS,
    input  wire        SDRAM_nCAS,
    input  wire        SDRAM_CLK,
    input  wire        SDRAM_CKE,
    input  wire [3:0]  SDRAM_DQM
);

    localparam [2:0] CMD_AutoRefresh = 3'b001;
    localparam [2:0] CMD_BankActivate= 3'b011;
    localparam [2:0] CMD_Write       = 3'b100;
    localparam [2:0] CMD_Read        = 3'b101;

    wire [2:0] cmd = {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE};
    wire       cmd_valid = !SDRAM_nCS;

    reg [31:0] mem [0:SIZE_WORDS-1];
    integer init_i;
    initial for (init_i = 0; init_i < SIZE_WORDS; init_i = init_i + 1) mem[init_i] = 32'hDEAD_BEEF;

    // Latched {bank,row} from the most recent Activate.
    reg [12:0] bank_row;  // {BA[1:0], A[10:0]}

    // ---- Address reconstruction ---------------------------------------------
    // The stored-word index must be exactly how sdram.v decomposed the byte
    // address: sdram.v drives
    //     SDRAM_BA  <= addr[22:21]          (bank, 2 bits)
    //     SDRAM_A   <= addr[20:10]          (row, 11 bits)
    //     SDRAM_A[9:0] <= {1'b0, addr[9:2]} (column, 8 bits, zero-padded)
    // so the dense word index is {bank, row, col} = 2 + 11 + 8 = 21 bits,
    // i.e. exactly addr[22:2].
    //
    // This was originally `{bank_row, SDRAM_A[9:0]}` -- 13 + 10 = 23 bits
    // assigned to a 21-bit target. The two BANK bits were silently truncated
    // off the top, aliasing all four banks onto one (so anything past 2 MB
    // overwrote earlier data), and the column's two zero pad bits were left
    // sitting in the middle of the index. Verilator reported it as WIDTHTRUNC
    // and -Wno-fatal demoted it to a warning that nothing was reading.
    //
    // Only the bottom COL_WIDTH bits of SDRAM_A are the column, so the concat
    // below is 13 + 8 = 21 bits with no truncation and no padding.
    localparam COL_WIDTH = 8;

    // ---- Read path: CAS=2 delay, counted from COMMAND DETECTION --------------
    // Stage d1 is the cycle this model first SEES CMD_Read on the bus; real
    // SDRAM with CAS=2 drives data 2 clocks after that, so the drive window is
    // stage d3, not d2.
    //
    // This is off-by-one-sensitive and was originally wrong (a 2-stage chain,
    // i.e. an effective CAS of 1). The window closed exactly one cycle before
    // sdram.v sampled, so sdram.v latched a tri-stated bus and EVERY read
    // returned 0x00 -- which looked like a compute bug (all accumulators tie,
    // every image classifies as class 0) rather than a model bug.
    //
    // The alignment, tick by tick, where each tick is (model posedge on
    // clk_sdram, THEN sdram.v posedge on clk -- clk_sdram is 180 degrees
    // shifted, so the model's edge leads within a tick):
    //   T0   : sdram.v registers CMD_Read (pins update after this edge)
    //   T0+1 : model sees CMD_Read              -> d1
    //   T0+2 : (CAS cycle 1)                    -> d2
    //   T0+3 : model drives DQ  ... and later in the SAME tick sdram.v's
    //          counter reaches T_RCD+CAS+1 and latches dout_buf <= dq_in.
    // The model's leading edge is what makes the same-tick handoff work.
    reg        rd_cmd_d1, rd_cmd_d2, rd_cmd_d3;
    reg [20:0] rd_addr_d1, rd_addr_d2, rd_addr_d3;

    always @(posedge SDRAM_CLK) begin
        rd_cmd_d1  <= (cmd_valid && cmd == CMD_Read);
        rd_addr_d1 <= {bank_row, SDRAM_A[COL_WIDTH-1:0]};
        rd_cmd_d2  <= rd_cmd_d1;
        rd_addr_d2 <= rd_addr_d1;
        rd_cmd_d3  <= rd_cmd_d2;
        rd_addr_d3 <= rd_addr_d2;
    end

    wire        driving   = rd_cmd_d3;
    wire [31:0] drive_data = mem[rd_addr_d3];
    assign SDRAM_DQ = driving ? drive_data : 32'bz;

    // ---- Write path: SAME cycle as CMD_Write, not delayed --------------------
    // sdram.v schedules CMD_Write and its dq_out/dq_oen drive together, in the
    // same case block ({WRITE,T_RCD}) -- both become visible on the bus at the
    // identical next edge, and dq_oen reverts (stops driving) the cycle after
    // that (a single-cycle drive window, matching its own timing-diagram
    // comment showing "Din" aligned directly under "Write" in the same
    // column, not the next one). So this model must sample SDRAM_DQ/SDRAM_DQM
    // in the SAME cycle it observes CMD_Write, using bank_row's already-
    // current value (bank_row finishes updating from the preceding Activate
    // exactly one cycle before Write/Read both become visible -- verified
    // against the same T_RCD=1 gap the read path relies on above).
    wire [20:0] wr_addr = {bank_row, SDRAM_A[COL_WIDTH-1:0]};

    always @(posedge SDRAM_CLK) begin
        if (cmd_valid && cmd == CMD_Write) begin
            if (!SDRAM_DQM[0]) mem[wr_addr][7:0]   <= SDRAM_DQ[7:0];
            if (!SDRAM_DQM[1]) mem[wr_addr][15:8]  <= SDRAM_DQ[15:8];
            if (!SDRAM_DQM[2]) mem[wr_addr][23:16] <= SDRAM_DQ[23:16];
            if (!SDRAM_DQM[3]) mem[wr_addr][31:24] <= SDRAM_DQ[31:24];
        end
    end

    // ---- Activate latch (combinational-timed, same cycle as command) --------
    always @(posedge SDRAM_CLK) begin
        if (cmd_valid && cmd == CMD_BankActivate) begin
            bank_row <= {SDRAM_BA, SDRAM_A};
        end
    end

    // CMD_AutoRefresh: no-op for a behavioral model (nothing to simulate --
    // it doesn't touch stored data; the point of exercising it here is the
    // shim's arbitration/timing, not any data effect).

endmodule
