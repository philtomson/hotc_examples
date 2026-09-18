// sim_main_ack_probe.cpp -- regression test for the kan_sdram_shim
// request/ack contract. See kan_ack_probe.v for what is measured and why.
//
// Usage: Vkan_ack_probe [idle_gap_cycles] [run_cycles]
// Exit 0 = every completed handshake corresponds to a real SDRAM write.
//
// This must be run across MANY idle_gap values, not one: the bug it was
// written to catch is invisible at some request spacings purely by phase
// luck (see the `ack_probe` target in the Makefile, and the same lesson in
// test/run_phase_sweep.py).
#include <verilated.h>
#include <cstdio>
#include "Vkan_ack_probe.h"
static Vkan_ack_probe *dut; static VerilatedContext *ctxp;
static void tick(){ dut->clk=0; dut->clk_sdram=1; dut->eval(); ctxp->timeInc(1);
                    dut->clk=1; dut->clk_sdram=0; dut->eval(); ctxp->timeInc(1); }
int main(int argc,char**argv){
  ctxp=new VerilatedContext; Verilated::commandArgs(argc,argv); dut=new Vkan_ack_probe;
  int gap = (argc>1)? atoi(argv[1]) : 40;
  long cycles = (argc>2)? atol(argv[2]) : 3000000;
  dut->idle_gap = gap;
  dut->req_enable=1;
  dut->resetn=0; for(int i=0;i<64;i++) tick();
  dut->resetn=1;
  // Count from reset -- nothing can complete during sdram.v's init/config
  // (granted cannot rise while core_busy), so no baseline subtraction, and
  // therefore no partially-counted operation at a window boundary.
  for(long i=0;i<cycles;i++) tick();
  // Quiesce: stop issuing and let any in-flight operation retire, so the
  // two counters are compared at a point where nothing is mid-flight.
  dut->req_enable=0;
  for(long i=0;i<100000 && !dut->req_idle;i++) tick();
  for(long i=0;i<64;i++) tick();
  if(!dut->req_idle){ printf("FAIL: requester never quiesced (stuck handshake)\n"); return 3; }
  unsigned h=dut->handshakes_done, w=dut->writes_issued;
  printf("idle_gap=%d  handshakes_completed=%u  real_sdram_writes=%u  refreshes=%u\n",
         gap, h, w, dut->refreshes_issued);
  if (h!=w) { printf("  *** MISMATCH: %d handshake(s) completed with NO write issued (%.3f%% of bytes lost)\n",
                     (int)h-(int)w, 100.0*(double)((int)h-(int)w)/(double)(h?h:1)); return 2; }
  printf("  handshakes and writes agree\n"); return 0;
}
