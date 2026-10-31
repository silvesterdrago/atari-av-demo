# NOISE AV -- Atari ST visuals for a live noise set.
# Target: 1040 STF on an SM124, mono 640x400 @ 71Hz.

VASM      := tools/vasm/vasmm68k_mot
VASM_URL  := http://sun.hasenbraten.de/vasm/release/vasm.tar.gz
TARGET    := dist/NOISEAV.TOS
BRIDGE    := tools/midibridge
FIFO      := /tmp/noiseav.midi

# EmuTOS ships with Hatari. Override with `make run TOS=/path/to/tos.img`
# to test against a dump of the real machine's TOS 1.04.
TOS ?= $(firstword $(wildcard \
         /opt/homebrew/share/hatari/tos.img \
         /usr/local/share/hatari/tos.img \
         /usr/share/hatari/tos.img))

# Two emulators, deliberately. Homebrew's is file-based: it takes MIDI from a
# FIFO, which lets the bridge merge EVERY CoreMIDI device into one stream --
# keyboard and sequencer at the same time. A PortMidi build talks to CoreMIDI
# directly with no bridge, but opens exactly ONE port, so it is one device or
# the other. run-live is usually what you want.
HATARI_PM  := tools/hatari-pm/Hatari.app/Contents/MacOS/Hatari
HATARI_BIN := $(if $(wildcard $(HATARI_PM)),$(HATARI_PM),hatari)
MIDIPORT   ?= IAC Driver Bus 1

COMMON := --tos $(TOS) --machine st --memsize 1 --monitor mono \
          --sound off --gemdos-drive C -d dist --auto 'C:\NOISEAV.TOS'
HATARI      := $(HATARI_BIN) $(COMMON)
HATARI_FILE := hatari $(COMMON)

# Hatari opens a MIDI *output* device whenever MIDI is enabled, and on the
# Homebrew build that defaults to a Linux ALSA path and fails -- taking the
# input down with it. Hence --midi-out /dev/null.
MIDIOPTS := --midi-in $(FIFO) --midi-out /dev/null

