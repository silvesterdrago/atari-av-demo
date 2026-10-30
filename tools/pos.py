#!/usr/bin/env python3
"""Send a position, an effect or transport to the show, on the control channel.

    tools/pos.py 18                 # position 18: the corridor
    tools/pos.py 15 16 --gap 4      # walk two positions, four seconds apart
    tools/pos.py strobe             # effect: the strobe on or off
    tools/pos.py freeze --hold 2    # effect held for two seconds
    tools/pos.py --rate 16          # the strobe's period, in frames
    tools/pos.py --start            # transport start: back to a known state
    tools/pos.py --ramp 8           # CC 4 up and down over 8 s: where the
                                    # picture starts to dirty, and its ceiling
    tools/pos.py --monitor IAC      # print what Live is actually sending

The code IS the position in the storyboard, so `18` means their frame 18 and
nothing else has to be looked up. ARC.TOS answers 1-66 and 99; a build that
does not know a position ignores it.

Two destinations:

    --list            print the CoreMIDI outputs and stop, to find the name
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
CC_STROBE = 1           # and CC_STROBE in src/core/tail.s
CC_FOLLOW = 4           # and CC_FOLLOW: the envelope follower's level
FOLLOW_CLEAN = 5        # at or under this the ST clears the picture entirely
HIT_CH = 10             # where drums.py and the pads play
PAD_BASE = 36           # and PAD_BASE in src/core/head.s
PER_MIN, PER_MAX = 12, 40       # STROBE_HALF and STROBE_MAX, in frames
VBL = 71.2
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


class In:
    """An input, to read what Live sends rather than to send anything.

    Setting the follower by ear is two thresholds -- silence has to read 5 or
    under, the loudest moment 120 or over -- and neither is visible from the
    Atari, which only shows their consequences. So this prints the numbers.
    """

    def __init__(self, hint):
        try:
            import mido
        except ImportError:
            sys.exit("нет mido: запусти команду через\n"
                     "  uv run --with mido --with python-rtmidi")
        names = mido.get_input_names()
        match = [n for n in names if hint.lower() in n.lower()] if hint else names
        if not match:
            sys.exit(f"нет входа с {hint!r}; есть: " + ", ".join(names) or "ничего")
        self.port = mido.open_input(match[0])
        self.name = match[0]

    def run(self):
        print(f"слушаю {self.name}; Ctrl-C чтобы выйти")
        peak, floor = 0, 127
        try:
            for m in self.port:
                if m.type == "control_change":
                    if m.control == CC_FOLLOW:
                        peak = max(peak, m.value)
                        floor = min(floor, m.value)
                        print(f"\rCC {m.control} ch{m.channel + 1} = {m.value:3}"
                              f"   за всё время: низ {floor}, верх {peak}   ",
                              end="", flush=True)
                    else:
                        print(f"\nCC {m.control} ch{m.channel + 1} = {m.value}")
                elif m.type in ("note_on", "note_off"):
                    v = getattr(m, "velocity", 0)
                    print(f"\n{m.type} ch{m.channel + 1} нота {m.note} vel {v}")
        except KeyboardInterrupt:
            print(f"\nниже всего {floor}, выше всего {peak}")


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
    ap.add_argument("--hit", type=int, nargs="?", const=8, metavar="N",
                    help=f"N ударов по каналу {HIT_CH}: проверка, доходит ли "
                         "MIDI вообще -- удары понимает любая сборка")
    ap.add_argument("--rate", type=int, metavar="FRAMES", default=None,
                    help=f"период строба в кадрах, {PER_MIN}-{PER_MAX} "
                         f"({VBL/2/PER_MIN:.1f}-{VBL/2/PER_MAX:.1f} Гц)")
    ap.add_argument("--cc", nargs=2, type=int, metavar=("N", "V"), default=None,
                    help="сырой контроллер: номер 0-7 и значение 0-127")
    ap.add_argument("--ramp", type=float, nargs="?", const=8.0, metavar="SEC",
                    help="прогнать CC 4 от 0 до 127 и обратно за SEC секунд: "
                         f"ниже {FOLLOW_CLEAN} картинка обязана быть чистой")
    ap.add_argument("--monitor", nargs="?", const="", metavar="NAME",
                    help="слушать вход CoreMIDI и печатать, что приходит")
    ap.add_argument("--list", action="store_true",
                    help="перечислить выходы CoreMIDI и выйти")
    ap.add_argument("--start", action="store_true", help="транспорт: start")
    ap.add_argument("--stop", action="store_true", help="транспорт: stop")
    a = ap.parse_args()

    if a.list:
        try:
            import mido
        except ImportError:
            sys.exit("нет mido: запусти через\n"
                     "  uv run --with mido --with python-rtmidi tools/pos.py --list")
        for n in mido.get_output_names():
            print(n)
        return
    if a.monitor is not None:
        In(a.monitor).run()
        return
    if not a.what and not (a.start or a.stop or a.rate or a.cc or a.hit
                           or a.ramp):
        ap.error("нечего слать")
    if a.rate is not None and not (PER_MIN <= a.rate <= PER_MAX):
        ap.error(f"период {PER_MIN}..{PER_MAX} кадров; короче нельзя, "
                 "нижняя граница зашита в ядре")
    if a.cc and not (0 <= a.cc[0] <= 7 and 0 <= a.cc[1] <= 127):
        ap.error("CC: номер 0-7, значение 0-127")
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

    ctl = 0xB0 | (a.ch - 1)
    try:
        if a.start:
            send([START], "транспорт: start")
        if a.rate is not None:
            # the ST does per = PER_MIN + v*(PER_MAX-PER_MIN)//127 in INTEGER
            # arithmetic, so the inverse has to round up: rounding down asks
            # for a shorter period than requested, and a shorter period is
            # more flashes a second, which is the one direction that is not
            # ours to give away
            span = PER_MAX - PER_MIN
            v = min(127, -((-(a.rate - PER_MIN) * 127) // span))
            got = PER_MIN + (v * span) // 127
            send([ctl, CC_STROBE, v],
                 f"период строба {got} кадров, {VBL/2/got:.2f} Гц "
                 f"(CC {CC_STROBE} = {v})"
                 + ("" if got == a.rate else f" — ближайшее к {a.rate}, шкала грубее"))
        if a.cc:
            send([ctl, a.cc[0], a.cc[1]], f"CC {a.cc[0]} = {a.cc[1]}")
        if a.ramp:
            # 20 Hz, which is the rate a follower in Live is asked to send at
            steps = max(2, int(a.ramp * 20) // 2)
            seq = list(range(0, 128, max(1, 128 // steps)))
            for v in seq + seq[::-1]:
                dest.raw([ctl, CC_FOLLOW, v])
                print(f"\rCC {CC_FOLLOW} = {v:3}", end="", flush=True)
                time.sleep(a.ramp / (2 * len(seq)))
            dest.raw([ctl, CC_FOLLOW, 0])
            print(f"\nпрогон окончен; чисто должно быть при {FOLLOW_CLEAN} и ниже")
        if a.hit:
            # the oldest path there is, and the one every build understands:
            # if this does nothing either, no MIDI is reaching the machine
            st = 0x90 | (HIT_CH - 1)
            for i in range(a.hit):
                dest.raw([st, PAD_BASE + (i % 8), 120])
                time.sleep(0.15)
                dest.raw([st, PAD_BASE + (i % 8), 0])
                time.sleep(0.1)
            print(f"{a.hit} ударов по каналу {HIT_CH}, ноты "
                  f"{PAD_BASE}..{PAD_BASE + 7}")
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
