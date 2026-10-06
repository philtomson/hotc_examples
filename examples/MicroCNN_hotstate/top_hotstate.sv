`include "ila_config.vh"

// System clock frequency, for the UART baud divisors. 30 MHz is what the
// Tang Nano 20K's Gowin_rPLL produces; a board built with NO_RPLL passes its
// oscillator frequency instead (e.g. -D SYS_CLK_HZ=50_000_000).
`ifndef SYS_CLK_HZ
`define SYS_CLK_HZ 30_000_000
`endif

`timescale 1ns/1ps

module top (
    input  logic       clk,    
    input  logic       rst,    
    output logic [5:0] led,    
    input  logic       rx_in,
    output logic       tx_out
);

    logic system_clk;
    logic npu_clk;
    logic npu_sleep;
    logic npu_done;
    logic [2:0] class_result;

    // system_clk is the PLL's full-rate output. clkoutd (an exact /2 of the
    // same VCO) is kept wired as system_clk_half for timing-margin
    // experiments -- driving system_clk from it also needs SYS_CLK_HZ halved
    // so the UART baud divisors stay right. Nothing uses it by default.
    logic system_clk_full, system_clk_half;
`ifdef NO_RPLL
    // Boards without the GW1N/GW2A rPLL (Tang Primer 25K, GW5A): run straight
    // off the board oscillator. SYS_CLK_HZ must then be that oscillator's
    // frequency, so the UARTs' baud divisors stay right.
    assign system_clk_full = clk;
    assign system_clk_half = 1'b0;
`else
    Gowin_rPLL u_pll (
        .clkout(system_clk_full),
        .clkoutd(system_clk_half),
        .clkin(clk)
    );
`endif
    assign system_clk = system_clk_full;

    // Hotstate runs at system_clk; the datapath is clocked from the same
    // continuous clock.  We deliberately bypass Gowin_DCS clock gating:
    // the original repo documents that nextpnr-himbaechel needs one more
    // DCS than the chip has (9/8) and silently produces a broken clock
    // tree on real hardware (see MicroCNN-TangNano20k/Makefile notes).
    // npu_sleep is still driven to the outside world (power gating intent)
    // but no longer stops the clock inside this design.
    assign npu_clk = system_clk;

    logic [7:0] rx_data;
    logic       rx_valid;

    uart_rx #(.CLK_FREQ(`SYS_CLK_HZ)) u_uart_rx (
        .clk(system_clk),
        .rst(rst),
        .rx_in(rx_in),
        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    logic        img_we;
    logic [9:0]  img_waddr;
    logic [23:0] img_wdata;
    logic        npu_software_rst;

    logic npu_software_rst_raw;
    logic soc_loading;

    soc_controller u_soc_ctrl (
        .clk(system_clk),
        .rst(rst),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .img_we(img_we),
        .img_waddr(img_waddr),
        .img_wdata(img_wdata),
        .npu_rst_out(npu_software_rst_raw),
        .loading(soc_loading)
    );

    // npu_rst_out above is purely combinational and fans out widely as an
    // async `posedge rst` to every flop in u_npu/u_ila_capture; nextpnr
    // never checks reset recovery/removal timing (see reset_sync.sv for
    // the full explanation). Synchronize the deassertion edge so that
    // hazard becomes an ordinary, STA-checked FF-to-FF path.
    reset_sync u_npu_rst_sync (
        .clk(system_clk),
        .async_rst_in(npu_software_rst_raw),
        .sync_rst_out(npu_software_rst)
    );

    logic [9:0]  img_raddr;
    logic        img_ren;
    logic [23:0] img_rdata;

    img_ram u_img_ram (
        .wr_clk(system_clk),
        .we(img_we),
        .waddr(img_waddr),
        .wdata(img_wdata),
        .rd_clk(npu_clk),
        .re(img_ren),
        .raddr(img_raddr),
        .rdata(img_rdata)
    );

