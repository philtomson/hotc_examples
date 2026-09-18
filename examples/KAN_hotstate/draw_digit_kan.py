#!/usr/bin/env python3
# draw_digit_kan.py -- draw a digit, classify it on KAN_hotstate, and read the
# answer OFF THE BOARD'S LEDs.
#
# Why no result byte: this board's on-board BL616 bridge is reliable host->FPGA
# but intermittent FPGA->host (see plans/kan_hotstate.md). So the answer never
# makes that trip -- top.v shows the classified digit in BINARY on led[3:0],
# with led[4] lit once a classification exists and led[5] as the heartbeat.
#
# Adapted from examples/Tsetlin_hotstate_uart/draw_digit_uart.py. The canvas,
# brush and MNIST-style centering are carried over verbatim -- they were tuned
# against that design's own reference and there is no reason to re-derive them.
# What differs is the FRAME FORMAT, which is KAN's, not Tsetlin's:
#
#   Tsetlin: 28x28 -> 98 bytes, 1 bit per pixel, threshold 51
#   KAN:     28x28 -> 2x2 MEAN -> 14x14 -> 196 bytes, 8-bit quantised
#
# The quantiser is KAN_LUT's own (src/utils.jl quantize_input) with the layer-1
# metadata a=-8.0, b=8.0, n_in=8:
#
#   byte = clamp(round((v + 8) * 255/16), 0, 255)      for v in [0,1]
#
# which maps the whole pixel range into 128..143 -- a narrow band, which is
# correct and was verified against tb_data.txt (min 128, max 143).
#
# Byte order is ROW-major (p = r*14 + c). Julia's reshape is column-major, so
# this was NOT assumed: sample 0 of tb_data.txt was rendered both ways and only
# row-major draws the "7" that its own label says it is.
#
# Usage:
#   python3 draw_digit_kan.py --port /dev/ttyUSB1
#   python3 draw_digit_kan.py --port /dev/ttyUSB1 --self-test   # no GUI
#
# NOTE the board must have been sent its 6,750,208 weight bytes since power-up
# (send_batch.py does this) -- otherwise it is still in load_weights() and will
# ignore images entirely.
import argparse
import math
import sys
import time

import serial
import tkinter as tk

GRID = 28
CELL = 18
CSIZE = CELL * GRID


