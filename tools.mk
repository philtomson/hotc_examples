# tools.mk — Synthesis tool paths, shared by all examples/*/Makefile.synth
#
# Each tool defaults to its bare name (works when the tool is on PATH).
# Override any variable without editing this file by either:
#
#   1. Command line:   make YOSYS=/opt/oss-cad-suite/bin/yosys synth
#   2. Environment:    export NEXTPNR_ECP5=/usr/local/bin/nextpnr-ecp5
#   3. local.mk:       echo 'YOSYS = /opt/oss-cad-suite/bin/yosys' >> local.mk
#                      (local.mk is gitignored — safe for per-machine settings)
#
# Common install locations:
#   OSS CAD Suite (Linux/Mac):  /opt/oss-cad-suite/bin/
#   Homebrew (macOS):           /opt/homebrew/bin/  or  /usr/local/bin/
#   System packages (Debian):   /usr/bin/
#   YosysHQ nightly (custom):   ~/yosys-install/bin/
#
# To check which tool paths are active:  make -f tools.mk show-tools
#   (run from the repo root, or from an example with the right relative path)

# ── Synthesis ─────────────────────────────────────────────────────────────────
YOSYS          ?= yosys

# ── ECP5 place-and-route (nextpnr-ecp5 + prjtrellis pack/program) ─────────────
NEXTPNR_ECP5   ?= nextpnr-ecp5
ECPPACK        ?= ecppack
DFU_UTIL       ?= dfu-util

# ── Nexus place-and-route (nextpnr-nexus + prjoxide pack) ────────────────────
# CrossLink-NX / Certus-NX. prjoxide is the Nexus counterpart of prjtrellis;
# the pack step is `prjoxide pack design.fasm design.bit`.
NEXTPNR_NEXUS  ?= nextpnr-nexus
PRJOXIDE       ?= prjoxide

# ── GateMate place-and-route (nextpnr-himbaechel or Cologne Chip p_r) ─────────
NEXTPNR_HIMB   ?= nextpnr-himbaechel
PR_TOOL        ?= p_r

# ── Gowin bitstream packer (part of the Yosys-Gowin / apicula flow) ───────────
GOWIN_PACK     ?= gowin_pack

# ── Xilinx/AMD Vivado (Kria KV260 and other UltraScale+ boards) ───────────────
VIVADO         ?= vivado

# ── FPGA programmer (used for GateMate, Kria, and other boards) ───────────────
OPENFPGALOADER ?= openFPGALoader

# ── Python (used for firmware assembly, waveform scripts, etc.) ───────────────
PYTHON3        ?= python3

# ── Diagnostic target ─────────────────────────────────────────────────────────
show-tools:
	@echo "YOSYS          = $(YOSYS)"
	@echo "NEXTPNR_ECP5   = $(NEXTPNR_ECP5)"
	@echo "ECPPACK        = $(ECPPACK)"
	@echo "DFU_UTIL       = $(DFU_UTIL)"
	@echo "NEXTPNR_NEXUS  = $(NEXTPNR_NEXUS)"
	@echo "PRJOXIDE       = $(PRJOXIDE)"
	@echo "NEXTPNR_HIMB   = $(NEXTPNR_HIMB)"
	@echo "PR_TOOL        = $(PR_TOOL)"
	@echo "GOWIN_PACK     = $(GOWIN_PACK)"
	@echo "VIVADO         = $(VIVADO)"
	@echo "OPENFPGALOADER = $(OPENFPGALOADER)"
	@echo "PYTHON3        = $(PYTHON3)"

.PHONY: show-tools
