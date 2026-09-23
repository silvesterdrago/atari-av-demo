#!/usr/bin/env python3
"""Bake a halftone ripple tank: dots sized by waves spreading from anchors.

Eight anchors sit on the grid, one a pad. A hit sends a ripple out from its
anchor; ripples from different anchors add, so they interfere, and each fades
as it goes. With nothing playing every dot sits at its resting size, small.

Three things are baked because none of them can be afforded per cell:

  * NEGD, one byte a (anchor, cell): minus the distance from that anchor,
    in eighths of a cell. The frame adds the wavefront position to it and
    has a phase, with no distance to compute.
  * PACKET, sixteen amplitudes by 256 phases. A ripple is a LOCAL packet --
    two cycles that decay -- not an endless sine, so the ring is visible as
    a ring. Spreading loss needs no separate table: the packet rides at
    radius ~ct and the slot's own amplitude decay stands in for it.
  * LEVEL, the sum of four packets (0..252, 128 at rest) to a dot size, so
    the frame needs no multiply and no clamping.

    python3 tools/genhalf.py        # writes src/half.bin + half_preview.png

File layout:
    0                   NRAD sprites, CH rows of CW/8 bytes, size 0 first
    SPRITES             LEVEL, 256 bytes
    PACKETS             16 x 256 bytes
    DISTS               NANCH x NCELL bytes, minus distance
"""
import math, os, struct, zlib

W, H     = 640, 400
CW, CH   = 32, 25          # 20 x 16 cells
NCOL     = W // CW
NROW     = H // CH
NCELL    = NCOL * NROW
NRAD     = 13
ASPECT   = 1.25            # pixel height / width on an SM124
NANCH    = 8
NAMP     = 16
PKLEN    = 88              # phases the packet lasts; 0 is the wavefront
REST     = 32              # a slot's neutral contribution; four make 128
SWING    = 31              # how far a full-amplitude packet swings
OUT      = "src/half.bin"
PREVIEW  = "half_preview.png"

# Anchors on the cell grid, laid out as the pads are: two rows of four.
ANCHORS = [(2, 4), (7, 4), (12, 4), (17, 4),
           (2, 11), (7, 11), (12, 11), (17, 11)]
assert len(ANCHORS) == NANCH

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

# Four slots at rest sum to 4*REST = 128, which has to come out as the
# smallest visible dot. Above that the dots swell, below it they shrink away
# -- so interference reads in both directions.
LEVEL = len(blob)
for v in range(256):
    # steep, so that ONE ripple already swells its crest to size 8 and
    # hollows its trough to nothing; and resting at 2, not 1, so the dots
    # are visible when nothing is playing
    i = int(round((v - 4*REST) / 4.0)) + 2
    blob.append(max(0, min(NRAD-1, i)))

PACKETS = len(blob)
for amp in range(NAMP):
    a = SWING * amp / (NAMP-1)
    for s in range(256):
        if s >= PKLEN:                  # the ripple has gone by
            blob.append(REST)
            continue
        env = 1.0 - s/PKLEN             # and fades as it travels
        v = REST + a * env * math.sin(s * 2*math.pi * 2 / PKLEN)
        blob.append(max(1, min(2*REST-1, int(round(v)))))

DISTS = len(blob)
for ax, ay in ANCHORS:
    for cy in range(NROW):
        for cx in range(NCOL):
            # cells are wider than tall on the glass, so the distance is
            # measured in what the eye sees, not in cells
            dx = (cx - ax) * 1.0
            dy = (cy - ay) * (CH * ASPECT / CW)
            d = int(round(math.hypot(dx, dy) * 8))
            blob.append((-d) & 0xff)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, 'wb').write(bytes(blob))
print(f"{OUT}: {len(blob)} bytes")
print(f"  {NCOL} x {NROW} cells of {CW}x{CH}, {NRAD} sizes, {NANCH} anchors")
print(f"  src/shows/halftone.s: SPRITES {SPRITES} LEVEL {LEVEL} "
      f"PACKETS {PACKETS} DISTS {DISTS}")
print(f"  a cell costs 4 slots x 38 = 152 cycles, a redraw {CH*28}")

# ---------------------------------------------------------------- preview
# Two anchors ringing at different ages, which is what interference looks
# like: the rings cross and the dots there swell or vanish.
active = [(1, 15, 40), (6, 11, 96)]    # anchor, amplitude, wavefront
fb = bytearray(W*H//8)
for cy in range(NROW):
    for cx in range(NCOL):
        cell = cy*NCOL + cx
        v = 0
        for an, amp, t in active:
            nd = blob[DISTS + an*NCELL + cell]
            v += blob[PACKETS + amp*256 + ((nd + t) & 0xff)]
        v += REST * (4 - len(active))
        i = blob[LEVEL + min(255, v)]
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
