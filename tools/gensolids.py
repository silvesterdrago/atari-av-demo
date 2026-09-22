#!/usr/bin/env python3
"""Bake eight solids as filled, dither-shaded triangles.

Outlines were the wrong primitive: about 50 cycles a pixel, and a dense
wireframe reads as a heap of pixels. A filled span is about one cycle a
pixel, because a word write covers sixteen -- so the solids are filled with
ordered dither instead, which is both far cheaper and has a silhouette.

Everything the ST cannot afford is done here: rotation, projection, backface
culling, and the lighting level per face. All the machine does is fill spans.

    python3 tools/gensolids.py      # writes src/solids.bin + preview

File layout:
    0..31   dither table, 8 levels x 4 rows, one byte each (8x4 cell)
    32..    poses, a flat array with a fixed stride:
            ((shape*SCALES + scale)*ANGLES + angle) * STRIDE
            each pose: nverts.b, ntris.b,
                       verts[nverts] x { x.b, y.b } signed, cell-relative,
                       tris[ntris]  x { i0.b, i1.b, i2.b, level.b }
"""
import math, os, struct, zlib

SCALES, ANGLES = 8, 24
STRIDE  = 96
EXTENT  = 70
LEVELS  = 8
LIGHT   = (-0.45, -0.72, 0.53)
OUT     = "src/solids.bin"
PREVIEW = "solids_preview.png"

# Eight fills, ordered roughly by density but chosen to be visually
# DISTINCT rather than evenly spaced. In one bit two neighbouring densities
# look the same, so two faces meeting at an edge merge into one blob --
# which is exactly what the first version did. Stripes against checks
# against dots separate instantly, with no outline needed.
PATTERNS = [
    (0x80, 0x00, 0x08, 0x00),   # 0  sparse dots, almost black
    (0x88, 0x22, 0x88, 0x22),   # 1  quarter dots
    (0xAA, 0xAA, 0xAA, 0xAA),   # 2  vertical hairlines
    (0xAA, 0x55, 0xAA, 0x55),   # 3  fine check
    (0xFF, 0x00, 0xFF, 0x00),   # 4  horizontal hairlines
    (0xCC, 0x66, 0x33, 0x99),   # 5  diagonal
    (0xEE, 0xBB, 0xEE, 0xBB),   # 6  three quarters
    (0xFF, 0xFF, 0xFF, 0xFF),   # 7  solid
]


def dither_table():
    tbl = []
    for p in PATTERNS:
        tbl += list(p)
    return bytes(tbl)


def ring(n, y, r, phase=0.0):
    return [(r*math.cos(phase+i*2*math.pi/n), y, r*math.sin(phase+i*2*math.pi/n))
            for i in range(n)]

def cube():
    v = [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),
         (-1,-1, 1),(1,-1, 1),(1,1, 1),(-1,1, 1)]
    f = [[0,1,2,3],[4,5,6,7],[0,1,5,4],[3,2,6,7],[0,3,7,4],[1,2,6,5]]
    return v, f

def slab():
    v = [(-1,-0.42,-1),(1,-0.42,-1),(1,0.42,-1),(-1,0.42,-1),
         (-1,-0.42, 1),(1,-0.42, 1),(1,0.42, 1),(-1,0.42, 1)]
    f = [[0,1,2,3],[4,5,6,7],[0,1,5,4],[3,2,6,7],[0,3,7,4],[1,2,6,5]]
    return v, f

def octahedron():
    v = [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]
    f = [[0,2,4],[0,4,3],[0,3,5],[0,5,2],[1,4,2],[1,3,4],[1,5,3],[1,2,5]]
    return v, f

def tetrahedron():
    v = [(1,1,1),(1,-1,-1),(-1,1,-1),(-1,-1,1)]
    return v, [[0,1,2],[0,2,3],[0,3,1],[1,3,2]]

def pyramid():
    v = [(-1,0.7,-1),(1,0.7,-1),(1,0.7,1),(-1,0.7,1),(0,-1.1,0)]
    return v, [[0,1,2,3],[0,1,4],[1,2,4],[2,3,4],[3,0,4]]

def hexprism():
    v = ring(6,-0.8,1.0) + ring(6,0.8,1.0)
    f = [[0,1,2,3,4,5],[6,7,8,9,10,11]]
    f += [[i,(i+1)%6,6+(i+1)%6,6+i] for i in range(6)]
    return v, f

