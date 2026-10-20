#!/usr/bin/env python3
"""Bake a hyperspace jump as whole screens, and page-flip through them.

Two cheaper ideas failed first, and both for the same reason.

Real streaks are out of reach: an arbitrary line is about 50 cycles a pixel
and the reference holds some 80 000 pixels of them -- four million cycles,
thirty-six frames for one picture. And a particle with a trail, which is
cheap, cannot draw a streak here: radial speed is proportional to radius, so
at r=300 one frame of travel is 37 pixels and the "trail" comes out as a
ring of dots rather than a line. Slowing the growth enough to connect the
dots would take seven seconds to cross the screen.

What rescues it is that this field is SELF-SIMILAR. Stars sit at radii
r0*G^(m+u) for every integer m, so scaling the whole picture by G maps the
set exactly onto itself. A loop of NFRAMES screens, each the previous one
scaled by G^(1/NFRAMES), therefore closes seamlessly -- and playing it costs
the machine nothing at all beyond one write to the screen base register.
Which means the generator can spend whatever it likes: proper radial
streaks, as long and as dense as the reference has them.

    python3 tools/genhyper.py       # writes src/hyper.bin + hyper_preview.png

File layout: NFRAMES screens of 32000 bytes, ST mono, 80 bytes a row. Each
is 256-byte aligned by construction (32000 = 125*256), so the base register
can point straight at any of them.
"""
import math, os, random, struct, sys, zlib

W, H     = 640, 400
CX, CY   = 320, 200
# Frame count and output come from the command line: a binary sharing the
# machine with other scenes cannot afford twelve of these twice over.
NFRAMES  = int(sys.argv[1]) if len(sys.argv) > 1 else 12
G        = 2.0             # one loop is one doubling of every radius
BLUR     = 0.34            # streak length as a fraction of radius
R0       = 2.2
NSTAR    = 210             # (angle, phase) pairs, each repeated per octave
RMAX     = 430.0
OUT      = sys.argv[2] if len(sys.argv) > 2 else "src/hyper.bin"
PREVIEW  = OUT.replace("src/", "").replace(".bin", "_preview.png")

rnd = random.Random(11)
# One star is an angle and a radial phase; copies of it live at every octave,
# which is what makes the loop close.
stars = [(rnd.uniform(0, 2*math.pi), rnd.random()) for _ in range(NSTAR)]
OCTAVES = int(math.log(RMAX/R0, G)) + 2

blob = bytearray()
counts = []
for k in range(NFRAMES):
    s = G ** (k/NFRAMES)
    fb = bytearray(W*H//8)

    def plot(x, y):
        if 0 <= x < W and 0 <= y < H:
            fb[y*80 + (x >> 3)] |= 0x80 >> (x & 7)

    def streak(a, r1, r2, thick):
        dx, dy = math.cos(a), math.sin(a)
        n = int(max(2, (r2-r1)*1.5))
        for i in range(n+1):
            r = r1 + (r2-r1)*i/n
            x, y = CX + dx*r, CY + dy*r
            plot(int(x+0.5), int(y+0.5))
            if thick > 1:                       # thicken across the ray
                plot(int(x - dy + 0.5), int(y + dx + 0.5))

    n = 0
    for a, u in stars:
        for m in range(OCTAVES):
            r = R0 * G**(m + u) * s
            if r > RMAX:
                break
            r1 = r * (1.0 - BLUR)
            if r1 < 1.0:
                r1 = r * 0.5
            streak(a, r1, r, 2 if r > 210 else 1)
            n += 1
    counts.append(n)
    blob += fb

os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, 'wb').write(bytes(blob))
print(f"{OUT}: {len(blob)} bytes, {NFRAMES} screens of 32000")
print(f"  {counts[0]} streaks a frame, {OCTAVES} octaves of {NSTAR} stars")
print(f"  one loop doubles every radius; at one frame a VBL that is "
      f"{NFRAMES/71.2*1000:.0f} ms a doubling")

pix = bytearray(W*H)
for y in range(H):
    for x in range(W):
        pix[y*W+x] = 255 if blob[y*80 + (x >> 3)] >> (7 - (x & 7)) & 1 else 0
def png(path, p, w, h):
    raw = b''.join(b'\x00' + bytes(p[y*w:(y+1)*w]) for y in range(h))
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c))
    open(path, 'wb').write(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 0, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
png(PREVIEW, pix, W, H)
print(f"{PREVIEW}: written, {sum(1 for v in pix if v)} pixels lit")