# --- shows ----------------------------------------------------------------
# Each source in src/shows/ is one idea and builds its own binary on top of
# src/core/. dist/NOISEAV.TOS is the older all-in-one show and is left alone.
SHOW_SRCS := $(wildcard src/shows/*.s)
SHOW_DEPS := src/core/head.s src/core/tail.s src/shows/flipbook.inc \
              src/shows/dissolve.inc src/shows/morph.inc \
              src/shows/acts1.inc src/shows/acts2.inc src/shows/acts3.inc \
              src/shows/acts7.inc
SHOW_BINS :=

define SHOW_RULE
SHOW_BINS += dist/$(shell echo $(notdir $(basename $(1))) | tr a-z A-Z).TOS
dist/$(shell echo $(notdir $(basename $(1))) | tr a-z A-Z).TOS: $(1) $$(SHOW_DEPS) | $$(VASM) dist
	$$(VASM) -Ftos -quiet -o $$@ $$<
endef
$(foreach s,$(SHOW_SRCS),$(eval $(call SHOW_RULE,$(s))))

# Baked geometry. The shows incbin these, so they have to exist before the
# assembler runs -- and they are generated, not tracked.
src/big.bin: tools/genbig.py tools/gensolids.py
	python3 tools/genbig.py
src/grid.bin: tools/gengrid.py
	python3 tools/gengrid.py
src/hyper.bin: tools/genhyper.py
	python3 tools/genhyper.py
src/half.bin: tools/genhalf.py
	python3 tools/genhalf.py
src/solids.bin: tools/gensolids.py
	python3 tools/gensolids.py
src/shapes.bin: tools/genshapes.py
	python3 tools/genshapes.py
src/vectors.bin: tools/genvectors.py
	python3 tools/genvectors.py
src/plasma.inc: tools/genplasma.py
	python3 tools/genplasma.py
src/shuriken.inc: tools/genshuriken.py
	python3 tools/genshuriken.py
src/tetrapod.inc: tools/gentetrapod.py
	python3 tools/gentetrapod.py

dist/MONOLITH.TOS: src/big.bin
dist/GRID.TOS:     src/grid.bin
dist/VIEWER.TOS:   dist/TEST.DAT
dist/CORRIDOR.TOS: dist/CORRIDOR.DAT
dist/CUBES4.TOS:   src/cubes4.bin
dist/TUNNEL.TOS:   dist/TUNNEL.DAT
dist/WAVE.TOS:     dist/WAVE.DAT
dist/DESYNC.TOS:   dist/DESYNC.DAT
dist/DRIFT.TOS:    dist/DRIFT.DAT
dist/DISSOLVE.TOS: dist/DISSOLVE.DAT dist/CORRIDOR.DAT
dist/FLOOR.TOS:    dist/FLOOR.DAT
# Frame 14 is frame 13 plus a block on the horizon, stamped into the frames
# at start-up, so it shares FLOOR.DAT rather than shipping another 750 KB.
SHOW_BINS += dist/FIELD.TOS
dist/FIELD.TOS: src/shows/floor.s $(SHOW_DEPS) dist/FLOOR.DAT | $(VASM) dist
	$(VASM) -Ftos -quiet -DPOINT=1 -o $@ $<
# Baked tables that travel beside the binary instead of inside it. Four
# scenes hold 855 KB between them, which no megabyte carries at once, so a
# set shares one buffer and reads the entered scene's file into it. Every
# .DAT has to sit beside the .TOS wherever it runs.
dist/HYPER.DAT: src/hyper.bin | dist
	cp $< $@
dist/CUBES.DAT: src/cubes.bin | dist
	cp $< $@
dist/SOLIDS.DAT: src/solids.bin | dist
	cp $< $@
dist/BIG.DAT: src/big.bin | dist
	cp $< $@
dist/TEST.DAT: src/test.bin | dist
	cp $< $@
src/test.bin: tools/gentest.py tools/sysload.py
	python3 tools/gentest.py
dist/CORRIDOR.DAT: src/corr.bin | dist
	cp $< $@
dist/TUNNEL.DAT: src/tun.bin | dist
	cp $< $@
dist/WAVE.DAT: src/wave.bin | dist
	cp $< $@
dist/DESYNC.DAT: src/desy.bin | dist
	cp $< $@
dist/DRIFT.DAT: src/drift.bin | dist
	cp $< $@
dist/DISSOLVE.DAT: src/dis.bin | dist
	cp $< $@
dist/CUTS.DAT: src/cut.bin | dist
	cp $< $@
dist/TUNPLAIN.DAT: src/tunp.bin | dist
	cp $< $@
src/tunp.bin: tools/genflip.py tools/sysload.py
	python3 tools/genflip.py tunp
dist/BRANCH.DAT: src/branch.bin | dist
	cp $< $@
src/branch.bin: tools/genflip.py tools/sysload.py
	python3 tools/genflip.py branch
dist/PIT.DAT: src/pit.bin | dist
	cp $< $@
src/pit.bin: tools/genflip.py tools/sysload.py
	python3 tools/genflip.py pit
dist/PITBOLD.DAT: src/pitb.bin | dist
	cp $< $@
src/pitb.bin: tools/genflip.py tools/sysload.py
	python3 tools/genflip.py pitb
dist/WALLS.DAT: src/walls.bin | dist
	cp $< $@
src/walls.bin: tools/genflip.py tools/sysload.py
	python3 tools/genflip.py walls
dist/EXPAND.DAT: src/expand.bin | dist
	cp $< $@
src/expand.bin: tools/genflip.py tools/sysload.py
	python3 tools/genflip.py expand
dist/STILLS.DAT: src/stills.bin | dist
	cp $< $@
src/stills.bin: tools/genstills.py tools/sysload.py
	python3 tools/genstills.py
src/cut.bin: tools/gendis.py tools/sysload.py
	python3 tools/gendis.py cuts
dist/FLOOR.DAT: src/floor.bin | dist
	cp $< $@
src/corr.bin: tools/genflip.py tools/sysload.py
	python3 tools/genflip.py corr
src/tun.bin: tools/genflip.py tools/sysload.py
	python3 tools/genflip.py tun
src/wave.bin: tools/genflip.py tools/sysload.py
	python3 tools/genflip.py wave
src/desy.bin: tools/genflip.py tools/sysload.py
	python3 tools/genflip.py desy
src/floor.bin: tools/genflip.py tools/sysload.py
	python3 tools/genflip.py floor
src/drift.bin: tools/genflip.py tools/sysload.py
	python3 tools/genflip.py drift
src/dis.bin: tools/gendis.py tools/sysload.py
	python3 tools/gendis.py
DATS := dist/HYPER.DAT dist/CUBES.DAT dist/SOLIDS.DAT dist/BIG.DAT
dist/HYPER.TOS:    dist/HYPER.DAT
dist/HALFTONE.TOS: src/half.bin src/shows/halftone_blit.inc
dist/SOLIDS.TOS:   src/solids.bin
dist/SHAPES.TOS:   src/shapes.bin
dist/VECTORS.TOS:  src/vectors.bin
dist/PLASMA.TOS:   src/plasma.inc
dist/SHURIKEN.TOS: src/shuriken.inc
dist/TETRAPOD.TOS: src/tetrapod.inc

# Every scene in one binary, switched on the number keys.
# The five flipbooks in one binary, sharing a 750 KB buffer: the switch has
# to read the whole scene off the card, which is the point of it.
dist/CORRSET.TOS: src/corrset.s $(SHOW_DEPS) dist/CORRIDOR.DAT dist/TUNNEL.DAT \
                  dist/WAVE.DAT dist/DESYNC.DAT dist/DRIFT.DAT | $(VASM) dist
	$(VASM) -Ftos -quiet -o $@ $<

MULTI := dist/MULTI.TOS
$(MULTI): src/multi.s $(SHOW_SRCS) $(SHOW_DEPS) src/grid.bin src/half.bin \
          src/solids.bin src/big.bin | $(VASM) dist
	$(VASM) -Ftos -quiet -o $@ src/multi.s

MULTIB := dist/MULTIB.TOS
$(MULTIB): src/multib.s $(SHOW_SRCS) $(SHOW_DEPS) src/cubes.bin src/half.bin \
           dist/HYPER.DAT | $(VASM) dist
	$(VASM) -Ftos -quiet -o $@ src/multib.s

MULTIC := dist/MULTIC.TOS
$(MULTIC): src/multic.s $(SHOW_SRCS) $(SHOW_DEPS) src/grid.bin src/half.bin \
           $(DATS) | $(VASM) dist
	$(VASM) -Ftos -quiet -o $@ src/multic.s

# The whole arc in one binary, addressed by position number. Not built by
# `make shows`: it lives in src/ beside the other sets, not in src/shows/.
dist/ARC.TOS: src/arc.s $(SHOW_DEPS) | $(VASM) dist
	$(VASM) -Ftos -quiet -o $@ $<
arc: dist/ARC.TOS dist/CORRIDOR.DAT dist/TUNNEL.DAT dist/WAVE.DAT \
     dist/DESYNC.DAT dist/DRIFT.DAT dist/FLOOR.DAT dist/DISSOLVE.DAT \
     dist/CUTS.DAT dist/STILLS.DAT \
     dist/TUNPLAIN.DAT dist/BRANCH.DAT dist/PIT.DAT dist/PITBOLD.DAT dist/WALLS.DAT dist/EXPAND.DAT

# Watch it switch. The number keys drive the rehearsal list; the MIDI pipe is
# set up too, so tools/pos.py can send positions from another terminal.
#
# This one runs the HOMEBREW hatari on purpose. The two builds take different
# MIDI options -- the PortMidi build has --midi and takes its ports from a
# config file, the Homebrew build has --midi-in and reads a file or a pipe --
# and HATARI_BIN prefers the PortMidi one, which is the wrong build for a pipe.
ARCRUN := --tos $(TOS) --machine st --memsize 1 --monitor mono --sound off \
          --gemdos-drive C -d dist --auto 'C:\ARC.TOS'

# Opening a FIFO for reading BLOCKS until somebody holds the other end, so
# without a writer parked on it Hatari hangs before it boots. The holder opens
# O_RDWR, which never blocks and never hands Hatari EOF -- the same reason
# midibridge.c and tools/pos.py do.
# Everything the card needs and nothing else, in one directory, so there is no
# guessing about which binary is on it. ARC.TOS is the show; PRIMS.TOS is the
# fallback that cannot fail for lack of a file, because it reads none.
# The spec another session writes the arrangement against is generated from
# the source, so a card cannot be built against a stale one.
spec:
	python3 tools/specgen.py

card: spec-check arc arc2 dist/PRIMS.TOS
	@rm -rf dist/card && mkdir -p dist/card
	@cp dist/ARC.TOS dist/PRIMS.TOS dist/card/
	@cp dist/CORRIDOR.DAT dist/TUNNEL.DAT dist/WAVE.DAT dist/DESYNC.DAT \
	    dist/DRIFT.DAT dist/FLOOR.DAT dist/DISSOLVE.DAT dist/CUTS.DAT \
	    dist/STILLS.DAT dist/card/
	@cp dist/TUNPLAIN.DAT dist/BRANCH.DAT dist/PIT.DAT dist/PITBOLD.DAT dist/WALLS.DAT dist/EXPAND.DAT dist/card/
	@cp dist/ARC2.TOS dist/POSTER.DAT dist/card/
	@ls -l dist/card
	@echo "итого: $$(du -sh dist/card | cut -f1)"

# ARC with the poster: a second binary on purpose, so the one that has been
# run stays the one that has been run. -DPOSTER adds the Enter key, position
# 66 and the band player; without it the source assembles to the same bytes
# as before, which is checked by arc2-same.
dist/ARC2.TOS: src/arc.s $(SHOW_DEPS) | $(VASM) dist
	$(VASM) -Ftos -quiet -DPOSTER=1 -o $@ $<
dist/POSTER.DAT: src/poster.bin | dist
	cp $< $@
arc2: dist/ARC2.TOS dist/POSTER.DAT arc

arc2-same: dist/ARC.TOS
	@$(VASM) -Ftos -quiet -o /tmp/arc-nopos.TOS src/arc.s
	@cmp /tmp/arc-nopos.TOS dist/ARC.TOS && echo "ARC.TOS не изменился"

spec-check:
	@python3 tools/specgen.py --check

# The same binary with the diagnostic bars on, to put on the card when
# something does not arrive: bar two counts MIDI bytes the program consumed,
# so it separates "nothing is reaching the machine" from "the codes mean
# something else in the binary that is actually on the card".
dist/ARCDIAG.TOS: src/arc.s $(SHOW_DEPS) | $(VASM) dist
	$(VASM) -Ftos -quiet -DDIAG=1 -DACIABAR=1 -o $@ $<
arc-diag: dist/ARCDIAG.TOS arc

run-arc: arc fifo
	@python3 -c "import os, time; os.open('$(FIFO)', os.O_RDWR); time.sleep(99999)" & \
	 echo $$! > /tmp/noiseav-hold.pid
	-hatari $(ARCRUN) $(MIDIOPTS)
	@kill `cat /tmp/noiseav-hold.pid` 2>/dev/null; rm -f /tmp/noiseav-hold.pid

# The same, but through CoreMIDI on the PortMidi build: whole messages, none
# of the pipe's trickle, and the closest thing to the real rig -- Live sends
# to a virtual port and this reads it. MIDIPORT picks the port; the default
# needs IAC enabled in Audio MIDI Setup.
run-arc-pm: arc
	@test -x $(HATARI_PM) || { echo "run tools/build-hatari-pm.sh first"; exit 1; }
	@printf '[Midi]\nbEnableMidi = TRUE\nsMidiInPortName = %s\nsMidiOutPortName = Off\n' \
	        "$(MIDIPORT)" > /tmp/noiseav-arc.cfg
	$(HATARI_PM) --configfile /tmp/noiseav-arc.cfg --midi 1 $(ARCRUN)

multi: $(MULTI) $(MULTIB) $(MULTIC)
	@ls -la $(MULTI) $(MULTIB) $(MULTIC) $(DATS)

all: $(TARGET) $(SHOW_BINS) $(MULTI) $(MULTIB) $(MULTIC)

shows: $(SHOW_BINS)
	@ls -la $(SHOW_BINS)

# Run one show: make run-show SHOW=SPARKS   (add MIDI with run-show-live)
SHOW ?= SPARKS
SHOWRUN := --gemdos-drive C -d dist --auto 'C:\$(SHOW).TOS'

run-show: dist/$(SHOW).TOS
	$(HATARI_BIN) --tos $(TOS) --machine st --memsize 1 --monitor mono \
	              --sound off $(SHOWRUN)

run-show-live: dist/$(SHOW).TOS $(BRIDGE) fifo
	@$(BRIDGE) -o $(FIFO) & echo $$! > /tmp/noiseav-bridge.pid
	-hatari --tos $(TOS) --machine st --memsize 1 --monitor mono \
	        --sound off $(SHOWRUN) $(MIDIOPTS)
	@kill `cat /tmp/noiseav-bridge.pid` 2>/dev/null; rm -f /tmp/noiseav-bridge.pid

$(TARGET): src/main.s src/cubes.bin | $(VASM) dist
	$(VASM) -Ftos -quiet -o $@ $<

# Wireframe cube frames, baked offline -- see the header of gencubes.py
src/cubes.bin: tools/gencubes.py
	python3 tools/gencubes.py
src/cubes4.bin: tools/gencubes.py
	python3 tools/gencubes.py big

dist:
	@mkdir -p dist

# --- toolchain bootstrap ---------------------------------------------------
# vasm alone produces a TOS executable (-Ftos), so vlink is not needed yet.
tools: $(VASM)

$(VASM):
	@echo "fetching and building vasm..."
	cd tools && curl -sSL -o vasm.tar.gz $(VASM_URL) && tar xzf vasm.tar.gz
	@$(MAKE) -s -C tools/vasm CPU=m68k SYNTAX=mot

$(BRIDGE): tools/midibridge.c
	clang -O2 -Wall -o $@ $< -framework CoreMIDI -framework CoreFoundation

fifo:
	@test -p $(FIFO) || { rm -f $(FIFO); mkfifo $(FIFO); }

# --- running ---------------------------------------------------------------
# ESC quits the show, then close the Hatari window.
run: $(TARGET)
	$(HATARI)

# What MIDI devices does macOS see?
midi-list: $(BRIDGE)
	@$(BRIDGE) -l

# Play it live from a real MIDI keyboard. The keyboard may be plugged in
# before or after starting; the bridge picks up new devices by itself.
# Every MIDI device at once, via the bridge. Needs Homebrew's file-based
# Hatari, which is why this does not use $(HATARI).
run-live: $(TARGET) $(BRIDGE) fifo
	@$(BRIDGE) -o $(FIFO) & echo $$! > /tmp/noiseav-bridge.pid
	-$(HATARI_FILE) $(MIDIOPTS)
	@kill `cat /tmp/noiseav-bridge.pid` 2>/dev/null; rm -f /tmp/noiseav-bridge.pid

# Straight to CoreMIDI, no bridge -- but ONE device only, chosen with
# `make run-pm MIDIPORT='MPK mini 3'` (see `make midi-list`). For keyboard and
# sequencer together, use run-live instead.
run-pm: $(TARGET)
	@test -x $(HATARI_PM) || { echo "run tools/build-hatari-pm.sh first"; exit 1; }
	@printf '[Midi]\nbEnableMidi = TRUE\nsMidiInPortName = %s\nsMidiOutPortName = Off\n' \
	        "$(MIDIPORT)" > /tmp/noiseav-midi.cfg
	$(HATARI) --configfile /tmp/noiseav-midi.cfg --midi 1

# Same, driven by the synthetic generator instead of a keyboard.
run-midi: $(TARGET) fifo
	@python3 tools/midifeed.py $(FIFO) & echo $$! > /tmp/noiseav-feed.pid
	-$(HATARI_FILE) $(MIDIOPTS)
	@kill `cat /tmp/noiseav-feed.pid` 2>/dev/null; rm -f /tmp/noiseav-feed.pid

# --- diagnostics -----------------------------------------------------------
# Draws a bar along the top row: one byte per frame that overran its budget
# in the last 64. See README for how to read it back out of a capture.
diag: | $(VASM)
	@mkdir -p dist-diag
	$(VASM) -Ftos -quiet -DDIAG=1 -o dist-diag/NOISEAV.TOS src/main.s
	hatari --tos $(TOS) --machine st --memsize 1 --monitor mono --sound off \
	       --gemdos-drive C -d dist-diag --auto 'C:\NOISEAV.TOS'

clean:
	rm -rf dist dist-*
	rm -f $(BRIDGE) src/cubes.bin cubes_preview.png src/cubes4.bin cubes4_preview.png
	rm -f src/big.bin src/grid.bin grid_preview.png grid_preview_sparse.png
	rm -f src/hyper.bin src/hyper10.bin hyper_preview.png
	rm -f src/test.bin test_preview.png src/half.bin half_preview.png
	rm -f src/solids.bin src/shapes.bin src/vectors.bin src/plasma.inc plasma_preview.png src/shuriken.inc src/tetrapod.inc tetrapod_preview.png

distclean: clean
	rm -rf tools/vasm tools/vlink tools/*.tar.gz tools/hatari-pm-build

.PHONY: all multi shows tools fifo run run-live run-midi run-pm run-show run-show-live midi-list diag clean distclean
