# MicroCNN_hotstate -- host-side benchmark targets and a lint of the generated
# core. No hotc needed: the generated microcode is checked in. The bitstream
# is built by Makefile.synth_primer25k (Tang Primer 25K) or
# Makefile.synth_tang20k_gowin (Tang Nano 20K).

PYTHON ?= python3

# Override per invocation, e.g.  make hw-infer IDX=26 PORT=/dev/ttyUSB1
PORT  ?= /dev/ttyUSB1
BAUD  ?= 115200
IDX   ?= 0
SPLIT ?= test

MODULE = main_controller
IP_DIR = ../../IP

.DEFAULT_GOAL := help

help:
	@echo "MicroCNN_hotstate -- BloodMNIST CNN classifier, control plane = one hotstate"
	@echo "machine. No hotc needed; microcode is checked in."
	@echo ""
	@echo "Bitstream -- pick your board:"
	@echo "  Tang Primer 25K, open-source flow (yosys+slang, nextpnr, apycula):"
	@echo "    make -f Makefile.synth_primer25k pack|prog|prog_verified"
	@echo "  Tang Nano 20K, Gowin's gw_sh (Gowin EDA IDE):"
	@echo "    make -f Makefile.synth_tang20k_gowin pack|prog|prog_verified GW_SH=/path/to/gw_sh"
	@echo "  (prog_verified loads a checked-in, hardware-verified bitstream -- no build)"
	@echo ""
	@echo "Then, with the board on \$$(PORT) (default /dev/ttyUSB1):"
	@echo "  make hw-infer  IDX=26     classify one test image on the FPGA"
	@echo "  make sw-golden IDX=26     same image through the quantized Python model"
	@echo "  make benchmark IDX=26     both"
	@echo "  make lint                 Verilator lint of the generated core"

hw-infer:
	$(PYTHON) uart_medmnist_loader.py $(IDX) --split $(SPLIT) --port $(PORT) --baud $(BAUD)

sw-golden:
	$(PYTHON) golden_benchmark.py $(IDX) --split $(SPLIT)

benchmark: hw-infer sw-golden

lint: $(MODULE)_tb.v $(MODULE)_template.v
	verilator --lint-only -Wall -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-EOFNEWLINE -Wno-SYMRSVDWORD -Wno-PINMISSING -Wno-TIMESCALEMOD -Wno-LITENDIAN -Wno-SELRANGE -Wno-STMTDLY -Wno-PINCONNECTEMPTY -Wno-UNDRIVEN -Wno-BLKSEQ $(MODULE)_tb.v $(MODULE)_template.v $(IP_DIR)/hotstate.sv $(IP_DIR)/microcode.sv $(IP_DIR)/control.sv $(IP_DIR)/next_address.sv $(IP_DIR)/stack.sv $(IP_DIR)/switch.sv $(IP_DIR)/timer.sv $(IP_DIR)/variable.sv
	@echo "Verilog lint check successful!"

# The hotc-generated files are checked in here (there is no hotc to
# regenerate them), so clean removes only what a build produces.
clean:
	rm -rf obj_dir build_primer25k build_tang20k

.PHONY: help hw-infer sw-golden benchmark lint clean
