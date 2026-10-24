#!/usr/bin/env python3
"""Bake one reference scene into a loop of ST screens, played back off the card.

    python3 tools/genflip.py corr    # src/corr.bin + corr_preview.{png,gif}
    python3 tools/genflip.py tun

Both scenes here move by their `phase`, and both are periodic in it: the
corridor's panels travel one panel period per turn, and the tunnel's frames
sit at depths ratio**k, so advancing a whole turn maps the set onto itself.
phase = i/NFRAMES therefore loops seamlessly however fast it is played, and
the ST draws nothing at all.

24 screens is 750 KB, which a 1 MB machine holds once, so each scene gets its
own binary. The file is NFRAMES screens of 32000 bytes, ST mono: 80 bytes a
row, MSB leftmost, a set bit is ink.
"""
import sys
from PIL import Image
from sysload import H, W, pack, sysmod

NFRAMES = 24            # must match src/shows/flipbook.inc

# t is the tunnel side bar's thickness at z=1, which sets the axial length of
# the band every frame is cut from: 28 runs the top and bottom bars of the six
# visible frames over 19, 10, 5, 3, 3, 3 pixels.
# amp scales with the row spacing: their grid is 640x360, ours 400 rows, so
# 52 * 400/360 keeps the waves the same size relative to the gaps they ride in.
SCENES = {"corr": ("corridor", {}),
          "tun":  ("tunnel", {"t": 28}),
          "wave": ("wave", {"amp": 58})}

name = sys.argv[1] if len(sys.argv) > 1 else ""
if name not in SCENES:
    sys.exit(f"usage: genflip.py [{'|'.join(SCENES)}]")
fn, kw = SCENES[name]

s = sysmod(H, mitre=True)
frames = [getattr(s, fn)(phase=i / NFRAMES, **kw) for i in range(NFRAMES)]
assert frames[0].tobytes() == getattr(s, fn)(phase=1.0, **kw).tobytes(), \
    f"{fn} is not periodic in phase: the loop would jump"

out = f"src/{name}.bin"
open(out, "wb").write(b"".join(pack(im) for im in frames))
print(f"{out}: {NFRAMES * 32000} bytes, {NFRAMES} frames of {fn}")

cols = 4
rows = (NFRAMES + cols - 1) // cols
sheet = Image.new("L", (W // 2 * cols, H // 2 * rows), 0)
for i, im in enumerate(frames):
    half = im.convert("L").resize((W // 2, H // 2), Image.NEAREST)
    sheet.paste(half, (W // 2 * (i % cols), H // 2 * (i // cols)))
sheet.save(f"{name}_preview.png")

# 2 VBLs a frame on the ST, so 28 ms here is the same speed on the glass
gf = [im.convert("L") for im in frames]
gf[0].save(f"{name}_preview.gif", save_all=True, append_images=gf[1:],
           duration=28, loop=0)
print(f"{name}_preview.png, {name}_preview.gif: written")
