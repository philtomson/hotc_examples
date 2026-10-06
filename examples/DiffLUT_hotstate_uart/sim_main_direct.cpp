#include <verilated.h>
#include "Vtb_direct.h"
int main(int argc, char **argv) {
    VerilatedContext *ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    Vtb_direct *top = new Vtb_direct{ctx};
    top->eval();
    while (!ctx->gotFinish() && ctx->time() < 10ULL * 1000 * 1000 * 1000) {
        QData next_time = top->nextTimeSlot();
        if (next_time == 0) break;
        ctx->time(next_time);
        top->eval();
    }
    delete top;
    delete ctx;
    return 0;
}
