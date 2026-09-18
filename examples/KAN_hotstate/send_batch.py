#!/usr/bin/env python3
"""send_batch.py -- drive KAN_hotstate on a real Tang Nano 20K over UART.

Streams weights.bin (6,750,208 bytes) into the board's SDRAM, then classifies
every sample in KAN_LUT's tb_data.txt and reports full-batch accuracy.

Usage:  python3 send_batch.py [port] [--samples N]
        default port /dev/ttyUSB2  (the Tang Nano 20K's FT2232 channel B;
        channel A, one device lower, is the JTAG interface, not the UART)

IMPORTANT -- the board must be freshly programmed before each run. kan_control's
main() is `load_weights(); while (1) step();`, so the weight load happens once
at boot. Running this script a second time without re-flashing would feed
6.75 MB of weight data into load_image(), which is expecting 196-byte images.
Re-run `make -f Makefile.synth_tang20k prog` first.

This does NOT reuse KAN_LUT's test_nano20k.py: that script parses tb_data.txt
as comma-separated `label,byte0,...,byte195`, which is not this file's format.
tb_data.txt is 196 image bytes as 2-hex-digit pairs, a space, then 10 reference
per-class score bytes (verified against generate_test_vectors.jl). The expected
class is the argmax of those 10 scores -- the same reference the Verilator
harness and the software golden model are checked against, so hardware, sim and
golden model are all being held to one standard.
"""
import sys, time, argparse
import serial

DEFAULT_BAUD = 2_000_000
WEIGHT_BYTES = 6_750_208
TB_DATA = "/home/phil/devel/FPGA/KAN_LUT/examples/MNIST/FPGA/tb_data.txt"


def parse_tb_data(path):
    samples = []
    for line in open(path):
        line = line.strip()
        if len(line) < 392 + 1 + 20:
            continue
        img = bytes(int(line[p * 2:p * 2 + 2], 16) for p in range(196))
        scores = [int(line[393 + q * 2:393 + q * 2 + 2], 16) for q in range(10)]
        samples.append((img, max(range(10), key=lambda q: scores[q]), scores))
    return samples


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port", nargs="?", default="/dev/ttyUSB2")
    ap.add_argument("--baud", type=int, default=DEFAULT_BAUD,
                    help="UART baud. The on-board bridge runs at 2 Mbaud, but the "
                         "external USB-TTL workaround (see kan_tang20k_extuart.cst) "
                         "needs 115200 -- that PL2303 silently clamps higher rates.")
    ap.add_argument("--samples", type=int, default=0, help="0 = all")
    ap.add_argument("--leds", action="store_true",
                    help="Do not wait for a result byte. The board displays the "
                         "classified digit in binary on led[3:0] instead (see "
                         "top.v) -- used because this board's FPGA->host UART "
                         "direction is intermittent. Pauses after each image so "
                         "the LEDs can be read.")
    ap.add_argument("--timeout", type=float, default=10.0,
                    help="seconds to wait for each result byte")
    args = ap.parse_args()

    weights = open("weights.bin", "rb").read()
    if len(weights) != WEIGHT_BYTES:
        sys.exit(f"weights.bin is {len(weights)} bytes, expected {WEIGHT_BYTES} "
                 f"-- run pack_weights.py")

    samples = parse_tb_data(TB_DATA)
    if args.samples:
        samples = samples[:args.samples]
    print(f"Loaded {len(weights)} weight bytes and {len(samples)} test samples")

    ser = serial.Serial(args.port, args.baud, timeout=args.timeout)
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    print(f"Streaming weights to {args.port} at {args.baud} baud "
          f"(~{WEIGHT_BYTES * 10 / args.baud:.0f}s at line rate)...")
    t0 = time.time()
    CHUNK = 65536
    for i in range(0, len(weights), CHUNK):
        ser.write(weights[i:i + CHUNK])
        done = min(i + CHUNK, len(weights))
        print(f"  {done} / {len(weights)}  "
              f"({done * 100 // len(weights)}%)", end="\r", flush=True)
    ser.flush()
    dt = time.time() - t0
    print(f"\nWeights streamed in {dt:.1f}s ({len(weights)/dt/1024:.0f} KB/s)")

    # Anything the board emitted during the load would mean it fell out of
    # load_weights() early -- i.e. the byte count desynced.
    stray = ser.in_waiting
    if stray:
        junk = ser.read(stray)
        print(f"WARNING: {stray} unexpected byte(s) during weight load: "
              f"{junk[:16].hex()} -- the board may have desynced; re-flash "
              f"and retry before trusting these results")

    correct = 0
    mism = []
    t0 = time.time()
    for i, (img, expected, scores) in enumerate(samples):
        ser.write(img)
        ser.flush()
        if args.leds:
            print(f"  sample {i}: sent. Expected digit = {expected}. "
                  f"Read led[3:0] on the board (binary), led[4] = valid.")
            input("    press Enter for the next sample (Ctrl-C to stop)...")
            continue
        res = ser.read(1)
        if len(res) != 1:
            print(f"\nTIMEOUT waiting for result on sample {i} "
                  f"(after {args.timeout}s). Board is not responding.")
            print(f"Partial result: {correct}/{i} correct")
            return 1
        pred = res[0]
        if pred == expected:
            correct += 1
        else:
            mism.append((i, expected, pred))
        print(f"  sample {i:3d}: got {pred} expected {expected}  "
              f"{'OK ' if pred == expected else 'MISS'}   "
              f"running {correct}/{i+1}", end="\r", flush=True)
    dt = time.time() - t0

    n = len(samples)
    print(f"\n\nHARDWARE RESULT: {correct}/{n} correct "
          f"({correct/n*100:.2f}%)  [{dt/n*1000:.1f} ms/sample]")
    if mism:
        print(f"Mismatches ({len(mism)}): " +
              ", ".join(f"#{i}(exp {e}, got {g})" for i, e, g in mism[:20]))
    print("PASS -- matches the reference on every sample" if correct == n
          else "FAIL -- hardware disagrees with the reference")
    return 0 if correct == n else 1


if __name__ == "__main__":
    sys.exit(main())
