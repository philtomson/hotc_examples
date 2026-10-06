// argmax10.v — combinational argmax over the 10 per-class sums (7 bits each,
// class k at sums[k*7 +: 7]). Ties resolve to the lowest class index, matching
// the Julia model's argmax.
`timescale 1ns / 1ps

module argmax10 (
    input  wire [69:0] sums,
    output reg  [3:0]  digit
);
    integer k;
    reg [6:0] best;
    always @(*) begin
        best  = sums[6:0];
        digit = 4'd0;
        for (k = 1; k < 10; k = k + 1) begin
            if (sums[k*7 +: 7] > best) begin
                best  = sums[k*7 +: 7];
                digit = k[3:0];
            end
        end
    end
endmodule
