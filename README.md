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
make run-live      # bridge + emulator, play the keys
```

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

## Scenes

The show is **scene 1, the moire field**. Keys `1`-`4` switch; `0` re-enables
auto-cycling; `ESC` quits. Any other key is a manual hit, so you can drive it
without a MIDI cable. Scenes 2-4 are the earlier prototypes, kept for reference.

| # | Scene | Status |
|---|-------|--------|
| 1 | **Moire field** | the show |
| 2 | Moire, full redraw | reference |
| 3 | Band | reference |
| 4 | Strobe plate | reference |

### Scene 1: moire generated into a scrolling field

Scrolling on a plain ST means moving the screen base register, and there is
only one of those, so **everything on screen scrolls together**. You cannot
hold a static layer over a moving one in a single framebuffer. So rather than
drawing moire *over* a scroll, the moire is generated *into the leading edge*
of the field. Each frame only the newly uncovered strip is written; everything
already on screen just slides.

The vertical axis therefore stops being space and becomes **time** — the screen
is the last couple of seconds of the pattern's history, flowing past.

Consequences:

* **It is cheap.** At one page per frame that is 512 bytes written instead of
  the 16 000 a half-screen moire redraw costs.
* **Silence is free.** Scroll speed comes from the envelope, so when the level
  is zero the picture freezes and the frame costs nothing at all.
* **Pitch sets the spatial frequency.** MIDI note number drives `field_step`,
  the rate the stripe index advances per page, so playing higher compresses the
  banding.
* **Hard hits punch noise.** Above `NOISE_HIT` the leading edge is filled from
  the noise pool instead of the stripe table, so a hit stays visible as a band
  scrolling away behind the beat.

Two details make it seamless:

* The base register steps 256 bytes — 3 rows plus **128 pixels of horizontal
  shear**. The stripe patterns repeat every 16 pixels and 128 is eight whole
  periods, so the shear is invisible by construction.
* The window wraps after 128 pages, so every page below 125 is written twice,
  at `p` and at `p+128`. The jump back lands on identical bytes. Verified: 30
  consecutive frames across several wraps show no discontinuity.

### Frame budget

A mono frame is ~112 000 cycles at 8 MHz. `movem.l` with eight registers moves
32 bytes per ~88 cycles, so a *full*-screen fill is ~90 000 cycles — nearly the
whole frame. Build with `-DDIAG=1` to get a bar on the top row showing how many
of the last 64 frames overran their budget; `-DSTARTSCENE=n` boots straight into
one scene and `-DAUTOCYCLE=1` restores cycling. The build compares the system VBL
counter at `$462` against its own frame count, so it catches any frame that took
longer than one.

Measured on the machine:

| Scene | Computed cost | Overruns / 64 frames |
|-------|---------------|----------------------|
| 1 Moire field | 1 400 cycles at one page/frame, ~9 900 flat out, 0 frozen | 0-1 |
| 2 Moire, full redraw | ~43 000 cycles | 0-2 |
| 3 Band | ~79 000 cycles worst case | 0-1 |
| 4 Strobe plate | one word write | 0-1 |

Even the near-free scenes report 0-1 per 64, so roughly one in sixty-four is
baseline jitter rather than the cost of an effect. Scene 1 sits at that floor.

## Known limits, and what they cost

1. **MIDI goes through the BIOS** (`Bconstat`/`Bconin`), one trap per byte.
   Fine at this density; will eat frame time once MIDI clock at 24 ppqn is
   added. Fix: our own 6850 ACIA interrupt handler with a ring buffer.
2. **Single buffered**, so fast changes tear. Fix: two framebuffers, flip on
   the screen base register. Costs 32 KB.
3. **Erase-then-fill overdraws** the overlap in the Band scene.
4. Tested against **EmuTOS 1.4.0**; the real machine runs Atari TOS 1.04 (DE).
   All calls used are standard TOS 1.x, but confirm on hardware.

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
