#!/usr/bin/env python3
"""Bake the eight solids as projected VERTEX tables instead of bitmaps.

Bitmaps cost area, which is why the baked sprites topped out at a 96x96 box.
Vertices cost nothing by comparison -- eight solids at eight scales and
thirty-two angles is about 50 KB -- so the figures can fill their cell. The
price is that the ST has to draw the lines itself, which is why the show
redraws a cell only when its pose has actually changed.

    python3 tools/genvectors.py      # writes src/vectors.bin + preview

File layout, all big-endian:
    dir:  8 entries x { nverts.w, nedges.w, stride.w, pad.w,
                        edges_off.l, poses_off.l }
    edges: per shape, nedges x { from.b, to.b }
    poses: per shape, scale-major then angle, nverts x { x.b, y.b }
           signed, relative to the cell centre
"""
import math, os, struct, zlib

SCALES  = 8
ANGLES  = 32
EXTENT  = 72                # px from centre; cells are 160 x 200
OUT     = "src/vectors.bin"
PREVIEW = "vectors_preview.png"


def ring(n, y, r, phase=0.0):
    return [(r*math.cos(phase + i*2*math.pi/n), y,
             r*math.sin(phase + i*2*math.pi/n)) for i in range(n)]


def ring_edges(base, n):
    return [(base+i, base+(i+1) % n) for i in range(n)]


def extrude(poly2d, zt):
    n = len(poly2d)
    v = [(x, y, -zt) for x, y in poly2d] + [(x, y, zt) for x, y in poly2d]
    return v, ring_edges(0, n) + ring_edges(n, n) + [(i, i+n) for i in range(n)]


def star2d(points=5, r_out=1.0, r_in=0.42):
    pts = []
    for i in range(points*2):
        r = r_out if i % 2 == 0 else r_in
        a = -math.pi/2 + i*math.pi/points
        pts.append((r*math.cos(a), r*math.sin(a)))
    return pts


def plus2d(arm=1.0, w=0.34):
    a = arm
    return [(-w,-a),(w,-a),(w,-w),(a,-w),(a,w),(w,w),
            (w,a),(-w,a),(-w,w),(-a,w),(-a,-w),(-w,-w)]


def cube():
    v = [(x,y,z) for x in (-1,1) for y in (-1,1) for z in (-1,1)]
    e = [(i,j) for i in range(8) for j in range(8)
         if j > i and sum(1 for k in range(3) if v[i][k] != v[j][k]) == 1]
    return v, e

