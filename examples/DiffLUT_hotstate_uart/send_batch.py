#!/usr/bin/env python3
# send_batch.py — send the full packed test set (images.bin, written by
# gen_vectors.py) to DiffLUT_hotstate_uart over UART, one 784-byte image at a
# time, and report agreement against the Julia model's predictions
# (gen/expect.hex) and the true labels (gen/labels.hex).
#
# Use this, not a single test image, to judge whether a build actually works.
#
#   python3 send_batch.py --port /dev/ttyUSB1
#   python3 send_batch.py --port /dev/ttyUSB1 --limit 20

import argparse

import numpy as np
import serial


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", default="/dev/ttyUSB1")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--limit", type=int, default=0, help="only send the first N images (0 = all)")
    args = p.parse_args()

    img = np.fromfile("images.bin", dtype=np.uint8)
    n = img.size // 784
    img = img.reshape(n, 784)
    expect = np.array([int(l, 16) for l in open("gen/expect.hex")])
    labels = np.array([int(l, 16) for l in open("gen/labels.hex")])
    if args.limit:
        n = min(n, args.limit)

    ser = serial.Serial(args.port, args.baud, timeout=5)
    ser.reset_input_buffer()

    model_ok = label_ok = 0
    for i in range(n):
        ser.write(img[i].tobytes())
        r = ser.read(1)
        if len(r) != 1:
            print(f"image {i}: TIMEOUT")
            continue
        d = r[0] & 0xF
        model_ok += d == expect[i]
        label_ok += d == labels[i]
        if (i + 1) % 50 == 0:
            print(f"{i + 1}/{n}: model agreement {model_ok}/{i + 1}, label acc {label_ok}/{i + 1}")

    print(f"\nRESULT: {model_ok}/{n} match the Julia model, "
          f"{label_ok}/{n} match the true labels ({label_ok / n:.4f} accuracy)")


if __name__ == "__main__":
    main()
