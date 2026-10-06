// tb_dlut_uart.v — end-to-end testbench: bit-bangs `n_img` binarized MNIST
// images (784 bytes each, from gen/images.hex) into the UART RX pin at
// 115200 baud, decodes the single result byte per image from uart_txd, and
// checks it against the Julia model's predictions (gen/expect.hex).
//
//   gen/images.hex  — N lines × 784 hex bytes (bit-packed threshold bits)
//   gen/expect.hex  — N lines, predicted digit per image (hex)
//   plusargs: +n=<images> (default 20)
//
// Note on inference latency: after the 784th byte the registered pipeline
// settles in 4 clocks and the loader waits 16 before asserting tx, so the
// response arrives ~80 UART bit-times after the last data byte. The receiver
// task below has a generous inter-byte timeout.
`timescale 1ns / 1ps

module tb_dlut_uart;
    localparam IMG_BYTES = 784;
    localparam CLK_HALF  = 10;        // 50 MHz (20 ns period)
    localparam BITP      = 434;       // 115200 baud @ 50 MHz

    reg clk = 0, rst_n = 0, uart_rxd = 1;
    wire uart_txd, done_led;
    integer n_img = 20, k;

    dlut_hw_top_uart dut (
        .clk(clk), .rst_n(rst_n),
        .uart_rxd(uart_rxd), .uart_txd(uart_txd),
        .done_led(done_led)
    );
    always #CLK_HALF clk = ~clk;

    reg [7:0] images  [0:IMG_BYTES*500-1];
    reg [7:0] expectv [0:499];
    integer errors, i, d;
    reg [7:0] resp;

    task send_byte(input [7:0] data);
        integer b;
        begin
            uart_rxd = 0;                       // START
            repeat (BITP) @(posedge clk);
            for (b = 0; b < 8; b = b + 1) begin
                uart_rxd = data[b];
                repeat (BITP) @(posedge clk);
            end
            uart_rxd = 1;                       // STOP
            repeat (BITP) @(posedge clk);
        end
    endtask

    // decode one response byte from uart_txd: wait for the START bit (line
    // falls), then sample the 8 data bits at their centers
    task recv_byte(output [7:0] r);
        integer b;
        begin
            @(negedge uart_txd);
            #(BITP * 30);                       // 1.5 bits: mid first data bit
            for (b = 0; b < 8; b = b + 1) begin
                r[b] = uart_txd;
                #(BITP * 20);
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("n=%d", n_img)) n_img = 20;
        $readmemh("gen/images.hex", images);
        $readmemh("gen/expect.hex", expectv);
        $display("[TB] img[0]=%h img[1]=%h img[202]=%h img[203]=%h img[784]=%h img[786]=%h",
                 images[0], images[1], images[202], images[203],
                 images[784], images[786]);
        rst_n = 0;
        repeat (20) @(posedge clk);
        rst_n = 1;
        repeat (20) @(posedge clk);

        // image 0: dump the response waveform at half-bit resolution
        begin
            reg [95:0] wave;
            fork
                begin
                    for (d = 0; d < IMG_BYTES; d = d + 1)
                        send_byte(images[d]);
                end
                begin
                    @(negedge uart_txd);
                    for (k = 0; k < 96; k = k + 1) begin
                        wave[k] = uart_txd;
                        #(BITP * 10);
                    end
                end
            join_any
            $display("[TB] response waveform (half-bit samples, LSB = first): %b", wave);
            repeat (2000) @(posedge clk);
        end
        errors = 0;
        for (i = 0; i < n_img; i = i + 1) begin
            // the loader's response can begin while the last image bytes are
            // still being sent, so the receiver must run concurrently
            fork
                begin : send_image
                    for (d = 0; d < IMG_BYTES; d = d + 1)
                        send_byte(images[i * IMG_BYTES + d]);
                end
                begin : recv_result
                    recv_byte(resp);
                end
            join
            if (i == 0) begin
                // raw waveform dump: uart_txd sampled every half bit around the response
                $display("[TB] txd waveform dump not shown for i>0");
            end
            $display("[TB] image %0d resp=%h expect=%h", i, resp, expectv[i]);
            if (resp[3:0] !== expectv[i]) begin
                $display("[TB] MISMATCH image %0d: sim=%0d expect=%0d",
                         i, resp[3:0], expectv[i]);
                errors = errors + 1;
            end else if (i < 5) begin
                $display("[TB] image %0d: digit %0d (expected %0d) OK",
                         i, resp[3:0], expectv[i]);
            end
        end
        if (errors == 0)
            $display("[TB] PASS: %0d/%0d images match the Julia model", n_img, n_img);
        else
            $display("[TB] FAIL: %0d/%0d mismatched", errors, n_img);
        $finish;
    end
endmodule
