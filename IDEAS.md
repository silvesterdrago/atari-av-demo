# Ideas

A running list. Nothing here is committed to; it is the pile we pick from.
Things move out of here into the code, or down into *Parked* with a reason.

---

## Next up

### The eight knobs
The MPK mini 3 has eight rotary encoders sending CC, and we ignore `$B0`
entirely right now. Pads give discrete gestures; knobs give continuous
parameters, which is what turns this from reactive into playable.

Candidates to map: glitch threshold, stripe frequency range, envelope decay
rate, scroll speed floor, shear lockout, how much noise a hard hit punches in.

This used to be blocked on the MIDI path — a knob sweep is dozens of messages
per second and the BIOS cost a `trap` per byte. Since we read the ACIA
ourselves into a ring buffer, that objection is gone.

Worth checking first: are the knobs absolute or relative, and on which CC
numbers. `tools/midibridge -v` will say.

### A better glitch trigger
The cube tear fires on about 40% of hits, because the pads pin at 127 and
"hard" cannot be distinguished from "very hard". Options that sidestep
saturation entirely:

* two pads struck close together
* the same pad struck twice quickly
* one pad reserved as a dedicated glitch pad
* a knob setting the threshold live, so it is tunable mid-set

### MIDI clock
`$F8` at 24 ppqn is already parsed and currently only nudges the envelope.
Tempo-locked behaviour would lock the visuals to the rest of the rig: rotation
stepping on the beat, shear on the bar, decay measured in sixteenths rather
than frames.

---

## Building shows

Each idea is now its own file in `src/shows/` on top of `src/core/`, building
its own binary. See the README for the three hooks. Adding an idea means one
file and nothing else — no scene tables, no touching a working show.

Done so far: `SPARKS`, `GLYPHS`, `SHAPES`, `SOLIDS`. `VECTORS` is parked.

## Filled solids, not wireframes

The lesson from `VECTORS` failing, and from looking at what STe mono demos
actually put on screen: **outlines are the most expensive way to cover a
screen and the hardest to read.**

An outline costs roughly 50 cycles a pixel — a byte read, an OR, a mask
rotate, Bresenham bookkeeping, all for one pixel. A filled span costs about
one cycle a pixel, because a word write covers sixteen of them. That is a
factor of fifty, and it is why demos draw *filled* polygons with ordered
dither as shading rather than wireframes.

For this project that means: same solids, but draw their faces filled with
dither patterns. A 60x60 face is about 5 000 cycles; a solid showing three
visible faces is 15 000; four solids fit in a frame with room left.

Two things make it cheaper still, and both are free:

* **Bake the visible-face list per pose.** The generator already knows every
  vertex position at every angle, so it can work out which faces point at the
  camera and store that list. Backface culling then costs nothing at runtime.
* **Draw the cell off-screen and copy it in.** A solid takes ~1.8 frames, so
  the beam catches cells mid-redraw: a chunk missing, or briefly blank. A
  4000-byte shadow buffer and a row copy fixes it for about 25 000 cycles. I
  tried this and broke it — the program died on the fifth cell and I reverted
  rather than thrash further, so it needs doing properly.
* ~~Fill quads as quads~~ — **done, and it barely helped.** Only the cube,
  slab and hex prism have quads; the rest of the set is triangles already. The
  grid still refreshes at ~4 Hz.
* **Fewer, bigger solids.** This is the real lever, and it is a design choice
  rather than an optimisation. Eight big shaded solids is more than an 8 MHz
  68000 will redraw quickly. Four cells doubles the rate; one large solid
  centre-screen would run at full speed, with the pads choosing which solid
  and how it spins.
* **Bake the spans, not the vertices.** For a fixed set of poses the generator
  could emit, per face, the left and right x for each row — then the ST does
  nothing but write words.

## Visual material

### Strobe as a modifier, not a scene
Palette register `$FF8240` inverts the whole mono display for one word write.
It is currently scene 5, which is the wrong shape — it should be a modifier
that can sit over *any* scene. See the safety note in the README before
wiring it to anything fast.

### Deliberate diagonal drift
The screen base register steps 256 bytes: three rows down and 128 pixels
sideways. In the moire field that shear is cancelled on purpose, because the
stripe patterns repeat every 16 pixels. Writing pages with an offset instead
would turn it into a controlled diagonal crawl.

---

## Technical debt

### Double buffering
Single buffered, so fast changes tear. Two framebuffers flipped on the screen
base register; costs 32 KB, which is affordable in 1 MB. Not urgent while the
cubes scene is the show, since opaque tiles hide most of it.

### Confirm the ACIA handler on real hardware
Our handler chains to the previous one so the keyboard keeps working, and it
is only tested against EmuTOS. TOS 1.04 may differ — verify on the machine.

---

## Open questions

* **Does the keyboard still work** after we took over the `$118` vector? It
  should — we chain — but this has not been confirmed on hardware. Keys
  `1`-`5` and `ESC` are the test.
* **Is the glitch too frequent** at the current threshold, played for real?
* **Does the show need more than one scene** in practice, or is one deep
  scene with good control better than five shallow ones?

---

## Parked

* **`VECTORS` — wireframes drawn in real time.** Filling the cell works and the
  data is tiny, but capping the work per frame means a figure visibly comes
  apart as it is redrawn: some edges are a frame or two behind the rest. A cube
  survived that; the star, plus and cut stone became a heap of pixels. The
  outline was the wrong primitive — see *Filled solids* above. The source is
  still in `src/shows/` but the idea is closed.

* **Standalone scroll field** — became the layer underneath the moire rather
  than a scene of its own, which is what made the moire cheap.
* **Bootable `.ST` floppy image** — delivery is solved via TOS on microSD.
  Worth remembering that TOS only auto-runs `*.PRG` from an `AUTO` folder, so
  autostart means renaming the extension; the bytes are identical.
* **Colour modes** — the machine runs an SM124, so mono is the target. The
  code still detects the mode and runs in low-res, but nothing is designed
  for it.

## Бюджет на одно большое тело (измерено, не прикинуто)

Валюта — строки спанов, а не грани и не пиксели. Ширина почти бесплатна:
строка стоит ~1150 циклов постоянных затрат и ~3 цикла на байт, значит
**~97 строк на кадр** — это весь бюджет.

Стоимость фигуры не зависит от масштаба: `строк = k * высота`, где
`k ≈ видимых граней / 2 + 0.5`. Куб 2.15, алмазик 4.02, октаэдр 3.01,
тетраэдр 2.00 (по худшему углу, а не по среднему). Отсюда главное:
**высота × видимые грани ≈ константа**.

Жёсткий потолок сверху, до всякой геометрии: тронуть 32000 байт экрана
один раз = 99k циклов = 0.89 кадра. Фигура во весь экран не может
обновляться чаще ~35 Гц ничем и никогда.

Двойка взята: 729 циклов на строку спана стало 379, а тело перестало
платить за очистку всей клетки. Куб 1.84 -> 0.91 кадра, алмазик
1.66 -> 0.81. Оба укладываются в один кадр при высоте ~110 px.

Осталось про одно большое тело:

- Очистка по боксу для фигуры во весь экран это ~0.8 кадра. Дешевле
  писать каждый байт бокса ровно один раз (фон слева и справа от
  силуэта тем же проходом): силуэт выпуклый, так что генератор может
  отдать его отдельной парой цепочек. Для клетки это не выгодно
  (очистка байта ~10 циклов против ~250 на строку спанов), а для
  экрана выгодно вдвое.
- Двойная буферизация убирает артефакт разрыва, стоит 64 КБ из 1 МБ.
