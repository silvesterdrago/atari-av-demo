#!/usr/bin/env python3
"""Bake the act's still compositions into one file, a screen apiece.

    python3 tools/genstills.py      # src/stills.bin + stills_preview.png

Most of act V is a single picture, not a loop, and a flipbook is the wrong
carrier for that: 24 screens of a still is 768 KB to say what 32 KB says. So
the stills live together in one file and the ST reads the ONE screen it wants
-- 32000 bytes, about 85 ms off the card, against two seconds for a loop.

The file is N screens of 32000 bytes, ST mono: 80 bytes a row, MSB leftmost,
a set bit is ink. The index of each is what src/arc.s's position table points
at, and the table printed at the end is what has to agree with it.

Six of these are in their system.py, the rest are from build56.py and
extra.py, which are not importable at our size -- they bind W, H and the
camera at import. They are short, so they are reimplemented here against the
patched module instead, which also means our corridor and floor corrections
apply to them.
"""
import math
import random
import sys
from PIL import Image, ImageChops, ImageDraw
from sysload import H, W, pack, sysmod

s = sysmod(H, mitre=True)
CX, CY = W // 2, H // 2
new, bar, R = s.new, s.bar, s.R


def tilt_square():
    """27: the nested squares turned and pushed out past the frame."""
    return s._zoom_rotate(s.concentric(n=4, t=22, k=0.66), 32, 1.35)


def double_perspective_b():
    """29: their frames_corridor -- two vanishing systems over each other."""
    return ImageChops.logical_or(s.corridor(light=True),
                                 s.tunnel(n=4, ratio=1.6, t=14, light=False))


def planes_from_side():
    """32: planes entering from the left and closing off-centre."""
    im, d = new()
    P = (W * 0.6, CY)
    s.wedge(d, (0, CY), P, 150, 2)
    s.wedge(d, (0, 0), P, 46, 2)
    s.wedge(d, (0, H), P, 46, 2)
    s.wedge(d, (W, 0), P, 16, 2)
    s.wedge(d, (W, H), P, 16, 2)
    return im


def hex_tunnel(n=6, k=0.68, t=16):
    """36: hexagonal frames receding to the centre."""
    im, d = new()

    def hexa(sc):
        return [(CX + math.cos(math.radians(a)) * W * 0.62 * sc,
                 CY + math.sin(math.radians(a)) * H * 0.62 * sc)
                for a in (180, 240, 300, 0, 60, 120)]

    outer, inner = hexa(1.0), hexa(k ** (n - 1))
    for p, q in zip(outer, inner):
        s.thick_line(d, p, q, 8)
    for i in range(n):
        pts = hexa(k ** i)
        s.poly_line(d, pts + pts[:2], max(5, t * k ** (i * 0.6)))
    return im


def swirl(arms=10, twist=3.2):
    """37: the one deliberate curve in the whole set."""
    im = Image.new("1", (W, H), 0)
    px = im.load()
    for y in range(H):
        for x in range(W):
            dx, dy = (x - CX) / H, (y - CY) / H
            r = math.hypot(dx, dy) + 1e-6
            a = math.atan2(dy, dx)
            v = (a * arms / (2 * math.pi) + twist * math.log(r)) % 1.0
            if v < 0.5 and r > 0.11:
                px[x, y] = 1
    return im


def layered():
    """38: the corridor with one wall cut away and a flat grid behind it."""
    im = s.corridor(panels=True)
    g = s.grid(10, 6, 9)
    m = Image.new("1", (W, H), 0)
    pts = [s.cz(-1, -1, 1), s.cz(-1, -1, 6), s.cz(-1, 1, 6), s.cz(-1, 1, 1)]
    ImageDraw.Draw(m).polygon([(R(x), R(y)) for x, y in pts], fill=1)
    out = im.copy()
    out.paste(Image.new("1", (W, H), 0), (0, 0), m)
    out.paste(g, (0, 0), m)
    d = ImageDraw.Draw(out)
    s.thick_line(d, s.cz(-1, -1, 1), s.cz(-1, -1, 6), 12)
    s.thick_line(d, s.cz(-1, 1, 1), s.cz(-1, 1, 6), 12)
    return out


