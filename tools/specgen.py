#!/usr/bin/env python3
"""Keep CONTROL.md's tables generated from the source, not written by hand.

    python3 tools/specgen.py            # rewrite the generated blocks
    python3 tools/specgen.py --check    # fail if they are out of date

Another session writes the arrangement against CONTROL.md, so a number that
has drifted there costs somebody a rehearsal. Everything a sequencer has to
know -- the control channel, the effect codes, the controllers, and which
position is what -- is read out of src/core/*.s and src/arc.s and written
between the markers below. Prose outside them is ours to write.

`make card` runs --check, so a card cannot be built against a stale spec.
"""
import re
import sys

DOC = "CONTROL.md"
CORE = ("src/core/head.s", "src/core/tail.s")
ARC = "src/arc.s"
FILES = ["CORRIDOR", "TUNNEL", "WAVE", "DESYNC", "DRIFT", "FLOOR",
         "TUNPLAIN", "BRANCH", "PIT", "PITBOLD", "WALLS", "EXPAND"]

# What each effect code is for, in Russian; the numbers come from the source.
FX_TEXT = {
    "FX_STROBE":  ("строб вкл/выкл", "не нужно"),
    "FX_STROBEH": ("строб, пока держишь", "note-off гасит"),
    "FX_SYNC":    ("строб по долям, пока держишь", "note-off гасит"),
    "FX_FREEZE":  ("стоп-кадр, пока держишь", "note-off отпускает"),
    "FX_FLASH":   ("один инвертированный кадр", "не нужно"),
    "FX_INVERT":  ("инверсия, пока держишь — без мигания", "note-off гасит"),
    "FX_SHIFT":   ("сдвиг картинки, пока держишь", "note-off возвращает"),
    "FX_NOISE":   ("полоски шума поверх картинки, пока держишь", "note-off убирает"),
    "FX_REVERSE": ("петля назад, пока держишь", "note-off возвращает"),
    "FX_HALF":    ("петля вполовину скорости, пока держишь", "note-off возвращает"),
}
CC_TEXT = {
    "CC_STROBE": "период строба, 0–127 → {STROBE_HALF}–{STROBE_MAX} кадров",
    "CC_SHIFT":  "потолок сдвига {FX_SHIFT}, до {SHIFT_MAX} страниц по 256 байт",
    "CC_NOISE":  "потолок шума {FX_NOISE}, до {NOISE_MAX} полосок",
    "CC_FOLLOW": "огибающая из Live: пол под скоростью петли и под разломом",
}
# The names the positions go by, so the table reads as their storyboard does.
POS_TEXT = {1: "чёрное", 2: "точка", 3: "линия", 4: "две линии", 5: "квадрат",
            6: "тонкий крест", 7: "жирный крест", 8: "бабочка", 9: "жирный X",
            10: "горизонтали", 11: "вертикали", 13: "пол", 14: "пол с бруском",
            15: "вложенные квадраты", 16: "ступени", 17: "туннель",
            18: "коридор", 19: "туннель без панелей", 20: "комната",
            21: "развилка", 22: "провал тонкий", 23: "провал жирный",
            24: "множественные пространства A", 25: "стены и пол",
            26: "расширение", 40: "волна", 43: "блуждающая ось", 44: "рассинхрон",
            49: "развал коридора", 50: "развал туннеля", 52: "дыры в коридоре",
            27: "наклонённые квадраты", 28: "двойная перспектива A",
            29: "двойная перспектива B", 30: "коридор в коридоре",
            31: "скрещенные плоскости", 32: "плоскости сбоку", 33: "горка",
            34: "яма", 35: "спираль", 36: "шестигранный туннель",
            37: "вихрь", 38: "слои", 39: "сложные структуры", 41: "лучи",
            58: "сжатие", 59: "квадрат", 60: "четыре угла", 61: "две линии",
            62: "одна линия", 63: "тире", 64: "точка", 65: "чёрное"}


