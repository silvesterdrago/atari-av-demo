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
* keep draining once per frame as a safety net, so a missed interrupt costs a
  byte rather than the whole session

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
