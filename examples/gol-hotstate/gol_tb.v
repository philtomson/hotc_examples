// Auto-generated testbench for gol
`timescale 1ns / 1ps

module gol_tb (
    output reg clk,
    output reg rst,
    output reg hlt,
    // Output signals as ports (for C++ harness visibility)
    output wire [15:0] pixel_color,
    output wire [8:0] blit_x,
    output wire [8:0] blit_y,
    output wire [5:0] r,
    output wire [5:0] c,
    output wire [9:0] base,
    output wire [9:0] ni,
    output wire [6:0] nr,
    output wire [6:0] nc,
    output wire [3:0] self,
    output wire [3:0] sum,
    output wire [3:0] nb,
    output wire [3:0] neigh,
    output wire flip,
    output wire cell_wr_val,
    output wire btn_prev,
    output wire seed_mode,
    output wire sclk,
    output wire mosi,
    output wire cs_n,
    output wire dc,
    output wire lcd_resetn,
    output wire [7:0] spi_byte,
    output wire spi_dc,
    output wire [9:0] win_x1,
    output wire [9:0] win_x2,
    output wire [8:0] win_y1,
    output wire [8:0] win_y2,
    output wire [15:0] px_cnt,
    output wire [9:0] entry,
    output wire [9:0] c_start,
    output wire [9:0] c_end,
    output wire [8:0] r_start,
    output wire [8:0] r_end,
    output wire [15:0] num_pixels,
    output wire grid0__wr_en,
    output wire grid1__wr_en,
    output wire sR__wr_en,
    output wire sC__wr_en,
    output wire [8:0] debug_adr,
    output wire [235:0] states_out,
    output wire ready,
    output wire lhs_out,
    output wire jmp_flag_out,
    output wire [8:0] jmp_bus_out,
    output wire br_out,
    output wire fj_out,
    output wire [8:0] next_pc,
    output wire state_capture
);

    initial begin
        clk = 0;
        rst = 1;
        hlt = 0;
        #40 rst = 0;
    end

    always #10 clk = ~clk;

    reg mode_btn;

// Device Under Test
gol dut (
    .clk(clk),
    .rst(rst),
    .mode_btn(mode_btn),
    .pixel_color(pixel_color),
    .blit_x(blit_x),
    .blit_y(blit_y),
    .r(r),
    .c(c),
    .base(base),
    .ni(ni),
    .nr(nr),
    .nc(nc),
    .self(self),
    .sum(sum),
    .nb(nb),
    .neigh(neigh),
    .flip(flip),
    .cell_wr_val(cell_wr_val),
    .btn_prev(btn_prev),
    .seed_mode(seed_mode),
    .sclk(sclk),
    .mosi(mosi),
    .cs_n(cs_n),
    .dc(dc),
    .lcd_resetn(lcd_resetn),
    .spi_byte(spi_byte),
    .spi_dc(spi_dc),
    .win_x1(win_x1),
    .win_x2(win_x2),
    .win_y1(win_y1),
    .win_y2(win_y2),
    .px_cnt(px_cnt),
    .entry(entry),
    .c_start(c_start),
    .c_end(c_end),
    .r_start(r_start),
    .r_end(r_end),
    .num_pixels(num_pixels),
    .grid0__wr_en(grid0__wr_en),
    .grid1__wr_en(grid1__wr_en),
    .sR__wr_en(sR__wr_en),
    .sC__wr_en(sC__wr_en),
    .debug_adr(debug_adr),
    .states_out(states_out),
    .ready(ready),
    .lhs_out(lhs_out),
    .jmp_flag_out(jmp_flag_out),
    .jmp_bus_out(jmp_bus_out),
    .br_out(br_out),
    .fj_out(fj_out),
    .next_pc(next_pc),
    .state_capture(state_capture)
);

// Include user stimulus
`include "user_tb.v"

endmodule
