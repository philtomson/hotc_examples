#!/usr/bin/env python3
# send_batch.py — send every sample in batch_ref.bin (real MNIST test
# images, from examples/Tsetlin_hotstate) over UART to
# Tsetlin_hotstate_uart on real hardware, and compare the hardware's
# prediction against both the true label and Julia's own prediction
# (the same file examples/Tsetlin_hotstate's batch_test.cpp uses to
# validate the SPI/direct-BRAM-load design in simulation).
#
# batch_ref.bin format: 4-byte little-endian sample count, then per
# sample: 1 byte true label, 1 byte Julia prediction, 98 bytes image.
#
# Usage:
#   python3 send_batch.py --port /dev/ttyUSB1
#   python3 send_batch.py --port /dev/ttyUSB1 --limit 10   # first N only

import argparse
import struct
import sys
import time

import serial


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", default="/dev/ttyUSB1")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--file", default="batch_ref.bin")
    p.add_argument("--limit", type=int, default=None, help="only test the first N samples")
    args = p.parse_args()

    with open(args.file, "rb") as f:
        data = f.read()
    (nsamples,) = struct.unpack("<i", data[:4])
    if args.limit:
        nsamples = min(nsamples, args.limit)

    ser = serial.Serial(args.port, args.baud, timeout=3)
    time.sleep(0.2)

    agree_julia = 0
    agree_true = 0
    off = 4
    for s in range(nsamples):
        true_label = data[off]
        julia_pred = data[off + 1]
        img = data[off + 2 : off + 2 + 98]
        off += 2 + 98

        ser.reset_input_buffer()
        ser.write(img)
        ser.flush()
        result = ser.read(1)
        if not result:
            print(f"sample {s}: TIMEOUT (no response)")
            continue
        fpga_pred = result[0] & 0xF

        ok_julia = fpga_pred == julia_pred
        ok_true = fpga_pred == true_label
        agree_julia += ok_julia
        agree_true += ok_true
        flag = "" if ok_julia else "  <-- MISMATCH vs Julia"
        print(f"sample {s}: true={true_label} julia={julia_pred} fpga={fpga_pred}{flag}")

    ser.close()
    print(f"\nAgreement vs Julia: {agree_julia}/{nsamples} ({100.0*agree_julia/nsamples:.1f}%)")
    print(f"Agreement vs true label: {agree_true}/{nsamples} ({100.0*agree_true/nsamples:.1f}%)")


if __name__ == "__main__":
    main()
