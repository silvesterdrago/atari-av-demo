#!/usr/bin/env python3
"""Bake a halftone screen: one sprite a dot size, plus the wave tables.

The arithmetic here is about what a full screen costs to touch at all. Even
a straight copy is 4.6 cycles a byte, so 32000 bytes is 1.3 frames -- a
halftone that redraws every cell every frame cannot run at 71 Hz whatever
it does. What makes it work is that a dot's sprite covers its WHOLE cell,
black surround included, so there is no clearing and a cell only needs
touching when its dot changes SIZE. On a field that moves smoothly that is
a third of the cells, and a third of two frames fits inside one.

    python3 tools/genhalf.py        # writes src/half.bin + half_preview.png

Cell is CW x CH pixels, CW/8 bytes wide, and the dots are drawn as ellipses
because the SM124's pixels are taller than they are wide -- a circle in
pixels reads as a squashed dot on the glass.

File layout:
    0..                 NRAD sprites, CH rows of CW/8 bytes, size 0 first
    +NRAD*CH*CW/8       three 256-byte wave tables, values 0..85
"""
import math, os, struct, zlib

W, H     = 640, 400
CW, CH   = 32, 25          # 20 x 16 cells
NCOL     = W // CW
NROW     = H // CH
NRAD     = 13              # dot sizes, 0 (empty) .. 12 (nearly touching)
ASPECT   = 1.25            # pixel height / width on an SM124
OUT      = "src/half.bin"
PREVIEW  = "half_preview.png"

assert W % CW == 0 and H % CH == 0

def sprite(i):
    """one cell: a filled ellipse of size i, and black everywhere else"""
    rows = bytearray(CH * (CW//8))
    if i:
        rx = i * (CW/2) / (NRAD-1)
        ry = rx / ASPECT
        cx, cy = (CW-1)/2.0, (CH-1)/2.0
        for y in range(CH):
            for x in range(CW):
                dx, dy = (x-cx)/rx, (y-cy)/ry
                if dx*dx + dy*dy <= 1.0:
                    rows[y*(CW//8) + (x >> 3)] |= 0x80 >> (x & 7)
    return bytes(rows)

blob = bytearray()
for i in range(NRAD):
    blob += sprite(i)
SPRITES = len(blob)

# Three waves summed make the field. Values are kept to 0..85 so that three
# of them cannot overflow a byte, which lets the ST add them without care.
for k, (amp, bias) in enumerate(((42, 42), (42, 42), (42, 42))):
    t = bytearray()
    for n in range(256):
        t.append(int(bias + amp*math.sin(n*2*math.pi/256)))
    blob += t

# Three waves sum to 0..255, and this turns that into a dot size without a
# multiply in the frame.
LEVELS = len(blob)
for v in range(256):
    blob.append((v * NRAD) // 256)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, 'wb').write(bytes(blob))
print(f"{OUT}: {len(blob)} bytes ({SPRITES} sprites + 768 wave + 256 level)")
print(f"  {NCOL} x {NROW} cells of {CW}x{CH}, {NRAD} sizes")
print(f"  a changed cell costs {CH}*28 = {CH*28} cycles, "
      f"all of them {NCOL*NROW*CH*28/1000:.0f}k = "
      f"{NCOL*NROW*CH*28/112000:.1f} frames")
print(f"  src/shows/halftone.s: NCOL {NCOL} NROW {NROW} NRAD {NRAD} "
      f"CW {CW} CH {CH} WAVES {SPRITES} LEVELS {LEVELS}")

# ---------------------------------------------------------------- preview
wave = [blob[SPRITES + k*256 + n] for k in range(3) for n in range(256)]
def wv(k, n):
    return blob[SPRITES + k*256 + (n & 255)]

fb = bytearray(W*H//8)
t1, t2, t3 = 30, 90, 170
for cy in range(NROW):
    for cx in range(NCOL):
        v = wv(0, cx*37 + t1) + wv(1, cy*43 + t2) + wv(2, (cx+cy)*29 + t3)
        i = blob[LEVELS + (v & 255)]
        sp = blob[i*CH*(CW//8):(i+1)*CH*(CW//8)]
        for y in range(CH):
            for b in range(CW//8):
                fb[(cy*CH + y)*80 + cx*(CW//8) + b] = sp[y*(CW//8) + b]

pix = bytearray(W*H)
for y in range(H):
    for x in range(W):
        pix[y*W+x] = 255 if fb[y*80 + (x >> 3)] >> (7 - (x & 7)) & 1 else 0
def png(path, p, w, h):
    raw = b''.join(b'\x00' + bytes(p[y*w:(y+1)*w]) for y in range(h))
    def chunk(tt, d):
        c = tt + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c))
    open(path, 'wb').write(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 0, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
png(PREVIEW, pix, W, H)
print(f"{PREVIEW}: written")
