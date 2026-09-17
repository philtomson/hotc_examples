// tm_uart_loader.c — UART image loader + result reporter for
// Tsetlin_hotstate_uart. Replaces spi_deserializer.v + tm_hw_top.v's
// run_gpio/data_loaded gating from the SPI-based Tsetlin_hotstate example:
// receives a 98-byte MNIST image over UART, writes it into tm_core_v2's
// input_bram via img_waddr/img_wdata/img_wen, drives tm_seq_controller's
// go/done handshake, and reports the winning class back over UART TX as a
// single byte. Loops forever -- one image in, one result byte out, repeat.
//
// tm_seq_controller.c's own handshake (unchanged, see its source) is:
//   while (!go) {}
//   ... 200-clause evaluation + argmax ...
//   done = 1;
//   while (go) {}
//   done = 0;
// i.e. go/done are LEVEL signals, not pulses: go must stay asserted until
// done is observed, then the caller drops go, which lets tm_seq_controller
// drop done in turn. This mirrors tm_hw_top.v's run_request_reg/
// inference_done gating exactly, just replacing the SPI/run_gpio trigger
// with "98th UART byte received".

bool go = 0;              // level handshake to tm_seq_controller

_BitInt(7) img_waddr = 0;
_BitInt(8) img_wdata = 0;
bool       img_wen   = 0;

_BitInt(8) byte_idx;       // canonical for-loop induction var -> hw timer

bool       rx_done;
_BitInt(8) rx_byte;

bool       done;           // from tm_seq_controller
_BitInt(4) winner;         // from tm_seq_controller (result)

bool       tx_start = 0;
_BitInt(8) tx_data  = 0;
bool       tx_busy;

void step() {
    // Receive the 98-byte image, one byte per UART rx_done pulse.
    // img_waddr = byte_idx is a direct copy from an exposed hardware
    // timer's count into a differently-sized state variable (8 vs 7
    // bits) -- see plans/bugs.md item 10 and
    // plans/timer_count_direct_copy_support.md for the full story of why
    // this once needed a 7-instruction per-bit workaround and doesn't
    // anymore.
    for (byte_idx = 0; byte_idx < 98; byte_idx++) {
        while (!rx_done) {}
        img_waddr = byte_idx;
        img_wdata = rx_byte;
        img_wen = 1;
        img_wen = 0;
    }

    // Trigger inference and wait for it to complete.
    go = 1;
    while (!done) {}

    // Send the winning class back as a single byte, then release go so
    // tm_seq_controller can drop done and reset for the next request.
    tx_data = winner;
    // Hold tx_start until uart_tx acknowledges by raising tx_busy, rather
    // than blindly pulsing it for a fixed 2 cycles -- a naive pulse can be
    // missed by uart_tx's independent busy-wait poll (two separate
    // hotstate machines, no shared clock-enable to guarantee alignment).
    // Matches examples/webserver/response_streamer.v's proven
    // WAIT_TX_FREE/WAIT_TX_BUSY handshake shape.
    tx_start = 1;
    while (!tx_busy) {}
    tx_start = 0;
    while (tx_busy) {}

    go = 0;
}

void main() {
    while (1) { step(); }
}