def diamond():
    """hexagonal bipyramid -- a crystal"""
    v = ring(6,0.0,1.0) + [(0,-1.25,0),(0,1.05,0)]
    f = [[i,(i+1)%6,6] for i in range(6)] + [[i,(i+1)%6,7] for i in range(6)]
    return v, f

def triprism():
    v = ring(3,-0.85,1.05) + ring(3,0.85,1.05)
    f = [[0,1,2],[3,4,5]] + [[i,(i+1)%3,3+(i+1)%3,3+i] for i in range(3)]
    return v, f

SHAPES = [("cube",cube),("diamond",diamond),("octahedron",octahedron),
          ("pyramid",pyramid),("tetra",tetrahedron),("hexprism",hexprism),
          ("triprism",triprism),("slab",slab)]


def norm(a):
    l = math.sqrt(sum(c*c for c in a)) or 1.0
    return tuple(c/l for c in a)

def sub(a,b): return (a[0]-b[0], a[1]-b[1], a[2]-b[2])
def cross(a,b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def dot(a,b): return sum(x*y for x,y in zip(a,b))


def fix_winding(verts, faces):
    """convex solids sit around the origin, so an outward normal points away
    from the centroid -- flip any face that does not"""
    out = []
    for f in faces:
        n = cross(sub(verts[f[1]], verts[f[0]]), sub(verts[f[2]], verts[f[0]]))
        c = [sum(verts[i][k] for i in f)/len(f) for k in range(3)]
        out.append(list(reversed(f)) if dot(n, c) < 0 else list(f))
    return out


def rotate(v, ax, ay):
    x,y,z = v
    y,z = y*math.cos(ax)-z*math.sin(ax), y*math.sin(ax)+z*math.cos(ax)
    x,z = x*math.cos(ay)+z*math.sin(ay), -x*math.sin(ay)+z*math.cos(ay)
    return x,y,z


def project(v, f):
    x,y,z = v
    d = 4.0
    k = d/(d-z)
    return x*f*k, y*f*k


def build_pose(verts, faces, si, ai, pf):
    s  = 0.74 + 0.26*(si/(SCALES-1))
    ax = ai*2*math.pi/ANGLES
    ay = ai*2*math.pi/ANGLES*0.618
    rv = [rotate([c*s for c in v], ax, ay) for v in verts]
    pv = [project(v, pf) for v in rv]
    # Which faces are visible, and how lit each one is
    vis = []
    for f in faces:
        n = norm(cross(sub(rv[f[1]], rv[f[0]]), sub(rv[f[2]], rv[f[0]])))
        if n[2] <= 0.02:                       # facing away, or edge-on
            continue
        vis.append((0.5 + 0.5*dot(n, LIGHT), f))

    # Assign the fills by RANK, not by absolute brightness. Mapping
    # brightness straight onto levels let two faces meeting at an edge land
    # on the same fill, and then they merge into one blob with no edge --
    # which is what the first two attempts looked like. Ranking guarantees
    # they differ, and since the order still comes from the light direction
    # it still reads as lighting.
    vis.sort(key=lambda t: -t[0])
    faces_out = []
    n = len(vis)
    for i, (lit, f) in enumerate(vis):
        if n == 1:
            lvl = LEVELS - 1
        else:
            lvl = LEVELS - 1 - round(i * (LEVELS - 1) / (n - 1))
        # Cut the face into a left and a right chain of edges, top to bottom.
        # Doing it here means the ST never searches for the topmost vertex,
        # never wraps around the polygon and never works out a direction: it
        # walks two lists. And filling a quad as a quad rather than as two
        # triangles halves the scanlines, which is the whole point -- a row
        # costs ~180 cycles of overhead against ~40 of filling.
        m = len(f)
        ys = [pv[j][1] for j in f]
        imin = ys.index(min(ys))
        imax = ys.index(max(ys))
        a, b, k = [], [], imin
        while True:
            a.append(f[k])
            if k == imax: break
            k = (k + 1) % m
        k = imin
        while True:
            b.append(f[k])
            if k == imax: break
            k = (k - 1) % m
        faces_out.append((lvl, a, b))
    return pv, faces_out


# calibrate the projection so the biggest pose just reaches EXTENT
worst = 0.0
for name, fn in SHAPES:
    v, f = fn(); f = fix_winding(v, f)
    for si in (SCALES-1,):
        for ai in range(ANGLES):
            pv, _ = build_pose(v, f, si, ai, 1.0)
            for x, y in pv:
                worst = max(worst, abs(x), abs(y))
PF = EXTENT/worst
print(f"projection factor {PF:.2f} -> max extent {EXTENT} px")

blob = bytearray(dither_table())
assert len(blob) == 32
maxblob, maxtris = 0, 0
for name, fn in SHAPES:
    v, f = fn(); f = fix_winding(v, f)
    for si in range(SCALES):
        for ai in range(ANGLES):
            pv, faces_out = build_pose(v, f, si, ai, PF)
            b = bytearray()
            b += struct.pack('BB', len(pv), len(faces_out))
            for x, y in pv:
                b += struct.pack('bb', max(-128,min(127,round(x))),
                                       max(-128,min(127,round(y))))
            for lvl, ca, cb in faces_out:
                b += struct.pack('BBB', lvl, len(ca), len(cb))
                b += bytes(ca) + bytes(cb)
            maxblob = max(maxblob, len(b))
            maxtris = max(maxtris, len(faces_out))
            assert len(b) <= STRIDE, (name, len(b))
            blob += b + bytes(STRIDE-len(b))

os.makedirs("src", exist_ok=True)
open(OUT,'wb').write(blob)
for name, fn in SHAPES:
    v, f = fn()
    print(f"  {name:11s} {len(v):2d} verts {len(f):2d} faces")
print(f"largest pose {maxblob} bytes of {STRIDE}, up to {maxtris} visible faces")
print(f"{OUT}: {len(blob)} bytes ({len(blob)/1024:.0f} KB)")
print(f"asm: SOL_SCALES={SCALES} SOL_ANGLES={ANGLES} SOL_STRIDE={STRIDE} "
      f"SOL_POSES_OFF=32 SOL_LEVELS={LEVELS}")


# ---- preview: fill the triangles the same way the ST will ----
def write_png(path, w, h, rows):
    raw = b''.join(b'\x00'+bytes(r) for r in rows)
    def chunk(t,d):
        c=t+d
        return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c)&0xffffffff)
    open(path,'wb').write(b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB',w,h,8,0,0,0,0))
        + chunk(b'IDAT', zlib.compress(raw,9)) + chunk(b'IEND',b''))

