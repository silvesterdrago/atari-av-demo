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

Done so far: `SPARKS`, `GLYPHS`, `SHAPES`.

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

* **Standalone scroll field** — became the layer underneath the moire rather
  than a scene of its own, which is what made the moire cheap.
* **Bootable `.ST` floppy image** — delivery is solved via TOS on microSD.
  Worth remembering that TOS only auto-runs `*.PRG` from an `AUTO` folder, so
  autostart means renaming the extension; the bytes are identical.
* **Colour modes** — the machine runs an SM124, so mono is the target. The
  code still detects the mode and runs in low-res, but nothing is designed
  for it.
