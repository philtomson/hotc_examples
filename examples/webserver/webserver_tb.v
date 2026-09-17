// webserver_tb.v — Self-contained Verilator integration testbench
// Generates 36 ns clock (27.7 MHz), simulates UART transmissions using
// integer-aligned delays to ensure perfect Verilator timing precision.

`timescale 1ns / 1ps

module webserver_tb (
    output reg clk,
    output reg rst_n,
    output reg uart_rxd,
    output wire uart_txd,
    output wire led0,
    output wire led1,
    output wire led2,
    output wire led3
);

    // 27.7 MHz Clock generator (period = 36 ns, half-period = 18 ns)
    initial clk = 0;
    always #18 clk = ~clk;

    // Instantiate Design Under Test (DUT)
    webserver_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd),
        .led0(led0),
        .led1(led1),
        .led2(led2),
        .led3(led3)
    );

    // Bit period is exactly 234 cycles * 36 ns/cycle = 8424 ns
    parameter BIT_PERIOD = 8424;

    // Task to send a byte over UART RX line
    task send_byte(input [7:0] data);
        integer bit_idx;
        begin
            // START bit (low)
            uart_rxd = 0;
            #BIT_PERIOD;
            
            // 8 Data bits (LSB first)
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                uart_rxd = data[bit_idx];
                #BIT_PERIOD;
            end
            
            // STOP bit (high)
            uart_rxd = 1;
            #BIT_PERIOD;
            #(BIT_PERIOD * 2); // padding between bytes
        end
    endtask

    // Task to send a full string over UART
    task send_string(input [8*100-1:0] str, input integer len);
        integer char_idx;
        reg [7:0] char;
        begin
            for (char_idx = len - 1; char_idx >= 0; char_idx = char_idx - 1) begin
                char = str[char_idx*8 +: 8];
                send_byte(char);
            end
        end
    endtask

    // Capture received UART TX bytes and print to console
    reg [7:0] rx_char;
    integer rx_bit_idx;
    
    always @(negedge uart_txd) begin
        // Wait 1.5 periods to center sample
        #(BIT_PERIOD * 1.5);
        for (rx_bit_idx = 0; rx_bit_idx < 8; rx_bit_idx = rx_bit_idx + 1) begin
            rx_char[rx_bit_idx] = uart_txd;
            #BIT_PERIOD;
        end
        $write("%c", rx_char);
        $fflush();
    end

    // Monitor trace
    initial begin
        $monitor("Time=%0t | RX_PC=%3d HTTP_PC=%3d | rxd=%b txd=%b rx_done=%b rx_data=0x%h led0=%b", 
                 $time, dut.u_rx.debug_adr, dut.u_http.debug_adr, uart_rxd, uart_txd, dut.rx_done, dut.rx_data, led0);
    end

    // Main Test Stimulus Sequence
    initial begin
        $display("\n==================================================");
        $display("   STARTING FPGA HTTP WEBSERVER INTEGRATION TEST");
        $display("==================================================");
        
        // Initialize lines
        rst_n = 1;
        uart_rxd = 1;
        
        // Assert reset for 10 cycles
        #100;
        rst_n = 0;
        #500;
        rst_n = 1;
        #1000;
        
        $display("\n[TEST 1] Query Initial JSON Status (/s)");
        $display("--------------------------------------------------");
        send_string({"GET /s", 8'h0d, 8'h0a, 8'h0d, 8'h0a}, 10);
        
        // Wait for response to stream completely
        #2500000;
        
        $display("\n[TEST 2] Toggle LED 0 ON (/01)");
        $display("--------------------------------------------------");
        send_string({"GET /01", 8'h0d, 8'h0a, 8'h0d, 8'h0a}, 11);
        #1500000;
        
        $display("\n[TEST 3] Query Updated JSON Status (/s)");
        $display("--------------------------------------------------");
        send_string({"GET /s", 8'h0d, 8'h0a, 8'h0d, 8'h0a}, 10);
        #2500000;
        
        $display("\n[TEST 4] Test 404 Route (/invalid)");
        $display("--------------------------------------------------");
        send_string({"GET /invalid", 8'h0d, 8'h0a, 8'h0d, 8'h0a}, 16);
        #2000000;

        $display("\n==================================================");
        $display("   INTEGRATION TEST COMPLETE");
        $display("==================================================");
        $finish;
    end

endmodule
