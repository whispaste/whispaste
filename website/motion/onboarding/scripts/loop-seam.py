#!/usr/bin/env python3
# Loop-seam gate: frame 1 (t = 0) and the last frame (t = 4.967 s) must look the
# same, so the 5 s loop closes without a jump. Compares the mean absolute pixel
# difference (0-255) of the seam with the median difference of ordinary adjacent
# frames. Seam passes when it stays under max(1.0, 2 x median adjacent).
#   usage: scripts/loop-seam.py <composition-id> <theme> [...]
import os, statistics, sys
from PIL import Image, ImageChops, ImageStat
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, "..")

def diff(a, b):
    d = ImageChops.difference(Image.open(a).convert("RGB"), Image.open(b).convert("RGB"))
    return sum(ImageStat.Stat(d).mean) / 3

ok_all = True
for id_, theme in zip(sys.argv[1::2], sys.argv[2::2]):
    frames = os.path.join(root, "renders", f"{id_}-{theme}-frames")
    path = lambda n: os.path.join(frames, f"frame_{n:06d}.png")
    seam = diff(path(1), path(150))
    adjacent = [diff(path(n), path(n + 1)) for n in range(1, 150)]
    median = statistics.median(adjacent)
    limit = max(1.0, 2 * median)
    ok = seam <= limit
    ok_all = ok_all and ok
    print(f"{id_:15} {theme:7} seam {seam:6.3f}  median-adjacent {median:6.3f}  limit {limit:6.3f}  {'PASS' if ok else 'FAIL'}")
sys.exit(0 if ok_all else 1)
