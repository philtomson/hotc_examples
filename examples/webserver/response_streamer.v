// response_streamer.v — High-speed synthesizable Verilog ROM streamer
// Automatically reads HTTP response arrays from BRAM (.mem files)
// and handles UART serialization with dynamic LED JSON state injection.

`timescale 1ns / 1ps

module response_streamer (
    input  wire        clk,
    input  wire        rst,
    input  wire        tx_start,      // Strobe from http_server
    input  wire [7:0]  active_route,  // Selected route from http_server
    input  wire        led0,          // Current led0 state
    input  wire        led1,          // Current led1 state
    input  wire        uart_tx_busy,  // Busy signal from uart_tx
    output reg         tx_start_out,  // Strobe to uart_tx
    output reg  [7:0]  tx_byte_out,   // Byte to uart_tx
    output reg         streamer_busy  // High while actively streaming
);

    // Response ROM arrays in BRAM
    reg [7:0] rom_main     [0:3853];
    reg [7:0] rom_redirect [0:72];
    reg [7:0] rom_status   [0:108];
    reg [7:0] rom_404      [0:98];

    // Preload responses from generated .mem hex files
    initial begin
        $readmemh("response_main.mem",     rom_main);
        $readmemh("response_redirect.mem", rom_redirect);
        $readmemh("response_status.mem",   rom_status);
        $readmemh("response_404.mem",      rom_404);
    end

    // FSM States
    localparam IDLE         = 3'd0;
    localparam FETCH        = 3'd1;
    localparam WAIT_TX_FREE = 3'd2;
    localparam STROBE       = 3'd3;
    localparam WAIT_TX_BUSY = 3'd4;
    localparam NEXT         = 3'd5;

    // fsm_encoding="none" opts this register out of yosys's automatic FSM
    // extraction/re-encoding pass (run by synth_gowin's default flow).
    // Without it, the streamer synthesizes and PNRs cleanly and matches
    // this RTL in Verilator simulation, but on real Tang Nano 9K/20K
    // hardware it never leaves IDLE after tx_start -- confirmed via a
    // real debug output port that state settles on an unreachable
    // encoding, and confirmed the attribute is the fix by isolating it
    // against the fully unmodified RTL (0 bytes without it, correct
    // 73/109/3769-byte responses with it, nothing else changed). Likely
    // triggered by STROBE (3'd3) being declared but never reached by any
    // transition -- see plans/bugs.md.
    (* fsm_encoding = "none" *) reg [2:0]  state;
    reg [7:0]  route;
    reg [11:0] idx;
    reg [11:0] limit;
    reg [7:0]  curr_byte;

    always @(posedge clk) begin
        if (rst) begin
            state         <= IDLE;
            tx_start_out  <= 1'b0;
            tx_byte_out   <= 8'h00;
            streamer_busy <= 1'b0;
            idx           <= 12'd0;
            route         <= 8'd0;
            limit         <= 12'd0;
        end else begin
            case (state)
                IDLE: begin
                    tx_start_out <= 1'b0;
                    if (tx_start) begin
                        route         <= active_route;
                        idx           <= 12'd0;
                        streamer_busy <= 1'b1;
                        state         <= FETCH;
                        
                        // Set loop limits based on active route
                        case (active_route)
                            8'd0:    limit <= 12'd3854; // rom_main
                            8'd1:    limit <= 12'd73;   // rom_redirect
                            8'd3:    limit <= 12'd109;  // rom_status
                            default: limit <= 12'd99;   // rom_404
                        endcase
                    end else begin
                        streamer_busy <= 1'b0;
                    end
                end

                FETCH: begin
                    if (idx >= limit) begin
                        state         <= IDLE;
                        streamer_busy <= 1'b0;
                    end else begin
                        state <= WAIT_TX_FREE;
                        
                        // Fetch byte from active ROM and handle inline JSON injections
                        case (route)
                            8'd0: curr_byte <= rom_main[idx];
                            8'd1: curr_byte <= rom_redirect[idx];
                            8'd3: begin
                                if (idx == 12'd98) begin
                                    curr_byte <= led0 ? 8'h31 : 8'h30; // '1' or '0'
                                end else if (idx == 12'd107) begin
                                    curr_byte <= led1 ? 8'h31 : 8'h30; // '1' or '0'
                                end else begin
                                    curr_byte <= rom_status[idx];
                                end
                            end
                            default: curr_byte <= rom_404[idx];
                        endcase
                    end
                end

                WAIT_TX_FREE: begin
                    if (!uart_tx_busy) begin
                        tx_byte_out  <= curr_byte;
                        tx_start_out <= 1'b1;
                        state        <= WAIT_TX_BUSY;
                    end
                end

                WAIT_TX_BUSY: begin
                    // Wait until UART transmitter begins transmitting
                    if (uart_tx_busy) begin
                        tx_start_out <= 1'b0;
                        state        <= NEXT;
                    end
                end

                NEXT: begin
                    // Wait for UART transmitter to finish before sending next character
                    if (!uart_tx_busy) begin
                        idx   <= idx + 12'd1;
                        state <= FETCH;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
