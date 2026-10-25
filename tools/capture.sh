#!/bin/zsh
# Assemble a source and record it running headless.
#   tools/capture.sh SRC NAME VBLS [extra -D flags...]
# Writes build/<NAME>.avi; read it with tools/avipng.py.
set -e
cd "$(dirname "$0")/.."
SRC="$1"; NAME="$2"; VBLS="$3"; shift 3
# --frameskips 0 matters: benchmark mode otherwise redraws every sixth VBL
# and the AVI repeats the stale screen, so a 2-VBL animation reads back as
# a 6-VBL one playing every third frame.
# Hatari refuses a GEMDOS drive path over 255 chars and then blocks on a
# modal alert, so the drive lives at a short fixed path.
OUT=/tmp/navcap
mkdir -p "$OUT/d-$NAME" build
tools/vasm/vasmm68k_mot -Ftos -quiet -DDIAG=1 "$@" -o "$OUT/d-$NAME/X.TOS" "$SRC"
for f in hyper:HYPER cubes:CUBES solids:SOLIDS big:BIG test:TEST grid:GRID corr:CORRIDOR tun:TUNNEL wave:WAVE dis:DISSOLVE desy:DESYNC drift:DRIFT; do
  [ -f "src/${f%%:*}.bin" ] && cp -f "src/${f%%:*}.bin" "$OUT/d-$NAME/${f##*:}.DAT"
done
TOS=$(ls /opt/homebrew/share/hatari/tos.img)
hatari --tos $TOS --machine st --memsize 1 --monitor mono --sound off \
  --gemdos-drive C -d "$OUT/d-$NAME" --auto 'C:\X.TOS' \
  --benchmark --frameskips 0 --run-vbls $VBLS --avirecord --avi-vcodec png \
  --avi-file "build/$NAME.avi" >"build/$NAME.log" 2>&1 || true
ls -l "build/$NAME.avi"
