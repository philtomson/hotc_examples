// http_server.c — Lightweight HTTP streaming parser for hybrid FPGA Webserver
// Inputs: rx_done, rx_byte (UART), tx_busy (from Verilog response streamer)
// Outputs: tx_start (trigger strobe for streamer), active_route, led0, led1

#pragma hotwright counter crlf

bool tx_start = 0;
bool led0 = 0;             // High = Active
bool led1 = 0;             // High = Active

bool rx_done;
_BitInt(8) rx_byte;
bool tx_busy;

_BitInt(8) active_route = 0; // 0 = main page, 1 = redirect, 2 = 404, 3 = JSON status
_BitInt(8) crlf = 0;

void step() {
    // Step 1: Parse request line "GET /" character by character
    while (!rx_done) {}
    if (rx_byte != 'G') return;
    
    while (!rx_done) {}
    if (rx_byte != 'E') return;
    
    while (!rx_done) {}
    if (rx_byte != 'T') return;
    
    while (!rx_done) {}
    if (rx_byte != ' ') return;
    
    while (!rx_done) {}
    if (rx_byte != '/') return;
    
    // Step 2: Read next character to determine route
    while (!rx_done) {}
    if (rx_byte == 's') {
        active_route = 3;
    } else if (rx_byte == '0') {
        active_route = 1;
        while (!rx_done) {}
        if (rx_byte == '1') { led0 = 1; }
        else if (rx_byte == '0') { led0 = 0; }
    } else if (rx_byte == '1') {
        active_route = 1;
        while (!rx_done) {}
        if (rx_byte == '1') { led1 = 1; }
        else if (rx_byte == '0') { led1 = 0; }
    } else if (rx_byte == ' ' || rx_byte == '\r' || rx_byte == '\n') {
        active_route = 0;
    } else {
        active_route = 2;
    }
    
    // Step 3: Skip remaining request headers until we see \r\n\r\n
    crlf = 0;
    while (1) {
        if (crlf >= 4) {
            break;
        }
        
        while (!rx_done) {}
        if (rx_byte == '\r' || rx_byte == '\n') {
            crlf++;
        } else {
            crlf = 0;
        }
    }
    
    // Step 4: Kick off Verilog response streamer
    tx_start = 1;
    tx_start = 0;
    
    // Step 5: Wait until transmission is done
    while (tx_busy) {}
}

void main() {
    while (1) {
        step();
    }
}
