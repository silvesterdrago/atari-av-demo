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

Few and large beats many and small here: sixteen blocks, 64 to 96 pixels
across, displaced up to 96. That also holds the composition to two batches, so
a picture takes four VBLs instead of seven.

Two constraints the table guarantees, so the ST needs no clipping and no bit
shifting. Every x and displacement is a multiple of 16 pixels and every width
a multiple of 32, so both ends of every copy are word-aligned -- which is all
a 68000 needs for move.l -- and whole longs fit a row. And every block, fully
displaced, lies inside the screen; a partial displacement is between there and
its origin, so it does too.

Blocks are ordered outside in, so the count rising with the amount IS the
break-up spreading from the edges -- what their `dist` test does with
probability.

    0  nblk.w, then nblk x {xb y wb h uxb uy} as words
       xb, wb, uxb in BYTES; y, h, uy in rows
"""
import math
import random
import struct
from PIL import Image
from sysload import H, W, sysmod

NBLK = 16
AMTFULL = 4096          # must match AMTFULL in src/shows/dissolve.s
OUT = "src/dis.bin"
GIF = "dis_preview.gif"

rnd = random.Random(7)
blocks = []
while len(blocks) < NBLK:
    w = rnd.choice((64, 96))
    h = rnd.randint(40, 80)
    x = rnd.randrange(0, W - w + 1, 16)
    y = rnd.randint(0, H - h)
    dist = math.hypot(x + w / 2 - W / 2, y + h / 2 - H / 2) / math.hypot(W / 2, H / 2)
    if rnd.random() > dist * 1.3:
        continue
    ux = rnd.choice((-96, -64, -48, -32, 32, 48, 64, 96))
    uy = rnd.choice((-1, 1)) * rnd.randint(14, 44)
    ux = max(-x, min(ux, W - w - x)) // 16 * 16
    uy = max(-y, min(uy, H - h - y))
    blocks.append((dist, x, y, w, h, ux, uy))
blocks.sort(key=lambda b: -b[0])

tab = struct.pack(">H", len(blocks))
for _, x, y, w, h, ux, uy in blocks:
    assert x % 16 == ux % 16 == 0 and w in (64, 96)   # dissolve.s has a
                                                     # row per width
    assert 0 <= x and x + w <= W and 0 <= y and y + h <= H
    assert 0 <= x + ux and x + ux + w <= W
    assert 0 <= y + uy and y + uy + h <= H
    tab += struct.pack(">6h", x // 8, y, w // 8, h, ux // 8, uy)
assert len(tab) == 2 + NBLK * 12, "TABSZ in src/shows/dissolve.s must match"
open(OUT, "wb").write(tab)
print(f"{OUT}: {len(tab)} bytes, {len(blocks)} blocks")


def compose(src, amt):
    """exactly what the ST does: count and displacement both out of amt"""
    out = src.copy()
    n = len(blocks) * amt // AMTFULL
    for _, x, y, w, h, ux, uy in blocks[:n]:
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
        n = len(blocks) * amt // AMTFULL
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