def complex_structures():
    """39: the corridor with its floor ruled as well."""
    im = s.corridor()
    d = ImageDraw.Draw(im)
    for xf in (-0.6, -0.2, 0.2, 0.6):
        s.thick_line(d, s.cz(xf, 1, 1), s.cz(xf, 1, 6), 7)
    return im


def sunburst(n=16):
    """41: wedges from the centre to the edge, which a span that walks rows
    cannot draw live -- the ones off the sides are horizontal."""
    im, d = new()
    L = W
    for i in range(n):
        a0 = 2 * math.pi * i / n
        a1 = a0 + math.pi / n
        d.polygon([(CX, CY),
                   (R(CX + L * math.cos(a0)), R(CY + L * math.sin(a0))),
                   (R(CX + L * math.cos(a1)), R(CY + L * math.sin(a1)))], fill=1)
    return im


def grid_walls():
    """24: a corridor whose walls and ceiling are grids too."""
    im, d = new()
    zs = [1.42 ** k for k in range(6)]          # geometric, as everywhere else
    for sx in (-1, 1):
        for yf in (-1, -0.33, 0.33, 1):
            s.poly_line(d, [s.cz(sx, yf, z) for z in (1, 6)], 8)
        for z in zs:
            s.thick_line(d, s.cz(sx, -1, z), s.cz(sx, 1, z), max(4, 14 / z))
    for xf in (-1, -0.33, 0.33, 1):
        s.thick_line(d, s.cz(xf, -1, 1), s.cz(xf, -1, 6), 8)
    for z in zs:
        s.thick_line(d, s.cz(-1, -1, z), s.cz(1, -1, z), max(4, 14 / z))
        s.thick_line(d, s.cz(-1, 1, z), s.cz(1, 1, z), max(4, 14 / z))
    ew, eh = W / 6, H / 6
    bar(d, CX - ew / 2, CY - eh / 2, CX + ew / 2, CY + eh / 2)
    return im


def lens_grid(k=0.55):
    """45: a flat grid read through a lens -- the error is the optics, not the
    geometry, so the ruling itself has to stay regular and only the sampling
    bend. One over 1 + k*r^2 keeps the centre still and stretches the edges."""
    src = s.grid(14, 9, 7)
    sp = src.load()
    im = Image.new("1", (W, H), 0)
    px = im.load()
    for y in range(H):
        for x in range(W):
            dx, dy = (x - CX) / CX, (y - CY) / CY
            f = 1.0 + k * (dx * dx + dy * dy)
            sx, sy = int(CX + dx * CX / f), int(CY + dy * CY / f)
            if 0 <= sx < W and 0 <= sy < H and sp[sx, sy]:
                px[x, y] = 1
    return im


def cracked_room(jag=26, push=22):
    """53: the room split down a jagged fault, the far half pushed off register."""
    base = s.room_corner()
    rnd = random.Random(53)                 # one fixed crack, not a new one a run
    pts = [(CX + rnd.randint(-jag, jag), y) for y in range(0, H + 41, 40)]
    m = Image.new("1", (W, H), 0)
    ImageDraw.Draw(m).polygon([(0, 0)] + pts + [(0, H)], fill=1)
    out = Image.new("1", (W, H), 0)
    out.paste(base, (0, 0), m)
    far = ImageChops.invert(m.convert("L")).convert("1")
    out.paste(base.transform((W, H), Image.AFFINE, (1, 0, -push, 0, 1, -9)), (0, 0), far)
    d = ImageDraw.Draw(out)
    for a, b in zip(pts, pts[1:]):
        s.thick_line(d, a, b, 5)
    return out


def shear_break(n=11, amp=34):
    """47: the corridor cut into vertical slices, each knocked off register.
    Live this is the shear that was priced and put off; baked it is a crop and
    a paste, because nothing has to hold the slices apart in real time."""
    base = s.corridor()
    rnd = random.Random(47)
    out = Image.new("1", (W, H), 0)
    w = W // n
    for i in range(n):
        x0 = i * w
        x1 = W if i == n - 1 else x0 + w
        out.paste(base.crop((x0, 0, x1, H)), (x0, rnd.randint(-amp, amp)))
    return out


