#!/usr/bin/env python3
"""Frames of the mitred corridor, baked for playback off the card.

    python3 tools/gencorr.py    # writes src/corr.bin + corr_preview.{png,gif}

The corridor's panels and floor bars travel one panel period per unit of
phase, so phase = i/NFRAMES over a whole turn returns the picture to itself:
the frames loop seamlessly however fast they are played, and nothing has to
be drawn on the ST. 24 of them is 750 KB, which a 1 MB machine holds once --
so this scene gets its own binary and cannot join a set.

The file is NFRAMES screens of 32000 bytes, ST mono: 80 bytes a row, MSB
leftmost, a set bit is ink.
"""
from PIL import Image
from sysload import H, W, pack, sysmod

NFRAMES = 24            # must match src/shows/corridor.s
OUT = "src/corr.bin"
PREVIEW = "corr_preview.png"
GIF = "corr_preview.gif"

s = sysmod(H, mitre=True)
frames = [s.corridor(phase=i / NFRAMES) for i in range(NFRAMES)]

open(OUT, "wb").write(b"".join(pack(im) for im in frames))
print(f"{OUT}: {NFRAMES * 32000} bytes, {NFRAMES} frames")
print(f"  src/shows/corridor.s must use NFRAMES equ {NFRAMES}")

cols = 4
rows = (NFRAMES + cols - 1) // cols
sheet = Image.new("L", (W // 2 * cols, H // 2 * rows), 0)
for i, im in enumerate(frames):
    half = im.convert("L").resize((W // 2, H // 2), Image.NEAREST)
    sheet.paste(half, (W // 2 * (i % cols), H // 2 * (i // cols)))
sheet.save(PREVIEW)
print(f"{PREVIEW}: written {sheet.size}")

# 2 VBLs a frame on the ST, so 28 ms here is the same speed on the glass
gf = [im.convert("L") for im in frames]
gf[0].save(GIF, save_all=True, append_images=gf[1:], duration=28, loop=0)
print(f"{GIF}: written")
