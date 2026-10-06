#!/usr/bin/env python3
# send_image.py — send a 784-byte binarized MNIST image over UART to
# DiffLUT_hotstate_uart, and print the returned digit.
#
# Usage:
#   python3 send_image.py --port /dev/ttyUSB1                      # all-zero image
#   python3 send_image.py --port /dev/ttyUSB1 --image path.bin     # 784 raw bytes

import argparse
import sys
import time

import serial


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", default="/dev/ttyUSB1")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--image", help="path to a 784-byte binarized image file; "
                                   "defaults to all-zero")
    args = p.parse_args()

    if args.image:
        with open(args.image, "rb") as f:
            img = f.read()
        if len(img) != 784:
            sys.exit(f"error: image file is {len(img)} bytes, expected exactly 784")
    else:
        img = bytes(784)

    ser = serial.Serial(args.port, args.baud, timeout=3)
    time.sleep(0.2)
    ser.reset_input_buffer()

    print(f"Sending 784-byte image to {args.port}...")
    ser.write(img)
    ser.flush()

    print("Waiting for result byte...")
    result = ser.read(1)
    if result:
        print(f"Predicted digit: {result[0] & 0xF}")
    else:
        sys.exit("error: no response byte received (timeout)")


if __name__ == "__main__":
    main()
