#!/usr/bin/env python3
"""The block table DISSOLVE breaks its picture with, live on the ST.

    python3 tools/gendis.py     # writes src/dis.bin + dis_preview.gif

Their dissolve lifts rectangular regions out of a picture and pastes them back
displaced, and the displacement is proportional to how deep the break-up is --
so the blocks slide out and slide back rather than appearing whole. The table
therefore carries each block's displacement AT FULL BREAK-UP, as a direction
the ST scales by the current amount. The blank left behind is the black gap,
so no tile has to be removed for one to open: a removed tile is the one thing
in their scene that cannot breathe.

The break-up also comes in levels, and each level has its OWN set of blocks
rather than the previous set plus more. Crossing into one therefore re-deals
the whole picture, which is what makes it read as a fault rather than a script
playing out. Each level takes more of the frame and reaches further in toward
the vanishing point: the radius it draws from starts at the rim and walks to
the centre, so the deepest level can break the far end of the corridor.

Area grows by COUNT, never by block size: 4 blocks at the rim to 16 at the
centre. A larger block costs its area twice over -- blanked, then laid down --
and eight blocks a frame is already the ceiling that fits. Because each level
is drawn independently, old territory loses blocks as the new ground is taken,
which is the only way coverage can move inward on a fixed budget.

Two constraints the table guarantees, so the ST needs no clipping and no bit
shifting. Every x and displacement is a multiple of 16 pixels and every width
a multiple of 32, so both ends of every copy are word-aligned -- which is all
a 68000 needs for move.l -- and whole longs fit a row. And every block, fully
displaced, lies inside the screen; a partial displacement is between there and
its origin, so it does too.

Blocks are ordered outside in, so the count rising with the amount IS the
break-up spreading from the edges -- what their `dist` test does with
probability.

    0            nlev.w
    2 + j*LEVSZ  level j: count.w, then MAXBLK x {xb y wb h uxb uy} as words,
                 the entries past count never read
                 xb, wb, uxb in BYTES; y, h, uy in rows
"""
import math
import random
import struct
import sys
from PIL import Image
from sysload import H, W, sysmod

# `cuts` makes the same table with every displacement at zero, which the ST
# reads as a block that is blanked and never laid back: their frame 52, the
# corridor punched full of holes. One table format, two scenes.
CUTS = len(sys.argv) > 1 and sys.argv[1] == "cuts"

AMTFULL = 4096          # all four must match src/shows/dissolve.s
NLEV = 6
MAXBLK = 16
COUNTS = (4, 6, 9, 11, 14, 16)
RMIN = (0.78, 0.62, 0.47, 0.32, 0.16, 0.0)      # how far in each level reaches
OUT = "src/cut.bin" if CUTS else "src/dis.bin"
GIF = ("cut_preview.gif" if CUTS else "dis_preview.gif")
SHEET = ("cut_levels.png" if CUTS else "dis_levels.png")


def level(j):
    """one level's blocks, drawn from its own stream so no level is another's
    superset -- crossing into it re-deals the picture"""
    rnd = random.Random(7 + 101 * j)
    out = []
    while len(out) < COUNTS[j]:
        w = rnd.choice((64, 96))
        h = rnd.randint(40, 80)
        # The RADIUS is drawn, not the position. Drawing a position instead
        # makes the middle of the frame improbable -- there is little area
        # there -- and the deepest level then never reaches the far end of the
        # corridor. Drawing r also thins the rim as a level widens, which is
        # the old territory giving way.
        r = rnd.uniform(RMIN[j], 1.0)
        a = rnd.uniform(0, 2 * math.pi)
        x = min(W - w, max(0, round((W / 2 + math.cos(a) * r * W / 2 - w / 2) / 16) * 16))
        y = min(H - h, max(0, round(H / 2 + math.sin(a) * r * H / 2 - h / 2)))
        r = math.hypot(x + w / 2 - W / 2, y + h / 2 - H / 2) / math.hypot(W / 2, H / 2)
        if r < RMIN[j]:
            continue                    # clamping into the frame pulls a block
                                        # inward, past its level's floor
        if CUTS:
            ux = uy = 0
        else:
            ux = rnd.choice((-96, -64, -48, -32, 32, 48, 64, 96))
            uy = rnd.choice((-1, 1)) * rnd.randint(14, 44)
        ux = max(-x, min(ux, W - w - x)) // 16 * 16
        uy = max(-y, min(uy, H - h - y))
        out.append((r, x, y, w, h, ux, uy))
    out.sort(key=lambda b: -b[0])
    return out


levels = [level(j) for j in range(NLEV)]

area = [sum(b[3] * b[4] for b in lv) for lv in levels]
reach = [min(b[0] for b in lv) for lv in levels]
for j in range(1, NLEV):
    assert area[j] > area[j - 1], "a level has to take more of the frame"
    assert reach[j] < reach[j - 1], "and reach further in"
    shared = {b[1:] for b in levels[j]} & {b[1:] for b in levels[j - 1]}
    assert len(shared) <= 1, "levels must not be one another's supersets"
