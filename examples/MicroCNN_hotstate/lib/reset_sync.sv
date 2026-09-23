`timescale 1ns/1ps

// Reset synchronizer: async assert, synchronous deassert.
//
// WHY THIS EXISTS: soc_controller.sv generates npu_rst_out purely
// combinationally (hold_npu_in_reset | (rst_stretch > 0) | rst). That
// signal fans out widely and is used as an ASYNCHRONOUS reset
// (`posedge rst`) by every flop in npu_top_hotstate and ila_capture.
// nextpnr-himbaechel's STA (see build/pnr.log -- grep for "recovery" or
// "removal" finds nothing) only checks ordinary posedge->posedge setup
// timing on the npu_clk domain; it never checks reset recovery/removal
// time at all. That means a marginal recovery-time violation on this
// specific, wide-fanout, once-per-inference deassertion edge would be
// completely invisible to every STA report this project has ever
// produced, yet would manifest as build-to-build (P&R-routing-dependent)
// flakiness on real hardware with zero functional RTL change -- exactly
// the symptom pattern seen chasing the class_result glitch (see
// hotc_microcnn_hotstate_classifier_bug_hunt.md).
//
// This module converts that hazard into an ordinary FF-to-FF path (which
// IS properly checked by setup/hold STA) by construction: assertion is
// still immediate/asynchronous (a reset firing a cycle early is always
// safe), but deassertion is delayed two clk edges, guaranteeing at least
// one full clock period of margin before any downstream consumer's next
// active edge -- the standard "reset synchronizer" pattern.
//
// NOTE: this only fixes recovery/removal margin on the *destination*
// side (npu_top_hotstate, ila_capture). It does not, and cannot, prove
// anything about real P&R timing -- Verilator has no routing-delay or
// recovery/removal model, so simulation can only confirm this doesn't
// change functional behavior, not that it fixes the hardware-only bug.
module reset_sync (
    input  logic clk,
    input  logic async_rst_in,   // combinational, may be marginal/glitchy
    output logic sync_rst_out    // clean: async assert, sync deassert
);
    logic meta;

    always_ff @(posedge clk or posedge async_rst_in) begin
        if (async_rst_in) begin
            meta         <= 1'b1;
            sync_rst_out <= 1'b1;
        end else begin
            meta         <= 1'b0;
            sync_rst_out <= meta;
        end
    end
endmodule
