// tm_hw_top_uart_tb.v — Verilator integration testbench for
// tm_hw_top_uart: sends a real MNIST test image (sample 0 of
// batch_ref.bin, via sample0.hex) over simulated UART, waits for the
// 1-byte classification result, and checks it against Julia's own
// prediction for that sample (digit 7). A real image is used rather than
// the all-zero image this testbench originally sent: an all-zero image
// written to input_bram[0] on every iteration is indistinguishable from
// one correctly advancing through the image, so it can't catch a stuck
// write address -- which is exactly what was silently broken here (see
// plans/bugs.md item 10). The input_bram[] dumps below are what caught
// it: they showed writes landing at input_bram[0] instead of advancing.

`timescale 1ns / 1ps

module tm_hw_top_uart_tb (
    output reg  clk,
    output reg  rst_n,
    output reg  uart_rxd,
    output wire uart_txd,
    output wire done_led
);

    // 27 MHz clock generator (period = 36 ns, half-period = 18 ns)
    initial clk = 0;
    always #18 clk = ~clk;

    tm_hw_top_uart dut (
        .clk(clk), .rst_n(rst_n),
        .uart_rxd(uart_rxd), .uart_txd(uart_txd),
        .done_led(done_led)
    );

    // Bit period is exactly 234 cycles * 36 ns/cycle = 8424 ns (115200 baud)
    parameter BIT_PERIOD = 8424;

    task send_byte(input [7:0] data);
        integer bit_idx;
        begin
            uart_rxd = 0;                     // START bit
            #BIT_PERIOD;
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                uart_rxd = data[bit_idx];
                #BIT_PERIOD;
            end
            uart_rxd = 1;                     // STOP bit
            #BIT_PERIOD;
        end
    endtask

    // Capture the single result byte sent back over uart_txd.
    reg [7:0] result_byte;
    reg       result_seen;
    integer   rx_bit_idx;
    always @(negedge uart_txd) begin
        if (!result_seen) begin
            #(BIT_PERIOD * 1.5);              // center of first data bit
            for (rx_bit_idx = 0; rx_bit_idx < 8; rx_bit_idx = rx_bit_idx + 1) begin
                result_byte[rx_bit_idx] = uart_txd;
                #BIT_PERIOD;
            end
            result_seen = 1;
        end
    end

    integer i;
    reg [7:0] test_img [0:97];

    initial begin
        result_seen = 0;
        uart_rxd = 1;
        rst_n = 1;
        #100;  rst_n = 0;
        #500;  rst_n = 1;
        #1000;

        // Real MNIST sample 0 from batch_ref.bin (true=7, julia=7).
        $readmemh("sample0.hex", test_img);

        $display("[TB] t=%0t Sending 98-byte test image over UART...", $time);
        for (i = 0; i < 98; i = i + 1) send_byte(test_img[i]);

        $display("[TB] t=%0t All 98 bytes sent. go=%b done=%b.", $time, dut.go, dut.done);
        // Dump what actually landed in input_bram vs. what was sent --
        // this is what caught item 10 (see file header comment).
        $display("[TB]   input_bram[25]=%02h (sent %02h)", dut.tm.core.input_bram[25], test_img[25]);
        $display("[TB]   input_bram[28]=%02h (sent %02h)", dut.tm.core.input_bram[28], test_img[28]);
        $display("[TB]   input_bram[29]=%02h (sent %02h)", dut.tm.core.input_bram[29], test_img[29]);
        $display("[TB]   input_bram[30]=%02h (sent %02h)", dut.tm.core.input_bram[30], test_img[30]);
        $display("[TB]   input_bram[97]=%02h (sent %02h)", dut.tm.core.input_bram[97], test_img[97]);
        $display("[TB] Waiting for result byte...");
        wait (result_seen);
        $display("[TB] t=%0t Result byte captured.", $time);
        #(BIT_PERIOD);  // let STOP bit clear

        if (result_byte[3:0] === 4'd7) begin
            $display("[TB] PASS: result=%0d (expected 7, matches Julia's prediction for this sample)", result_byte[3:0]);
        end else begin
            $display("[TB] FAIL: result=%0d (expected 7)", result_byte[3:0]);
        end

        $finish;
    end

    // Safety timeout
    initial begin
        #40000000;  // 40 ms sim time
        if (!result_seen) $display("[TB] t=%0t TIMEOUT: no result byte received (go=%b done=%b)", $time, dut.go, dut.done);
        $finish;
    end

    // Progress heartbeat
    always @(posedge dut.go)   $display("[TB] t=%0t go asserted", $time);
    always @(posedge dut.done) $display("[TB] t=%0t done asserted (winner=%0d)", $time, dut.winner);

endmodule
