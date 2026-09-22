#!/usr/bin/env python3
"""How big can one solid be, and how many faces can it have.

Cost of a redraw, on an STF in mono:

    rows  = ROWF * H          scanlines walked; ROWF ~ visible_faces / 2
    bytes = BOXF * H^2 / 8    the bounding box, written exactly once --
          + 2 * rows          erasing last frame's figure and painting this
                              one are the same pass, plus the two partial
                              bytes at each span's ends
    cost  = rows * CROW + bytes * CBYTE

ROWF and AREAF are properties of the shape alone (scale-free), measured
below off the baked poses at the WORST angle -- a budget that only holds
on average shows up as a stutter once per revolution.

CROW and CBYTE are properties of the machine and of the span loop, and
are measured, not guessed.

CBYTE = 3.1, from src/shows/bench.s at three different loads (4 fills of
the screen take 4 frames, 5 take 5, 9 take 8), which brackets it to
2.92..3.24 against a book cost of 2.75 -- so the shifter stealing the bus
in mono costs a bulk movem.l store only about 13%. A whole 32000-byte
screen touched once is 99k cycles: 0.89 of a frame. THAT is the hard
ceiling on a screen-filling figure, before any geometry at all.

CROW = 335 per pixel of figure height, measured on the fixed bench in
solids.s (-DBENCHSOLID): a 112-px cube of 240 span-rows takes 1.00 frames,
less the 31k cell clear. It was 615 before the row loop was cleaned up and
the picture went to half vertical resolution. CBYTE is doubled to 6.2
because every byte is now written twice, once for each of the two screen
rows a span covers.

The bench matters more than it looks: the show itself skips cells whose
pose has not moved and excites cells at random, so its own redraw count
swings 15..45 between frames and cannot attribute a 20% change to
anything. One shape, one pose, redrawn unconditionally, repeated 8 times
a pass to get resolution finer than a frame.
"""
import math, sys
exec(open('tools/gensolids.py').read().split('# calibrate the projection')[0])

FRAME = 112000
CROW  = float(sys.argv[1]) if len(sys.argv) > 1 else 335.0
CBYTE = float(sys.argv[2]) if len(sys.argv) > 2 else 6.2
SCRH  = 400


def factors(verts, faces):
    worst = 0.0
    for si in range(SCALES):
        for ai in range(ANGLES):
            for x, y in [project(rotate([c*(0.72+0.28*(si/(SCALES-1))) for c in v],
                                        ai*2*math.pi/ANGLES,
                                        ai*2*math.pi/ANGLES*0.618), 1.0)
                         for v in verts]:
                worst = max(worst, abs(x), abs(y))
    pf = 70/worst
    rf = af = 0.0
    nf = 0
    for si in range(SCALES):
        for ai in range(ANGLES):
            pv, fo = build_pose(verts, faces, si, ai, pf)
            h = max(p[1] for p in pv) - min(p[1] for p in pv) + 1
            rows = area = 0.0
            for lvl, ca, cb in fo:
                ys = [pv[j][1] for j in ca]
                rows += max(ys) - min(ys) + 1
                pts = [pv[j] for j in ca] + [pv[j] for j in reversed(cb[1:-1])]
                area += abs(sum(pts[i][0]*pts[(i+1) % len(pts)][1]
                                - pts[(i+1) % len(pts)][0]*pts[i][1]
                                for i in range(len(pts))))/2
            w = max(p[0] for p in pv) - min(p[0] for p in pv) + 1
            rf = max(rf, rows/h)
            af = max(af, w/h)          # bounding box, not silhouette
            nf = max(nf, len(fo))
    return rf, af, nf


def cost(rf, af, H):
    rows = rf*H
    return rows*CROW + (af*H*H/8 + 2*rows)*CBYTE


def maxH(rf, af, frames):
    lo, hi = 4.0, 2000.0
    for _ in range(60):
        mid = (lo+hi)/2
        if cost(rf, af, mid) <= frames*FRAME: lo = mid
        else: hi = mid
    return lo


print(f"span loop: {CROW:.0f} cycles a scanline, {CBYTE:.1f} a byte "
      f"(frame = {FRAME} cycles)\n")
print(f"  {'shape':11s} {'faces':>5s} {'vis':>4s} {'rows/px':>8s} "
      f"{'  tallest it can be, px, at'}")
print(f"  {'':11s} {'':5s} {'':4s} {'':8s} "
      f"{'71Hz':>6s} {'35Hz':>6s} {'18Hz':>6s} {'9Hz':>6s}")
rows_out = []
for name, fn in SHAPES:
    v, f = fn(); f = fix_winding(v, f)
    rf, af, nf = factors(v, f)
    hs = [maxH(rf, af, k) for k in (1, 2, 4, 8)]
    cap = lambda h: f"{min(h, SCRH):6.0f}" + ("*" if h >= SCRH else " ")
    print(f"  {name:11s} {len(f):5d} {nf:4d} {rf:8.2f} "
          + " ".join(cap(h) for h in hs))
    rows_out.append((name, len(f), nf, rf, af, hs))
print("\n  * = taller than the 400-line screen, so screen-filling")
