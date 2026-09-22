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

# ── Build provenance ───────────────────────────────────────────────────────
# Every variable above is `?=`, so a build silently takes whichever binary the
# PATH happens to serve. That is the right default -- and it is also how a whole
# afternoon got lost: this machine carries THREE yosys installs (/usr/local
# 0.56, ~/bin/oss-cad-suite 0.69, ~/tools/oss-cad-suite 0.48) and TWO
# nextpnr-himbaechels (0.11.1 and 0.7), and a failure report that says only
# "synthesis failed" cannot be matched to the tools that produced it. A netlist
# turned up whose size matched one yosys while the reporter's PATH named
# another, and that discrepancy was never resolved -- there was no record.
#
# So every synthesis flow prints what it is about to use. $(TOOL_BANNER) is a
# recipe fragment, not a target: it has to run inside the build whose log you
# will later be reading, not as a separate step someone forgets.
#
# Version flags differ per tool and some have none, so each is tried in turn and
# a tool that answers nothing still gets its resolved path printed -- the path
# is the more useful half anyway.

# -V on stderr (nextpnr does this), then --version, then give up: gowin_pack
# has no version flag at all and answers -h with a usage block, which is worse
# than saying nothing. Anything usage-shaped is discarded.
# Drop the noise first: gowin_pack is a Python entry point and greets -V with
# UserWarnings about numpy/msgspec before anything useful, and has no version
# flag at all -- a usage block is worse than saying nothing.
_tool_ver = $$( v=$$( { '$(1)' -V 2>&1 || '$(1)' --version 2>&1; } \
                      | grep -vE 'Warning|warnings\.warn|^ |^/' \
                      | grep -v '^$$' | head -1 ); \
                case "$$v" in usage:*|Usage:*|'') echo '(no version flag)';; \
                              *) echo "$$v" | cut -c1-52;; esac )
_tool_pth = $$( command -v '$(1)' 2>/dev/null || echo '*** NOT FOUND ***' )

define _tool_line
	@printf '    %-11s %-38s %s\n' '$(1)' "$(call _tool_pth,$(2))" "$(call _tool_ver,$(2))"
endef

# Use as the first line of a synth/pnr/pack recipe:  $(TOOL_BANNER)
define TOOL_BANNER
	@echo "--- tools for this build (override in local.mk, or make YOSYS=... ) ---"
	$(call _tool_line,yosys,$(YOSYS))
	$(call _tool_line,nextpnr,$(NEXTPNR_HIMB))
	$(call _tool_line,gowin_pack,$(GOWIN_PACK))
endef

# Standalone equivalent, for asking without building.
tool-versions:
	$(TOOL_BANNER)

.PHONY: tool-versions
