#!/usr/bin/env python3
"""Feed test MIDI into Hatari's MIDI IN pipe, for when no keyboard is around.

    make run-midi                       # pattern mode, via the Makefile
    python3 tools/midifeed.py FIFO pads # sweep the 8 pads, one at a time

Modes:
  pattern  steady 16ths with a velocity pattern (default)
  pads     hold each of the 8 pad notes in turn, to compare their looks
"""
import sys, time

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/noiseav.midi"
mode = sys.argv[2] if len(sys.argv) > 2 else "pattern"

PAD_BASE = 36          # matches PAD_BASE in src/main.s
HOLD     = 8.0         # seconds per pad in pads mode

with open(path, "wb", buffering=0) as f:
    if mode == "pads":
        while True:
            for pad in range(8):
                note = PAD_BASE + pad
                sys.stderr.write(f"pad {pad + 1} -> note {note}\n")
                end = time.time() + HOLD
                while time.time() < end:
                    f.write(bytes([0x90, note, 100]))
                    time.sleep(0.15)
                    f.write(bytes([0x80, note, 0]))
                    time.sleep(0.05)
    else:
        bpm     = float(sys.argv[3]) if len(sys.argv) > 3 else 120.0
        step    = 60.0 / bpm / 4
        pattern = [127, 40, 70, 40, 100, 40, 70, 55]
        i = 0
        while True:
            note = PAD_BASE + (i % 8)
            f.write(bytes([0x90, note, pattern[i % len(pattern)]]))
            time.sleep(step * 0.5)
            f.write(bytes([0x80, note, 0]))
            time.sleep(step * 0.5)
            i += 1
