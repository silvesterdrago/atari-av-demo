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
SHOW_DEPS := src/core/head.s src/core/tail.s
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
src/solids.bin: tools/gensolids.py
	python3 tools/gensolids.py
src/shapes.bin: tools/genshapes.py
	python3 tools/genshapes.py
src/vectors.bin: tools/genvectors.py
	python3 tools/genvectors.py

dist/MONOLITH.TOS: src/big.bin
dist/GRID.TOS:     src/grid.bin
dist/HYPER.TOS:    src/hyper.bin
dist/SOLIDS.TOS:   src/solids.bin
dist/SHAPES.TOS:   src/shapes.bin
dist/VECTORS.TOS:  src/vectors.bin

all: $(TARGET) $(SHOW_BINS)

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
	rm -f $(BRIDGE) src/cubes.bin cubes_preview.png
	rm -f src/big.bin src/grid.bin grid_preview.png grid_preview_sparse.png
	rm -f src/hyper.bin hyper_preview.png
	rm -f src/solids.bin src/shapes.bin src/vectors.bin

distclean: clean
	rm -rf tools/vasm tools/vlink tools/*.tar.gz tools/hatari-pm-build

.PHONY: all shows tools fifo run run-live run-midi run-pm run-show run-show-live midi-list diag clean distclean
