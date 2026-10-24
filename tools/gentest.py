#!/usr/bin/env python3
"""Screens for settling two questions on the real SM124, before any dithering.

1. Is a pixel really 1:1.2? Squares and circles are drawn twice, once with
   equal pixel counts and once pre-squashed by 1.2. Whichever pair reads as
   square and round on the glass gives the answer.
2. How should the reference art reach 640x400? Either rendered natively at
   640x400 by their own generator, or composed at 640x480 (square pixels,
   4:3) and squashed to 400 rows. Each scene appears both ways, back to back.

    python3 tools/gentest.py        # writes src/test.bin + test_preview.png

The file is N screens of 32000 bytes, ST mono: 80 bytes a row, MSB leftmost,
a set bit is ink.
"""
import os, struct, sys, zlib
from PIL import Image, ImageDraw

W, H = 640, 400
ASPECT = 1.2            # pixel height / width if the tube really is 4:3
TALL = 480              # square-pixel canvas that matches a 4:3 screen
SRC = os.path.expanduser("~/Downloads/AV_LIVE_handoff/05_source-code")
OUT = "src/test.bin"
PREVIEW = "test_preview.png"


def calib():
    """left pair has equal pixel counts, right pair is pre-squashed by 1.2"""
    im = Image.new("1", (W, H), 0)
    d = ImageDraw.Draw(im)
    s = 160
    sq = int(round(s / ASPECT))
    for cx, hh in ((160, s), (480, sq)):
        d.rectangle([cx-s//2, 110-hh//2, cx+s//2, 110+hh//2], outline=1, width=3)
        d.ellipse([cx-s//2, 290-hh//2, cx+s//2, 290+hh//2], outline=1, width=3)
    return im


def ladder():
    """lines 1..8 px thick, horizontal and vertical, to see what survives"""
    im = Image.new("1", (W, H), 0)
    d = ImageDraw.Draw(im)
    y = 30
    for t in (1, 2, 3, 4, 6, 8):
        d.rectangle([40, y, 300, y + t - 1], fill=1)
        y += t + 22
    x = 360
    for t in (1, 2, 3, 4, 6, 8):
        d.rectangle([x, 30, x + t - 1, 370], fill=1)
        x += t + 36
    return im


def pack(im):
    """one 640x400 bilevel image -> 32000 bytes of ST mono"""
    im = im.convert("1")
    assert im.size == (W, H), im.size
    px = im.load()
    out = bytearray()
    for y in range(H):
        row = bytearray(W // 8)
        for x in range(W):
            if px[x, y]:
                row[x >> 3] |= 0x80 >> (x & 7)
        out += row
    return bytes(out)


# The canvas size has to be right BEFORE the module is imported: system.py
# computes CX, CY from W, H at import, and binds them again as cz()'s default
# arguments, so assigning s.H afterwards moves the geometry but leaves the
# vanishing point behind -- and the corridor's corner edges stop meeting its
# end wall. One patched copy per size, imported separately.
import importlib.util, re, tempfile
_MODS = {}


# A corner edge is a thick_line ending on the AXIS of the far opening's
# corner, so Pillow caps it flat and perpendicular to the diagonal while the
# end wall is axis-aligned: that leaves a wedge about t/2 across open at each
# corner, which the pack's own 1920x1080 frames show. Simply running the line
# past the corner closes the wedge but then the cap pokes out beyond the wall.
#
# Drawn as a trapezoid instead, the far end lands across the end wall frame's
# corner -- from its outer corner to its inner one -- so the edge meets the
# frame along the frame's own thickness and neither gaps nor overhangs. The
# slight narrowing toward the far end is what perspective asks for anyway.
MITRE = '''    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        _p = cz(sx, sy, 1, vx, vy)
        _q = cz(sx, sy, zend, vx, vy)
        _dx, _dy = _q[0] - _p[0], _q[1] - _p[1]
        _l = math.hypot(_dx, _dy) or 1.0
        _nx, _ny = -_dy / _l * t / 2, _dx / _l * t / 2
        _f = t * 0.8 / 2
        _a = (_q[0] + sx * _f, _q[1] + sy * _f)
        _b = (_q[0] - sx * _f, _q[1] - sy * _f)
        if (_a[0] - _q[0]) * _nx + (_a[1] - _q[1]) * _ny < 0:
            _a, _b = _b, _a        # keep the quad simple: a self-crossing one
        d.polygon([(R(_p[0] + _nx), R(_p[1] + _ny)), (R(_a[0]), R(_a[1])),
                   (R(_b[0]), R(_b[1])), (R(_p[0] - _nx), R(_p[1] - _ny))], fill=1)'''
PLAIN = '''    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        thick_line(d, cz(sx, sy, 1, vx, vy), cz(sx, sy, zend, vx, vy), t)'''

# A floor bar is drawn as an axis-aligned rectangle of some thickness, which
# is the wrong shape: a bar lying on the floor spans a slice of DEPTH, so its
# near edge is wider than its far edge and the two edges sit at the heights
# perspective puts them. Drawn as the quad across that slice, the taper and
# the thinning with distance both come out of the projection and no thickness
# formula is needed at all.
BARS_PLAIN = '''            y = cz(0, 1, z, vx, vy)[1]
            xl, xr = cz(-1, 1, z, vx, vy)[0], cz(1, 1, z, vx, vy)[0]
            th = max(3, 26 / z)
            bar(d, xl, y - th / 2, xr, y + th / 2)'''
BARS_PERSP = '''            _za, _zb = max(1.0, z), min(zend, z + 0.20)
            if _zb > _za:
                _q4 = [cz(-1, 1, _za, vx, vy), cz(1, 1, _za, vx, vy),
                       cz(1, 1, _zb, vx, vy), cz(-1, 1, _zb, vx, vy)]
                d.polygon([(R(_x), R(_y)) for _x, _y in _q4], fill=1)'''


def sysmod(h, mitre=False):
    key = (h, mitre)
    if key in _MODS:
        return _MODS[key]
    src = open(os.path.join(SRC, "system.py")).read()
    src = re.sub(r'^W, H, S = .*$', f'W, H, S = {W}, {h}, 1', src, count=1, flags=re.M)
    if mitre:
        assert PLAIN in src, "corridor's corner-edge loop moved"
        assert BARS_PLAIN in src, "corridor's floor-bar thickness moved"
        src = src.replace(BARS_PLAIN, BARS_PERSP, 1)
        src = src.replace(PLAIN, MITRE, 1)
    d = tempfile.mkdtemp()
    f = os.path.join(d, f"sysv{h}{'m' if mitre else ''}.py")
    open(f, "w").write(src)
    spec = importlib.util.spec_from_file_location(f"sysv{h}{'m' if mitre else ''}", f)
    m = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = m
    spec.loader.exec_module(m)
    assert (m.W, m.H) == (W, h) and (m.CX, m.CY) == (W//2, h//2)
    _MODS[key] = m
    return m


def render(scene, mode, mitre=False):
    """mode 'native' renders at 640x400; 'squash' at 640x480 then drops rows"""
    im = scene(sysmod(H if mode == "native" else TALL, mitre))
    if mode == "squash":
        im = im.resize((W, H), Image.NEAREST)
    return im


SCENES = [("corridor", lambda s: s.corridor(phase=0.0)),
          ("tunnel",   lambda s: s.tunnel()),
          ("spiral",   lambda s: s.spiral()),
          ("concentric", lambda s: s.concentric())]

shots = [("calibration", calib()), ("thickness", ladder())]
for name, fn in SCENES:
    for mode in ("native", "squash"):
        try:
            shots.append((f"{name}_{mode}", render(fn, mode)))
        except Exception as e:
            print(f"  {name} {mode}: FAILED {type(e).__name__}: {e}")

shots.append(("corridor_mitred", render(SCENES[0][1], "native", mitre=True)))

blob = b"".join(pack(im) for _, im in shots)
os.makedirs("src", exist_ok=True)
open(OUT, "wb").write(blob)
print(f"{OUT}: {len(blob)} bytes, {len(shots)} screens")
for i, (n, _) in enumerate(shots):
    print(f"  {i}  {n}")
print(f"  src/shows/viewer.s must use NSHOT equ {len(shots)}")

cols = 2
rows = (len(shots) + cols - 1) // cols
sheet = Image.new("L", (W * cols, H * rows), 0)
for i, (_, im) in enumerate(shots):
    sheet.paste(im.convert("L"), (W * (i % cols), H * (i // cols)))
sheet.save(PREVIEW)
print(f"{PREVIEW}: written {sheet.size}")
