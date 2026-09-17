//////////////////////////////////////////////////////////////////////////////////
// Company: HotWright Inc.
// Copyright (c) 2022 
// All Rights Reserved
// Engineer: Steve Casselman 
// 
// Create Date: 07/20/2020 08:03:43 PM
// Design Name: hotstate
// Module Name: next_address
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 10ns / 1ns

module next_address#(parameter BUS_WIDTH = 8)(
    input [BUS_WIDTH-1:0] address,
    input [BUS_WIDTH-1:0] jmp_adr,
    input [BUS_WIDTH-1:0] returnadr,
    input [BUS_WIDTH-1:0] interrupt_address,
    input [BUS_WIDTH-1:0] switch_adr,
    input switch_active, 
    input ready,
    input jmp_enb,
    input fired,
    input rst,
    input hlt,
    input sub_pop,
    input interrupt,
    input clk,
    output reg [BUS_WIDTH-1:0] nextadr
    );
    
  
    always @(posedge clk) begin
        if (rst == 1||ready == 0) begin 
        nextadr <= 0;
        end
        else if (hlt == 1) nextadr <= address;
        else
          nextadr <=  switch_active?switch_adr:(fired?interrupt_address:(jmp_enb ? jmp_adr: (sub_pop ? returnadr : address + 1)));
    end
endmodule
