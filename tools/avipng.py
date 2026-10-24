#!/usr/bin/env python3
"""Pull frames out of a Hatari AVI, and read the diagnostic bars off them.

    python3 tools/avipng.py shots  run.avi outdir 100,200   # write PNGs
    python3 tools/avipng.py bars   run.avi 100,200          # overruns etc

--avi-vcodec png stores each frame as a whole PNG, so no decoder is needed.
The bars sit on rows 0, 4, 8, 12; a show may invert the palette, so "lit" is
read against the pixel at x=600, past the end of every bar.
"""
import os, struct, sys, zlib

SIG = bytes([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
IEND = b'IEND\xaeB`\x82'


def frames(path):
    data = open(path, 'rb').read()
    out, i = [], 0
    while True:
        j = data.find(SIG, i)
        if j < 0:
            return data, out
        out.append(j); i = j + 8


def rows(buf, upto=None):
    i, idat, hdr, plte = 8, [], None, None
    while i < len(buf):
        ln = struct.unpack('>I', buf[i:i+4])[0]; t = buf[i+4:i+8]
        if t == b'IHDR': hdr = struct.unpack('>IIBBBBB', buf[i+8:i+8+ln])
        elif t == b'PLTE': plte = buf[i+8:i+8+ln]
        elif t == b'IDAT': idat.append(buf[i+8:i+8+ln])
        elif t == b'IEND': break
        i += 12 + ln
    w, h, ct = hdr[0], hdr[1], hdr[3]
    nch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]; st = w*nch
    raw = zlib.decompress(b''.join(idat))
    prev = bytearray(st); p = 0; out = []
    for y in range(h if upto is None else upto+1):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p+st]); p += st
        if f == 1:
            for x in range(nch, st): line[x] = (line[x]+line[x-nch]) & 255
        elif f == 2:
            for x in range(st): line[x] = (line[x]+prev[x]) & 255
        elif f == 3:
            for x in range(st):
                a = line[x-nch] if x >= nch else 0
                line[x] = (line[x]+((a+prev[x])>>1)) & 255
        elif f == 4:
            for x in range(st):
                a = line[x-nch] if x >= nch else 0
                b, c = prev[x], (prev[x-nch] if x >= nch else 0)
                pa, pb, pc = abs(b-c), abs(a-c), abs(a+b-2*c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x]+pr) & 255
        px = (lambda x: plte[line[x]*3]) if ct == 3 else (lambda x: line[x*nch])
        out.append([px(x) > 100 for x in range(w)])
        prev = line
    return out


mode, path = sys.argv[1], sys.argv[2]
data, starts = frames(path)
if mode == 'shots':
    outdir, want = sys.argv[3], [int(x) for x in sys.argv[4].split(',')]
    os.makedirs(outdir, exist_ok=True)
    print(f"{len(starts)} frames in avi")
    for n in want:
        if n >= len(starts):
            print(f"frame {n}: out of range"); continue
        s = starts[n]; e = data.find(IEND, s) + len(IEND)
        p = os.path.join(outdir, f"frame{n:04d}.png")
        open(p, 'wb').write(data[s:e])
        print(f"wrote {p}")
else:
    for n in [int(x) for x in sys.argv[3].split(',')]:
        if n >= len(starts):
            print(f"frame {n}: out of range"); continue
        s = starts[n]; e = data.find(IEND, s) + len(IEND)
        r = rows(data[s:e], 13)
        def bar(y):
            bg = r[y][600]; k = 0
            while k < 600 and r[y][k] != bg: k += 1
            return k // 8
        print(f"frame {n:5d}  overruns={bar(0):3d}  midi={bar(4):3d}  "
              f"show={bar(8):3d}  frames/pass={bar(12):3d}")
