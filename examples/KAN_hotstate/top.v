`timescale 1ns / 1ps

// Top-level module for the KAN_hotstate MNIST classifier, Tang Nano 20K.
// Wires uart_rx + uart_tx + kan_control (all hotc-compiled hotstate
// machines) to kan_sdram_shim (hand Verilog, wrapping KAN_LUT's sdram.v)
// and the board's PLL/pins. Pin names match KAN_LUT's nano20k.cst so that
// file can be reused unmodified.
module top (
    input  wire sys_clk,    // Onboard 27 MHz oscillator (pin 4)
    input  wire uart_rx,    // Port name matches nano20k.cst exactly so that
    output wire uart_tx,    // file can be reused unmodified. Verilog scopes
                             // a module TYPE name (the `uart_rx`/`uart_tx`
                             // hotstate modules instantiated below) and a
                             // plain signal/port name separately, so this
                             // is not a name collision -- but to keep this
                             // file unambiguous to read, the instances
                             // below are still wired through distinctly
                             // named internal wires, not these ports
                             // directly.

    // Tang Nano 20K embedded SDRAM (internal hard macro; no pin
    // constraints of its own -- see nano20k.cst)
    output wire        O_sdram_clk,
    output wire        O_sdram_cke,
    output wire        O_sdram_cs_n,
    output wire        O_sdram_cas_n,
    output wire        O_sdram_ras_n,
    output wire        O_sdram_wen_n,
    inout  wire [31:0]  IO_sdram_dq,
    output wire [10:0]  O_sdram_addr,
    output wire [1:0]   O_sdram_ba,
    output wire [3:0]   O_sdram_dqm,

    output wire [5:0] led
);

    wire clk;         // 54 MHz
    wire clk_sdram;   // 54 MHz, phase-shifted for SDRAM

    Gowin_rPLL pll (
        .clkout(clk),
        .clkoutp(clk_sdram),
        .clkin(sys_clk)
    );

    // Power-on reset stretch, same shape as KAN_LUT's nano20k_top.sv --
    // SDRAM's own init/config sequence (see sdram.v) needs the reset held
    // long enough to complete before anything issues a command.
    reg [15:0] rst_cnt = 0;
    reg        rst_stretch = 1;
    always @(posedge clk) begin
        if (rst_cnt != 16'hFFFF) begin
            rst_cnt <= rst_cnt + 1;
            rst_stretch <= 1;
        end else begin
            rst_stretch <= 0;
        end
    end
    // Reset is the power-on stretch ALONE. The board's S1 button is on pin 88,
    // which is also the MODE0 configuration strap (schematic net
    // PIN88_MODE0_KEY1); on this board it reads LOW, so including it as
    // `~(rst_stretch | ~s1)` held the entire design in permanent reset.
    //
    // Measured on hardware 2026-09-17: with s1 in the reset term, the only
    // thing that ran was the free-running heartbeat counter -- which is the
    // one counter deliberately outside the reset branch -- while every
    // reset-gated status flag stayed clear and kan_control never responded to
    // a fully streamed 6.75 MB weight load. Adding PULL_MODE=UP to the pin did
    // not change it, confirming the pin is driven low rather than floating.
    wire resetn = ~rst_stretch;
    wire rst    = ~resetn;               // active-high, for the hotstate IP cores

    // ---- UART -------------------------------------------------------------
    wire        rx_done_w;
    wire        rx_busy_w;
    wire [7:0]  rx_data_w;
    wire        tx_start_w;
    wire [7:0]  tx_data_w;
    wire        tx_busy_w;
    wire        tx_bit_w;

    uart_rx u_uart_rx (
        .clk(clk),
        .rst(rst),
        .rx_in(uart_rx),
        .rx_data(rx_data_w),
        .rx_done(rx_done_w),
        .rx_busy(rx_busy_w)
    );

    uart_tx u_uart_tx (
        .clk(clk),
        .rst(rst),
        .tx_start(tx_start_w),
        .tx_data(tx_data_w),
        .tx_bit(tx_bit_w),
        .tx_busy(tx_busy_w)
    );
    assign uart_tx = tx_bit_w;

    // ---- SDRAM shim ---------------------------------------------------------
    wire        sdram_wr_req_w;
    wire        sdram_rd_req_w;
    wire [22:0] sdram_addr_w;
    wire [7:0]  sdram_wr_data_w;
    wire        sdram_busy_w;
    wire [7:0]  sdram_rd_byte_w;

    kan_sdram_shim #(.FREQ(54_000_000)) u_sdram_shim (
        .clk(clk),
        .clk_sdram(clk_sdram),
        .resetn(resetn),
        .sdram_wr_req(sdram_wr_req_w),
        .sdram_rd_req(sdram_rd_req_w),
        .sdram_addr(sdram_addr_w),
        .sdram_wr_data(sdram_wr_data_w),
        .sdram_busy(sdram_busy_w),
        .sdram_rd_byte(sdram_rd_byte_w),
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

    // ---- kan_control --------------------------------------------------------
    kan_control u_kan_control (
        .clk(clk),
        .rst(rst),
        .sdram_busy(sdram_busy_w),
        .sdram_rd_byte(sdram_rd_byte_w),
        .rx_done(rx_done_w),
        .rx_byte(rx_data_w),
        .tx_busy(tx_busy_w),
        .sdram_wr_req(sdram_wr_req_w),
        .sdram_rd_req(sdram_rd_req_w),
        .sdram_addr(sdram_addr_w),
        .sdram_wr_data(sdram_wr_data_w),
        .tx_start(tx_start_w),
        .tx_data(tx_data_w)
        // All other kan_control outputs (byte_idx, p, q, acc, ... debug
        // signals) are internal-visibility-only: left unconnected here,
        // same as gol-hotstate's top.v leaves gol's internal state outputs
        // unconnected.
    );

    // ---- Result display on the LEDs -----------------------------------------
    // The classified digit is shown in BINARY on led[3:0] instead of being
    // read back over UART. The host->FPGA direction of this board's on-board
    // BL616 bridge is reliable, but the FPGA->host direction is intermittent
    // (see plans/kan_hotstate.md), so the answer never has to make that trip:
    // draw a digit, send 196 bytes, read the answer off the board.
    //
    //   led[3:0]  classified digit, binary (0..9)
    //   led[4]    TOGGLES on every classification. Not a sticky "valid" flag:
    //             that latched on the first result and then sat on forever,
    //             which tells you nothing about whether a NEW answer arrived.
    //             Toggling means led[4] visibly flips each time you classify.
    //   led[5]    heartbeat (~1.6 Hz) -- clock/PLL/reset sanity
    //
    // LEDs are ACTIVE LOW on this board (verified: vendor spec says "Low
    // voltage level enable", and confirmed on hardware), hence the ~ below.
    reg [7:0] result_q      = 8'h00;
    reg       result_tog    = 1'b0;
    reg [24:0] heartbeat    = 0;

    always @(posedge clk) begin
        if (rst) begin
            result_q   <= 8'h00;
            result_tog <= 1'b0;
        end else if (tx_start_w) begin
            result_q   <= tx_data_w;     // kan_control's own result byte
            result_tog <= ~result_tog;   // flips per classification
        end
        heartbeat <= heartbeat + 1;      // free-running, deliberately not reset
    end

    assign led = ~{heartbeat[24], result_tog, result_q[3:0]};

endmodule
