# Makefile for examples/webserver
# Orchestrates response-ROM regeneration and Verilator simulation.
#
# http_server_template.v / uart_tx_template.v / uart_rx_template.v are
# hotc's OUTPUT, checked in as-is -- this repo doesn't ship the hotc
# compiler itself, so there's no rule to rebuild them here. response_*.h/
# .mem, by contrast, come from generate_response.py (plain Python, no
# hotc) and DO regenerate from index.html below if you edit it.

SIMULATOR = verilator
SIM_FLAGS = --timing --cc -Wno-fatal --exe --trace --trace-structs --build

IP_DIR = ../../IP
IP_SRCS = $(IP_DIR)/hotstate.sv \
          $(IP_DIR)/microcode.sv \
          $(IP_DIR)/control.sv \
          $(IP_DIR)/next_address.sv \
          $(IP_DIR)/stack.sv \
          $(IP_DIR)/switch.sv \
          $(IP_DIR)/timer.sv \
          $(IP_DIR)/variable.sv

HOTC_TEMPLATES = http_server_template.v uart_tx_template.v uart_rx_template.v

.PHONY: all generate sim sim_interactive clean

all: generate

# response_streamer.v's $readmemh calls need the *.mem siblings below, not
# just the *.h files http_server_template.v needs.
generate: response_main.mem response_redirect.mem response_404.mem response_status.mem

# generate_response.py writes response_<name>.mem as a side effect of the
# same invocation that writes the .h fragment below (see its own source) --
# giving the .mem its own rule (same recipe) rather than leaving it as an
# undeclared byproduct of the .h rule means `make` notices and regenerates
# it if it's missing even when the .h is already up to date (this is
# exactly the gap that let response_main.mem etc. go missing while
# response_main.h stayed checked into git: nothing ever re-ran the .h
# recipe to re-trigger the byproduct, since only the byproduct was gone).
response_main.h response_main.mem: index.html generate_response.py
	python3 generate_response.py --status 200 index.html > response_main.h

response_redirect.h response_redirect.mem: generate_response.py
	python3 generate_response.py --status 302 > response_redirect.h

response_404.h response_404.mem: generate_response.py
	python3 generate_response.py --status 404 > response_404.h

response_status.h response_status.mem: generate_response.py
	python3 generate_response.py --status 201 > response_status.h

sim: generate
	@echo "=== Compiling Verilator simulation ==="
	$(SIMULATOR) $(SIM_FLAGS) -I. sim_main.cpp webserver_tb.v webserver_top.v response_streamer.v $(HOTC_TEMPLATES) $(IP_SRCS) --top webserver_tb
	@echo "=== Running simulation ==="
	./obj_dir/Vwebserver_tb

sim_interactive: generate
	@echo "=== Compiling Interactive Verilator simulation ==="
	$(SIMULATOR) $(SIM_FLAGS) -I. sim_interactive.cpp webserver_top.v response_streamer.v $(HOTC_TEMPLATES) $(IP_SRCS) --top webserver_top
	@echo "=== Running Interactive simulation ==="
	./obj_dir/Vwebserver_top

# Only removes what generate_response.py can rebuild (response_*.h/.mem)
# and simulation build output -- *_template.v/*.mem/*_symbols.toml etc. are
# hotc's checked-in output, not regenerable without hotc, so clean leaves
# them alone.
# NOTE: in THIS repo the hotc-generated files are checked in -- that is the
# whole point, since there is no hotc here to regenerate them. So clean must
# remove only what a build produces. The same recipe is correct in the hotc
# source repo, where these files ARE build output, which is exactly why the
# destructive version survived the copy. Same trap as smith_waterman's
# `make clean` (hotc 5871e964).
clean:
	rm -rf obj_dir webserver_sim.vcd hardware_trace.csv http_server_sim.csv

