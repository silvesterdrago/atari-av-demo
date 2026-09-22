#!/usr/bin/env python3
"""Bake eight rotating wireframe solids into 1-bit sprites.

One solid per pad. Same trick as tools/gencubes.py -- the ST cannot draw
wireframes in real time, so the rotation is computed here and the machine
only blits.

Sizing is a real constraint. At the cubes show's 96x96 box, eight solids at
eight scales and twelve angles would be 663 KB, which is uncomfortable in
1 MB alongside ~100 KB of BSS. 64x64 fitted easily but the figures looked
mean, so this is the cubes' 96x96 box with six scales instead of eight:
663 KB, and the pulse loses a little resolution rather than the figures
losing half their size.

    python3 tools/genshapes.py        # writes src/shapes.bin + preview
"""
import math, os, struct, zlib

W_BYTES = 12                # 96 px, same box the cubes used
W       = W_BYTES * 8
H       = 96
SCALES  = 6                 # six, not eight: area is what costs memory
ANGLES  = 12
OUT     = "src/shapes.bin"
PREVIEW = "shapes_preview.png"


def ring(n, y, r, phase=0.0):
    return [(r * math.cos(phase + i * 2 * math.pi / n), y,
             r * math.sin(phase + i * 2 * math.pi / n)) for i in range(n)]


def ring_edges(base, n, closed=True):
    e = [(base + i, base + (i + 1) % n) for i in range(n)]
    return e if closed else e[:-1]


def extrude(poly2d, zt=0.35):
    """a flat outline pushed out along z, front + back + the walls"""
    n = len(poly2d)
    v = [(x, y, -zt) for x, y in poly2d] + [(x, y, zt) for x, y in poly2d]
    e = ring_edges(0, n) + ring_edges(n, n) + [(i, i + n) for i in range(n)]
    return v, e


def star2d(points=5, r_out=1.0, r_in=0.42):
    pts = []
    for i in range(points * 2):
        r = r_out if i % 2 == 0 else r_in
        a = -math.pi / 2 + i * math.pi / points
        pts.append((r * math.cos(a), r * math.sin(a)))
    return pts


def plus2d(arm=1.0, wide=0.34):
    a, w = arm, wide
    return [(-w, -a), (w, -a), (w, -w), (a, -w), (a, w), (w, w),
            (w, a), (-w, a), (-w, w), (-a, w), (-a, -w), (-w, -w)]


