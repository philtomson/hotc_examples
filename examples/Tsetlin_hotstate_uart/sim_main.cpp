// sim_main.cpp — Verilator simulation runner for Tsetlin_hotstate_uart
#include <climits>
#include <verilated.h>
#include "Vtm_hw_top_uart_tb.h"
#include <iostream>

static const uint64_t MAX_SIM_TIME = 15000000000ULL;

int main(int argc, char **argv)
{
    VerilatedContext *ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);

    Vtm_hw_top_uart_tb *top = new Vtm_hw_top_uart_tb{ctx};

    top->eval();

    while (!ctx->gotFinish() && ctx->time() < MAX_SIM_TIME) {
        QData next_time = top->nextTimeSlot();
        if (next_time == 0 || next_time >= MAX_SIM_TIME) break;
        ctx->time(next_time);
        top->eval();
    }

    delete top;
    delete ctx;

    std::cout << "\n[SIM] Verilator simulation completed.\n";
    return 0;
}
