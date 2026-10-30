#!/usr/bin/env python3
"""Run a position headless and compare the screen with the data it came from.

    python3 tools/verify.py 42 45 48        # these positions
    python3 tools/verify.py --stills        # every position that is a still

`-DGOTO=<position>` opens ARC on one position with MIDI out of the loop, which
is the only way to check a position exactly: the emulator's MIDI is lossy
enough that a dropped byte reads as a wrong picture. The position table says
which screen of `STILLS.DAT` a position should be showing, so a still is a
pixel-for-pixel claim and the answer is a number of differing bytes, not an
opinion. Loops and break-ups are not stills; for those this only says the
machine ran and the screen is not blank.
"""
import os
import re
import subprocess
import sys
import tempfile

from PIL import Image, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VASM = f"{ROOT}/tools/vasm/vasmm68k_mot"
TOS = "/opt/homebrew/share/hatari/tos.img"
# low byte of a $02xx/$03xx position -> the file it was baked from
BINS = ["corr", "tun", "wave", "desy", "drift", "floor",
        "tunp", "branch", "pit", "pitb", "walls", "expand"]
VBLS = 900                      # EmuTOS boots for ~800 of them before ours runs
SHOT = VBLS - 10                # and the still itself needs six frames to read
FRAMESZ = 32000


def pos_tbl():
    src = open(f"{ROOT}/src/arc.s").read()
    body = src[src.index("pos_tbl:"):src.index("name_tbl:")]
    vals = []
    for line in body.splitlines():
        m = re.match(r"\s*dc\.w\s+([^;]+)", line)
        if m:
            vals += [int(v.strip()[1:], 16) for v in m.group(1).split(",")
                     if v.strip().startswith("$")]
    return vals


def shot(pos, work):
    """Assemble ARC opening on one position, run it, return the last frame."""
    d = f"{work}/d{pos}"
    os.makedirs(d, exist_ok=True)
    subprocess.run([VASM, "-Ftos", "-quiet", f"-DGOTO={pos}",
                    "-o", f"{d}/X.TOS", f"{ROOT}/src/arc.s"], check=True)
    for f in os.listdir(f"{ROOT}/dist"):
        if f.endswith(".DAT"):
            os.link(f"{ROOT}/dist/{f}", f"{d}/{f}")
    avi = f"{work}/{pos}.avi"
    subprocess.run(["hatari", "--tos", TOS, "--machine", "st", "--memsize", "1",
                    "--monitor", "mono", "--sound", "off", "--gemdos-drive", "C",
                    "-d", d, "--auto", "C:\\X.TOS", "--benchmark",
                    "--frameskips", "0", "--run-vbls", str(VBLS), "--avirecord",
                    "--avi-vcodec", "png", "--avi-file", avi],
                   capture_output=True)
    # avipng.py runs its CLI at import, so it is called, not imported
    subprocess.run([sys.executable, f"{ROOT}/tools/avipng.py", "shots", avi,
                    f"{work}/png{pos}", str(SHOT)], check=True,
                   capture_output=True)
    png = f"{work}/png{pos}/" + os.listdir(f"{work}/png{pos}")[0]
    # Hatari records 436 rows, the screen plus the bottom border; the screen
    # itself starts at row 0, so the extra rows come off the bottom
    im = Image.open(png).convert("L").point(lambda v: 255 if v > 100 else 0)
    im = im.crop((0, 0, 640, 400))
    lit = im.point(lambda v: 1 if v else 0, "1")
    return lit.tobytes(), ImageChops.invert(lit.convert("L")).convert("1").tobytes()


def main():
    vals = pos_tbl()
    if "--stills" in sys.argv:
        want = [i for i, v in enumerate(vals, 1) if v >> 8 == 6]
    else:
        want = [int(a) for a in sys.argv[1:]]
    if not want:
        sys.exit("нечего проверять")
    stills = open(f"{ROOT}/src/stills.bin", "rb").read()
    bad = 0
    with tempfile.TemporaryDirectory() as work:
        for pos in want:
            v = vals[pos - 1]
            got, inv = shot(pos, work)
            if v >> 8 == 6:
                idx = v & 0xFF
                exp = stills[idx * FRAMESZ:(idx + 1) * FRAMESZ]
                d1 = sum(a != b for a, b in zip(got, exp))
                d2 = sum(a != b for a, b in zip(inv, exp))
                diff = min(d1, d2)
                pol = "" if d1 <= d2 else ", палитра инверсная"
                print(f"поз {pos}: экран {idx}, отличий — {diff}{pol}")
                bad += diff != 0
            elif v >> 8 in (2, 3):
                name = BINS[v & 0xFF]
                buf = open(f"{ROOT}/src/{name}.bin", "rb").read()
                n = len(buf) // FRAMESZ
                diff = min(sum(a != b for a, b in
                               zip(got, buf[i * FRAMESZ:(i + 1) * FRAMESZ]))
                           for i in range(n))
                print(f"поз {pos}: петля {name}, лучший экран отличий — {diff}")
                bad += diff != 0
            else:
                ink = min(sum(bin(b).count("1") for b in got),
                          sum(bin(b).count("1") for b in inv))
                print(f"поз {pos}: не статика; закрашено {ink} бит")
                bad += ink == 0
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
