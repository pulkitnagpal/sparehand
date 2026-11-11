#!/bin/zsh
# The full Sparehand walkthrough, on a fresh test home folder. Your real Desktop and files are never touched.
#   1. A messy Desktop  →  Claude notices and plans  →  you approve  →  watch it sort on Sparehand's own screen
#   2. New screenshots land  →  the learned skill decides on this Mac, no Claude  →  approve
#   3. The menu-bar feed shows both, with Undo
cd "${0:A:h}/.."
H="${TMPDIR:-/tmp}/sparehand-walkthrough"
B=.build/debug
rm -rf "$H"; mkdir -p "$H/Desktop" "$H/Downloads"
swift build >/dev/null 2>&1 || { echo "build failed"; exit 1; }
pkill -f "$B/SparehandApp" 2>/dev/null
done_count() { SPAREHAND_HOME="$H" $B/sparehand feed 2>/dev/null | grep -c "\] done"; }

SPAREHAND_HOME="$H" $B/sparehand demo-seed 40 >/dev/null
echo "1 · A messy Desktop: 40 screenshots (receipts, tickets, chats, recipes…)."
echo "    Sparehand looks: Qwen screens on this Mac, then Claude plans. A card appears top right in ~20 s."
echo "    Click its main button, then watch the panel at the bottom right."
SPAREHAND_HOME="$H" $B/SparehandApp --demo --look-now >/dev/null 2>&1 &
APP=$!
until [ "$(done_count)" -ge 1 ]; do sleep 1; kill -0 $APP 2>/dev/null || { echo "Sparehand quit"; exit 1; }; done
echo "    Done. Close the panel when you've seen it."
sleep 12

echo "2 · Eight new screenshots land. Sparehand learned this, so it decides on your Mac: no Claude, no internet."
SPAREHAND_HOME="$H" $B/sparehand demo-seed 8 >/dev/null
until [ "$(done_count)" -ge 2 ]; do sleep 1; kill -0 $APP 2>/dev/null || { echo "Sparehand quit"; exit 1; }; done

echo "3 · Click the hand in the menu bar: Today shows both jobs, each with Undo. Try one."
echo "    The sorted files are in $H/Pictures/Screenshots"
echo "    Press Return to finish (Sparehand quits; the test folder stays until restart)."
read
kill $APP 2>/dev/null
