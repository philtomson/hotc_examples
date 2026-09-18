`timescale 1ns / 1ps

// kan_fastload_dut.v -- DUT-only wrapper for the C++-driven fast functional
// test (sim_main_fastload.cpp). This module has NO internal clock generation
// or sequencing: clk/clk_sdram/resetn are plain input ports toggled directly
// from C++, the same pattern examples/hdmi_gpu/sim_main.cpp uses, and for the
// same reason. An earlier version of this testbench drove its own clock and
// streamed the weight file from Verilog #delay/@(posedge)/wait() tasks run by
// the --timing event scheduler; that scheduler's per-cycle overhead is far too
// high for a test that has to run tens of millions of cycles (measured:
// it could not clear 2000 of the 6,750,208 weight bytes in over a minute of
// wall time). That version has been deleted rather than left to rot.
module kan_fastload_dut (
    input  wire clk,
    input  wire clk_sdram,
    input  wire resetn,

    input  wire       rx_done,
    input  wire [7:0] rx_byte,
    output wire       tx_start,
    output wire [7:0] tx_data,

    output wire        sdram_wr_req,
    output wire        sdram_rd_req,
    output wire        sdram_busy,

    // Refresh-observability tap for the C++ harness (mirrors
    // kan_fastload_tb.v's own refresh_count check).
    output wire refresh_active,

    // Per-image-byte ack. kan_control's load_image() has no handshake of its
    // own, but hotc emits a write-enable for the writable-BRAM store
    // `in_mem[p] = rx_byte`, which pulses exactly once per accepted byte.
    // The harness uses it to hold rx_done until the byte is really consumed,
    // instead of guessing a pulse width (a 1-cycle pulse is missed outright;
    // too long a hold would be consumed twice).
    output wire in_mem_wr_en,

    // Layer-1 result tap. kan_control exposes layer1_out__wr_en as a port,
    // but not the address/data of the store, so those come from hierarchical
    // references into the generated module's states_bus. The bit ranges are
    // read straight off kan_control_template.v's own BRAM write:
    //     layer1_out_bram[states_bus[81:74]] <= states_bus[220:212];
    // and let the harness check layer 1 against a software golden model
    // instead of only seeing the final class.
    output wire       l1_wr_en,
    output wire [7:0] l1_wr_addr,
    output wire [8:0] l1_wr_data
);

    wire rst = ~resetn;

    // Trivial 1-cycle-busy uart_tx stand-in: this harness only checks
    // tx_start/tx_data (the classification result), not real UART framing.
    reg tx_busy = 0;
    always @(posedge clk) tx_busy <= rst ? 1'b0 : tx_start;

    wire [22:0] sdram_addr;
    wire [7:0]  sdram_wr_data;
    wire [7:0]  sdram_rd_byte;

    kan_control u_kan_control (
        .clk(clk),
        .rst(rst),
        .sdram_busy(sdram_busy),
        .sdram_rd_byte(sdram_rd_byte),
        .rx_done(rx_done),
        .rx_byte(rx_byte),
        .tx_busy(tx_busy),
        .sdram_wr_req(sdram_wr_req),
        .sdram_rd_req(sdram_rd_req),
        .sdram_addr(sdram_addr),
        .sdram_wr_data(sdram_wr_data),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .in_mem__wr_en(in_mem_wr_en),
        .layer1_out__wr_en(l1_wr_en)
    );

    wire O_sdram_clk, O_sdram_cke, O_sdram_cs_n, O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n;
    wire [31:0] IO_sdram_dq;
    wire [10:0] O_sdram_addr;
    wire [1:0]  O_sdram_ba;
    wire [3:0]  O_sdram_dqm;

    kan_sdram_shim #(.FREQ(54_000_000)) u_shim (
        .clk(clk),
        .clk_sdram(clk_sdram),
        .resetn(resetn),
        .sdram_wr_req(sdram_wr_req),
        .sdram_rd_req(sdram_rd_req),
        .sdram_addr(sdram_addr),
        .sdram_wr_data(sdram_wr_data),
        .sdram_busy(sdram_busy),
        .sdram_rd_byte(sdram_rd_byte),
        .O_sdram_clk(O_sdram_clk),
        .O_sdram_cke(O_sdram_cke),
        .O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_cas_n(O_sdram_cas_n),
        .O_sdram_ras_n(O_sdram_ras_n),
        .O_sdram_wen_n(O_sdram_wen_n),
        .IO_sdram_dq(IO_sdram_dq),
        .O_sdram_addr(O_sdram_addr),
        .O_sdram_ba(O_sdram_ba),
        .O_sdram_dqm(O_sdram_dqm)
    );

    sim_only_sdram_model #(.SIZE_WORDS(1687552)) u_sdram_model (
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

    // CMD_AutoRefresh = {nRAS,nCAS,nWE} = 3'b001
    assign l1_wr_addr = u_kan_control.states_bus[81:74];
    assign l1_wr_data = u_kan_control.states_bus[220:212];

    assign refresh_active = !O_sdram_cs_n && O_sdram_ras_n == 1'b0 && O_sdram_cas_n == 1'b0 && O_sdram_wen_n == 1'b1;

endmodule
