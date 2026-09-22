# NOISE AV — Atari ST visuals for a live noise set

## Target hardware

A **1040 STF** on an **SM124** monitor:

| | |
|---|---|
| CPU | 68000 @ 8 MHz |
| RAM | 1 MB |
| Screen | 640×400, 1 bit, **71 Hz** (high res) |
| Framebuffer | 32000 bytes, 80 bytes/row |
| Blitter | **none** (STF, not STE) |
| DMA sound | **none** — YM2149 only |
| Sync input | MIDI IN (6850 ACIA, 31250 baud) |
| Loading | floppy, drive A |

The lack of a blitter is the constraint that shapes everything. A frame is
~112 000 CPU cycles. The fastest bulk write the 68000 has is `movem.l` with
eight registers: 32 bytes per ~88 cycles. A **full**-screen fill is therefore
~90 000 cycles — nearly the whole frame, with nothing left for logic. So the
rule is: *never touch the whole screen every frame.*

## Build and run

```
make          # assemble  -> dist/NOISEAV.TOS
make run      # boot Hatari straight into it (mono, 1MB ST)
make run-midi # same, with a MIDI IN pipe at /tmp/noiseav.midi
```

### Playing it from a real MIDI keyboard

```
make midi-list     # what does macOS see?
make run-live      # everything at once: keyboard AND sequencer
make run-pm        # one device only, no bridge (MIDIPORT='MPK mini 3')
```

**Use `run-live` for a real setup.** The bridge connects to *every* CoreMIDI
source and merges them into one stream, so a keyboard and a sequencer can play
together. `run-pm` skips the bridge entirely by letting Hatari talk to CoreMIDI
itself, but PortMidi opens exactly **one** port — pick the keyboard and the
sequencer is gone, and the other way round.

Both carry full MIDI throughput now that the ACIA is drained from Timer A.

Hatari expects a file or device for `--midi-in`, and macOS has no `/dev/midi`
node — CoreMIDI is an API, not a device file. So `tools/midibridge.c` pulls
bytes off CoreMIDI and pushes them into a FIFO that Hatari reads. It connects
to every MIDI source it finds and listens for `kMIDIMsgSetupChanged`, so the
keyboard can be plugged in before *or* after starting.

Two details that are easy to get wrong:

* The FIFO is opened `O_RDWR`, not `O_WRONLY`. That never blocks waiting for a
  reader and never reports EOF, so Hatari can start, stop and restart
  underneath the bridge without it noticing.
* Enabling MIDI in Hatari also opens a MIDI **output** device, which on the
  Homebrew build defaults to a Linux ALSA path and fails — taking MIDI input
  down with it. Hence `--midi-out /dev/null`.

Active sensing (`FE`) is dropped by default: it is pure keepalive chatter and
costs a BIOS trap per byte on the ST. `--keep-sensing` passes it through.

What the keys do: velocity sets scroll speed (so silence freezes the picture),
note number sets the stripe frequency, and hard hits punch noise into the field.

Without a keyboard, the synthetic generator does the same job:

```
make run-midi
```

ESC quits the show and returns to the desktop.

## Layout: core plus one file per show

```
src/core/head.s     takes over the machine, sets up the screen, runs the loop
src/core/tail.s     MIDI ACIA + ring + parser, timers, envelope, diagnostics
src/shows/*.s       one idea per file, one binary per file
src/main.s          the older all-in-one show -- left alone on purpose
```

A show includes the core around itself and supplies three entry points:

| hook | when |
|---|---|
| `show_init` | once, after the screen is set up and cleared |
| `show_frame` | once per vertical blank |
| `show_note_on` | `d0` = strength 0..255 (velocity through the curve), `d1` = pad index * 2 |

```asm
    include "src/core/head.s"
show_init:     ...  rts
show_frame:    ...  rts
show_note_on:  ...  rts
    include "src/core/tail.s"
    section bss
my_state:  ds.w 1
```

