#include <verilated.h>
#include <cstdlib>
#include "verilated_vcd_c.h"
#include "verilator_sim.h"
#include "Vgol_tb___024root.h"

#include <fstream>
#include <iostream>
#include <iomanip>
#include <vector>
#include <string>
#include <sstream>
#include <map>
#include <algorithm>
#include <getopt.h>

#define VCD_FILE_DEFAULT "sim_wf.vcd"
#define CSV_FILE_DEFAULT "hardware_trace.csv"

int main(int argc, char **argv)
{
    int max_cycles = 1000;

    if (argc > 1) max_cycles = atoi(argv[1]);

    const char* env_var_vcd = getenv("VCD_FILE");
    if(!env_var_vcd)
       env_var_vcd = VCD_FILE_DEFAULT;
    // Construct context object, design object, and trace object
    VerilatedContext *m_contextp = new VerilatedContext; // Context
    m_contextp->timeunit(-9);      // 1ns
    m_contextp->timeprecision(-12); // 1ps
    VerilatedVcdC *m_tracep = new VerilatedVcdC;         // Trace
    V_tb *m_duvp = new V_tb;                 // Design
    // Trace configuration
    m_contextp->traceEverOn(true);     // Turn on trace switch in context
    m_duvp->trace(m_tracep, 3);        // Set depth to 3
    m_tracep->open(env_var_vcd); // Open the VCD file to store data

    std::ofstream csv_file(CSV_FILE_DEFAULT);
    csv_file << "Cycle,Address,States,Ready,LHS,JmpFlag,JmpBus,Br,Fj,NextPC,StateCap,Rst\n";

    // Write data to the waveform file with timeout
    int cycle = 0;

    // Initialize simulation time and dump initial state
    m_contextp->time(0);
    m_duvp->eval();
    m_tracep->dump(0);

    // Main simulation loop
    while (!m_contextp->gotFinish() && cycle < max_cycles)
    {
        int last_clk = m_duvp->clk;
        
        // Run for one full clock period (20 units)
        for (int i = 0; i < 20; i++) {
            m_contextp->timeInc(1);
            m_duvp->eval();
            m_tracep->dump(m_contextp->time());
            
            // Detect rising edge for logging
            if (m_duvp->clk && !last_clk) {
                if (m_duvp->rst == 0) {
                    csv_file << cycle << ",0x" << std::hex << (int)m_duvp->debug_adr << ",0x";
                    for (int i = 7; i >= 0; i--) csv_file << std::hex << std::setfill('0') << std::setw(8) << m_duvp->states_out[i];
                    csv_file << std::dec << "," 
                             << (int)m_duvp->ready << "," 
                             << (int)m_duvp->lhs_out << "," 
                             << (int)m_duvp->jmp_flag_out << ",0x" 
                             << (int)m_duvp->jmp_bus_out << "," 
                             << (int)m_duvp->br_out << "," 
                             << (int)m_duvp->fj_out << ",0x" << std::hex 
                             << (long long)m_duvp->next_pc << std::dec << "," 
                             << (int)m_duvp->state_capture << "," 
                             << (int)m_duvp->rst << "\n";
                    cycle++;
                }
            }
            last_clk = m_duvp->clk;
        }
    }
    if (cycle >= max_cycles) {
        std::cout << "Simulation timeout after " << max_cycles << " cycles" << std::endl;
    } else {
        std::cout << "Simulation completed after " << cycle << " cycles" << std::endl;
    }
    // Remember to close the trace object to save data in the file
    m_tracep->close();
    // Close CSV file
    csv_file.close();
    // Free memory
    delete m_duvp;
    return 0;
}
