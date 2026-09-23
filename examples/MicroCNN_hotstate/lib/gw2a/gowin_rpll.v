// Tang Nano 20K (GW2AR-18C): system clock PLL for top_hotstate.sv.
// 27 MHz in -> 30 MHz out: IDIV_SEL=8 and FBDIV_SEL=9 give 27 * 10/9, with
// ODIV_SEL=32 keeping the VCO in range. clkoutd is CLKOUT / 2
// (DYN_SDIV_SEL=2); nothing uses it by default. No dynamic control, no
// external feedback, fixed 50% duty.
module Gowin_rPLL (
    output clkout,
    output clkoutd,
    input  clkin
);
    rPLL #(
        .FCLKIN("27"),
        .DYN_IDIV_SEL("false"), .IDIV_SEL(8),
        .DYN_FBDIV_SEL("false"), .FBDIV_SEL(9),
        .DYN_ODIV_SEL("false"), .ODIV_SEL(32),
        .PSDA_SEL("0000"), .DYN_DA_EN("true"), .DUTYDA_SEL("1000"),
        .CLKOUT_FT_DIR(1'b1), .CLKOUTP_FT_DIR(1'b1),
        .CLKOUT_DLY_STEP(0), .CLKOUTP_DLY_STEP(0),
        .CLKFB_SEL("internal"),
        .CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"), .CLKOUTD_BYPASS("false"),
        .DYN_SDIV_SEL(2),
        .CLKOUTD_SRC("CLKOUT"), .CLKOUTD3_SRC("CLKOUT"),
        .DEVICE("GW2AR-18C")
    ) u_pll (
        .CLKOUT(clkout),
        .LOCK(),
        .CLKOUTP(),
        .CLKOUTD(clkoutd),
        .CLKOUTD3(),
        .RESET(1'b0), .RESET_P(1'b0),
        .CLKIN(clkin),
        .CLKFB(1'b0),
        .FBDSEL(6'd0), .IDSEL(6'd0), .ODSEL(6'd0),
        .PSDA(4'd0), .DUTYDA(4'd0), .FDLY(4'd0)
    );
endmodule
