#!/usr/bin/env python3
"""Send a position, an effect or transport to the show, on the control channel.

    tools/pos.py 18                 # position 18: the corridor
    tools/pos.py 15 16 --gap 4      # walk two positions, four seconds apart
    tools/pos.py strobe             # effect: the strobe on or off
    tools/pos.py freeze --hold 2    # effect held for two seconds
    tools/pos.py --start            # transport start: back to a known state

The code IS the position in the storyboard, so `18` means their frame 18 and
nothing else has to be looked up. ARC.TOS answers 1-66 and 99; a build that
does not know a position ignores it.

Two destinations:

    --port 'TM-1'     a CoreMIDI output, which is the real machine through
                      the interface. Needs mido; if the system python has
                      none, run the whole command under
                      `uv run --with mido --with python-rtmidi`.
    --fifo PATH       the pipe Hatari reads with --midi-in, for the emulator.
                      No dependencies at all.

Hatari's file MIDI drops most of a burst -- measured, 4 bytes of 14 -- so
--fifo repeats every message 25 times by default. A real MIDI cable does not
need that, and --port sends once.
"""
import argparse
import os
import sys
import time

CH = 16                 # must match CTRL_CH in src/core/head.s
POS_MAX = 66
SAFE = 99

EFFECTS = {"strobe": 100,       # on or off
           "strobeh": 101,      # while held
           "sync": 102,         # locked to the beat, while held
           "freeze": 103,       # while held
           "flash": 104}        # one inverted frame

START, STOP = 0xFA, 0xFC


def codes(words):
    out = []
    for w in words:
        if w in EFFECTS:
            out.append((EFFECTS[w], w))
            continue
        try:
            n = int(w)
        except ValueError:
            sys.exit(f"не позиция и не эффект: {w!r}; эффекты: {', '.join(EFFECTS)}")
        if not (1 <= n <= POS_MAX or n == SAFE):
            sys.exit(f"позиция вне 1..{POS_MAX} (и не {SAFE}): {n}")
        out.append((n, f"позиция {n}"))
    return out


class Fifo:
    """Hatari reads this as a file, so a message is just bytes in a pipe.

    Opened O_RDWR, never write-only, which is the same thing midibridge.c
    does and for the same reason: a write-only end that closes gives Hatari
    EOF on the pipe, and it stops reading MIDI for the rest of the run. With
    a reader of our own always on it there is no EOF, so the script can be
    run again and again against one emulator.
    """

    def __init__(self, path):
        self.fd = os.open(path, os.O_RDWR)

    def raw(self, data):
        os.write(self.fd, bytes(data))

    def close(self):
        os.close(self.fd)


class Port:
    def __init__(self, hint):
        try:
            import mido
        except ImportError:
            sys.exit("нет mido: запусти команду через\n"
                     "  uv run --with mido --with python-rtmidi tools/pos.py ...")
        self.mido = mido
        names = mido.get_output_names()
        if not names:
            sys.exit("CoreMIDI не видит ни одного выхода")
        match = [n for n in names if hint.lower() in n.lower()] if hint else names
        if not match:
            sys.exit(f"нет выхода с {hint!r}; есть: " + ", ".join(names))
        self.name = match[0]
        self.out = mido.open_output(self.name)

    def raw(self, data):
        self.out.send(self.mido.Message.from_bytes(list(data)))

    def close(self):
        self.out.close()


def main():
    ap = argparse.ArgumentParser(description="положение, эффект или транспорт")
    ap.add_argument("what", nargs="*", help="позиция 1-66, 99, или эффект")
    ap.add_argument("--port", metavar="NAME", default=None,
                    help="выход CoreMIDI, часть имени (реальная машина)")
    ap.add_argument("--fifo", metavar="PATH", default=None, help="пайп для Hatari")
    ap.add_argument("--ch", type=int, default=CH, help=f"командный канал (по умолчанию {CH})")
    ap.add_argument("-v", "--velocity", type=int, default=100,
                    help="с какой силой входить, 1-127")
    ap.add_argument("--hold", type=float, default=0.0,
                    help="секунд держать ноту: для эффектов «пока держишь»")
    ap.add_argument("--gap", type=float, default=0.0, help="секунд между кодами")
    ap.add_argument("--repeat", type=int, default=None,
                    help="сколько раз слать каждое сообщение (для --fifo по умолчанию 25)")
    ap.add_argument("--start", action="store_true", help="транспорт: start")
    ap.add_argument("--stop", action="store_true", help="транспорт: stop")
    a = ap.parse_args()

    if not a.what and not (a.start or a.stop):
        ap.error("нечего слать")
    if a.fifo and a.port:
        ap.error("или --fifo, или --port")
    if not (1 <= a.ch <= 16):
        ap.error("канал 1..16")
    if not (1 <= a.velocity <= 127):
        ap.error("velocity 1..127")

    dest = Fifo(a.fifo) if a.fifo else Port(a.port or "")
    rep = a.repeat if a.repeat is not None else (25 if a.fifo else 1)
    status = 0x90 | (a.ch - 1)

    def send(data, label):
        for _ in range(rep):
            dest.raw(data)
            if rep > 1:
                time.sleep(0.12)
        print(label)

    try:
        if a.start:
            send([START], "транспорт: start")
        for i, (code, label) in enumerate(codes(a.what)):
            if i and a.gap:
                time.sleep(a.gap)
            send([status, code, a.velocity], f"{label}, velocity {a.velocity}")
            if a.hold:
                time.sleep(a.hold)
                send([status, code, 0], f"{label}: отпустил")
        if a.stop:
            send([STOP], "транспорт: stop")
    finally:
        dest.close()


if __name__ == "__main__":
    main()
