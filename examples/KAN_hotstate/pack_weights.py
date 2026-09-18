#!/usr/bin/env python3
# pack_weights.py -- pack KAN_LUT's trained MNIST LUT weights into the same
# flat byte blob KAN_LUT's test_nano20k.py streams over UART: little-endian
# 16-bit per LUT entry, layer1 then layer2, no framing. Same algorithm as
# test_nano20k.py's load_luts(), reused verbatim (not re-derived) so this
# stays byte-for-byte identical to what real hardware testing sends.

import json
import os
import struct
import sys

# Point this at your KAN_LUT checkout: https://github.com/philtomson/KAN_LUT
# Override with the KAN_LUT_MNIST environment variable or argv[2].
KAN_LUT_MNIST = os.environ.get(
    "KAN_LUT_MNIST",
    os.path.expanduser("~/devel/FPGA/KAN_LUT/examples/MNIST"),
)


def load_luts(json_path, d_out, d_in):
    with open(json_path, "r") as f:
        data = json.load(f)
    luts_dict = data["luts"]
    bin_data = bytearray()
    for q in range(d_out):
        for p in range(d_in):
            vals = luts_dict[f"lut_{q+1}_{p+1}"]
            for v in range(256):
                val = vals[v]
                if val < 0:
                    val = (1 << 16) + val
                bin_data.extend(struct.pack("<H", val))
    return bin_data


def main():
    global KAN_LUT_MNIST
    out_path = sys.argv[1] if len(sys.argv) > 1 else "weights.bin"
    if len(sys.argv) > 2:
        KAN_LUT_MNIST = sys.argv[2]
    if not os.path.isdir(KAN_LUT_MNIST):
        sys.exit(f"KAN_LUT MNIST dir not found: {KAN_LUT_MNIST}\n"
                 f"Clone https://github.com/philtomson/KAN_LUT and set "
                 f"KAN_LUT_MNIST=<path>/examples/MNIST")
    l1 = load_luts(f"{KAN_LUT_MNIST}/mnist_luts_layer1.json", 64, 196)
    l2 = load_luts(f"{KAN_LUT_MNIST}/mnist_luts_layer2.json", 10, 64)
    weights = l1 + l2
    expected = 6750208
    assert len(weights) == expected, f"got {len(weights)}, expected {expected}"
    with open(out_path, "wb") as f:
        f.write(weights)
    print(f"Wrote {len(weights)} bytes to {out_path}")


if __name__ == "__main__":
    main()
