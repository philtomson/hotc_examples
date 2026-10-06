// sim_main.cpp — Verilator clock driver for tb_dlut_uart (all test logic
// lives in the Verilog testbench; this just advances time).
#include <verilated.h>
#include "Vtb_dlut_uart.h"

static const uint64_t MAX_SIM_TIME = 30ULL * 1000 * 1000 * 1000 * 1000;  // 400 ms

int main(int argc, char **argv)
{
    VerilatedContext *ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    Vtb_dlut_uart *top = new Vtb_dlut_uart{ctx};
    top->eval();
    while (!ctx->gotFinish() && ctx->time() < MAX_SIM_TIME) {
        QData next_time = top->nextTimeSlot();
        if (next_time == 0 || next_time >= MAX_SIM_TIME) break;
        ctx->time(next_time);
        top->eval();
    }
    delete top;
    delete ctx;
    return 0;
}