```
make shows                      # build every show
make run-show SHOW=SPARKS       # run one
make run-show-live SHOW=SPARKS  # run one with all MIDI devices
```

Any key is a full-strength hit on one of the eight pads, so a show can be
driven with nothing plugged in.

**Caveat worth knowing:** `src/core/` was copied out of `src/main.s` rather
than extracted from underneath it, so the two share code by duplication for
now. That was deliberate — `main.s` is the show that works and it was not
worth risking a refactor. Once a show on the core has earned its keep,
`main.s` should be ported onto it and the copy deleted.

### Shows

| show | idea |
|---|---|
| `SPARKS` | each pad throws a burst of particles from its cell; they arc under gravity and die at the edges. Single pixels, so ~20 000 cycles for 160 particles |
| `GLYPHS` | lines of text marching up a hardware-scrolled field; pads pick the line, hard hits chew it |
| `SHAPES` | the cubes show with a different solid per pad — cube, cut stone, octahedron, plus, tetrahedron, star, hex prism, pyramid |
| `VECTORS` | the same eight solids, drawn from vertex tables instead of bitmaps, filling their cells |

#### VECTORS: what filling the cell actually costs

Bitmaps cost **area**, which is what capped `SHAPES` at a 96×96 box. Vertex
tables cost almost nothing — eight solids at eight scales and thirty-two
angles is **48 KB** against 648 KB of sprites — so here the figures are 144 px
in a 160 px cell. The price is that the ST draws the lines itself.

Measured, against `drums.py` at 110 BPM:

| drawing strategy | overruns per 64 frames |
|---|---|
| one whole cell per frame | **40** |
| blank + a full 32-edge batch in one frame | **45** |
| blank on its own frame, then 24 edges per frame | **0** |

So the work is capped: a cell is blanked on one frame and strokes in over the
next one or two. With all eight cells moving, a full pass is about 19 frames —
roughly **4 Hz**. Cells at rest are not redrawn at all, so when only a few
pads are being played the ones that move refresh far faster.

That is the real trade-off, and it is the machine's answer rather than a
shortcut:

* `VECTORS` — figures fill the cell, whole grid redraws at ~4 Hz
* `SHAPES` — figures are 96 px, everything moves at 71 Hz

Two things that turned out to matter more than expected: blanking the cell is
expensive enough to need its own frame (and `clr.l` to memory costs 20 cycles
where `move.l` from a zeroed register costs 12), and a figure never reaches
more than 76 rows from the cell centre, so 40 of the cell's 200 rows never
need clearing.

#### SHAPES and the memory budget

Eight solids baked by `tools/genshapes.py`. Sizing is the whole design
problem, because sprite data grows with **area**: eight solids at eight
scales and twelve angles is 384 KB in a 64×64 box and 864 KB in a 96×96 one.

64×64 fitted easily and looked mean — the figures were far too small. So the
set is now the cubes' 96×96 box with **six** scales instead of eight: 648 KB.
The pulse loses a little resolution rather than the figures losing half their
size, and the show hands back the core's noise pool and scroll buffer
(`POOL_SIZE`, `RANGE_PAGES`) to pay for it.

The other half of "too small" was the scale range. It ran 0.40–1.00, so a
figure at rest was 40% of full size, and since the envelope decays quickly
most cells sat near the bottom of that range most of the time. It is now
0.72–1.00: always substantial, with the swell on top.

Measured zero frame overruns.

Two 68000 traps worth remembering, both found by looking at the screen:

Two 68000 traps worth remembering, both found by looking at the screen:

* `divu` divides the **whole 32-bit register**. Masking only the low word
  left stale bits in the high word, which corrupted the angle and indexed a
  random sprite — one cell rendered as vertical bars. Worse, if the quotient
  overflows 16 bits `divu` leaves the register untouched, so the failure is
  silent.
* The flat solids (plus, star) vanish into a single line when seen edge-on,
  so they are extruded deeper than looks right on paper.