class App:
    def __init__(self, port, baud):
        self.ser = serial.Serial(port, baud, timeout=3)
        time.sleep(0.2)
        self.ser.reset_input_buffer()

        self.canvas_px = [[0] * GRID for _ in range(GRID)]  # 0..255 intensity
        self.brush = 2  # matches sim_interactive.cpp's default (~3px strokes)

        self.root = tk.Tk()
        self.root.title("Tsetlin Machine digit classifier (UART, real hardware)")

        self.cv = tk.Canvas(self.root, width=CSIZE, height=CSIZE, bg="#202020",
                             highlightthickness=0)
        self.cv.grid(row=0, column=0, rowspan=6, padx=8, pady=8)
        self.cells = [[None] * GRID for _ in range(GRID)]
        for r in range(GRID):
            for c in range(GRID):
                x0, y0 = c * CELL, r * CELL
                self.cells[r][c] = self.cv.create_rectangle(
                    x0, y0, x0 + CELL, y0 + CELL, fill="#202020", outline="#343438")

        self.result_var = tk.StringVar(value="?")
        tk.Label(self.root, textvariable=self.result_var, font=("Helvetica", 72),
                 width=2).grid(row=0, column=1, padx=8)
        self.status_var = tk.StringVar(value="draw a digit, then Classify")
        tk.Label(self.root, textvariable=self.status_var, wraplength=180,
                 justify="left").grid(row=1, column=1, sticky="w", padx=8)

        tk.Button(self.root, text="Classify (Enter)", command=self.classify
                  ).grid(row=2, column=1, sticky="ew", padx=8)
        tk.Button(self.root, text="Clear (C)", command=self.clear
                  ).grid(row=3, column=1, sticky="ew", padx=8)

        self.cv.bind("<B1-Motion>", lambda e: self.paint(e, erase=False))
        self.cv.bind("<Button-1>", lambda e: self.paint(e, erase=False))
        self.cv.bind("<B3-Motion>", lambda e: self.paint(e, erase=True))
        self.cv.bind("<Button-3>", lambda e: self.paint(e, erase=True))
        self.root.bind("<Return>", lambda e: self.classify())
        self.root.bind("<space>", lambda e: self.classify())
        self.root.bind("c", lambda e: self.clear())
        self.root.bind("<BackSpace>", lambda e: self.clear())
        self.root.bind("<Escape>", lambda e: self.root.destroy())
        self.root.bind("=", lambda e: self.adjust_brush(1))
        self.root.bind("+", lambda e: self.adjust_brush(1))
        self.root.bind("-", lambda e: self.adjust_brush(-1))

    def adjust_brush(self, delta):
        self.brush = max(1, min(5, self.brush + delta))
        self.status_var.set(f"brush size: {self.brush}")

    # ---- drawing -----------------------------------------------------------
    def paint(self, event, erase):
        col, row = event.x // CELL, event.y // CELL
        if not (0 <= row < GRID and 0 <= col < GRID):
            return
        sigma = self.brush * 0.30 + 0.25
        ext = int(sigma * 2.5) + 1
        for dr in range(-ext, ext + 1):
            for dc in range(-ext, ext + 1):
                r, c = row + dr, col + dc
                if not (0 <= r < GRID and 0 <= c < GRID):
                    continue
                if erase:
                    self.canvas_px[r][c] = 0
                else:
                    v = 255.0 * math.exp(-(dr * dr + dc * dc) / (2.0 * sigma * sigma))
                    v = min(255, int(v))
                    if v > self.canvas_px[r][c]:
                        self.canvas_px[r][c] = v
        self.redraw()

    def redraw(self):
        for r in range(GRID):
            for c in range(GRID):
                v = self.canvas_px[r][c]
                self.cv.itemconfig(self.cells[r][c], fill=f"#{v:02x}{v:02x}{v:02x}")

    def clear(self):
        self.canvas_px = [[0] * GRID for _ in range(GRID)]
        self.result_var.set("?")
        self.status_var.set("cleared")
        self.redraw()

    # ---- MNIST-style centering (carried over from sim_interactive.cpp) -----
    def centered(self):
        rmin, rmax, cmin, cmax = GRID, -1, GRID, -1
        for r in range(GRID):
            for c in range(GRID):
                if self.canvas_px[r][c] > 8:
                    rmin, rmax = min(rmin, r), max(rmax, r)
                    cmin, cmax = min(cmin, c), max(cmax, c)
        dst = [[0] * GRID for _ in range(GRID)]
        if rmin > rmax:
            return dst
        h, w = rmax - rmin + 1, cmax - cmin + 1
        scale = (GRID * 0.80) / max(h, w)
        oh, ow = max(1, int(h * scale + 0.5)), max(1, int(w * scale + 0.5))
        roff, coff = (GRID - oh) // 2, (GRID - ow) // 2
        for r in range(oh):
            sr = rmin + int(r / scale)
            for c in range(ow):
                sc = cmin + int(c / scale)
                dst[roff + r][coff + c] = self.canvas_px[sr][sc]
        return dst

    # ---- 28x28 -> 196-byte KAN frame ---------------------------------------
    # 2x2 mean downsample to 14x14, then KAN_LUT's quantize_input with the
    # layer-1 metadata (a=-8, b=8, n_in=8). Row-major, verified against
    # tb_data.txt rather than assumed.
    def make_frame(self, norm):
        out = bytearray(196)
        for r in range(14):
            for c in range(14):
                v = (norm[2*r][2*c] + norm[2*r][2*c + 1] +
                     norm[2*r + 1][2*c] + norm[2*r + 1][2*c + 1]) / 4.0
                v /= 255.0                                  # canvas 0..255 -> 0..1
                q = int(round((v + 8.0) * (255.0 / 16.0)))
                out[r * 14 + c] = max(0, min(255, q))
        return bytes(out)

    # ---- classify: send the frame; the board shows the answer on its LEDs ---
    def classify(self):
        norm = self.centered()
        frame = self.make_frame(norm)
        self.status_var.set("sending...")
        self.root.update_idletasks()
        try:
            self.ser.write(frame)
            self.ser.flush()
        except serial.SerialException as e:
            self.status_var.set(f"serial error: {e}")
            return
        self.result_var.set("LEDs")
        self.status_var.set("sent 196 bytes -- read led[3:0] on the board (binary)")

    def run(self):
        self.root.mainloop()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", default="/dev/ttyUSB1")
    # 2 Mbaud is the documented configuration for this example (see
    # plans/kan_hotstate.md): with the result shown on the LEDs rather than
    # returned over UART, nothing depends on the board's intermittent
    # FPGA->host direction, so the fast rate is usable. A mismatch here is
    # silent -- the board would just receive garbage pixels.
    p.add_argument("--baud", type=int, default=2000000)
    args = p.parse_args()

    try:
        app = App(args.port, args.baud)
    except serial.SerialException as e:
        sys.exit(f"error opening {args.port}: {e}")
    app.run()


if __name__ == "__main__":
    main()