def equs(paths):
    out = {}
    for p in paths if isinstance(paths, tuple) else (paths,):
        for line in open(p):
            m = re.match(r"^([A-Z_][A-Z0-9_]*)\s+equ\s+(\d+)", line)
            if m:
                out.setdefault(m.group(1), int(m.group(2)))
    return out


def positions():
    src = open(ARC).read()
    body = src[src.index("pos_tbl:"):src.index("name_tbl:")]
    vals = []
    for line in body.splitlines():
        m = re.match(r"\s*dc\.w\s+([^;]+)", line)
        if m:
            vals += [int(v.strip()[1:], 16) for v in m.group(1).split(",")
                     if v.strip().startswith("$")]
    assert len(vals) == 66, f"pos_tbl has {len(vals)} entries, not 66"
    return vals


def blocks():
    c = equs(CORE)
    a = equs(ARC)
    fx = {**{k: c[k] for k in FX_TEXT if k in c}, **{k: a[k] for k in FX_TEXT if k in a}}
    assert len(fx) == len(FX_TEXT), f"effects missing from the source: {set(FX_TEXT) - set(fx)}"

    lines = ["| что | где | как читается |", "|---|---|---|",
             f"| удары | любой канал, **кроме** {c['CTRL_CH']} | нота → `(нота − {c['PAD_BASE']}) & 7`, velocity → сила |",
             f"| команды | **канал {c['CTRL_CH']}** | нота → код, velocity → сила входа |",
             "| транспорт | вне каналов | `$FA` start, `$FC` stop, `$F8` clock |", "",
             "| код | эффект | отпускание |", "|---|---|---|"]
    for name, code in sorted(fx.items(), key=lambda kv: kv[1]):
        what, off = FX_TEXT[name]
        lines.append(f"| {code} | {what} | {off} |")
    lines += ["", "| CC | что |", "|---|---|"]
    for name, text in sorted(CC_TEXT.items(), key=lambda kv: c[kv[0]]):
        lines.append(f"| {c[name]} | {text.format(**{**c, **fx})} |")
    codes = "\n".join(lines)

    vals = positions()
    inst, still, card = [], [], []
    for i, v in enumerate(vals, 1):
        if not v:
            continue
        kind, idx = v >> 8, v & 0xFF
        name = POS_TEXT.get(i, "?")
        if kind == 1:
            inst.append(f"| {i:02} | {name} |")
        elif kind == 6:
            still.append(f"| {i:02} | {name} | экран {idx} |")
        else:
            note = {2: "", 3: ", тот же что у 13", 4: " + разлом",
                    5: " + вырезы"}[kind]
            card.append(f"| {i:02} | {name} | `{FILES[idx]}.DAT`{note} |")
    pos = ("**Морф — переключение в один кадр, данных нет:**\n\n"
           "| поз | что |\n|---|---|\n" + "\n".join(inst) +
           "\n\n**Статика — чтение одного экрана из `STILLS.DAT`, ~85 мс:**\n\n"
           "| поз | что | где |\n|---|---|---|\n" + "\n".join(still) +
           "\n\n**Петли — вход стоит чтения 768 КБ, около двух секунд:**\n\n"
           "| поз | что | файл |\n|---|---|---|\n" + "\n".join(card) +
           f"\n\nПлюс {a['SAFE_POS']} — страховочная точка на чёрном. "
           "Остальные коды 1–66 не делают ничего.")
    return {"codes": codes, "positions": pos}


def main():
    check = "--check" in sys.argv
    doc = open(DOC).read()
    new = doc
    for name, body in blocks().items():
        a, b = f"<!-- {name}:start -->", f"<!-- {name}:end -->"
        if a not in new or b not in new:
            sys.exit(f"{DOC}: нет маркеров {a} / {b}")
        head, rest = new.split(a, 1)
        _, tail = rest.split(b, 1)
        new = f"{head}{a}\n{body}\n{b}{tail}"
    if new == doc:
        print(f"{DOC}: сходится с исходниками")
        return
    if check:
        sys.exit(f"{DOC} устарел: прогони `python3 tools/specgen.py`")
    open(DOC, "w").write(new)
    print(f"{DOC}: таблицы перегенерированы")


if __name__ == "__main__":
    main()