def collapse_fan(n=20, vx=0.62, vy=0.44, duty=0.55):
    """54: twenty wedges from the frame to one point, and the point is off
    centre -- that displacement is the whole difference from 41, which is the
    same fan drawn from the middle."""
    im, d = new()
    ax, ay = W * vx, H * vy

    def perim(u):
        """u in [0, 1) around the frame from the top-left corner."""
        t = u * 2 * (W + H)
        if t < W:
            return (t, 0)
        t -= W
        if t < H:
            return (W, t)
        t -= H
        if t < W:
            return (W - t, H)
        return (0, H - (t - W - H))

    for i in range(n):
        d.polygon([perim(i / n), perim(i / n + duty / n), (ax, ay)], fill=1)
    return im


# position in their sequence -> how to draw it. The ORDER here is the order in
# the file, and src/arc.s indexes it by that order.
STILLS = [
    (27, "tilt-square", tilt_square),
    (28, "double-perspective-A", s.double_perspective),
    (29, "double-perspective-B", double_perspective_b),
    (30, "corridor-in-corridor", s.nested_inverted),
    (31, "crossing-planes", s.crossing_planes),
    (32, "planes-from-side", planes_from_side),
    (33, "bend-A", lambda: s.floor(dip=-0.75, horizon=False)),
    (34, "bend-B", lambda: s.floor(dip=2.2)),
    (35, "spiral", s.spiral),
    (36, "hex-tunnel", hex_tunnel),
    (37, "swirl", swirl),
    (38, "layered", layered),
    (39, "complex-structures", complex_structures),
    (41, "sunburst", sunburst),
    # act IV: the two that have no phase to ride, so a still is the honest
    # carrier for them rather than a loop of one picture
    (20, "room", s.room_corner),
    (24, "multiple-spaces-A", grid_walls),
    # act VI: the act is CUT and jerky, so a still is what it asks for -- the
    # break comes from the effects over it, not from baked motion
    (42, "tilt", s.tilt),
    (45, "grid-distortion", lens_grid),
    (48, "fault-grid", s.fault_grid),
    (51, "unstable-A", s.unparallel),
    (53, "cracked-room", cracked_room),
    (54, "collapsing-perspective", collapse_fan),
    (57, "tilt-collapse", s.twisted_squares),
    # act II's one hole: a fan of rays cannot be morphed live, because a row
    # span draws a near-horizontal ray only as a stack of its own slots and
    # twelve rays do not fit in twenty
    (12, "radial", s.radial_bowtie),
    # the vanishing point at the far end of DRIFT's sweep, standing still: as
    # a phase of a loop it is not addressable, as a screen it is
    (46, "perspective-shift", lambda: s.axis_loss(dx=170, dy=-60)),
    (47, "break", shear_break),
]

shots = []
for pos, name, fn in STILLS:
    try:
        im = fn()
    except Exception as e:                      # one bad draw must not cost the rest
        sys.exit(f"позиция {pos} ({name}): {type(e).__name__}: {e}")
    assert im.size == (W, H), (pos, im.size)
    shots.append((pos, name, im))

out = "src/stills.bin"
open(out, "wb").write(b"".join(pack(im) for _, _, im in shots))
print(f"{out}: {len(shots) * 32000} bytes, {len(shots)} screens")
print(f"{'idx':>3} {'поз':>4}  что")
for i, (pos, name, _) in enumerate(shots):
    print(f"{i:3} {pos:4}  {name}")

cols = 4
rows = (len(shots) + cols - 1) // cols
sheet = Image.new("L", (W // 2 * cols, H // 2 * rows), 0)
for i, (_, _, im) in enumerate(shots):
    sheet.paste(im.convert("L").resize((W // 2, H // 2), Image.NEAREST),
                (W // 2 * (i % cols), H // 2 * (i // cols)))
sheet.save("stills_preview.png")
print("stills_preview.png: written")
