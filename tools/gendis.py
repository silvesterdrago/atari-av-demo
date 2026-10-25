#!/usr/bin/env python3
"""The block table DISSOLVE breaks its picture with, live on the ST.

    python3 tools/gendis.py     # writes src/dis.bin + dis_preview.gif

Their dissolve lifts rectangular regions out of a picture, blanks where they
came from and pastes most of them back displaced -- the break-up growing
toward the edges. Nothing about that needs floating point at run time, so the
ST gets a baked table and executes it: one block is a blank and a copy of
whole rows, which is the cheapest thing the machine does.

Two constraints the table guarantees, so the ST needs no clipping and no bit
shifting. Every x, width and horizontal shift is a multiple of 32 pixels (4
bytes), which keeps both ends of every copy long-aligned; and every block,
displaced, lies wholly inside the screen. y, height and vertical shift are
free, since a row is just a different address.

Blocks are ordered outside in, so consuming them in order IS the break-up
spreading from the edges -- what their `dist` test does with probability.

The frames it breaks are the corridor's own, so the scene reads CORRIDOR.DAT
for them and this file carries nothing but the table.

    0  nblk.w, then nblk x {xb y wb h dxb dy keep} as words
       xb, wb, dxb in BYTES; y, h, dy in rows
"""
import math
import random
import struct
from PIL import Image
from sysload import H, W, sysmod

NBLK = 60
OUT = "src/dis.bin"
GIF = "dis_preview.gif"

src = sysmod(H, mitre=True).corridor(phase=0.0)

rnd = random.Random(7)
blocks = []
while len(blocks) < NBLK:
    w = rnd.choice((32, 64, 96))
    h = rnd.randint(28, 64)
    x = rnd.randrange(0, W - w + 1, 32)
    y = rnd.randint(0, H - h)
    dist = math.hypot(x + w / 2 - W / 2, y + h / 2 - H / 2) / math.hypot(W / 2, H / 2)
    if rnd.random() > dist * 1.3:
        continue
    keep = rnd.random() < 0.75
    dx = rnd.choice((-64, -32, 0, 32, 64)) if keep else 0
    dy = rnd.randint(-20, 20) if keep else 0
    dx = max(-x, min(dx, W - w - x))
    dy = max(-y, min(dy, H - h - y))
    blocks.append((dist, x, y, w, h, dx, dy, keep))
blocks.sort(key=lambda b: -b[0])

tab = struct.pack(">H", len(blocks))
for _, x, y, w, h, dx, dy, keep in blocks:
    assert x % 32 == dx % 32 == w % 32 == 0
    assert 0 <= x and x + w <= W and 0 <= y and y + h <= H
    assert 0 <= x + dx and x + dx + w <= W
    assert 0 <= y + dy and y + dy + h <= H
    tab += struct.pack(">7h", x // 8, y, w // 8, h, dx // 8, dy, int(keep))

assert len(tab) == 2 + NBLK * 14, "TABSZ in src/shows/dissolve.s must match"
open(OUT, "wb").write(tab)
print(f"{OUT}: {len(tab)} bytes, {len(blocks)} blocks")

# Walk the table the way the ST will, so the preview is the real sequence
out = src.copy()
shots = [out.copy()]
for _, x, y, w, h, dx, dy, keep in blocks:
    out.paste(Image.new("1", (w, h), 0), (x, y))
    if keep:
        out.paste(src.crop((x, y, x + w, y + h)), (x + dx, y + dy))
    shots.append(out.copy())
gf = [im.convert("L") for im in shots[::4]] + [src.convert("L")]
gf[0].save(GIF, save_all=True, append_images=gf[1:], duration=160, loop=0)
print(f"{GIF}: written, {len(gf)} steps")
