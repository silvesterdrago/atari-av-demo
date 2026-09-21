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

HATARI := hatari --tos $(TOS) --machine st --memsize 1 --monitor mono \
                 --sound off --gemdos-drive C -d dist --auto 'C:\NOISEAV.TOS'

# Hatari opens a MIDI *output* device whenever MIDI is enabled, and on the
# Homebrew build that defaults to a Linux ALSA path and fails -- taking the
# input down with it. Hence --midi-out /dev/null.
MIDIOPTS := --midi-in $(FIFO) --midi-out /dev/null

all: $(TARGET)

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
run-live: $(TARGET) $(BRIDGE) fifo
	@$(BRIDGE) -o $(FIFO) & echo $$! > /tmp/noiseav-bridge.pid
	-$(HATARI) $(MIDIOPTS)
	@kill `cat /tmp/noiseav-bridge.pid` 2>/dev/null; rm -f /tmp/noiseav-bridge.pid

# Same, driven by the synthetic generator instead of a keyboard.
run-midi: $(TARGET) fifo
	@python3 tools/midifeed.py $(FIFO) & echo $$! > /tmp/noiseav-feed.pid
	-$(HATARI) $(MIDIOPTS)
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

distclean: clean
	rm -rf tools/vasm tools/vlink tools/*.tar.gz

.PHONY: all tools fifo run run-live run-midi midi-list diag clean distclean