**96 px is the ceiling for pre-baked sprites.** Bigger figures need the
rotation drawn on the ST from baked *vertex* tables instead of bitmaps — data
drops to about 36 KB and the figures could fill the cells, but it means
real-time line drawing, which only fits if cells are redrawn when they
actually move rather than every frame.

#### GLYPHS and the shear

The moire field got away with the screen base register's 256-byte step — 3
rows plus 128 pixels of shear — because stripe patterns repeat every 16
pixels, so the sideways part cancelled exactly. Text has no such luck; it
would be sliced into ribbons.

But `lcm(256, 80) = 1280` bytes, which is **exactly 16 rows and no shear at
all**. So the font is 16 pixels tall and one base step advances precisely one
line of text. The scroll is line-by-line rather than smooth, which suits a
wall of text better than a glide anyway.

The font is the ST's own 8×16 system font, found through Line-A by scanning
the three font headers for the one whose `form_height` is 16 — no font data in
the binary at all.

Erosion is a one-shot flag consumed by the next line printed, not a decaying
counter. Decaying it over frames left the text permanently eaten, because hits
arrive far more often than lines are printed.

The text itself is a table at the bottom of `src/shows/glyphs.s`, one line per
pad. It is meant to be edited.

## Scenes (src/main.s, the all-in-one show)

The show is **scene 1, the cubes**. Keys `1`-`5` switch; `0` re-enables
auto-cycling; `ESC` quits. Any other key is a manual hit, so you can drive it
without a MIDI cable.

| # | Scene | Status |
|---|-------|--------|
| 1 | **Cubes** | the show |
| 2 | Moire field | kept |
| 3 | Moire, full redraw | reference |
| 4 | Band | reference |
| 5 | Strobe plate | reference |

### Scene 1: cubes

A 4x2 grid of wireframe cubes laid out to match the controller's pads: pad 1
is top-left, pad 8 is bottom-right. Hitting a pad swells its cube and spins it
faster; the swell decays back down.

The rotation is **not** computed on the ST. Line-drawing 8 cubes costs roughly
90 000 of the frame's ~112 000 cycles before erasing anything, so the frames
are baked by `tools/gencubes.py` into 128 sprites (8 scales x 16 angles) and
the ST only copies them. Each tile is opaque and covers the cube's whole box,
so there is no erase pass at all: one write per cube per frame.

### Velocity

MPK pads bunch their dynamics up at the bottom and then pin at the top. A real
take gave `11, 18, 26, 33, 37, 41, 52, 83, 93, 101` and then six hits at `127`.
A linear map therefore wastes the whole soft half — velocity 11 landed on scale
zero, so a third of the hits did nothing visible at all.

Velocity now goes through `vel_tbl`, which is `255*(v/127)^0.65`. That lifts a
gentle tap to scale 1-2 and still leaves the top of the range intact.

| velocity | 11 | 26 | 41 | 52 | 83 | 101 | 127 |
|---|---|---|---|---|---|---|---|
| curved | 52 | 91 | 122 | 143 | 193 | 220 | 255 |
| was (linear) | 22 | 52 | 82 | 104 | 166 | 202 | 254 |

Glitches:

* above `GLITCH_VEL` (on the curved value) the cube tears into horizontal
  slabs for a few frames
* the whole-picture shear runs off **accumulated** energy rather than a single
  hit, because the pads saturate at 127 and cannot tell hard from very hard —
  density still carries information. It fires as a short burst with a lockout;
  held on continuously it just reads as broken sync rather than an accent

Two things the tearing code has to get right, both learned the hard way:

* The shift must be **even**. A `move.l` to an odd address is an address error
  on a 68000, so an odd shift crashes the machine the first time anyone hits a
  pad hard.
* It shifts what is **read**, not where it is written. Moving the destination
  smears pixels outside the cube's box, and since tiles are opaque only over
  their own box, nothing ever erases them again.

Regenerate the sprites (and a contact-sheet preview) with:

```
python3 tools/gencubes.py
```

### Frame budget

