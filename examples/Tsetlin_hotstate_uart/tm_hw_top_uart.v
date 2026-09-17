// tm_hw_top_uart.v — Hardware top-level with UART input (instead of SPI)
// Wraps uart_rx + uart_tx + tm_uart_loader + tm_top (unchanged sequencer +
// inference core). One image (98 bytes) in over UART RX, one result byte
// out over UART TX, looping forever -- no run_gpio/CS_N framing needed,
// unlike the SPI-based examples/Tsetlin_hotstate/tm_hw_top.v this mirrors.

`timescale 1ns / 1ps

module tm_hw_top_uart (
    // Board clock. This module is frequency-AGNOSTIC: it contains no counters
    // or dividers of its own, so nothing here needs retiming per board. All
    // baud timing lives in the uart_tx/uart_rx hotstate machines, whose
    // BIT_FULL/BIT_HALF the synth Makefiles derive from CLK_HZ (27 MHz on
    // Tang Nano 9K -> 230/114; 50 MHz on Tang Primer 25K -> 430/214).
    input  wire        clk,
    input  wire        rst_n,         // Active-low user reset button
    input  wire        uart_rxd,      // UART RX pin (image bytes in)
    output wire        uart_txd,      // UART TX pin (result byte out)
    output wire        done_led       // Lit (active-low) while idle, off during inference
`ifdef ILA_PROBE_ARGMAX
    ,
    output wire [15:0] ila_probe_argmax_a,
    output wire [15:0] ila_probe_argmax_b,
    output wire        ila_probe_idle
`endif
`ifdef ILA_PROBE_VOTE
    ,
    output wire [15:0] ila_probe_vote_a,
    output wire [15:0] ila_probe_vote_b,
    output wire        ila_probe_idle
`endif
`ifdef ILA_PROBE_CLAUSE
    ,
    output wire [15:0] ila_probe_clause_a,
    output wire [15:0] ila_probe_clause_b,
    output wire        ila_probe_idle
`endif
`ifdef ILA_PROBE_ROM
    ,
    // ROM readback probe -- see tm_core_v2.v. Separate from ILA_PROBE so the
    // normal ILA build (which watches tm_seq_controller) is untouched: this one
    // answers a different question and is a different 32-bit probe bus.
    output wire [15:0] ila_probe_rom_addr,
    output wire [15:0] ila_probe_rom_data,
    output wire        ila_probe_idle
`endif
`ifdef ILA_PROBE
    ,
    // ILA probe surface (plans/sandbox_multi_machine_ila.md, Phase 1).
    //
    // Guarded, because in a NORMAL build this module is the synthesis top and
    // every output needs a pin in the .cst -- these do not have one, and are
    // not meant to. In an ILA build the generated wrapper is the top and
    // instantiates this module, so these become internal wires feeding
    // ila_capture, not pins.
    //
    // The convention a wrapper generator can rely on: `ila_probe_states` is
    // the probed machine's full states_out and `ila_probe_adr` its debug_adr,
    // with widths taken from that machine's own generated _params.vh. Which
    // machine is probed is a property of the design, declared in the SandBox
    // catalog, not something the wrapper should guess.
    output wire [37:0] ila_probe_states,  // tm_seq_controller states_out
    output wire [6:0]  ila_probe_adr,     // tm_seq_controller debug_adr
    // Interlock for a multiplexed UART: high only when this design is not
    // mid-frame in either direction, so a wrapper can switch the shared line
    // away without parking uart_rx/uart_tx inside a bit-timing loop with a
    // stale sample. Both halves are already wires here.
    output wire        ila_probe_idle
`endif
);

    wire sys_rst = ~rst_n;

`ifdef ILA_PROBE_ARGMAX
    assign ila_probe_idle = ~rx_busy & ~tx_busy;
`endif
`ifdef ILA_PROBE_VOTE
    assign ila_probe_idle = ~rx_busy & ~tx_busy;
`endif
`ifdef ILA_PROBE_CLAUSE
    assign ila_probe_idle = ~rx_busy & ~tx_busy;
`endif
`ifdef ILA_PROBE_ROM
    assign ila_probe_idle = ~rx_busy & ~tx_busy;
`endif
`ifdef ILA_PROBE
    assign ila_probe_idle = ~rx_busy & ~tx_busy;
`endif

    // ── UART Receiver (115200 Baud) ──
    wire [7:0] rx_data;
    wire       rx_done;
    wire       rx_busy;
    uart_rx u_rx (
        .clk(clk), .rst(sys_rst),
        .rx_in(uart_rxd),
        .rx_data(rx_data), .rx_done(rx_done), .rx_busy(rx_busy)
    );

    // ── UART Transmitter (115200 Baud) ──
    wire       tx_start;
    wire [7:0] tx_data;
    wire       tx_busy;
    uart_tx u_tx (
        .clk(clk), .rst(sys_rst),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx_bit(uart_txd), .tx_busy(tx_busy)
    );

    // ── UART image loader / result reporter (hotstate) ──
    wire        go;
    wire [6:0]  img_waddr;
    wire [7:0]  img_wdata;
    wire        img_wen;
    wire        done;
    wire [3:0]  winner;
    tm_uart_loader u_loader (
        .clk(clk), .rst(sys_rst),
        .rx_done(rx_done), .rx_byte(rx_data),
        .tx_busy(tx_busy),
        .tx_start(tx_start), .tx_data(tx_data),
        .go(go),
        .img_waddr(img_waddr), .img_wdata(img_wdata), .img_wen(img_wen),
        .done(done), .winner(winner)
    );

    // ── Tsetlin Machine sequencer + inference core (unchanged) ──
    tm_top tm (
        .clk(clk), .rst(sys_rst),
        .go(go), .done(done), .result(winner),
        .img_waddr(img_waddr), .img_wdata(img_wdata), .img_wen(img_wen),
`ifdef ILA_PROBE
        .ctrl_debug_adr(ila_probe_adr), .ctrl_states_out(ila_probe_states), .ctrl_ready(),
`else
        .ctrl_debug_adr(), .ctrl_states_out(), .ctrl_ready(),
`endif
        .core_state(), .core_clause_idx(),
        .vote_0(), .vote_1(), .vote_2(), .vote_3(), .vote_4(),
        .vote_5(), .vote_6(), .vote_7(), .vote_8(), .vote_9(),
        .fire_count(), .clause0_viol(), .clause0_fired(),
        .rom16(), .dbg_clause_done()
    `ifdef ILA_PROBE_ROM
        , .ila_rom_addr(ila_probe_rom_addr), .ila_rom_data(ila_probe_rom_data)
`endif
    `ifdef ILA_PROBE_CLAUSE
        , .ila_clause_a(ila_probe_clause_a), .ila_clause_b(ila_probe_clause_b)
`endif
    `ifdef ILA_PROBE_VOTE
        , .ila_vote_a(ila_probe_vote_a), .ila_vote_b(ila_probe_vote_b)
`endif
    `ifdef ILA_PROBE_ARGMAX
        , .ila_argmax_a(ila_probe_argmax_a), .ila_argmax_b(ila_probe_argmax_b)
`endif
    );

    // Active-low LED: lit at idle, off while an inference is in progress.
    assign done_led = ~go;

endmodule