`ifdef ILA_ENABLE
    logic        trace_fc2_valid_out;
    logic [2:0]  trace_fc2_current_neuron;
    logic signed [31:0] trace_fc2_sum;
    logic [4:0]  trace_layer_phase;
    logic [2:0]  trace_predicted_class;
    logic signed [31:0] trace_psum_lane0;
    logic        trace_system_done;
    logic        trace_mult_ce;
    logic        trace_mult_clear;
    logic        trace_param_en;
    logic        trace_fc2_param_en_d;
    logic [63:0] trace_fc2_ram_rdata;
    logic        trace_fc1_valid_out;
    logic [4:0]  trace_fc1_current_neuron;
    logic [7:0]  trace_fc2_wdata;
    logic [5:0]  trace_fc1_ram_raddr;
    logic [11:0] trace_pool2_valid_cnt;
    logic        trace_conv2_channel_done_pulse;
    logic        trace_conv2_channel_done_pulse_d;
    logic        trace_conv2_channel_done_pulse_dd;
    logic        trace_conv2_filter_reset_pulse;
    logic [7:0]  trace_pool2_col_count;
    logic        trace_pool2_row_parity;
    logic [7:0]  trace_pool2_top_left;
    logic [7:0]  trace_pool2_bottom_left;
    logic        trace_pool2_reset_valid_overlap;
    logic [15:0] trace_conv2_valid_gated_cnt;
    logic        trace_accumulate;
    logic        trace_conv2_accumulate_d;
    logic        trace_dbg_npu_valid;
    logic        trace_conv2_npu_valid_gated;
    logic        trace_layer_state;
    logic        trace_conv2_start_pulse;
    logic [7:0]  trace_c2_pixel_cnt;
    logic [7:0]  trace_conv2_start_pulse_cnt;
    logic        trace_conv1_shift_en;
    logic [4:0]  trace_c2_lb_row;
    logic [4:0]  trace_c2_lb_col;
    logic        trace_system_done_pulse;
    logic        trace_conv2_early_stop;
    logic [7:0]  trace_pool2_out;
    logic        trace_pool2_valid;
    logic [3:0]  trace_c2_filter_cnt;
    logic [7:0]  trace_npu_out;
    logic [7:0]  trace_pool1_out;
    logic        trace_pool1_valid;
    logic [2:0]  trace_c1_filter_cnt;
    logic signed [31:0] trace_mac_sum;
    logic signed [31:0] trace_partial_sum;
    logic [7:0]  trace_conv2_ram_raddr;
    logic [7:0]  trace_ram_rdata0;
    logic        trace_conv2_shift_en;
    logic        trace_conv2_shift_en_d;
    logic [7:0]  trace_lb2_newest0;
    logic [3:0]  trace_filter_idx_w;
    logic        trace_conv2_chunk_sel_d;
    logic signed [31:0] trace_conv2_bias_read_data;
`endif

    npu_top_hotstate u_npu (
        .system_clk(system_clk),
        .npu_clk(npu_clk),
        .rst(npu_software_rst),
        .img_addr(img_raddr),
        .img_en(img_ren),
        .img_rdata(img_rdata),
        .class_idx(class_result),
        .npu_sleep(npu_sleep),
        .npu_done(npu_done)
`ifdef ILA_ENABLE
        ,
        .trace_fc2_valid_out(trace_fc2_valid_out),
        .trace_fc2_current_neuron(trace_fc2_current_neuron),
        .trace_fc2_sum(trace_fc2_sum),
        .trace_layer_phase(trace_layer_phase),
        .trace_predicted_class(trace_predicted_class),
        .trace_psum_lane0(trace_psum_lane0),
        .trace_system_done(trace_system_done),
        .trace_mult_ce(trace_mult_ce),
        .trace_mult_clear(trace_mult_clear),
        .trace_param_en(trace_param_en),
        .trace_fc2_param_en_d(trace_fc2_param_en_d),
        .trace_fc2_ram_rdata(trace_fc2_ram_rdata),
        .trace_fc1_valid_out(trace_fc1_valid_out),
        .trace_fc1_current_neuron(trace_fc1_current_neuron),
        .trace_fc2_wdata(trace_fc2_wdata),
        .trace_fc1_ram_raddr(trace_fc1_ram_raddr),
        .trace_pool2_valid_cnt(trace_pool2_valid_cnt),
        .trace_conv2_channel_done_pulse(trace_conv2_channel_done_pulse),
        .trace_conv2_channel_done_pulse_d(trace_conv2_channel_done_pulse_d),
        .trace_conv2_channel_done_pulse_dd(trace_conv2_channel_done_pulse_dd),
        .trace_conv2_filter_reset_pulse(trace_conv2_filter_reset_pulse),
        .trace_pool2_col_count(trace_pool2_col_count),
        .trace_pool2_row_parity(trace_pool2_row_parity),
        .trace_pool2_top_left(trace_pool2_top_left),
        .trace_pool2_bottom_left(trace_pool2_bottom_left),
        .trace_pool2_reset_valid_overlap(trace_pool2_reset_valid_overlap),
        .trace_conv2_valid_gated_cnt(trace_conv2_valid_gated_cnt),
        .trace_accumulate(trace_accumulate),
        .trace_conv2_accumulate_d(trace_conv2_accumulate_d),
        .trace_dbg_npu_valid(trace_dbg_npu_valid),
        .trace_conv2_npu_valid_gated(trace_conv2_npu_valid_gated),
        .trace_layer_state(trace_layer_state),
        .trace_conv2_start_pulse(trace_conv2_start_pulse),
        .trace_c2_pixel_cnt(trace_c2_pixel_cnt),
        .trace_conv2_start_pulse_cnt(trace_conv2_start_pulse_cnt),
        .trace_conv1_shift_en(trace_conv1_shift_en),
        .trace_c2_lb_row(trace_c2_lb_row),
        .trace_c2_lb_col(trace_c2_lb_col),
        .trace_system_done_pulse(trace_system_done_pulse),
        .trace_conv2_early_stop(trace_conv2_early_stop),
        .trace_pool2_out(trace_pool2_out),
        .trace_pool2_valid(trace_pool2_valid),
        .trace_c2_filter_cnt(trace_c2_filter_cnt),
        .trace_npu_out(trace_npu_out),
        .trace_pool1_out(trace_pool1_out),
        .trace_pool1_valid(trace_pool1_valid),
        .trace_c1_filter_cnt(trace_c1_filter_cnt),
        .trace_mac_sum(trace_mac_sum),
        .trace_partial_sum(trace_partial_sum),
        .trace_conv2_ram_raddr(trace_conv2_ram_raddr),
        .trace_ram_rdata0(trace_ram_rdata0),
        .trace_conv2_shift_en(trace_conv2_shift_en),
        .trace_conv2_shift_en_d(trace_conv2_shift_en_d),
        .trace_lb2_newest0(trace_lb2_newest0),
        .trace_filter_idx_w(trace_filter_idx_w),
        .trace_conv2_chunk_sel_d(trace_conv2_chunk_sel_d),
        .trace_conv2_bias_read_data(trace_conv2_bias_read_data)
`endif
    );

    // class_tx_data/class_tx_start/class_sent -- declared here (rather
    // than right next to uart_tx below) so class_tx_data can be included
    // directly in the ILA probe bus when ILA_ENABLE is on.
    logic class_tx_start;
    logic [7:0] class_tx_data;
    logic class_sent;

