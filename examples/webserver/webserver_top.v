// webserver_top.v — Top-level Verilog wrapper for Hotwright HTTP Server
// Coordinates uart_rx, uart_tx, and http_server on Tang Nano 20K FPGA

`timescale 1ns / 1ps

module webserver_top (
    input  wire        clk,           // 27 MHz clock oscillator
    input  wire        rst_n,         // Active-low user reset button
    input  wire        uart_rxd,      // RX pin (70)
    output wire        uart_txd,      // TX pin (69)
    output wire        led0,          // Red LED 0 (active-low, pin 15)
    output wire        led1,          // Green LED 1 (active-low, pin 16)
    output wire        led2,          // Status LED 2: RX activity (active-low, pin 17)
    output wire        led3           // Status LED 3: TX activity (active-low, pin 7)
`ifdef ILA_PROBE
    ,
    // ILA probe surface -- the contract from
    // plans/sandbox_multi_machine_ila.md Phase 1, satisfied here unchanged.
    // Guarded because in a normal build this module is the synthesis top and
    // every output needs a pin; in an ILA build the generated wrapper is the
    // top, so these become internal wires feeding ila_capture.
    //
    // http_server is the machine worth watching: it decides what the design
    // DOES with a request. Its probe is 11 state + 6 address bits = 17, against
    // Tsetlin's 45, which is why this design can afford a deeper capture.
    output wire [10:0] ila_probe_states,  // http_server states_out
    output wire [5:0]  ila_probe_adr,     // http_server debug_adr
    output wire        ila_probe_idle     // not mid-frame in either direction
`endif
);

    wire [7:0] rx_data;
    wire       rx_done;
    wire       rx_busy;
    
    wire       led0_raw;
    wire       led1_raw;
    
    wire       sys_rst;
    assign sys_rst = ~rst_n;

    wire       uart_tx_start;
    wire [7:0] uart_tx_byte;
    wire       uart_tx_busy;
    
    wire       http_tx_start;
    wire [7:0] active_route;
    wire       streamer_busy;
    wire       tx_busy_to_http;
    
    assign tx_busy_to_http = streamer_busy | uart_tx_busy;

    // ── UART Receiver (115200 Baud) ──
    uart_rx u_rx (
        .clk(clk),
        .rst(sys_rst),
        .rx_in(uart_rxd),
        .rx_data(rx_data),
        .rx_done(rx_done),
        .rx_busy(rx_busy)
    );

    // ── UART Transmitter (115200 Baud) ──
    uart_tx u_tx (
        .clk(clk),
        .rst(sys_rst),
        .tx_start(uart_tx_start),
        .tx_data(uart_tx_byte),
        .tx_bit(uart_txd),
        .tx_busy(uart_tx_busy)
    );

    // ── HTTP Web Server Controller ──
`ifdef ILA_PROBE
    // "Not mid-frame in either direction". Both wires already existed here, so
    // nothing new had to be plumbed to satisfy the contract.
    assign ila_probe_idle = ~rx_busy & ~uart_tx_busy;
`endif

    http_server u_http (
        .clk(clk),
        .rst(sys_rst),
        .rx_done(rx_done),
        .rx_byte(rx_data),
        .tx_busy(tx_busy_to_http),
        .tx_start(http_tx_start),
        .led0(led0_raw),
        .led1(led1_raw),
        .active_route(active_route)
`ifdef ILA_PROBE
        , .states_out(ila_probe_states), .debug_adr(ila_probe_adr)
`endif
    );

    // ── Hybrid response streamer ──
    response_streamer u_streamer (
        .clk(clk),
        .rst(sys_rst),
        .tx_start(http_tx_start),
        .active_route(active_route),
        .led0(led0_raw),
        .led1(led1_raw),
        .uart_tx_busy(uart_tx_busy),
        .tx_start_out(uart_tx_start),
        .tx_byte_out(uart_tx_byte),
        .streamer_busy(streamer_busy)
    );

    // ── On-Board LEDs (Active-Low on Tang Nano 20K) ──
    assign led0 = ~led0_raw;
    assign led1 = ~led1_raw;
    assign led2 = ~rx_done;       // blink active low when byte received
    assign led3 = ~uart_tx_start;  // blink active low when byte sent

endmodule
