#!/usr/bin/env python3
# Contact sheet for one theme: rows = beats 1-5, columns = 8 frames per beat
# (1, 20, 40, 60, 80, 100, 118, 140 at 30 fps), each cell labelled with its frame.
#   usage: scripts/contact-sheet.py <theme> <out.png>
# Reads renders/<id>-<theme>-frames/frame_NNNNNN.png (30 fps, 1-based).
import sys, os
from PIL import Image, ImageDraw
theme, out = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, "..")
ids = ["m1-welcome", "m2-recognition", "m3-access", "m4-autopaste", "m5-hotkey"]
frames = [1, 20, 40, 60, 80, 100, 118, 140]
w, h = 240, 150
sheet = Image.new("RGB", (w * len(frames) + 10 * (len(frames) + 1), h * len(ids) + 10 * (len(ids) + 1) + 24), (128, 128, 128))
d = ImageDraw.Draw(sheet)
d.text((10, 6), f"theme: {theme}  (cols: frames {', '.join(map(str, frames))} at 30 fps)", fill=(255, 255, 255))
for r, fid in enumerate(ids):
    for c, f in enumerate(frames):
        p = os.path.join(root, "renders", f"{fid}-{theme}-frames", f"frame_{f:06d}.png")
        im = Image.open(p).convert("RGB").resize((w, h), Image.LANCZOS)
        x0, y0 = 10 + c * (w + 10), 24 + 10 + r * (h + 10)
        sheet.paste(im, (x0, y0))
        label = f"M{r + 1} f{f}"
        d.rectangle((x0 + 3, y0 + 3, x0 + 58, y0 + 19), fill=(0, 0, 0))
        d.text((x0 + 7, y0 + 5), label, fill=(255, 255, 255))
sheet.save(out)
print(out)