`ifdef ILA_ENABLE
    // ── Minimal on-chip logic analyzer (ila_capture / ila_dump) ─────────
    // Debug instrumentation from bringing up this example on hardware,
    // kept for reference. Disabled: ILA_ENABLE is never defined (see
    // ila_config.vh), and the ila_capture/ila_dump modules are not
    // included in this repository.
    //
    // ila_capture stores one probe sample per cycle that capture_en is
    // high, until stop_trigger. ila_dump sends wr_ptr as a 2-byte header
    // before the samples, so the host knows how many are valid.
    //
    // Last probe used: pool2's output, one sample per pooled pixel, to
    // compare end to end against golden_benchmark.py's maxpool2 output.
    //   ila_probe    = {20'b0, c2_filter_cnt[3:0], pool2_out[7:0]}
    //   capture_en   = pool2_valid
    //   stop_trigger = layer_phase == 9 (FC1 start; pool2 is long done)
    //   2048 slots (ADDR_WIDTH=11) for 400 real samples (16 filters x 25)
    //
    // Pitfalls found with earlier probes:
    //   - c2_filter_cnt is an undelayed controller variable labelling a
    //     datapath that runs up to 2 cycles behind it, so the sample just
    //     after a filter boundary can carry the previous filter's label.
    //   - Size probe fields explicitly: a concatenation narrower than
    //     PROBE_WIDTH is silently zero-extended at the top, shifting every
    //     field from where the decoder expects it.
    //   - Gate capture_en on real events rather than every clock; a
    //     free-running capture wraps and keeps only the tail.
    localparam int ILA_PROBE_WIDTH = 32;
    localparam int ILA_ADDR_WIDTH  = 11;
    logic [ILA_PROBE_WIDTH-1:0] ila_probe;
    assign ila_probe = { 20'b0, trace_c2_filter_cnt, trace_pool2_out };

    logic [ILA_ADDR_WIDTH-1:0] ila_wr_ptr;
    logic ila_captured;
    logic [ILA_ADDR_WIDTH-1:0] ila_rd_addr;
    logic [ILA_PROBE_WIDTH-1:0] ila_rd_data;
    logic tx_busy; // shared uart_tx status, declared here so it's in scope for u_ila_dump below

    logic ila_stop_trigger;
    assign ila_stop_trigger = (trace_layer_phase == 5'd9);   // FC1 start -- pool2 long done

    ila_capture #(
        .PROBE_WIDTH(ILA_PROBE_WIDTH), .ADDR_WIDTH(ILA_ADDR_WIDTH)
    ) u_ila_capture (
        .clk(system_clk), .rst(npu_software_rst),
        .probe(ila_probe), .stop_trigger(ila_stop_trigger),
        .capture_en(trace_pool2_valid),
        .rd_addr(ila_rd_addr), .rd_data(ila_rd_data),
        .wr_ptr(ila_wr_ptr), .captured(ila_captured)
    );

    // 'D' (0x44) on the UART RX line requests a trace dump.
    // BUG (fixed): originally fired on ANY 0x44 byte on rx_data, with no
    // regard for whether the system was mid-image-load -- since raw
    // BloodMNIST pixel bytes span the full 0-255 range, some test images
    // (confirmed: index 100, 4 occurrences; index 26, 0) contain a 0x44
    // byte somewhere in their 2352-byte stream, spuriously firing a dump
    // request while soc_controller was still loading the image and
    // corrupting that run (empty/garbled classification byte, truncated
    // trace dump -- reproduced deterministically twice). Originally gated
    // on npu_done alone, on the assumption "npu_done is low for the
    // entire image-load window" -- true only for the very first load after
    // power-on. npu_done is a plain (non-one_shot) bool that stays HIGH
    // from the end of one inference until the next 'S' command's reset
    // pulse, which happens AFTER the next image's bytes are already
    // streamed in via 'L' -- so every load after the first still has
    // npu_done stuck high the whole time, and a stray 0x44 pixel byte in
    // THAT image spuriously fires a dump mid-load (confirmed on real
    // hardware: image 0's load flooded 162 bytes of a stale ILA dump
    // header+payload before the real classification byte). Fixed by also
    // requiring soc_controller's own state to genuinely be IDLE (not
    // mid-load), via the new `loading` output port.
    logic ila_start_dump;
    always_ff @(posedge system_clk or posedge rst) begin
        if (rst) ila_start_dump <= 1'b0;
        else     ila_start_dump <= rx_valid && (rx_data == 8'h44) && npu_done && !soc_loading;
    end

    logic ila_dumping;
    logic ila_tx_start;
    logic [7:0] ila_tx_data;

    ila_dump #(
        .PROBE_WIDTH(ILA_PROBE_WIDTH), .ADDR_WIDTH(ILA_ADDR_WIDTH)
    ) u_ila_dump (
        .clk(system_clk), .rst(rst),
        .start_dump(ila_start_dump), .captured(ila_captured), .wr_ptr(ila_wr_ptr),
        .rd_addr(ila_rd_addr), .rd_data(ila_rd_data),
        .tx_start(ila_tx_start), .tx_data(ila_tx_data), .tx_busy(tx_busy),
        .dumping(ila_dumping)
    );
`endif

    assign led = ~{2'b00, class_result};

`ifdef ILA_ENABLE
    // Shared uart_tx, arbitrated between the existing class-result byte
    // and the ILA dump. In practice these never overlap: the host script
    // always waits for the class-result byte before sending 'D', so a
    // simple fixed-priority mux (class byte wins ties) is sufficient --
    // no need for a stateful arbiter.
    logic tx_start;
    logic [7:0] tx_data;
    assign tx_start = class_tx_start | ila_tx_start;
    assign tx_data  = class_tx_start ? class_tx_data : ila_tx_data;

    uart_tx #(.CLK_FREQ(`SYS_CLK_HZ)) u_uart_tx (
        .clk(system_clk),
        .rst(rst),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_out(tx_out),
        .tx_busy(tx_busy)
    );
`else
    uart_tx #(.CLK_FREQ(`SYS_CLK_HZ)) u_uart_tx (
        .clk(system_clk),
        .rst(rst),
        .tx_start(class_tx_start),
        .tx_data(class_tx_data),
        .tx_out(tx_out),
        .tx_busy()
    );
`endif

    always_ff @(posedge system_clk or posedge rst) begin
        if(rst) begin
            class_tx_start <= 1'b0;
            class_tx_data  <= 8'd0;
            class_sent     <= 1'b0;
        end else begin
            class_tx_start <= 1'b0;

            // Clear the flag when the NPU starts a new inference
            if (!npu_done) begin
                class_sent <= 1'b0;
            end
            else if(!class_sent & npu_done) begin
                class_tx_start <= 1'b1;
                class_tx_data  <= {5'b00000, class_result} + 8'h30;
                class_sent     <= 1'b1;
            end
        end
    end
endmodule