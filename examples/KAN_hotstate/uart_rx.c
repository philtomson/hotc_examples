// uart_rx.c — 8N1 UART receiver hotstate machine
// Outputs: rx_data (received byte), rx_done (2-cycle strobe), rx_busy
// Input:   rx_in (serial line, idle high)
// Timer:   bit_delay

// BIT_FULL: cycles-4 for one bit period (230 = 27 MHz / 115200 baud).
// Overridden per board by the synth Makefile's CLK_HZ (see
// Makefile.synth_primer25k); the default keeps Tang Nano 9K/20K unchanged.
#ifndef BIT_FULL
#define BIT_FULL 230
#endif
// BIT_HALF: cycles-4 for one bit period (114 = 27 MHz / 115200 baud).
// Overridden per board by the synth Makefile's CLK_HZ (see
// Makefile.synth_primer25k); the default keeps Tang Nano 9K/20K unchanged.
#ifndef BIT_HALF
#define BIT_HALF 114
#endif

_BitInt(8) rx_data = 0;   // received byte
bool rx_done  = 0;         // pulse when byte is ready
bool rx_busy  = 0;         // high while receiving

bool rx_in;                // serial line input
int  bit_delay;            // baud-rate counter (HW_VAR_TIMER)

void step() {
    while (rx_in) {}       // wait for start bit (line goes low)
    rx_busy = 1, rx_data = 0;

    // Wait 1.5 bit periods to centre sampling in first data bit.
    // Hotstate timer loops: for(0;N;) takes N+2 cycles.
    // Centering: 114 setup + 230 bit wait = 344 cycles (~1.47 bit periods).
    for (bit_delay = 0; bit_delay < BIT_HALF; bit_delay++) {}  // 0.5 period
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}  // 1.0 period

    // Sample 8 data bits, LSB first
    if (rx_in) { rx_data[0]=1; } else { rx_data[0]=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}
    if (rx_in) { rx_data[1]=1; } else { rx_data[1]=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}
    if (rx_in) { rx_data[2]=1; } else { rx_data[2]=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}
    if (rx_in) { rx_data[3]=1; } else { rx_data[3]=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}
    if (rx_in) { rx_data[4]=1; } else { rx_data[4]=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}
    if (rx_in) { rx_data[5]=1; } else { rx_data[5]=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}
    if (rx_in) { rx_data[6]=1; } else { rx_data[6]=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}
    if (rx_in) { rx_data[7]=1; } else { rx_data[7]=0; }
    for (bit_delay = 0; bit_delay < BIT_FULL; bit_delay++) {}

    // Assert 2-cycle pulse on rx_done for reliable handshake
    rx_busy = 0, rx_done = 1;
    rx_done = 1;
    rx_done = 0;
}

void main() { while (1) { step(); } }
