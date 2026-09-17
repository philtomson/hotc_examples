# Makefile for ST7789 SPI LCD Game of Life on Tang Nano 9K — gol-hotstate
# Target FPGA: Sipeed Tang Nano 9K (Gowin GW1NR-LV9QN88PC6/I5)
#
# gol.c + lcd_driver.c were compiled together via hotc's multi-file merge
# (gol.c first, so generated module/file names take "gol"; see
# lcd_driver.h for the small set of variables shared by name between the
# two). gol_template.v and friends below are hotc's OUTPUT, checked in as-is
# -- this repo doesn't ship the hotc compiler itself, so there is no
# `generate` step. If you're not modifying the design, `make prog` just
# builds and flashes what's here.

IP_DIR    = ../../IP

-include ../../tools.mk
-include ../../local.mk

# ── Gowin device parameters ───────────────────────────────────────────────
GOWIN_DEVICE = GW1NR-LV9QN88PC6/I5
GOWIN_FAMILY = GW1N-9C
TOP          = top
CST          = lcd114.cst

SRCS = top.v \
       gol_template.v \
       $(IP_DIR)/hotstate.sv \
       $(IP_DIR)/microcode.sv \
       $(IP_DIR)/control.sv \
       $(IP_DIR)/next_address.sv \
       $(IP_DIR)/timer.sv \
       $(IP_DIR)/variable.sv \
       $(IP_DIR)/switch.sv \
       $(IP_DIR)/stack.sv

.PHONY: hw_sim synth pnr pack prog clean

# ── Simulation (Verilator; free-running trace capture, not self-checking) ──
hw_sim:
	verilator --timing --cc -Wno-fatal --exe --trace --trace-structs --build -I. \
	  sim_main.cpp gol_tb.v gol_template.v \
	  $(IP_DIR)/hotstate.sv $(IP_DIR)/microcode.sv $(IP_DIR)/control.sv \
	  $(IP_DIR)/next_address.sv $(IP_DIR)/stack.sv $(IP_DIR)/switch.sv \
	  $(IP_DIR)/timer.sv $(IP_DIR)/variable.sv --top gol_tb
	./obj_dir/Vgol_tb
	@echo "Trace: hardware_trace.csv, sim_wf.vcd"

synth:
	@echo "=== Yosys Gowin synthesis for $(TOP) (Tang Nano 9K) ==="
	$(YOSYS) -ql synth_tang9k.log -p " \
	  read_verilog -sv $(SRCS); \
	  hierarchy -check -top $(TOP); \
	  synth_gowin -top $(TOP) -json synth_tang9k.json; \
	  stat"
	@echo "=== Gowin 9K synthesis done — see synth_tang9k.log ==="

pnr: synth
	@echo "=== nextpnr-himbaechel Gowin 9K place and route ==="
	$(NEXTPNR_HIMB) \
	    --device $(GOWIN_DEVICE) \
	    -o family=$(GOWIN_FAMILY) \
	    --json synth_tang9k.json \
	    -o cst=$(CST) \
	    --write pnr_tang9k.json
	@echo "=== Gowin 9K P&R done — see pnr_tang9k.json ==="

pack: pnr
	@echo "=== gowin_pack: creating 9K bitstream ==="
	$(GOWIN_PACK) -d $(GOWIN_FAMILY) -o design_tang9k.fs pnr_tang9k.json
	@echo "=== Bitstream: design_tang9k.fs ==="

prog: pack
	@echo "=== openFPGALoader: programming Tang Nano 9K ==="
	$(OPENFPGALOADER) -b tangnano9k design_tang9k.fs
	@echo "=== Programming done ==="

clean:
	rm -f synth_tang9k.json synth_tang9k.log pnr_tang9k.json design_tang9k.fs
	rm -rf obj_dir hardware_trace.csv sim_wf.vcd