def cube():
    v = [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    e = [(i, j) for i in range(8) for j in range(8)
         if j > i and sum(1 for k in range(3) if v[i][k] != v[j][k]) == 1]
    return v, e


def octahedron():
    v = [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]
    e = [(a,b) for a in range(6) for b in range(6)
         if b > a and not (a//2 == b//2)]
    return v, e


def tetrahedron():
    v = [(1,1,1),(1,-1,-1),(-1,1,-1),(-1,-1,1)]
    e = [(0,1),(0,2),(0,3),(1,2),(1,3),(2,3)]
    return v, e


def pyramid():
    v = [(-1,0.7,-1),(1,0.7,-1),(1,0.7,1),(-1,0.7,1),(0,-1,0)]
    e = ring_edges(0, 4) + [(i, 4) for i in range(4)]
    return v, e


def gem():
    """a cut stone: flat table on top, girdle, point below"""
    table  = ring(8, -0.75, 0.50)
    girdle = ring(8, -0.15, 1.00)
    apex   = [(0.0, 1.05, 0.0)]
    v = table + girdle + apex
    e = ring_edges(0, 8) + ring_edges(8, 8)
    e += [(i, 8 + i) for i in range(8)]
    e += [(8 + i, 16) for i in range(8)]
    return v, e


def hexprism():
    top = ring(6, -0.8, 1.0)
    bot = ring(6, 0.8, 1.0)
    v = top + bot
    e = ring_edges(0, 6) + ring_edges(6, 6) + [(i, 6 + i) for i in range(6)]
    return v, e


def star_solid():
    return extrude(star2d(), 0.48)


def plus_solid():
    return extrude(plus2d(), 0.52)


SHAPES = [("cube", cube), ("diamond", gem), ("octahedron", octahedron),
          ("plus", plus_solid), ("tetra", tetrahedron), ("star", star_solid),
          ("hexprism", hexprism), ("pyramid", pyramid)]


def rotate(v, ax, ay):
    x, y, z = v
    y, z = y*math.cos(ax) - z*math.sin(ax), y*math.sin(ax) + z*math.cos(ax)
    x, z = x*math.cos(ay) + z*math.sin(ay), -x*math.sin(ay) + z*math.cos(ay)
    return x, y, z


def project(v, scale):
    x, y, z = v
    d = 4.0
    f = scale * (W * 0.70) / (d - 1.0)
    k = d / (d - z)
    return W/2 + x*f*k, H/2 + y*f*k


def plot(buf, x, y):
    if 0 <= x < W and 0 <= y < H:
        buf[y*W_BYTES + (x >> 3)] |= 0x80 >> (x & 7)


def line(buf, x0, y0, x1, y1):
    x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
    dx, dy = abs(x1-x0), -abs(y1-y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    while True:
        plot(buf, x0, y0)
        plot(buf, x0+1, y0)          # 2px wide, or it vanishes on a CRT
        if x0 == x1 and y0 == y1: break
        e2 = 2*err
        if e2 >= dy: err += dy; x0 += sx
        if e2 <= dx: err += dx; y0 += sy


def render(verts, edges, si, ai):
    buf = bytearray(W_BYTES * H)
    s  = 0.72 + 0.28 * (si / (SCALES - 1))   # never small: at rest a figure
                                            # should still read from the back
                                            # of a room
    ax = ai * 2*math.pi / ANGLES
    ay = ai * 2*math.pi / ANGLES * 0.618
    pts = [project(rotate(v, ax, ay), s) for v in verts]
    for a, b in edges:
        line(buf, pts[a][0], pts[a][1], pts[b][0], pts[b][1])
    return buf, max(max(abs(p[0]-W/2), abs(p[1]-H/2)) for p in pts)


sprites, worst = [], 0.0
for name, fn in SHAPES:
    verts, edges = fn()
    for si in range(SCALES):
        for ai in range(ANGLES):
            buf, ext = render(verts, edges, si, ai)
            sprites.append(buf)
            worst = max(worst, ext)

os.makedirs("src", exist_ok=True)
with open(OUT, "wb") as f:
    for sp in sprites:
        f.write(sp)

total = len(sprites) * W_BYTES * H
print(f"{len(SHAPES)} shapes x {SCALES} scales x {ANGLES} angles = {len(sprites)} sprites")
print(f"{W}x{H}, {W_BYTES} bytes/row, {W_BYTES*H} bytes/sprite")
print(f"max extent {worst:.1f} px of {W//2} half-box -> "
      f"{'FITS' if worst < W/2 - 2 else 'CLIPS!'}")
print(f"{OUT}: {total} bytes ({total/1024:.0f} KB)")
print(f"asm: SH_W_BYTES={W_BYTES} SH_H={H} SH_SPRITE={W_BYTES*H} "
      f"SH_SCALES={SCALES} SH_ANGLES={ANGLES} SH_COUNT={len(SHAPES)}")


def write_png(path, width, height, rows):
    raw = b''.join(b'\x00' + bytes(r) for r in rows)
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    open(path, 'wb').write(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 0, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


# contact sheet: one shape per row, a spread of angles across, mid scale
cols = 8
pw, ph = cols * W, len(SHAPES) * H
rows = [bytearray([0]*pw) for _ in range(ph)]
for r, (name, _) in enumerate(SHAPES):
    for c in range(cols):
        ai = c * ANGLES // cols
        sp = sprites[(r * SCALES + SCALES - 1) * ANGLES + ai]
        for y in range(H):
            for x in range(W):
                bit = (sp[y*W_BYTES + (x >> 3)] >> (7 - (x & 7))) & 1
                rows[r*H + y][c*W + x] = 255 if bit else 0
write_png(PREVIEW, pw, ph, rows)
print(f"{PREVIEW}: {pw}x{ph}, one shape per row")
