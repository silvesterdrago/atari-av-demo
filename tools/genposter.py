#!/usr/bin/env python3
"""Bake the poster for the ST: one screen plus the headline band in motion.

    python3 tools/genposter.py POSTER.png     # src/poster.bin

The whole poster is 32000 bytes, and the only thing that moves is one band
23 rows down. So the file is that screen followed by N versions of the band
alone -- 2240 bytes apiece -- and the machine blits one of them a frame. A
flipbook of whole screens would be 32000 a frame for a wave that touches
three per cent of the picture.

The dither is done ONCE, on the full screen, and the band states are cut out
of that same dithered image. Dithering each state on its own would renew the
noise under every letter and the band would boil; here a letter is lifted by
four whole pixels and nothing is resampled.
"""
import sys

import numpy as np
from PIL import Image

W, H = 640, 400             # the ST's mono screen
PW, PH = 640, 360           # the poster inside it, 2:1 from 1280x720
PAD = (H - PH) // 2         # black bars above and below
BAND1280 = (14, 60)         # the headline's ink, measured on the original
LIFT = 4                    # one cell at our scale: 8 px there, 4 here
HEAD = 4                    # rows of clearance above, or the lift clips tops
GROUP = 3                   # letters up at once


def glyphs_1280(img):
    """The headline's letters, found on the original where they are crisp."""
    y0, y1 = BAND1280
    paper = img[5]
    band = img[y0:y1]
    ink = np.where(paper[None, :], ~band, band)
    col = ink.any(axis=0)
    out, run = [], None
    for x, c in enumerate(col):
        if c and run is None:
            run = x
        elif not c and run is not None:
            out.append((run, x))
            run = None
    boxes = [(a, b) for a, b in out if b - a >= 4]
    edge = int(np.argmin(paper))
    boxes = [(a, b) for a, b in boxes if not (a < edge < b)]

    def height(g):
        rows = np.where(ink[:, g[0]:g[1]].any(axis=1))[0]
        return rows.max() - rows.min() + 1

    hs = sorted(height(g) for g in boxes)
    full = hs[len(hs) // 2]
    # the x between the names is a separator, not a letter, and it is the one
    # mark on the line that does not reach full height
    return [g for g in boxes if height(g) >= 0.7 * full]


def dither(grey):
    """Floyd-Steinberg, once, over the whole poster."""
    g = grey.astype(np.float32).copy()
    out = np.zeros(g.shape, bool)
    h, w = g.shape
    for y in range(h):
        for x in range(w):
            old = g[y, x]
            new = 1.0 if old > 0.5 else 0.0
            out[y, x] = new > 0.5
            e = old - new
            if x + 1 < w:
                g[y, x + 1] += e * 7 / 16
            if y + 1 < h:
                if x:
                    g[y + 1, x - 1] += e * 3 / 16
                g[y + 1, x] += e * 5 / 16
                if x + 1 < w:
                    g[y + 1, x + 1] += e * 1 / 16
    return out


def pack(bits):
    """ST mono: 80 bytes a row, MSB leftmost, and a SET bit comes out WHITE,
    the same way every other screen in the show is packed."""
    return np.packbits(bits, axis=1).tobytes()


def main():
    src = sys.argv[1]
    im = Image.open(src).convert("L")
    binary = np.array(im) > 127
    boxes = [(a // 2, b // 2) for a, b in glyphs_1280(binary)]

    small = np.asarray(im.resize((PW, PH), Image.BOX), dtype=np.float32) / 255
    white = dither(small)                       # True = white
    screen = np.zeros((H, W), bool)
    screen[PAD:PAD + PH] = white

    y0 = BAND1280[0] // 2 + PAD                 # where the ink starts
    y1 = BAND1280[1] // 2 + PAD
    top = y0 - HEAD
    band = screen[top:y1]

    states = [band.copy()]                      # 0 is the line at rest
    for s in range(len(boxes) + GROUP - 1):
        cur = band.copy()
        for i in range(s - GROUP + 1, s + 1):
            if not 0 <= i < len(boxes):
                continue
            a, b = boxes[i]
            glyph = band[HEAD:, a:b].copy()
            bg = band[HEAD - 2, a:b]            # the row above is background
            cur[:, a:b] = bg[None, :]
            cur[HEAD - LIFT:HEAD - LIFT + glyph.shape[0], a:b] = glyph
        states.append(cur)

    rows = y1 - top
    out = pack(screen) + b"".join(pack(s) for s in states)
    open("src/poster.bin", "wb").write(out)
    print(f"src/poster.bin: {len(out)} байт — экран 32000 + {len(states)} "
          f"полос по {rows * 80}")
    print(f"полоса: строка {top}, {rows} строк; {len(boxes)} букв, подъём {LIFT} px")
    Image.fromarray((states[6] * 255).astype(np.uint8)).save("poster_band.png")
    Image.fromarray((screen * 255).astype(np.uint8)).save("poster_screen.png")


if __name__ == "__main__":
    main()