CW, CH, cols = 160, 200, 4
pw, ph = CW*cols, CH*2
rows = [bytearray([0]*pw) for _ in range(ph)]
DT = dither_table()

def fill_poly(pv, ca, cb, lvl, cx, cy):
    def chain_x(ch, y):
        for i in range(len(ch)-1):
            y0, y1 = pv[ch[i]][1], pv[ch[i+1]][1]
            if y0 <= y <= y1 and y1 != y0:
                x0, x1 = pv[ch[i]][0], pv[ch[i+1]][0]
                return x0 + (x1-x0)*(y-y0)/(y1-y0)
        return pv[ch[-1]][0]
    y0 = min(pv[j][1] for j in ca)
    y1 = max(pv[j][1] for j in ca)
    for y in range(int(round(y0)), int(round(y1))+1):
        xa, xb = chain_x(ca, y), chain_x(cb, y)
        if xa > xb: xa, xb = xb, xa
        sy = int(cy+y)
        if not (0 <= sy < ph): continue
        pat = DT[lvl*4 + (sy & 3)]
        for x in range(int(round(cx+xa)), int(round(cx+xb))+1):
            if 0 <= x < pw and (pat >> (7-(x & 7))) & 1:
                rows[sy][x] = 255

for i,(name,fn) in enumerate(SHAPES):
    v,f = fn(); f = fix_winding(v,f)
    pv, faces_out = build_pose(v, f, SCALES-1, 4, PF)
    cx = (i % cols)*CW + CW//2
    cy = (i//cols)*CH + CH//2
    for lvl, ca, cb in faces_out:
        fill_poly(pv, ca, cb, lvl, cx, cy)
write_png(PREVIEW, pw, ph, rows)
print(f"{PREVIEW}: {pw}x{ph}")