def octahedron():
    v = [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]
    return v, [(a,b) for a in range(6) for b in range(6)
               if b > a and a//2 != b//2]

def tetrahedron():
    return [(1,1,1),(1,-1,-1),(-1,1,-1),(-1,-1,1)], \
           [(0,1),(0,2),(0,3),(1,2),(1,3),(2,3)]

def pyramid():
    v = [(-1,0.7,-1),(1,0.7,-1),(1,0.7,1),(-1,0.7,1),(0,-1,0)]
    return v, ring_edges(0,4) + [(i,4) for i in range(4)]

def gem():
    v = ring(8,-0.75,0.50) + ring(8,-0.15,1.00) + [(0.0,1.05,0.0)]
    e = ring_edges(0,8) + ring_edges(8,8)
    e += [(i,8+i) for i in range(8)] + [(8+i,16) for i in range(8)]
    return v, e

def hexprism():
    v = ring(6,-0.8,1.0) + ring(6,0.8,1.0)
    return v, ring_edges(0,6) + ring_edges(6,6) + [(i,6+i) for i in range(6)]

def star_solid(): return extrude(star2d(), 0.48)
def plus_solid(): return extrude(plus2d(), 0.52)

SHAPES = [("cube", cube), ("diamond", gem), ("octahedron", octahedron),
          ("plus", plus_solid), ("tetra", tetrahedron), ("star", star_solid),
          ("hexprism", hexprism), ("pyramid", pyramid)]


def rotate(v, ax, ay):
    x, y, z = v
    y, z = y*math.cos(ax)-z*math.sin(ax), y*math.sin(ax)+z*math.cos(ax)
    x, z = x*math.cos(ay)+z*math.sin(ay), -x*math.sin(ay)+z*math.cos(ay)
    return x, y, z


# one projection factor for everything, chosen so the largest pose of the
# largest shape just reaches EXTENT
def project(v, scale, f):
    x, y, z = v
    d = 4.0
    k = d/(d-z)
    return x*f*scale*k, y*f*scale*k


def pose_of(verts, si, ai, f):
    s  = 0.72 + 0.28*(si/(SCALES-1))
    ax = ai*2*math.pi/ANGLES
    ay = ai*2*math.pi/ANGLES*0.618
    return [project(rotate(v, ax, ay), s, f) for v in verts]


# calibrate f
f = 1.0
worst = 0.0
for name, fn in SHAPES:
    verts, _ = fn()
    for si in range(SCALES):
        for ai in range(ANGLES):
            for x, y in pose_of(verts, si, ai, 1.0):
                worst = max(worst, abs(x), abs(y))
f = EXTENT/worst
print(f"projection factor {f:.2f} -> max extent {EXTENT} px")

dir_entries, edge_blobs, pose_blobs = [], [], []
for name, fn in SHAPES:
    verts, edges = fn()
    eb = b''.join(struct.pack('BB', a, b) for a, b in edges)
    pb = bytearray()
    for si in range(SCALES):
        for ai in range(ANGLES):
            for x, y in pose_of(verts, si, ai, f):
                pb += struct.pack('bb', max(-128, min(127, round(x))),
                                        max(-128, min(127, round(y))))
    dir_entries.append((len(verts), len(edges), len(verts)*2, name))
    edge_blobs.append(eb)
    pose_blobs.append(bytes(pb))

DIR = 16*len(SHAPES)
off = DIR
edge_off, pose_off = [], []
for eb in edge_blobs:
    edge_off.append(off); off += len(eb)
for pb in pose_blobs:
    pose_off.append(off); off += len(pb)

out = bytearray()
for i, (nv, ne, st, name) in enumerate(dir_entries):
    out += struct.pack('>HHHHII', nv, ne, st, 0, edge_off[i], pose_off[i])
for eb in edge_blobs: out += eb
for pb in pose_blobs: out += pb

os.makedirs("src", exist_ok=True)
open(OUT, 'wb').write(out)
for i, (nv, ne, st, name) in enumerate(dir_entries):
    print(f"  {name:11s} {nv:2d} verts {ne:2d} edges")
print(f"{len(SHAPES)} shapes x {SCALES} scales x {ANGLES} angles")
print(f"{OUT}: {len(out)} bytes ({len(out)/1024:.0f} KB)")
print(f"asm: VEC_SCALES={SCALES} VEC_ANGLES={ANGLES} VEC_DIR_SIZE=16")


# preview: draw the largest pose of each shape with python, as a check
def write_png(path, w, h, rows):
    raw = b''.join(b'\x00'+bytes(r) for r in rows)
    def chunk(t, d):
        c = t+d
        return struct.pack('>I', len(d))+c+struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    open(path,'wb').write(b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8,0,0,0,0))
        + chunk(b'IDAT', zlib.compress(raw,9)) + chunk(b'IEND', b''))

CW, CH, cols = 160, 200, 4
pw, ph = CW*cols, CH*2
rows = [bytearray([0]*pw) for _ in range(ph)]
def pline(x0,y0,x1,y1):
    x0,y0,x1,y1 = int(round(x0)),int(round(y0)),int(round(x1)),int(round(y1))
    dx,dy = abs(x1-x0), -abs(y1-y0)
    sx = 1 if x0<x1 else -1
    sy = 1 if y0<y1 else -1
    err = dx+dy
    while True:
        if 0<=x0<pw and 0<=y0<ph: rows[y0][x0]=255
        if x0==x1 and y0==y1: break
        e2=2*err
        if e2>=dy: err+=dy; x0+=sx
        if e2<=dx: err+=dx; y0+=sy
for i,(name,fn) in enumerate(SHAPES):
    verts,edges = fn()
    p = pose_of(verts, SCALES-1, 3, f)
    cx = (i % cols)*CW + CW//2
    cy = (i//cols)*CH + CH//2
    for a,b in edges:
        pline(cx+p[a][0], cy+p[a][1], cx+p[b][0], cy+p[b][1])
write_png(PREVIEW, pw, ph, rows)
print(f"{PREVIEW}: {pw}x{ph}, figures at cell scale")
