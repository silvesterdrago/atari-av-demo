#!/usr/bin/env python3
"""Screens for settling two questions on the real SM124, before any dithering.

1. Is a pixel really 1:1.2? Squares and circles are drawn twice, once with
   equal pixel counts and once pre-squashed by 1.2. Whichever pair reads as
   square and round on the glass gives the answer.
2. How should the reference art reach 640x400? Either rendered natively at
   640x400 by their own generator, or composed at 640x480 (square pixels,
   4:3) and squashed to 400 rows. Each scene appears both ways, back to back.

    python3 tools/gentest.py        # writes src/test.bin + test_preview.png

The file is N screens of 32000 bytes, ST mono: 80 bytes a row, MSB leftmost,
a set bit is ink.
"""
import os
from PIL import Image, ImageDraw
from sysload import W, H, ASPECT, TALL, pack, sysmod

OUT = "src/test.bin"
PREVIEW = "test_preview.png"


def calib():
    """left pair has equal pixel counts, right pair is pre-squashed by 1.2"""
    im = Image.new("1", (W, H), 0)
    d = ImageDraw.Draw(im)
    s = 160
    sq = int(round(s / ASPECT))
    for cx, hh in ((160, s), (480, sq)):
        d.rectangle([cx-s//2, 110-hh//2, cx+s//2, 110+hh//2], outline=1, width=3)
        d.ellipse([cx-s//2, 290-hh//2, cx+s//2, 290+hh//2], outline=1, width=3)
    return im


def ladder():
    """lines 1..8 px thick, horizontal and vertical, to see what survives"""
    im = Image.new("1", (W, H), 0)
    d = ImageDraw.Draw(im)
    y = 30
    for t in (1, 2, 3, 4, 6, 8):
        d.rectangle([40, y, 300, y + t - 1], fill=1)
        y += t + 22
    x = 360
    for t in (1, 2, 3, 4, 6, 8):
        d.rectangle([x, 30, x + t - 1, 370], fill=1)
        x += t + 36
    return im


def render(scene, mode, mitre=False):
    """mode 'native' renders at 640x400; 'squash' at 640x480 then drops rows"""
    im = scene(sysmod(H if mode == "native" else TALL, mitre))
    if mode == "squash":
        im = im.resize((W, H), Image.NEAREST)
    return im


SCENES = [("corridor", lambda s: s.corridor(phase=0.0)),
          ("tunnel",   lambda s: s.tunnel()),
          ("spiral",   lambda s: s.spiral()),
          ("concentric", lambda s: s.concentric())]

shots = [("calibration", calib()), ("thickness", ladder())]
for name, fn in SCENES:
    for mode in ("native", "squash"):
        try:
            shots.append((f"{name}_{mode}", render(fn, mode)))
        except Exception as e:
            print(f"  {name} {mode}: FAILED {type(e).__name__}: {e}")

shots.append(("corridor_mitred", render(SCENES[0][1], "native", mitre=True)))

blob = b"".join(pack(im) for _, im in shots)
os.makedirs("src", exist_ok=True)
open(OUT, "wb").write(blob)
print(f"{OUT}: {len(blob)} bytes, {len(shots)} screens")
for i, (n, _) in enumerate(shots):
    print(f"  {i}  {n}")
print(f"  src/shows/viewer.s must use NSHOT equ {len(shots)}")

cols = 2
rows = (len(shots) + cols - 1) // cols
sheet = Image.new("L", (W * cols, H * rows), 0)
for i, (_, im) in enumerate(shots):
    sheet.paste(im.convert("L"), (W * (i % cols), H * (i // cols)))
sheet.save(PREVIEW)
print(f"{PREVIEW}: written {sheet.size}")