A mono frame is ~112 000 cycles at 8 MHz. `movem.l` with eight registers moves
32 bytes per ~88 cycles, so a *full*-screen fill is ~90 000 cycles — nearly the
whole frame. Build with `-DDIAG=1` to get a bar on the top row showing how many
of the last 64 frames overran their budget; `-DSTARTSCENE=n` boots straight into
one scene, `-DAUTOCYCLE=1` restores cycling, and `-DFORCEGLITCH=1` tears every
cube every frame so the glitch path can be exercised without depending on MIDI.
The DIAG build also draws a second bar four rows down: MIDI bytes consumed in
the last 64 frames. An empty second bar means nothing is reaching the ACIA at
all, which separates a delivery problem from a parsing one. The build compares the system VBL
counter at `$462` against its own frame count, so it catches any frame that took
longer than one.

Measured on the machine:

| Scene | Computed cost | Overruns / 64 frames |
|-------|---------------|----------------------|
| 1 Cubes | 8 tiles x 96 rows, ~66 000 cycles | 0 |
| 1 Cubes, all 8 tearing at once | ~72 000 cycles | 0 |
| 2 Moire field | 1 400 cycles at one page/frame, ~9 900 flat out, 0 frozen | 0-1 |
| 3 Moire, full redraw | ~43 000 cycles | 0-2 |
| 4 Band | ~79 000 cycles worst case | 0-1 |
| 5 Strobe plate | one word write | 0-1 |

Even the near-free scenes report 0-1 per 64, so roughly one in sixty-four is
baseline jitter rather than the cost of an effect.

The tearing blit originally recomputed its shift on every row and overran
*every* frame with all eight cubes torn. Hoisting that out to one shift per
eight rows made the inner loop identical to the plain blit and took it to zero.

Note that driving MIDI into headless Hatari is unreliable: the emulator does
not run at wall-clock speed, so a host-side feeder delivers bytes in bursts
with gaps long enough for the free-run fallback to cut in. Verify MIDI-driven
behaviour on hardware, or with `-DFORCEGLITCH=1` style build flags that remove
MIDI from the loop.

## Known limits, and what they cost

1. ~~MIDI goes through the BIOS~~ — **done**, see below.
2. **Single buffered**, so fast changes tear. Fix: two framebuffers, flip on
   the screen base register. Costs 32 KB.
3. **Erase-then-fill overdraws** the overlap in the Band scene.
4. Tested against **EmuTOS 1.4.0**; the real machine runs Atari TOS 1.04 (DE).
   All calls used are standard TOS 1.x, but confirm on hardware.

## MIDI input

The program reads the 6850 MIDI ACIA directly, into a 256-byte ring buffer,
rather than going through the BIOS. Two reasons.

The BIOS costs a `trap` per byte, which will not survive MIDI clock at 24 ppqn
alongside notes.

More urgently, **it does not work**. Under EmuTOS, bytes arrive in the 6850 and
sit there with RDRF stuck on, because nothing services the receive interrupt,
so `Bconstat(3)` reports an empty buffer forever. This was measured, not
guessed: the DIAG build carries three bars — frame overruns, bytes consumed by
the program, and bytes visible in the 6850 itself. With the BIOS path the third
bar was solid and the second was flat zero, with a no-MIDI control run showing
the third bar empty to prove the probe meant something.

What it takes to actually receive a byte:

* set the ACIA control register to `$95` (/16, 8N1, receive interrupt on)
* enable MFP channel 6 in `IERB` and `IMRB` — it is shared with the keyboard
* install a handler on the vector at `$118`, drain the ACIA into the ring, then
  chain to the previous handler so the keyboard keeps working
* **drain any byte already sitting in the ACIA when installing.** A stuck RDRF
  means there is no fresh edge to interrupt on, and one unread byte jams the
  port permanently. This is what made it look like "MIDI worked the first time
  and never again"
* **clear the channel's bit in `ISRB` before returning.** The ST's MFP runs in
  software end-of-interrupt mode, so a handler that does not clear its
  in-service bit fires exactly once and never again
