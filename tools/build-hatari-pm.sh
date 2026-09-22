#!/bin/sh
# Build Hatari with PortMidi, so the emulator talks to CoreMIDI directly and
# no FIFO bridge is needed.
#
# Homebrew's hatari is built WITHOUT PortMidi, which leaves only the
# file-based --midi-in/--midi-out options.
#
# The one trap: Hatari defaults to a universal (arm64 + x86_64) build on
# macOS, while Homebrew's portmidi is arm64 only. The x86_64 slice then fails
# to link, CMake's symbol check fails, and portmidi is silently reported as
# "not found". -DCMAKE_OSX_ARCHITECTURES=arm64 is what fixes it.
set -e

VER=2.6.1
URL="https://framagit.org/hatari/releases/-/raw/main/v$VER/hatari-$VER.tar.bz2"
SHA=b7dc09ebffc1b77da6837d37b116bc5a9b2fd46affff1021124101e3f6e76bc5
HERE=$(cd "$(dirname "$0")" && pwd)
WORK="$HERE/hatari-pm-build"
DEST="$HERE/hatari-pm"

command -v cmake >/dev/null || { echo "need cmake: brew install cmake"; exit 1; }
brew list portmidi >/dev/null 2>&1 || brew install portmidi

mkdir -p "$WORK"
cd "$WORK"
[ -f "hatari-$VER.tar.bz2" ] || curl -sSL -o "hatari-$VER.tar.bz2" "$URL"
echo "$SHA  hatari-$VER.tar.bz2" | shasum -a 256 -c -
[ -d "hatari-$VER" ] || tar xjf "hatari-$VER.tar.bz2"

cmake -S "hatari-$VER" -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_PREFIX_PATH=/opt/homebrew \
      -DCMAKE_INSTALL_PREFIX="$DEST" | grep -A12 "Libraries summary"

cmake --build build -j8
cmake --install build >/dev/null
rm -rf "$DEST/Hatari.app"
cp -R build/src/Hatari.app "$DEST/"

echo
echo "built: $DEST/Hatari.app/Contents/MacOS/Hatari"
"$DEST/Hatari.app/Contents/MacOS/Hatari" -h 2>&1 | grep -i "midi <bool>" \
    && echo "PortMidi support confirmed"
