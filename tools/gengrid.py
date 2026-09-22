#!/usr/bin/env python3
"""Bake the static half of a HALFTRON-style grid: city, horizon, perspective.

The whole point of this effect is that what looks expensive costs nothing.
The skyline and the converging lines never move, so they are baked here as
one finished 32000-byte screen and copied into both buffers once at start-up.
The ST then only moves the horizontal lines, which are whole screen rows --
the cheapest thing this machine can draw -- and puts the background back
underneath them out of the same image.

    python3 tools/gengrid.py        # writes src/grid.bin + grid_preview.png

File layout:
    0..31999        the background, ST mono format: 80 bytes a row, MSB left
    32000..         row table: PHASES x NLINES words, absolute screen rows,
                    nearest line first. Phase k moves the floor toward the
                    viewer; after the last phase the set repeats shifted by
                    one line, so it loops with no seam.
"""
import math, os, random, struct, zlib

W, H     = 640, 400
HORIZON  = 200
NLINES   = 6                # The far ones are NOT drawn as lines at all.
                            # Equal spacing on the ground bunches them up
                            # toward the horizon, where they merge into
                            # stair-steps; in the reference that whole
                            # region is one dithered band instead, and the
                            # lines only start once they are well apart.
PHASES   = 64
DEPTH    = 199.0            # 199/(i+p) rows below the horizon
NCONV    = 13               # converging lines
APEX     = 55               # the vanishing point sits this far ABOVE the
                            # horizon, behind the city, and the lines are cut
                            # at the city's base. They therefore arrive still
                            # separated instead of pinching into a triangle
                            # of merged stair-steps on screen.
BAND     = 30               # the band reaches down to the first line
OUT      = "src/grid.bin"
PREVIEW  = "grid_preview.png"

fb = bytearray(W*H//8)      # 1 = lit

def plot(x, y):
    if 0 <= x < W and 0 <= y < H:
        fb[y*80 + (x >> 3)] |= 0x80 >> (x & 7)

def hline(y, x0, x1, pat=0xFF):
    for x in range(max(0, x0), min(W, x1+1)):
        if pat >> (7 - (x & 7)) & 1:
            plot(x, y)

def vfill(x0, x1, y0, y1, pat):
    """pat is four bytes, an 8x4 dither cell"""
    for y in range(max(0, y0), min(H, y1+1)):
        row = pat[y & 3]
        for x in range(max(0, x0), min(W, x1+1)):
            if row >> (7 - (x & 7)) & 1:
                plot(x, y)

# ---------------------------------------------------------------- the city
# Buildings thin out and darken toward the edges, which is what gives the
# skyline a middle. Two dither densities and a solid top edge is enough
# structure at this size -- windows would vanish into the halftone.
rnd = random.Random(7)
DENSE  = (0xAA, 0x55, 0xAA, 0x55)   # fine check
SPARSE = (0x88, 0x22, 0x88, 0x22)   # quarter dots
x = -10
while x < W + 10:
    w = rnd.randint(7, 34)
    mid = 1.0 - abs(x + w/2 - W/2)/(W/2)        # 1 at the centre, 0 at the edge
    mid = max(0.0, min(1.0, mid))               # buildings hang off both ends
    h = int((10 + 62*mid**1.4) * rnd.uniform(0.55, 1.15))
    h = max(6, min(78, h))
    top = HORIZON - h
    vfill(x, x+w-1, top, HORIZON-1, DENSE if mid > 0.45 else SPARSE)
    hline(top, x, x+w-1)                        # a lit top edge reads as an edge
    if h > 45 and rnd.random() < 0.5:           # a mast on the tall ones
        mx = x + w//2
        for yy in range(top - rnd.randint(8, 26), top):
            plot(mx, yy)
    x += w + rnd.randint(0, 5)

# --------------------------------------------------- the distant ground
# A dithered band under the horizon, thinning as it comes forward. In the
# reference this is what fills the gap between the city and the first
# horizontal the machine flies; without it that gap is bare black.
for k in range(BAND):
    y = HORIZON + 1 + k
    d = 1.0 - k/BAND                            # dense at the horizon
    step = 4 if d > 0.80 else (8 if d > 0.55 else (16 if d > 0.25 else 32))
    off = (k*3) % step                          # break up the columns
    for x in range(off, W, step):
        plot(x, y)

# ------------------------------------------------------- the floor's lines
# Dotted, so they read as perspective guides without competing with the
# solid horizontals the ST will be flying over them. Drawn from the bottom
# of the screen up to the city's base only: their vanishing point is APEX
# rows further up, out of sight behind the city.
VPY = HORIZON - APEX
for i in range(NCONV):
    bx = -900 + i*(2*900 + W)/(NCONV-1)         # fan out past both edges
    dx, dy = bx - W/2, (H-1) - VPY
    steps = int(max(abs(dx), abs(dy)))
    for t in range(steps+1):
        if t & 1:
            continue
        y = VPY + dy*t/steps
        if y < HORIZON:                         # cut at the city
            continue
        plot(int(W/2 + dx*t/steps + 0.5), int(y + 0.5))

hline(HORIZON, 0, W-1)                          # the horizon itself, solid

# ------------------------------------------------------------ the row table
rows = bytearray()
for k in range(PHASES):
    # p reaches exactly 0 on the last phase, which puts the nearest line on
    # the bottom row of the screen just before the set wraps -- so the line
    # that pops leaves at the edge, where the pop cannot be seen.
    p = 1.0 - (k+1)/PHASES
    for i in range(1, NLINES+1):
        y = HORIZON + DEPTH/(i + p)
        # H-2, not H-1: the two nearest lines are two rows thick
        rows += struct.pack('>h', min(H-2, int(y)))

# How each line is drawn, by distance. The far ones bunch up a row apart, so
# solid white turns the horizon into a slab that buries the city -- dotted,
# they read as the dithered band the reference actually has. The nearest two
# get a second row, which is what gives the floor its weight underfoot.
style = bytearray()
for i in range(1, NLINES+1):
    if i <= 2:      style += bytes([0xFF, 2])
    elif i <= 4:    style += bytes([0xFF, 1])
    else:           style += bytes([0xAA, 1])

blob = bytes(fb) + bytes(rows) + bytes(style)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, 'wb').write(blob)
print(f"{OUT}: {len(blob)} bytes ({len(fb)} background"
      f" + {len(rows)} row table + {len(style)} style)")
r0 = [struct.unpack('>h', rows[2*i:2*i+2])[0] for i in range(NLINES)]
print(f"  phase 0 rows: {r0}")
print(f"  gaps:         {[r0[i]-r0[i+1] for i in range(NLINES-1)]}")
print(f"  src/shows/grid.s must use NLINES equ {NLINES}, PHASES equ {PHASES}")

# --------------------------------------------------------------- preview
def png(path, pix, w, h):
    raw = b''.join(b'\x00' + bytes(pix[y*w:(y+1)*w]) for y in range(h))
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c))
    open(path, 'wb').write(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 0, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

pix = bytearray(W*H)
for y in range(H):
    for x in range(W):
        pix[y*W+x] = 255 if fb[y*80 + (x >> 3)] >> (7 - (x & 7)) & 1 else 0
# what it will look like with the first phase's lines on it
for i, y in enumerate(r0):
    pat, thick = style[2*i], style[2*i+1]
    for t in range(thick):
        for x in range(W):
            if pat >> (7 - (x & 7)) & 1:
                pix[(y+t)*W+x] = 255
png(PREVIEW, pix, W, H)
print(f"{PREVIEW}: written")