* drain from the 200 Hz Timer C tick as well, as a safety net
* and, because the interrupt does not fire under Hatari at all, run **Timer A
  at 4 kHz** purely to empty the ACIA. A MIDI byte takes 320 us at 31250 baud,
  so a sweep every 244 us cannot miss one. Costs about 2% of the CPU and
  measured zero frame overruns; on real hardware it is a redundant safety net

### What does not work, and why

Under Hatari's file-based MIDI the ACIA interrupt is **never raised at all** —
measured directly, the interrupt counter stays at zero while bytes are visibly
arriving in the 6850. Everything the program receives comes from polling.

Polling can only lift **one byte out of each burst**: a three-byte message
crosses the wire in about a millisecond, and only one byte is ever visible
before the next overwrites it. Raising the poll rate does not help — going from
once per frame (71 Hz) to Timer C (200 Hz) changed the measured throughput not
at all, 13 bytes per 64 frames both times.

That was the state with polling at frame rate. Measured against `drums.py` at
110 BPM, which sends about 62 bytes/s:

| draining from | bytes received per 64 frames (56 expected) |
|---|---|
| once per frame, 71 Hz | 13 |
| Timer C, 200 Hz | 13 — no change |
| Timer A, 4 kHz | **45-60** |

200 Hz changes nothing because bytes arrive every 320 us; you have to look
faster than they arrive, not merely more often than once a frame. At 4 kHz
the sequencer comes through essentially intact.

This is an emulator limitation, not a fault in the ST code. Everything the ST
side controls was checked and is correct:

| checked | result |
|---|---|
| ACIA control register | `$95`, receive interrupt on — confirmed in Hatari's own trace |
| ACIA IRQ line | asserted per byte — `midi update irq irq_new=1` in the trace |
| MFP `IERB` bit 6 | set |
| MFP `IMRB` bit 6 | set |
| MFP `ISRB` bit 6 | cleared (software EOI) |
| MFP `AER` bit 4 | cleared (falling edge) |
| vector `$118` | hooked |
| MFP `IPRB` bit 6 | **never pending** |
| our handler | **never runs** |

The ACIA asks for an interrupt and the MFP never latches it. EmuTOS's own
handler is equally never reached — at boot EmuTOS sets `cr=0x95`, the IRQ line
goes high, and the byte then sits unread for eight hundred VBLs until our code
drains it by polling.

On real hardware the MIDI ACIA does raise MFP channel 6 — that is how every ST
MIDI program works — so dense MIDI has to be tested on the machine.

### Building Hatari with PortMidi

```
tools/build-hatari-pm.sh      # then: make run-pm
```

Homebrew's Hatari is built without PortMidi, which leaves only the file-based
`--midi-in`/`--midi-out` options and the bridge. A PortMidi build talks to
CoreMIDI directly: no bridge, no FIFO, and Hatari reads whole messages.

It does **not** fix the interrupt problem above — the ST still only sees about
one byte per burst — but it removes two moving parts from the chain.

One trap when building: Hatari defaults to a universal arm64 + x86_64 build on
macOS while Homebrew's portmidi is arm64 only. The x86_64 slice fails to link,
CMake's symbol check fails, and portmidi is reported as simply "not found".
`-DCMAKE_OSX_ARCHITECTURES=arm64` is the fix.

## Safety

Scene 4 flashes the whole screen. It is gated on the envelope and limited to a
toggle every 8 frames (~8.9 Hz), deliberately under the 15-25 Hz band where
photosensitive seizure risk peaks. The register can flip every frame at 71 Hz.
It should not.

## Roadmap

* **M3 — commit to a visual language.** Pick the scenes that earn their place,
  then push them properly.
* **M4 — solid framework.** ACIA interrupt handler + ring buffer, double
  buffering, and a bootable `.ST` floppy image for the real machine.
* **M5 — performance control.** MIDI channels/CCs mapped to scenes and
  parameters so it is playable, not just reactive.
