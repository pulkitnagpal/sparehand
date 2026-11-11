#!/bin/zsh
# Builds dist/Sparehand.app (with the sparehand CLI and the judge script inside) and dist/sparehand.
# Signs with a stable identity named "Sparehand Dev" when the keychain has one, so macOS keeps the
# permissions you granted across rebuilds; otherwise ad-hoc (permissions reset on every build).
set -euo pipefail
cd "${0:A:h}/.."
swift build -c release
BIN=.build/release
APP=dist/Sparehand.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/SparehandApp" "$APP/Contents/MacOS/Sparehand"
cp "$BIN/sparehand" "$APP/Contents/Resources/sparehand"
cp scripts/judge-server.sh "$APP/Contents/Resources/judge-server.sh"
cp "$BIN/sparehand" dist/sparehand
if security find-identity -v -p codesigning | grep -q "Sparehand Dev"; then
  codesign --force --deep --sign "Sparehand Dev" "$APP"
else
  echo "warning: no 'Sparehand Dev' signing identity; ad-hoc signing (macOS will ask for permissions again after each build)" >&2
  codesign --force --deep --sign - "$APP"
fi
echo "built $APP"
