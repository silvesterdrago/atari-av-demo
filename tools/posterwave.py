#!/usr/bin/env python3
"""Animate the headline of the poster: a wave that lifts letters by one cell.

    python3 tools/posterwave.py POSTER.png [out.mp4]

Only the top line moves. Everything else -- the vortex, the other lines, the
date, the logo -- is the file's own pixels, untouched.

Nothing is resampled. A letter is lifted by a whole number of pixels and the
strip it leaves is repainted from the background above the band, so the
texture never crawls: that is the one thing the brief rules out, and it is
also what a warp of a per-pixel dither would do.

The poster carries two polarities -- ink is black on the paper and white on
the block -- so a letter is drawn in the colour its own column calls for. A
letter that straddles the edge is left standing rather than guessed at.
"""
import collections
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

BAND = (14, 60)             # the headline, measured off the ink profile
BG_ROW = 5                  # a row above it, which is pure background
SECONDS = 18.0
FPS = 24                    # so a cycle lands on a frame and the loop can be
                            # checked rather than asserted
CYCLE = 6.0                 # one wave a cycle, inside the brief's 5-7 s and
                            # a whole divisor of the test, so the loop closes
SWEEP = 1.4                 # how long the wave takes to cross the line
HOLD = 0.22                 # how long one letter stays up


def letters(ink):
    """Columns of the band that carry ink, cut into glyphs at the gaps."""
    col = ink.any(axis=0)
    out, run = [], None
    for x, c in enumerate(col):
        if c and run is None:
            run = x
        elif not c and run is not None:
            out.append((run, x))
            run = None
    if run is not None:
        out.append((run, len(col)))
    return [(a, b) for a, b in out if b - a >= 4]


def cell_size(ink):
    """The grid the font is drawn on: its stroke is one cell wide."""
    c = collections.Counter()
    for row in ink:
        run = 0
        for v in row:
            if v:
                run += 1
            elif run:
                c[run] += 1
                run = 0
    return max(4, c.most_common(1)[0][0])


def main():
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else "poster_test.mp4"
    img = np.array(Image.open(src).convert("L")) > 127     # True = white
    H, W = img.shape
    y0, y1 = BAND

    paper = img[BG_ROW]                     # per column: True = white paper
    band = img[y0:y1]
    ink = np.where(paper[None, :], ~band, band)            # True = ink

    cell = cell_size(ink)
    glyphs = letters(ink)
    edge = int(np.argmin(paper))            # where the block begins
    glyphs = [(a, b) for a, b in glyphs if not (a < edge < b)]

    def height(g):
        rows = np.where(ink[:, g[0]:g[1]].any(axis=1))[0]
        return rows.max() - rows.min() + 1

    hs = sorted(height(g) for g in glyphs)
    full = hs[len(hs) // 2]
    # the x between the names is a separator, not a letter, and it is the one
    # mark on the line that does not reach full height
    moving = [g for g in glyphs if height(g) >= 0.7 * full]
    skipped = len(glyphs) - len(moving)
    print(f"{len(moving)} букв (пропущено {skipped}: ниже строчной), "
          f"клетка {cell} px, кромка блока на x={edge}")
    glyphs = moving

    # Only a moving glyph's own box is ever repainted, so the rest of the
    # poster stays the file's own bytes -- the block's soft edge included.
    frames = int(SECONDS * FPS)
    tmp = tempfile.mkdtemp()
    per = CYCLE * FPS
    first = join = None
    for f in range(frames):
        t = (f / FPS) % CYCLE
        pic = img.copy()
        for i, (a, b) in enumerate(glyphs):
            start = SWEEP * i / max(1, len(glyphs) - 1)
            if not (start <= t < start + HOLD):
                continue
            bg = paper[a]                                  # flat inside a box
            pic[y0 - cell:y1, a:b] = bg
            dst = pic[y0 - cell:y1 - cell, a:b]
            pic[y0 - cell:y1 - cell, a:b] = np.where(ink[:, a:b], not bg, dst)
        arr = (pic * 255).astype(np.uint8)
        if f == 0:
            first = arr.copy()
        if per == int(per) and f == int(per):
            join = arr.copy()                   # the frame the loop joins on
        Image.fromarray(arr).save(f"{tmp}/f{f:05d}.png")
    same = join is not None and np.array_equal(first, join)
    print("стык цикла:", "кадр в кадр" if same else "ПРОВЕРИТЬ: цикл не сошёлся")

    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS),
                    "-i", f"{tmp}/f%05d.png", "-c:v", "libx264", "-pix_fmt",
                    "yuv420p", "-crf", "12", out], check=True)
    for f in os.listdir(tmp):
        os.remove(f"{tmp}/{f}")
    os.rmdir(tmp)
    print(f"{out}: {SECONDS:.0f} с, {FPS} кадров в секунду, волна раз в {CYCLE} с")


if __name__ == "__main__":
    main()
