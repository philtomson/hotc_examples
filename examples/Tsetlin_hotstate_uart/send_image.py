#!/usr/bin/env python3
# send_image.py — send a 98-byte MNIST image over UART to
# Tsetlin_hotstate_uart on a Tang Nano 9K, and print the returned class.
#
# Usage:
#   python3 send_image.py --port /dev/ttyUSB1                    # all-zero test image
#   python3 send_image.py --port /dev/ttyUSB1 --image path.bin   # 98 raw bytes

import argparse
import sys
import time

import serial


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", default="/dev/ttyUSB1")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--image", help="path to a 98-byte raw image file; defaults to all-zero")
    args = p.parse_args()

    if args.image:
        with open(args.image, "rb") as f:
            img = f.read()
        if len(img) != 98:
            sys.exit(f"error: image file is {len(img)} bytes, expected exactly 98")
    else:
        img = bytes(98)

    ser = serial.Serial(args.port, args.baud, timeout=3)
    time.sleep(0.2)
    ser.reset_input_buffer()

    print(f"Sending 98-byte image to {args.port}...")
    ser.write(img)
    ser.flush()

    print("Waiting for result byte...")
    result = ser.read(1)
    if not result:
        sys.exit("error: no response (timeout)")

    print(f"Predicted digit: {result[0] & 0xF}")
    ser.close()


if __name__ == "__main__":
    main()
