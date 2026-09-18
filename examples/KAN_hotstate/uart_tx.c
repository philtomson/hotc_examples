// uart_tx.c — 8N1 UART transmitter hotstate machine
// Outputs: tx_bit (serial line, idle high), tx_busy
// Inputs:  tx_start (1-cycle write strobe), tx_data (byte to send)
// Timer:   bit_delay counts 230 cycles per bit (234 cycles total @ 27 MHz)

// BIT_FULL: cycles-4 for one bit period (230 = 27 MHz / 115200 baud).
// Overridden per board by the synth Makefile's CLK_HZ (see
// Makefile.synth_primer25k); the default keeps Tang Nano 9K/20K unchanged.
#ifndef BIT_FULL
#define BIT_FULL 230
#endif

bool tx_bit  = 1;          // serial line, idle high
bool tx_busy = 0;          // high while frame is in progress

bool         tx_start;     // CPU write strobe
_BitInt(8)   tx_data;      // byte to transmit

int bit_delay;             // baud-rate counter (HW_VAR_TIMER)

void step() {
    while (!tx_start) {}   // wait for CPU write

    tx_busy = 1;

    // START bit (line low)
    // Hotstate timer loops take N+2 cycles; if/else bit-set takes 2 cycles.
    // Per-bit = (N+2)+2 = N+4. For 234 cycles/bit (115200 baud @ 27 MHz): N=230.
    tx_bit = 0;
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}

    // 8 data bits, LSB first
    if (tx_data[0]) { tx_bit=1; } else { tx_bit=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}
    if (tx_data[1]) { tx_bit=1; } else { tx_bit=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}
    if (tx_data[2]) { tx_bit=1; } else { tx_bit=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}
    if (tx_data[3]) { tx_bit=1; } else { tx_bit=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}
    if (tx_data[4]) { tx_bit=1; } else { tx_bit=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}
    if (tx_data[5]) { tx_bit=1; } else { tx_bit=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}
    if (tx_data[6]) { tx_bit=1; } else { tx_bit=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}
    if (tx_data[7]) { tx_bit=1; } else { tx_bit=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}

    // STOP bit (line high)
    tx_bit = 1;
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}

    tx_busy = 0;
}

void main() { while (1) { step(); } }
