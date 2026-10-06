// dlut_uart_loader.c — hotc source for the DiffLUT-Net UART loader.
// Mirrors Tsetlin_hotstate_uart's tm_uart_loader.c: receives a 784-byte
// binarized MNIST image over UART (one byte per pixel, bit k of byte p =
// threshold-bit k for pixel p), writes it into image_reg via
// img_waddr/img_wdata/img_wen, waits for the free-running DiffLUT network
// pipeline to flush (4 cycles; 16 for margin), and reports the argmax digit
// back over UART TX as a single byte (low nibble). Loops forever.
//
// Differences from tm_uart_loader.c: 784 bytes (10-bit write address), the
// go/done handshake is replaced by a fixed timer wait (logic_net is a
// free-running registered pipeline, not a sequencer), and the result comes
// from the external combinational argmax over the 10 per-class sums.

bool       busy = 0;      // high while an image is being received/classified

_BitInt(10) img_waddr = 0;
_BitInt(8)  img_wdata = 0;
bool        img_wen   = 0;

_BitInt(10) byte_idx;      // canonical for-loop induction var -> hw timer
_BitInt(10) w;             // pipeline-flush wait loop -> hw timer

bool        rx_done;
_BitInt(8)  rx_byte;
bool        tx_busy;
_BitInt(4)  digit;         // external: combinational argmax over class sums

bool        tx_start = 0;
_BitInt(8)  tx_data  = 0;

void step() {
    busy = 1;

    // Receive the 784-byte image, one byte per uart_rx rx_done pulse.
    for (byte_idx = 0; byte_idx < 784; byte_idx++) {
        while (!rx_done) {}
        img_waddr = byte_idx;
        img_wdata = rx_byte;
        img_wen = 1;
        img_wen = 0;
    }

    // Pipeline flush: the network's output register settles 4 cycles after
    // the last input byte lands; 16 cycles is margin.
    for (w = 0; w < 16; w++) {
        img_wen = 0;
    }

    // Send the predicted digit back as a single byte, same tx handshake as
    // tm_uart_loader.c (hold tx_start until uart_tx raises tx_busy).
    tx_data = digit;
    tx_start = 1;
    while (!tx_busy) {}
    tx_start = 0;
    while (tx_busy) {}

    busy = 0;
}

void main() {
    while (1) { step(); }
}
