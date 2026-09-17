//////////////////////////////////////////////////////////////////////////////////
// Company: HotWright Inc.
// Copyright (c) 2022 
// All Rights Reserved
// Engineer: Steve Casselman
//  
// Create Date: 05/27/2021 12:33:30 PM
// Design Name: 
// Module Name: stack
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 10ns / 1ns


/* verilator lint_off WIDTHTRUNC */
module stack #(parameter DEPTH = 4,
               parameter WIDTH = 8
    )  (
    input  [WIDTH-1:0] push_adr,
    output reg [WIDTH-1:0] pop_adr,
    input clk,
    input rst,
    input sub_push,
    input sub_pop,
    input hlt,
    input fired
    );
    
    reg [WIDTH-1:0] stack_ram [DEPTH-1:0];
    reg [DEPTH-1:0] pointer;
    genvar i;
    always @(posedge clk) begin
    if (rst == 1) begin
        pointer <= 0;
        stack_ram[0] <= 0;
        pop_adr <= 0;
    end
    else begin
       if (sub_push == 1 && !hlt) begin
           stack_ram[pointer] <= fired ? push_adr : push_adr + 1;
          pointer <= pointer + 1;
          end
       else if (sub_pop == 1 && pointer > 0) pointer <= pointer - 1;
    end
    if (pointer > 0) pop_adr <= stack_ram[pointer - 1]; 
    end
endmodule
