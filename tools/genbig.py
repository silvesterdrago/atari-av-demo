#!/usr/bin/env python3
"""Bake the eight solids again, this time one at a time and filling the screen.

Same idea as gensolids.py -- rotation, projection, culling, lighting and the
left/right edge chains all happen here -- but three things had to change for a
figure ten times the area:

  * coordinates are WORDS. At 352 px across they do not fit a signed byte.
  * the blanking box is baked in. Working it out on the machine is where the
    cell version sprang a leak I never found, and the generator knows the
    exact answer for nothing. Rows only: the show blanks the full width of
    the screen, so there is no way left to get the horizontal extent wrong.
  * the top row is rounded down to even here, because the show draws every
    second row and doubles it, and every face has to land on the same grid.

    python3 tools/genbig.py         # writes src/big.bin

File layout:
    0..31   dither table, 8 levels x 4 rows (same as gensolids)
    32..    poses at ((shape*SCALES + scale)*ANGLES + angle) * STRIDE
            +0  nverts.b, nfaces.b
            +2  y0.w     first row to blank, centre-relative, even
            +4  rows.w   rows to blank, covering the doubled last row
            +6  pad.w
            +8  verts[nverts] x { x.w, y.w } signed, centre-relative
            ..  faces[nfaces] x { level.b, nA.b, nB.b, A idx.., B idx.. }
"""
import math, os, struct, sys

src = open('tools/gensolids.py').read().split('# calibrate the projection')[0]
src = src.replace('SCALES, ANGLES = 8, 24', 'SCALES, ANGLES = 4, 48')
src = src.replace('EXTENT  = 70', 'EXTENT  = 176')
src = src.replace('s  = 0.74 + 0.26*(si/(SCALES-1))', 's  = 0.90 + 0.10*(si/(SCALES-1))')
exec(src)

STRIDE = 128
OUT    = "src/big.bin"
SCRH   = 400

# One shape on screen at a time, so each one is calibrated on its own:
# sharing the calibration made a cube 346 px tall and an octahedron 184,
# since it is the cube's diagonal that sets the worst case.
PF = {}
for name, fn in SHAPES:
    v, f = fn(); f = fix_winding(v, f)
    worst = 0.0
    for ai in range(ANGLES):
        pv, _ = build_pose(v, f, SCALES-1, ai, 1.0)
        for x, y in pv:
            worst = max(worst, abs(x), abs(y))
    PF[name] = EXTENT/worst

blob = bytearray(dither_table())
assert len(blob) == 32
widest = 0
for si_shape, (name, fn) in enumerate(SHAPES):
    v, f = fn(); f = fix_winding(v, f)
    for si in range(SCALES):
        for ai in range(ANGLES):
            pv, fo = build_pose(v, f, si, ai, PF[name])
            iv = [(int(round(x)), int(round(y))) for x, y in pv]
            ys = [p[1] for p in iv]
            y0 = min(ys) & ~1                   # even: the doubling grid
            rows = max(ys) + 1 - y0 + 2         # + the twin row, + slack
            assert 0 <= SCRH//2 + y0 and SCRH//2 + y0 + rows <= SCRH, (name, y0, rows)
            # the show blanks a fixed 48-byte window at byte 16, so every
            # pose has to live inside x 128..511
            for x, _ in iv:
                assert -192 <= x <= 191, (name, x)
            p = bytearray()
            p += bytes([len(iv), len(fo)])
            p += struct.pack('>hhh', y0, rows, 0)
            for x, y in iv:
                p += struct.pack('>hh', x, y)
            for lvl, a, b in fo:
                p += bytes([lvl, len(a), len(b)]) + bytes(a) + bytes(b)
            widest = max(widest, len(p))
            assert len(p) <= STRIDE, (name, len(p))
            blob += p + bytes(STRIDE - len(p))

os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, 'wb').write(bytes(blob))
print(f"{OUT}: {len(blob)} bytes, {SCALES} scales x {ANGLES} angles, "
      f"stride {STRIDE} (widest pose {widest})")
# what the show will have to pay for
for name, fn in SHAPES:
    v, f = fn(); f = fix_winding(v, f)
    rr, hh, nf = 0, 0, 0
    for ai in range(ANGLES):
        pv, fo = build_pose(v, f, SCALES-1, ai, PF[name])
        ys = [p[1] for p in pv]
        h = max(ys) - min(ys) + 1
        rows = sum(max(pv[j][1] for j in a) - min(pv[j][1] for j in a) + 1
                   for _, a, _ in fo)
        rr = max(rr, rows); hh = max(hh, h); nf = max(nf, len(fo))
    print(f"  {name:11s} up to {hh:3.0f} px tall, {nf} faces visible, "
          f"{rr:4.0f} span-rows")
