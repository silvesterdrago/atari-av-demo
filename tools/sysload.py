#!/usr/bin/env python3
"""The reference generator, patched for the ST, plus the ST mono packer.

The pack ships its own system.py, which draws at 1920x1080 and whose art has
two defects at our scale (see MITRE and BARS_PERSP below). Both the test
screens and the baked animations need the same patched copy, so the patches
live here and nowhere else: an art fix applies to every build at once.
"""
import os, sys

W, H = 640, 400
ASPECT = 1.2            # pixel height / width if the tube really is 4:3
TALL = 480              # square-pixel canvas that matches a 4:3 screen
SRC = os.path.expanduser("~/Downloads/AV_LIVE_handoff/05_source-code")


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


# The tunnel has the same two defects as the corridor, in its own form. Its
# frames take a 1/z thickness from a formula and are stroked at a constant
# width, and its corner edges are a thick_line of a FIXED 8 px -- so a near
# frame is 22 px thick where the edge crossing it is 8, and every junction
# between the two reads as a collision rather than a joint.
#
# A frame is a band of the tunnel wall of some fixed length along the axis,
# which projects as 1/z**2: it thickens toward the viewer much faster than
# 1/z. The corner edges are then built as tapered bands sampled at the SAME
# depths with the SAME thickness, so each one is exactly as wide as the frame
# it crosses and the two meet flush.
#
# Frames also start nearer than z=1 and slide off the edges instead of
# vanishing at the border, which is what z=1 means: the screen itself.
TUNNEL_PLAIN = '''    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        thick_line(d, cz(sx, sy, 1, vx, vy), cz(sx, sy, zmax, vx, vy), 8)
    zs = []
    z = ratio ** (-phase)
    while z < zmax:
        if z >= 1.0:
            zs.append(z)
        z *= ratio
    for z in zs:
        frame_c(d, vx, vy, W / z, H / z, max(4, t / z))'''
TUNNEL_PERSP = '''    zs = []
    z = ratio ** (-phase - 3)
    while z < zmax:
        if z >= 0.8:
            zs.append(z)
        z *= ratio
    def _th(_z):
        return max(2.0, t / _z ** 2)
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        _ps = [(cz(sx, sy, _z, vx, vy), _th(_z)) for _z in zs + [zmax]]
        _dx = _ps[-1][0][0] - _ps[0][0][0]
        _dy = _ps[-1][0][1] - _ps[0][0][1]
        _l = math.hypot(_dx, _dy) or 1.0
        _ux, _uy = -_dy / _l, _dx / _l
        _a = [(R(p[0] + _ux * w / 2), R(p[1] + _uy * w / 2)) for p, w in _ps]
        _b = [(R(p[0] - _ux * w / 2), R(p[1] - _uy * w / 2)) for p, w in _ps]
        d.polygon(_a + _b[::-1], fill=1)
    for _z in zs:
        frame_c(d, vx, vy, W / _z, H / _z, _th(_z))'''


def sysmod(h=H, mitre=False):
    key = (h, mitre)
    if key in _MODS:
        return _MODS[key]
    src = open(os.path.join(SRC, "system.py")).read()
    src = re.sub(r'^W, H, S = .*$', f'W, H, S = {W}, {h}, 1', src, count=1, flags=re.M)
    if mitre:
        assert PLAIN in src, "corridor's corner-edge loop moved"
        assert BARS_PLAIN in src, "corridor's floor-bar thickness moved"
        assert src.count(TUNNEL_PLAIN) == 1, "tunnel's frame loop moved"
        src = src.replace(BARS_PLAIN, BARS_PERSP, 1)
        src = src.replace(PLAIN, MITRE, 1)
        src = src.replace(TUNNEL_PLAIN, TUNNEL_PERSP, 1)
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
