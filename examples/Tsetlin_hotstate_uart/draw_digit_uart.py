#!/usr/bin/env python3
# draw_digit_uart.py — draw a digit on a 28x28 canvas and classify it on
# real Tang Nano 9K hardware running Tsetlin_hotstate_uart, over UART.
#
# This is the UART/real-hardware counterpart of examples/Tsetlin_hotstate's
# sim_interactive.cpp (which drives a Verilator model over simulated SPI).
# The canvas-to-image packing, centering, and brush constants below are
# carried over verbatim from that tool since they're tuned to match the
# training data (Julia MLDatasets MNIST, booleanize(0.2)) -- freehand input
# skipped through centering, or packed with a different bit convention,
# will classify badly even on working hardware and look like a model
# problem. See send_image.py's docstring / the example README for the wire
# protocol (98 raw image bytes in, 1 result byte out); the bit-packing here
# was cross-checked offline against sample0.hex (known label 7) before
# ever touching hardware.
#
# Usage:
#   python3 draw_digit_uart.py --port /dev/ttyUSB1
#
# Mouse: left-drag draws, right-drag erases.
# Keys:  ENTER/SPACE = classify   C/BackSpace = clear   +/- = brush size

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

    # ---- 28x28 -> 98-byte packed image (threshold 51 = Julia booleanize(0.2)) -
    def make_frame(self, norm):
        out = bytearray(98)
        for r in range(GRID):
            for c in range(GRID):
                if norm[r][c] > 51:
                    idx = r * GRID + c
                    out[idx // 8] |= 1 << (idx % 8)
        return bytes(out)

    # ---- classify over UART --------------------------------------------------
    def classify(self):
        norm = self.centered()
        frame = self.make_frame(norm)
        self.status_var.set("sending...")
        self.root.update_idletasks()
        try:
            self.ser.reset_input_buffer()
            self.ser.write(frame)
            self.ser.flush()
            result = self.ser.read(1)
        except serial.SerialException as e:
            self.status_var.set(f"serial error: {e}")
            return
        if not result:
            self.status_var.set("timeout: no response from board")
            return
        digit = result[0] & 0xF
        self.result_var.set(str(digit))
        self.status_var.set("classified")

    def run(self):
        self.root.mainloop()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", default="/dev/ttyUSB1")
    p.add_argument("--baud", type=int, default=115200)
    args = p.parse_args()

    try:
        app = App(args.port, args.baud)
    except serial.SerialException as e:
        sys.exit(f"error opening {args.port}: {e}")
    app.run()


if __name__ == "__main__":
    main()
