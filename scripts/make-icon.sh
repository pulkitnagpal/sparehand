#!/bin/zsh
# Renders the logo (Sources/SparehandApp/UI/Logo.swift) into Resources/AppIcon.icns.
set -e
cd "${0:A:h}/.."
swift build --product SparehandApp >/dev/null
T=$(mktemp -d); .build/debug/SparehandApp --export-logo "$T" >/dev/null
I="$T/AppIcon.iconset"; mkdir -p "$I"
for s in 16 32 128 256 512; do cp "$T/icon_$s.png" "$I/icon_${s}x${s}.png"; cp "$T/icon_$((s*2)).png" "$I/icon_${s}x${s}@2x.png"; done
iconutil -c icns "$I" -o Resources/AppIcon.icns
cp "$T/logo_full.png" docs/logo.png
echo "wrote Resources/AppIcon.icns and docs/logo.png"
