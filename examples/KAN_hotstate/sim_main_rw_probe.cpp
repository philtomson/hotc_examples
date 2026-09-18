// sim_main_rw_probe.cpp -- driver for kan_rw_probe.v. See that file for what
// is being tested. Usage: Vkan_rw_probe [num_bytes]  (default 4096)
#include <verilated.h>
#include <cstdio>
#include <cstdlib>
#include "Vkan_rw_probe.h"
static Vkan_rw_probe *dut; static VerilatedContext *ctxp;
static void tick(){ dut->clk=0; dut->clk_sdram=1; dut->eval(); ctxp->timeInc(1);
                    dut->clk=1; dut->clk_sdram=0; dut->eval(); ctxp->timeInc(1); }
int main(int argc,char**argv){
  ctxp=new VerilatedContext; Verilated::commandArgs(argc,argv); dut=new Vkan_rw_probe;
  long n = (argc>1)? atol(argv[1]) : 4096;
  long stride = (argc>2)? atol(argv[2]) : 1;
  dut->num_bytes = n;
  dut->addr_stride = stride;
  dut->resetn=0; for(int i=0;i<64;i++) tick();
  dut->resetn=1;
  long limit = 4000L*n + 2000000L, c=0;
  while(!dut->finished && c<limit){ tick(); c++; }
  if(!dut->finished){
    printf("FAIL: probe did not finish in %ld cycles (writes=%u reads=%u)\n",
           limit, dut->writes_done, dut->reads_done);
    return 1;
  }
  printf("probes=%ld stride=%ld (span %ld bytes) writes=%u reads=%u mismatches=%u\n",
         n, stride, n*stride, dut->writes_done, dut->reads_done, dut->mismatches);
  if(dut->mismatches){
    printf("  first bad: addr=%u expected=0x%02x got=0x%02x  (%.1f%% of bytes wrong)\n",
           dut->first_bad_addr, dut->first_bad_exp, dut->first_bad_got,
           100.0*dut->mismatches/(double)n);
    printf("READBACK: FAIL\n"); return 1;
  }
  printf("READBACK: PASS -- every byte read back as written\n"); return 0;
}
