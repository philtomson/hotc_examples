#!/usr/bin/env python3
"""Pack the DiffLUT checkpoint's dumped test vectors into the gen/ files the
testbench and host scripts consume:
    gen/images.hex  — N lines × 784 hex bytes (bit-packed threshold bits)
    gen/expect.hex  — N hex lines, predicted digit per image
    images.bin      — the same images, raw bytes (host-side send_batch.py)

    python3 gen_vectors.py <checkpoint_dir> [--n 500]
"""
import argparse
import os

import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("checkpoint_dir")
ap.add_argument("--n", type=int, default=500)
args = ap.parse_args()

X = np.load(os.path.join(args.checkpoint_dir, "test_inputs.npy"))[: args.n]  # (N, 6272) 0/1
preds = np.load(os.path.join(args.checkpoint_dir, "test_preds.npy"))[: args.n]
labels = np.load(os.path.join(args.checkpoint_dir, "test_labels.npy"))[: args.n]
N = X.shape[0]

packed = np.packbits(X, axis=1, bitorder="little")  # (N, 784), bit k of byte p = X[p*8+k]

os.makedirs("gen", exist_ok=True)
with open("gen/images.hex", "w") as f:
    for b in range(N):
        f.write("\n".join(f"{v:02x}" for v in packed[b]) + "\n")
with open("gen/expect.hex", "w") as f:
    f.write("\n".join(f"{p:02x}" for p in preds) + "\n")
packed.tofile("images.bin")
with open("gen/labels.hex", "w") as f:
    f.write("\n".join(f"{l:02x}" for l in labels) + "\n")
print(f"wrote gen/ for {N} images (model accuracy vs labels on these: "
      f"{(preds == labels).mean():.4f})")
