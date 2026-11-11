#!/bin/zsh
# Renders the Sparehand 1.0 film from real captures.
#   1. scripts/demo-setup.sh builds the scene; the app's --film mode drives the real product and captures its windows.
#   2. This script stages them: scripts/video/compose.swift draws every frame, ffmpeg encodes.
#   scripts/video/make-film.sh <assets dir> <demo home> [out.mp4]
set -euo pipefail
cd "${0:A:h}/../.."
A="$1"; DEMO="$2"; OUT="${3:-dist/sparehand-1.0.mp4}"
mkdir -p .build/video "$(dirname "$OUT")"
swiftc -O scripts/video/compose.swift -o .build/video/compose
.build/video/compose "$A" "$DEMO" | ffmpeg -v error -y -f rawvideo -pix_fmt bgra -s 1920x1080 -r 30 -i - \
  -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -movflags +faststart "$OUT"
echo "wrote $OUT"
