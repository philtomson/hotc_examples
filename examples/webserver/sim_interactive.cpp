// sim_interactive.cpp — Real-time interactive TCP bridge for Verilator simulation
#include <climits>
#include <verilated.h>
#include "Vwebserver_top.h"
#include <iostream>
#include <queue>
#include <unistd.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <errno.h>

static const int CYCLES_PER_BIT = 234;

struct UartTxSim {
    std::queue<uint8_t> q;
    int state = 0; // 0 = idle, 1 = start, 2 = data, 3 = stop
    int bit_idx = 0;
    int cycle_cnt = 0;
    uint8_t current_byte = 0;
    bool line_val = 1;

    void step() {
        if (state == 0) {
            line_val = 1;
            if (!q.empty()) {
                current_byte = q.front();
                q.pop();
                state = 1; // start bit
                cycle_cnt = 0;
            }
        }
        
        if (state == 1) { // START bit
            line_val = 0;
            cycle_cnt++;
            if (cycle_cnt >= CYCLES_PER_BIT) {
                state = 2; // data bits
                bit_idx = 0;
                cycle_cnt = 0;
            }
        } else if (state == 2) { // DATA bits
            line_val = (current_byte >> bit_idx) & 1;
            cycle_cnt++;
            if (cycle_cnt >= CYCLES_PER_BIT) {
                bit_idx++;
                cycle_cnt = 0;
                if (bit_idx >= 8) {
                    state = 3; // stop bit
                }
            }
        } else if (state == 3) { // STOP bit
            line_val = 1;
            cycle_cnt++;
            if (cycle_cnt >= CYCLES_PER_BIT) {
                state = 0; // back to idle
                cycle_cnt = 0;
            }
        }
    }
};

struct UartRxSim {
    int state = 0; // 0 = idle, 1 = wait start half-period, 2 = wait data bits
    int bit_idx = 0;
    int cycle_cnt = 0;
    uint8_t current_byte = 0;
    bool prev_line = 0;
    bool byte_ready = false;
    uint8_t received_byte = 0;

    void step(bool line_val) {
        byte_ready = false;
        if (state == 0) {
            // Wait for falling edge (start bit)
            if (prev_line && !line_val) {
                state = 1;
                cycle_cnt = 0;
            }
        } else if (state == 1) {
            // Wait 1.5 bit periods to sample the middle of data bit 0
            cycle_cnt++;
            if (cycle_cnt >= CYCLES_PER_BIT + (CYCLES_PER_BIT / 2)) {
                state = 2;
                bit_idx = 0;
                cycle_cnt = 0;
                // Sample bit 0
                if (line_val) {
                    current_byte |= (1 << bit_idx);
                } else {
                    current_byte &= ~(1 << bit_idx);
                }
                std::cout << "[SIM RX] Bit 0 sampled: " << (int)line_val << "\n";
            }
        } else if (state == 2) {
            cycle_cnt++;
            if (cycle_cnt >= CYCLES_PER_BIT) {
                bit_idx++;
                cycle_cnt = 0;
                if (bit_idx < 8) {
                    // Sample next data bit
                    if (line_val) {
                        current_byte |= (1 << bit_idx);
                    } else {
                        current_byte &= ~(1 << bit_idx);
                    }
                    std::cout << "[SIM RX] Bit " << bit_idx << " sampled: " << (int)line_val << "\n";
                } else {
                    // Finished sampling all 8 data bits
                    received_byte = current_byte;
                    byte_ready = true;
                    state = 0;
                    current_byte = 0;
                }
            }
        }
        prev_line = line_val;
    }
};

int main(int argc, char **argv)
{
    VerilatedContext *ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);

    Vwebserver_top *top = new Vwebserver_top{ctx};
    
    // Set up non-blocking TCP socket to listen on port 8081
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        std::cerr << "Failed to create socket!\n";
        return 1;
    }
    
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    int flags = fcntl(server_fd, F_GETFL, 0);
    fcntl(server_fd, F_SETFL, flags | O_NONBLOCK);
    
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8081);
    
    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        std::cerr << "Failed to bind to port 8081!\n";
        return 1;
    }
    
    if (listen(server_fd, 3) < 0) {
        std::cerr << "Failed to listen!\n";
        return 1;
    }
    
    std::cout << "\n======================================================================\n";
    std::cout << "🚀 INTERACTIVE VERILATOR SIMULATION RUNNING\n";
    std::cout << "👉 Connect your browser directly to: http://localhost:8081\n";
    std::cout << "======================================================================\n\n";

    // Reset sequence
    top->rst_n = 1;
    top->uart_rxd = 1;
    top->eval();
    
    for (int i = 0; i < 100; i++) {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
    }
    top->rst_n = 0;
    for (int i = 0; i < 200; i++) {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
    }
    top->rst_n = 1;
    for (int i = 0; i < 200; i++) {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
    }

    UartTxSim tx_sim;
    UartRxSim rx_sim;
    int client_fd = -1;
    uint64_t main_time = 0;

    while (!ctx->gotFinish()) {
        // Periodically check for socket connections and read data
        if (main_time % 1000 == 0) {
            if (client_fd < 0) {
                client_fd = accept(server_fd, nullptr, nullptr);
                if (client_fd >= 0) {
                    int cflags = fcntl(client_fd, F_GETFL, 0);
                    fcntl(client_fd, F_SETFL, cflags | O_NONBLOCK);
                    std::cout << "[SIM] Client connected to simulator!\n";
                }
            }
            
            if (client_fd >= 0) {
                char buf[2048];
                int n = recv(client_fd, buf, sizeof(buf), 0);
                if (n > 0) {
                    for (int i = 0; i < n; i++) {
                        tx_sim.q.push(buf[i]);
                        if (buf[i] >= 32 && buf[i] <= 126) {
                            std::cout << "[Host -> FPGA] '" << (char)buf[i] << "'\n";
                        } else {
                            std::cout << "[Host -> FPGA] 0x" << std::hex << (int)(uint8_t)buf[i] << std::dec << "\n";
                        }
                    }
                } else if (n == 0 || (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK)) {
                    std::cout << "[SIM] Client disconnected.\n";
                    close(client_fd);
                    client_fd = -1;
                }
            }
        }

        // Cycle power saving usleep to keep host CPU usage low when idle
        if (client_fd < 0) {
            usleep(1000); // 1ms sleep when no active client
        }

        // Step UART Transmitter
        tx_sim.step();
        top->uart_rxd = tx_sim.line_val;

        // Toggle clock cycle
        top->clk = 0;
        top->eval();
        
        top->clk = 1;
        top->eval();

        // Step UART Receiver
        rx_sim.step(top->uart_txd);
        if (rx_sim.byte_ready) {
            if (rx_sim.received_byte >= 32 && rx_sim.received_byte <= 126) {
                std::cout << "[FPGA -> Host] '" << (char)rx_sim.received_byte << "'\n";
            } else {
                std::cout << "[FPGA -> Host] 0x" << std::hex << (int)rx_sim.received_byte << std::dec << "\n";
            }
            if (client_fd >= 0) {
                send(client_fd, &rx_sim.received_byte, 1, 0);
            }
        }

        main_time++;
    }

    if (client_fd >= 0) close(client_fd);
    close(server_fd);
    delete top;
    delete ctx;
    return 0;
}
