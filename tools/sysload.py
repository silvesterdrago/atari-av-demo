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
# A frame is a band of the tunnel wall cut across the axis, between depth z
# and z', so it is drawn as the four quads of wall between those depths. That
# puts BOTH of each corner's vertices -- outer at z, inner at z' -- on the ray
# through the vanishing point, which is the corner edge's own centre line, so
# the ring mitres into the edge instead of stepping across it. Stroking a
# rectangle inward cannot do this: it steps in equally in x and y, at 45
# degrees, while the ray runs at atan(H/W).
#
# Side bars then come out (W/2)/(H/2) = 1.6 times thicker than top and bottom,
# which is what perspective says: the side walls are further out. The corner
# edge takes the geometric mean of the two, so it sits between them.
#
# The corner edge starts at a FIXED depth, not at the nearest frame: the
# frames drift between z=0.84 and z=1.14, and whenever the nearest one was
# deeper than 1 its corner already sat inside the screen, so the edge began
# in mid-air some 38 pixels short of the corner -- a visible break in a
# third of the loop.
#
# t is the side bar's thickness at z=1, in pixels; the axial length of the
# band follows from it. Frames also start nearer than z=1 and slide off the
# edges, since z=1 is the screen itself.
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
    _u = min(0.45, t / (W / 2))
    _dz = _u / (1 - _u)
    def _shrink(_z):                      # 1/z - 1/z', the band's radial span
        _s = 1.0 / _z - 1.0 / (_z + _dz)
        _s = max(_s, 2.0 / (H / 2))       # the thin bar never under two pixels
        return min(_s, 0.9 / _z)
    def _far(_z):
        return 1.0 / (1.0 / _z - _shrink(_z))
    def _q(pts):
        d.polygon([(R(_x), R(_y)) for _x, _y in pts], fill=1)
    _zb = [0.75] + [_z for _z in zs if _z > 0.75] + [zmax]
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        _w = [math.sqrt(W * H) / 2 * _shrink(_z) for _z in _zb]
        _ps = [cz(sx, sy, _z, vx, vy) for _z in _zb]
        _dx, _dy = _ps[-1][0] - _ps[0][0], _ps[-1][1] - _ps[0][1]
        _l = math.hypot(_dx, _dy) or 1.0
        _ux, _uy = -_dy / _l, _dx / _l
        _a = [(p[0] + _ux * w / 2, p[1] + _uy * w / 2) for p, w in zip(_ps, _w)]
        _b = [(p[0] - _ux * w / 2, p[1] - _uy * w / 2) for p, w in zip(_ps, _w)]
        _q(_a + _b[::-1])
    for _z in zs:
        _zf = _far(_z)
        for _sy in (-1, 1):
            _q([cz(-1, _sy, _z, vx, vy), cz(1, _sy, _z, vx, vy),
                cz(1, _sy, _zf, vx, vy), cz(-1, _sy, _zf, vx, vy)])
        for _sx in (-1, 1):
            _q([cz(_sx, -1, _z, vx, vy), cz(_sx, 1, _z, vx, vy),
                cz(_sx, 1, _zf, vx, vy), cz(_sx, -1, _zf, vx, vy)])'''


# The floor's depths are a hand-typed default rounded to two figures, and
# their ratios run 1.40 to 1.48 -- while floor() steps the phase by a fixed
# 1.42, so the code already treats the set as geometric. It very nearly is,
# and the gap is what keeps the loop from closing: phase 0 and phase 1 differ
# by 15778 pixels. Made exactly geometric, the set maps onto itself under the
# step the generator already uses and the loop closes to the pixel. Nothing
# moves more than three rows out of four hundred, on lines 3 to 13 px thick.
#
# The set also runs ten deep rather than six, and zfar with it. Six ends 37 to
# 54 rows short of the horizon, and since the generator adds exactly ONE depth
# beyond the set, the line that closes that gap has to appear inside the frame:
# on the machine it materialised 16 rows from its neighbour partway through
# every turn. Ten fills the gap with a converging fan and the arrival stops
# reading as one. Twelve was built and compared too -- it leaves the same gap
# and only melts the fan into a blob at the vanishing point.
#
# zfar has to stay inside [1.42**(n-1), 1.42**n): at the top of that range the
# one extra depth is drawn at phase 0 and gone at phase 1, and the loop stops
# closing. So the reach of the set is the only lever on the arrival.
#
# pit() passes its own depths and zfar, so this leaves it alone.


# The phase step was the constant 1.42 whatever depths it was handed, so a
# scene passing its own set -- pit's step by about 1.35 -- marched its lines
# at a ratio its data does not have, and its loop missed by 18728 pixels. The
# step is now the set's OWN ratio unless one is given, so the data and the
# motion cannot disagree again, and pit's depths become geometric between the
# two ends it already had.
FLOOR_STEP = [
    ("          horizon=True, hole=None, dip=0.0):",
     "          horizon=True, hole=None, dip=0.0, step=None):"),
    ("    zz = [z * (1.42 ** (-phase)) for z in zs] + [zs[-1] * 1.42 ** (1 - phase)]",
     "    step = step or (zs[-1] / zs[0]) ** (1 / (len(zs) - 1))\n"
     "    zz = [z * (step ** (-phase)) for z in zs] + [zs[-1] * step ** (1 - phase)]"),
    ("zs=(1, 1.35, 1.8, 2.45, 3.3, 4.5)",
     "zs=tuple(4.5 ** (_k / 5) for _k in range(6))"),
]
# The floor family is laid out in absolute rows -- HZ=110 is the horizon and
# F=250 the focal length -- so rewriting W, H, S leaves it drawn for a
# 360-row canvas on our 400-row one: the near transverse line lands on row 360
# and stands there as a bar forty rows short of the bottom edge.
#
# Only the vertical is scaled, and it is scaled in the PROJECTION rather than
# in the constants. Scaling F itself would spread the floor sideways too,
# while the corridor -- whose cross-section is defined in W and H -- stretches
# vertically and keeps its width; the floor has to agree with it. Scaling
# inside fpt also follows every override, so pit's own HZ, F = 18, 300 comes
# out right without naming it here. Line weights are left alone: thickness is
# the one line-weight family of the set, not a dimension of the drawing.
FLOOR_Y = [
    ("HZ, F = 110, 250",
     "HZ, F = 110, 250\n_VS = {vs!r}            # our 400 rows against their 360"),
    ("    return vx + X * F / Z, HZ + (1 + Y) * F / Z",
     "    return vx + X * F / Z, (HZ + (1 + Y) * F / Z) * _VS"),
    ("        bar(d, 0, HZ - 4, W, HZ + 4)",
     "        bar(d, 0, HZ * _VS - 4, W, HZ * _VS + 4)"),
    ("    bar(d, CX - r, HZ - 4 - 2 * r, CX + r, HZ - 4)",
     "    bar(d, CX - r, HZ * _VS - 4 - 2 * r, CX + r, HZ * _VS - 4)"),
]
FLOOR_DEPTHS = [
    ("zs=(1, 1.4, 2.0, 2.9, 4.2, 6.2)", "zs=tuple(1.42 ** _k for _k in range(10))"),
    ("zfar=6.5", "zfar=1.42 ** 9.5"),
]


def sysmod(h=H, mitre=False):
    key = (h, mitre)
    if key in _MODS:
        return _MODS[key]
    src = open(os.path.join(SRC, "system.py")).read()
    src = re.sub(r'^W, H, S = .*$', f'W, H, S = {W}, {h}, 1', src, count=1, flags=re.M)
    for _old, _new in FLOOR_DEPTHS:
        assert src.count(_old) == 1, f"the floor's {_old!r} moved"
        src = src.replace(_old, _new, 1)
    for _old, _new in FLOOR_STEP:
        assert src.count(_old) == 1, f"the floor's {_old!r} moved"
        src = src.replace(_old, _new, 1)
    for _old, _new in FLOOR_Y:
        assert src.count(_old) == 1, f"the floor's {_old!r} moved"
        src = src.replace(_old, _new.format(vs=h / 360), 1)
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