print(f"{'level':5} {'blocks':>6} {'area':>7} {'of frame':>9} {'reaches to':>11}")
for j in range(NLEV):
    print(f"{j:5} {len(levels[j]):6} {area[j]:7} {area[j]*100//(W*H):8} % {reach[j]:11.2f}")

tab = struct.pack(">H", NLEV)
for lv in levels:
    tab += struct.pack(">H", len(lv))
    for _, x, y, w, h, ux, uy in lv:
        assert x % 16 == 0 and ux % 16 == 0 and w in (64, 96)   # dissolve.inc
                                                                # has a row
                                                                # per width
        assert 0 <= x and x + w <= W and 0 <= y and y + h <= H
        assert 0 <= x + ux and x + ux + w <= W
        assert 0 <= y + uy and y + uy + h <= H
        tab += struct.pack(">6h", x // 8, y, w // 8, h, ux // 8, uy)
    tab += bytes(12 * (MAXBLK - len(lv)))
assert len(tab) == 2 + NLEV * (2 + MAXBLK * 12), "TABSZ in dissolve.s must match"
open(OUT, "wb").write(tab)
print(f"{OUT}: {len(tab)} bytes, {NLEV} levels")


# One sheet of all six at the top of their own band, to see the coverage walk
# inward: it is the only view that shows a level whole.
def sheet():
    src = sysmod(H, mitre=True).corridor(phase=0.0)
    out = Image.new("L", (W * 2, H * 3), 0)
    for j in range(NLEV):
        amt = (j + 1) * AMTFULL // NLEV - 1
        out.paste(compose(src, amt).convert("L"), (W * (j % 2), H * (j // 2)))
    out.save(SHEET)
    print(f"{SHEET}: written {out.size}")


def compose(src, amt):
    """exactly what the ST does: the level out of amt, the displacement too"""
    out = src.copy()
    if amt == 0:
        return out
    for _, x, y, w, h, ux, uy in levels[min(NLEV - 1, NLEV * amt // AMTFULL)]:
        dx = (((ux // 8) * amt // AMTFULL) & ~1) * 8   # as the ST: asr, then
        dy = uy * amt // AMTFULL                       # even bytes
        out.paste(Image.new("1", (w, h), 0), (x, y))
        out.paste(src.crop((x, y, x + w, y + h)), (x + dx, y + dy))
    return out


# The preview is a VBL-by-VBL run of what show_frame does -- the envelope and
# the composition state machine -- so the pictures it holds, and how long it
# holds each, are the ones the machine produces. All five constants below have
# to match src/shows/dissolve.s.
KICK, ATTACK, DECAY = 6, 96, 20
PERBATCH, COPYSTEPS = 8, 2
FB_CRUISE, NFRAMES = 128, 24


def run(hits, vbls):
    tgt = amt = fphase = 0
    composing = copied = cblk = ck = camt = cn = 0
    shown, out = None, []
    for t in range(vbls):
        if t in hits:
            tgt = min(AMTFULL, tgt + hits[t] * KICK)
        tgt = max(0, tgt - DECAY)
        amt = min(tgt, amt + ATTACK) if amt < tgt else tgt
        fphase = (fphase + FB_CRUISE) % (NFRAMES * 256)
        n = 0 if amt == 0 else len(levels[min(NLEV - 1, NLEV * amt // AMTFULL)])
        if n == 0:                          # clean: the frame itself, 2 VBLs
            composing = 0
            if shown != (fphase >> 8, 0):
                shown = (fphase >> 8, 0)
                out.append((t, *shown))
        elif not composing:                 # start one, on this frame and depth
            composing, copied, cblk = 1, 0, 0
            ck, camt, cn = fphase >> 8, amt, n
        elif copied < COPYSTEPS:
            copied += 1
        else:
            cblk += PERBATCH
            if cblk >= cn:
                composing = 0
                shown = (ck, camt)
                out.append((t, *shown))
    return out


# Six hits about four a second, rising, then silence: the target stacks faster
# than it sinks, so the break-up climbs -- to about four fifths on this roll --
# and then subsides.
VBLS = 330
hits = {20 + i * 18: v for i, v in enumerate((70, 110, 140, 170, 200, 240))}
pics = run(hits, VBLS)
print(f"preview: {len(pics)} pictures over {VBLS} VBLs; "
      f"depth runs {' '.join(str(a * 100 // AMTFULL) for _, _, a in pics[::5])} %")

s = sysmod(H, mitre=True)
cache = {}
shots, holds = [], []
for (t, k, amt), nxt in zip(pics, [p[0] for p in pics[1:]] + [VBLS]):
    if k not in cache:
        cache[k] = s.corridor(phase=k / NFRAMES)
    shots.append(compose(cache[k], amt).convert("L"))
    holds.append(max(14, (nxt - t) * 14))
shots[0].save(GIF, save_all=True, append_images=shots[1:], duration=holds, loop=0)
print(f"{GIF}: written, {len(shots)} pictures")
sheet()
