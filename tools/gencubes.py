#!/usr/bin/env python3
"""Bake rotating wireframe cubes into 1-bit sprites for the ST.

Drawing 8 wireframe cubes with real line code would cost ~90k of the ST's
~112k cycles per frame before you even erase them. Blitting pre-rendered
tiles costs ~50k, so the rotation is computed here and the ST just copies.

Each tile is opaque and covers the cube's whole box, so no erase pass is
needed: one write per frame per cube.

    python3 tools/gencubes.py            # writes src/cubes.bin + preview

Output layout, tightly packed:
    sprite[scale][angle], scale 0..SCALES-1, angle 0..ANGLES-1
    each sprite is H rows of W_BYTES bytes, MSB = leftmost pixel
"""
import math, os, struct, zlib, sys

# Two sizes. The default is eight cubes in a four-by-two grid; "big" is four
# in a two-by-two, so each cell is twice as wide and the tile twice as big in
# both directions -- and the outline goes with it, from a 2x1 brush to a solid
# square of T, which is what "thicker" has to mean on a grid with no grey.
# T costs nothing either way: the tile is the same size and so is the blit.
BIG = len(sys.argv) > 1 and sys.argv[1] == "big"
if BIG:
    W_BYTES, H, OUT, PREVIEW = 24, 160, "src/cubes4.bin", "cubes4_preview.png"
    T = 4                           # outline thickness in pixels
    BRUSH = [(x - T // 2, y - T // 2) for y in range(T) for x in range(T)]
else:
    W_BYTES, H, OUT, PREVIEW = 12, 96, "src/cubes.bin", "cubes_preview.png"
    BRUSH = [(0, 0), (1, 0)]        # 1px vanishes on a CRT
W       = W_BYTES * 8
SCALES  = 8
ANGLES  = 16

VERTS = [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
def vidx(x, y, z): return VERTS.index((x, y, z))
EDGES = []
for i, a in enumerate(VERTS):
    for j, b in enumerate(VERTS):
        if j > i and sum(1 for k in range(3) if a[k] != b[k]) == 1:
            EDGES.append((i, j))
assert len(EDGES) == 12, len(EDGES)

def rotate(v, ax, ay):
    x, y, z = v
    y, z = y * math.cos(ax) - z * math.sin(ax), y * math.sin(ax) + z * math.cos(ax)
    x, z = x * math.cos(ay) + z * math.sin(ay), -x * math.sin(ay) + z * math.cos(ay)
    return x, y, z

def project(v, scale):
    x, y, z = v
    d = 4.0                                   # eye distance, mild perspective
    f = scale * (W * 0.70) / (d - 1.0)
    k = d / (d - z)
    return W / 2 + x * f * k, H / 2 + y * f * k

def plot(buf, x, y):
    if 0 <= x < W and 0 <= y < H:
        buf[y * W_BYTES + (x >> 3)] |= 0x80 >> (x & 7)

def line(buf, x0, y0, x1, y1):
    x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    while True:
        for bx, by in BRUSH:
            plot(buf, x0 + bx, y0 + by)
        if x0 == x1 and y0 == y1: break
        e2 = 2 * err
        if e2 >= dy: err += dy; x0 += sx
        if e2 <= dx: err += dx; y0 += sy

def render(scale_i, angle_i):
    buf = bytearray(W_BYTES * H)
    s  = 0.42 + 0.58 * (scale_i / (SCALES - 1))      # pulse range
    ax = angle_i * 2 * math.pi / ANGLES
    ay = angle_i * 2 * math.pi / ANGLES * 0.618      # incommensurate tumble
    pts = [project(rotate(v, ax, ay), s) for v in VERTS]
    for a, b in EDGES:
        line(buf, pts[a][0], pts[a][1], pts[b][0], pts[b][1])
    return buf

def write_png(path, width, height, rows):
    raw = b''.join(b'\x00' + bytes(r) for r in rows)
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 0, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
    open(path, 'wb').write(png)

sprites = []
extent = 0
for s in range(SCALES):
    for a in range(ANGLES):
        sprites.append(render(s, a))
        ss  = 0.42 + 0.58 * (s / (SCALES - 1))
        for v in VERTS:
            px, py = project(rotate(v, a * 2 * math.pi / ANGLES,
                                       a * 2 * math.pi / ANGLES * 0.618), ss)
            extent = max(extent, abs(px - W / 2), abs(py - H / 2))
print(f"max extent from centre: {extent:.1f} px (box half-size is {W//2}) "
      f"-> {'FITS' if extent < W/2 - 2 else 'CLIPS!'}")

os.makedirs("src", exist_ok=True)
with open(OUT, "wb") as f:
    for sp in sprites:
        f.write(sp)

total = len(sprites) * W_BYTES * H
print(f"{len(sprites)} sprites ({SCALES} scales x {ANGLES} angles)")
print(f"{W}x{H}, {W_BYTES} bytes/row, {W_BYTES*H} bytes/sprite")
print(f"{OUT}: {total} bytes ({total/1024:.0f} KB)")
print(f"asm constants:  CUBE_W_BYTES={W_BYTES}  CUBE_H={H}  "
      f"CUBE_SPRITE={W_BYTES*H}  CUBE_SCALES={SCALES}  CUBE_ANGLES={ANGLES}")

# contact sheet: every scale down the page, a few angles across
cols, rws = 8, SCALES
pw, ph = cols * W, rws * H
rows = [bytearray([0] * pw) for _ in range(ph)]
for s in range(SCALES):
    for c in range(cols):
        sp = sprites[s * ANGLES + (c * ANGLES // cols)]
        for y in range(H):
            for x in range(W):
                bit = (sp[y * W_BYTES + (x >> 3)] >> (7 - (x & 7))) & 1
                rows[s * H + y][c * W + x] = 255 if bit else 0
write_png(PREVIEW, pw, ph, rows)
print(f"{PREVIEW}: {pw}x{ph} contact sheet")
