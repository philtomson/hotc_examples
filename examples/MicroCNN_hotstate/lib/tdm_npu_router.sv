`timescale 1ns/1ps

// Time-Division Multiplexing (TDM) Router for the NPU.
// Hot-swaps inputs to the shared ws_conv_core_gowin between Layer 1
// and Layer 2 based on the layer_state flag. Demultiplexes and 
// gates the output valid signals.

module tdm_npu_router (
    input  logic        clk,
    input  logic        rst,
    
    // Control Flag (from Master FSM)
    input  logic        layer_state, // 0 = Conv1, 1 = Conv2
    
    // Conv1 Inputs
    input  logic        conv1_compute_en,
    input  logic [7:0]  conv1_data_in [0:3][0:2][0:2],
    input  logic [7:0]  conv1_weight_in [0:3][0:2][0:2],
    input  logic [31:0] conv1_bias_in,
    
    // Conv2 Inputs
    input  logic        conv2_compute_en,
    input  logic        conv2_accumulate,
    input  logic [7:0]  conv2_data_in [0:3][0:2][0:2],
    input  logic [7:0]  conv2_weight_in [0:3][0:2][0:2],
    input  logic [31:0] conv2_bias_in,

    // Qualifies conv2_valid_out_gated below. Deliberately separate from
    // conv2_accumulate: that input is correctly timed for mux_accumulate
    // (ws_conv_core_gowin's fold-vs-fresh select), but the folded result it
    // triggers isn't visible on npu_out until the following cycle, so
    // gating the output on it would latch the pre-fold partial into pool2.
    // The instantiation site drives this with conv2_accumulate_dd, one
    // cycle behind conv2_accumulate_d. On hardware, npu_out sampled on
    // that later cycle matched the golden model on all 1824 conv2 outputs.
    input  logic        conv2_accumulate_gate,
    
    // Shared NPU Output
    output logic [7:0]  npu_out,
    
    // Demultiplexed Valid Signals
    output logic        conv1_valid_out,
    output logic        conv2_valid_out_gated,

    // Debug tap: the raw (ungated) valid_out from the shared MAC core.
    // Unconditional (not `ifdef`-guarded) since it's a single extra wire.
    output logic        dbg_npu_valid,

    // Debug taps: ws_conv_core_gowin's mac_sum_dbg/partial_sum_dbg, passed
    // straight through (see that module's port comment).
    output logic signed [31:0] dbg_mac_sum,
    output logic signed [31:0] dbg_partial_sum
);

    // TDM MUX Routing Logic
    logic        mux_compute_en;
    logic        mux_accumulate;
    logic [7:0]  mux_data_in [0:3][0:2][0:2];
    logic [7:0]  mux_weight_in [0:3][0:2][0:2];
    logic [31:0] mux_bias_in;
    logic [3:0]  mux_shift_val;

    always_comb begin
        if (layer_state == 1'b0) begin
            // Route Conv1 Signals
            mux_compute_en = conv1_compute_en;
            mux_accumulate = 1'b0;                // Conv1 does not accumulate
            mux_data_in    = conv1_data_in;      
            mux_weight_in  = conv1_weight_in;   
            mux_bias_in    = conv1_bias_in;
            mux_shift_val  = 4'd9;
        end else begin
            // Route Conv2 Signals
            mux_compute_en = conv2_compute_en;  
            mux_accumulate = conv2_accumulate;  
            mux_data_in    = conv2_data_in;      
            mux_weight_in  = conv2_weight_in;
            mux_bias_in    = conv2_bias_in;
            mux_shift_val  = 4'd8;
        end
    end

    // Shared NPU Core Instantiation
    logic npu_valid;

    ws_conv_core_gowin #(
        .NUM_CORES(4)
    ) u_npu (
        .clk(clk),
        .rst(rst),
        .compute_en(mux_compute_en),
        .accumulate(mux_accumulate),
        .data_in(mux_data_in),
        .weight_in(mux_weight_in),
        .bias_in(mux_bias_in),
        .shift_val(mux_shift_val), 
        .mac_out(npu_out),
        .valid_out(npu_valid),
        .mac_sum_dbg(dbg_mac_sum),
        .partial_sum_dbg(dbg_partial_sum)
    );

    // Output Demultiplexer & Validation Gate
    
    // Conv1 gets the valid signal directly when active
    assign conv1_valid_out = npu_valid & (layer_state == 1'b0);

    // Conv2's gate differs from the original design's
    // `npu_valid & !conv2_accumulate`, because the hotstate controller
    // drives `accumulate` with different timing (a one_shot pulse, delayed
    // in npu_top_hotstate.sv). Each output pixel is a pre-fold partial sum
    // followed by the folded result, and only the folded result may reach
    // pool2. The qualifier is conv2_accumulate_gate (see its port comment)
    // rather than conv2_accumulate, because the fold written on
    // accumulate_d isn't visible on npu_out until the next cycle. Both the
    // polarity and the delay were measured on hardware; re-measure before
    // changing either.
    assign conv2_valid_out_gated = npu_valid & (layer_state == 1'b1) & conv2_accumulate_gate;

    assign dbg_npu_valid = npu_valid;

endmodule