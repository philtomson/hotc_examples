# Tsetlin_hotstate_uart — this example is synthesis-only in this repo, so there
# is no default build to run. Without this file a plain `make` in here fails with
# "No targets specified and no makefile found", which reads like something is
# broken when nothing is: the three Makefile.synth_* below are the whole story.
#
# No hotc is needed for any of them -- the generated microcode is checked in.

.DEFAULT_GOAL := help

help:
	@echo "Tsetlin_hotstate_uart -- MNIST Tsetlin machine, four hotstate machines"
	@echo "wired together by tm_hw_top_uart.v. No hotc needed; microcode is checked in."
	@echo ""
	@echo "Build a bitstream (pick your board):"
	@echo "  make -f Makefile.synth_tang9k    pack    Tang Nano 9K   (GW1N-9C)"
	@echo "  make -f Makefile.synth_tang20k   pack    Tang Nano 20K  (GW2A-18C)"
	@echo "  make -f Makefile.synth_primer25k pack    Tang Primer 25K (GW5A-25A)"
	@echo ""
	@echo "Add 'prog' instead of 'pack' to flash it over openFPGALoader."
	@echo ""
	@echo "Then send it MNIST digits over the board's UART:"
	@echo "  python3 send_batch.py --port /dev/ttyUSB1        # all of batch_ref.bin"
	@echo "  python3 send_batch.py --port /dev/ttyUSB1 --limit 10"
	@echo "  python3 draw_digit_uart.py --port /dev/ttyUSB1   # draw one by hand"
	@echo ""
	@echo "See README.md for the wiring, and KNOWN_ISSUES.md before debugging a"
	@echo "board that does not answer."

.PHONY: help
