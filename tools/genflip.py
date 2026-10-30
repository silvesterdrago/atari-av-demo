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
import math
import sys
from PIL import Image, ImageChops, ImageDraw

_or = ImageChops.logical_or         # two systems of depth over each other
from sysload import H, W, pack, sysmod

NFRAMES = 24            # must match src/shows/flipbook.inc

# Each scene is one turn of phase. Notes on the arguments:
#  tun   t is the side bar's thickness at z=1, which sets the axial length of
#        the band every frame is cut from: 28 runs the top and bottom bars of
#        the six visible frames over 19, 10, 5, 3, 3, 3 pixels.
#  wave  amp scales with the row spacing -- their grid is 640x360, ours 400
#        rows, so 52 * 400/360 keeps the waves the same size relative to the
#        gaps they ride in.
#  desy  dy likewise: the two halves are 16 rows out of step, not 14.
#  floor their phase marches the transverse lines and leaves the longitudinal
#        ones standing, which is the whole motion. The step comes from the
#        depth set itself, so the loop closes to the pixel -- see
#        tools/sysload.py, FLOOR_STEP.
#  drift their axis_loss holds the vanishing point at a FIXED offset, but the
#        loop it came from sweeps it. A full sine over the turn sweeps it out
#        to one side and back through the other, and closes on itself.
PITB_ZFAR = 3.2 ** 1.25
PITB_RINGS = 6


def pitb(s, p):
    """23 close up: the floor stands still and the terraces run into the pit.

    Three depths fit in frame here, so a marching floor moves exactly one
    transverse line, which reads as a glitch rather than as motion. The floor
    is fixed at phase 0 and the pit's own rings ride instead. Their inset is
    linear in f, so ring k at the end of a turn is exactly where ring k-1
    started: a new one opens at the rim as the innermost reaches the bottom,
    and the loop closes. The four wall edges stand, or the pit would have no
    sides.

    This is cut_pit with the rings put on a phase; it is reimplemented here
    rather than patched into the module, because 22 draws its pit through the
    same function and wants it still.
    """
    im = s.floor(phase=0.0, xs=range(-4, 5, 2),
                 zs=tuple(3.2 ** (k / 2) for k in range(3)),
                 zfar=PITB_ZFAR, t=16)
    x0, x1, z0, z1, depth, t_ = -3.0, 3.0, 1.05, 2.4, 1.0, 20
    rim = [s.fpt(x0, z0), s.fpt(x1, z0), s.fpt(x1, z1), s.fpt(x0, z1)]
    mask = Image.new("1", (W, H), 0)
    ImageDraw.Draw(mask).polygon([(s.R(x), s.R(y)) for x, y in rim], fill=1)
    inner, d = s.new()

    def ring(f):
        ix, iz = (x1 - x0) * 0.42 * f, (z1 - z0) * 0.42 * f
        return [s.fpt(x0 + ix, z0 + iz, depth * f), s.fpt(x1 - ix, z0 + iz, depth * f),
                s.fpt(x1 - ix, z1 - iz, depth * f), s.fpt(x0 + ix, z1 - iz, depth * f)]

    for a, b in zip(ring(0.0), ring(1.0)):
        s.thick_line(d, a, b, max(4, t_ - 3))
    for k in range(PITB_RINGS):
        f = (k + p) / PITB_RINGS
        r = ring(f)
        s.poly_line(d, r + [r[0]], max(4, t_ - f * PITB_RINGS))
    out = im.copy()
    out.paste(Image.new("1", (W, H), 0), (0, 0), mask)
    out.paste(inner, (0, 0), mask)
    s.poly_line(ImageDraw.Draw(out), rim + [rim[0]], t_ + 4)
    return out


SCENES = {"corr":  lambda s, p: s.corridor(phase=p),
          "tun":   lambda s, p: s.tunnel(phase=p, t=28),
          "wave":  lambda s, p: s.wave(phase=p, amp=58),
          "desy":  lambda s, p: s.desync(phase=p, dy=16),
          "floor": lambda s, p: s.floor(phase=p),
          # --- act IV, whose whole character is movement forward. Their own
          # depth sets are hand-typed and not quite geometric, so the loop
          # would not close; each one here is 1.42**k, the step the generator
          # already uses, which is the same correction the floor needed.
          "tunp":  lambda s, p: s.tunnel(phase=p, n=4, ratio=1.7, t=18),
          "branch": lambda s, p: s.branching(phase=p),
          "pit":   lambda s, p: s.pit(phase=p),
          "pitb":  pitb,
          "walls": lambda s, p: _or(s.rhythm_walls(phase=p),
                                    s.corridor(phase=p, panels=False, light=False)),
          "expand": lambda s, p: s.corridor(phase=p, panel_len=1.1, panel_gap=0.35),
          "drift": lambda s, p: s.axis_loss(phase=p,
                                            dx=round(170 * math.sin(2 * math.pi * p)),
                                            dy=round(-60 * math.sin(2 * math.pi * p)))}

name = sys.argv[1] if len(sys.argv) > 1 else ""
if name not in SCENES:
    sys.exit(f"usage: genflip.py [{'|'.join(SCENES)}]")
fn = SCENES[name]

s = sysmod(H, mitre=True)
frames = [fn(s, i / NFRAMES) for i in range(NFRAMES)]
assert frames[0].tobytes() == fn(s, 1.0).tobytes(), \
    f"{name} is not periodic in phase: the loop would jump"

out = f"src/{name}.bin"
open(out, "wb").write(b"".join(pack(im) for im in frames))
print(f"{out}: {NFRAMES * 32000} bytes, {NFRAMES} frames of {name}")

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
