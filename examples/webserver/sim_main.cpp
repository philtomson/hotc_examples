// sim_main.cpp — Verilator simulation runner for Hotwright HTTP Server
#include <climits>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vwebserver_tb.h"
#include <iostream>

// 15 seconds limit in simulation time (represented in time units)
static const uint64_t MAX_SIM_TIME = 15000000000ULL; 

int main(int argc, char **argv)
{
    VerilatedContext *ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    ctx->traceEverOn(true);

    Vwebserver_tb *top = new Vwebserver_tb{ctx};
    
    VerilatedVcdC *trace = new VerilatedVcdC;
    top->trace(trace, 5);
    trace->open("webserver_sim.vcd");

    // Prime the simulation
    top->eval();
    trace->dump(ctx->time());

    // Canonical Verilator event-driven loop
    while (!ctx->gotFinish() && ctx->time() < MAX_SIM_TIME) {
        QData next_time = top->nextTimeSlot();
        if (next_time == 0 || next_time >= MAX_SIM_TIME) {
            // No more scheduled events or limit reached
            break;
        }
        ctx->time(next_time);
        top->eval();
        trace->dump(ctx->time());
    }

    trace->close();
    delete trace;
    delete top;
    delete ctx;

    std::cout << "\n[SIM] Verilator simulation completed successfully.\n";
    return 0;
}
