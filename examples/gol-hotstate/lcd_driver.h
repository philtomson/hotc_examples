// lcd_driver.h — shared variable declarations for the gol-hotstate example's
// multi-file hotc build. hotc's multi-file merge does not support function
// prototypes (only full definitions), so this header declares only the
// variables that gol.c touches directly by name; everything else lives
// privately in lcd_driver.c. Declarations here must match lcd_driver.c's
// exactly (type + initializer) so the multi-file AST merge dedups them as the
// same variable instead of erroring on a type conflict.
//
// NOTE vs. spi_lcd/lcd_common.h: sprite_* variants expose cur_x/cur_y because
// their driver helpers take no parameters and read those globals for the box
// origin (hotc functions have no parameters without --hw-stack, and passing a
// 16-bit color through one risks switch-offset aliasing). gol.c follows the
// same no-param pattern via blit_x/blit_y, so this header adds those two.

// -- Shared with gol.c (re-declared in lcd_driver.c) ------------------------
// delay_cnt: reused by init_display() reset/init timing AND gol.c's frame
//            throttle loop. pixel_color: gol.c sets it before each fill.
// blit_x/blit_y: gol.c sets the top-left of the 2x2 cell to paint.
_BitInt(32) delay_cnt   = 0;
_BitInt(16) pixel_color = 0;
_BitInt(9)  blit_x      = 0;
_BitInt(9)  blit_y      = 0;
