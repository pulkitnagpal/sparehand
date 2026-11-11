#!/bin/zsh
# Sets up a believable messy Mac for a Sparehand demo, inside a test home folder, so your real files are never touched:
#   Desktop:   80 screenshots (receipts, tickets, chats, recipes…) from the last few months
#   Downloads: 6 old app installers
#   Browser:   a new window (Dia, Chrome or Safari) with 5 tabs about planning a Japan trip, open "for a few days"
# Nothing here tells Sparehand what to do. It sees this scene the same way it sees any Mac.
#
#   scripts/demo-setup.sh            set up, then start Sparehand on the Welcome screen
#   scripts/demo-setup.sh teardown   close the demo browser window and delete the test home
#   scripts/demo-setup.sh --here     use this account's own Desktop and Downloads (only in an account named like "Demo")
HERE_DIR="${0:A:h}"
if [[ -x "$HERE_DIR/Sparehand.app/Contents/MacOS/Sparehand" ]]; then          # the demo kit
  APPBIN="$HERE_DIR/Sparehand.app/Contents/MacOS/Sparehand"; CLI="$HERE_DIR/Sparehand.app/Contents/Resources/sparehand"; BUILD=0
elif [[ -x "$HOME/Applications/Sparehand.app/Contents/MacOS/Sparehand" && ! -f "$HERE_DIR/../Package.swift" ]]; then
  APPBIN="$HOME/Applications/Sparehand.app/Contents/MacOS/Sparehand"; CLI="$HOME/Applications/Sparehand.app/Contents/Resources/sparehand"; BUILD=0
else                                                                             # the repo
  cd "$HERE_DIR/.."; APPBIN="$PWD/.build/debug/SparehandApp"; CLI="$PWD/.build/debug/sparehand"; BUILD=1
fi
if [[ " $* " == *" --here "* ]]; then
  [[ "${USER:l}" == *demo* || -n "$SPAREHAND_DEMO_FORCE" ]] || { echo "--here only runs in a Demo account (this is $USER)."; exit 1; }
  H="$HOME"
else
  H="${SPAREHAND_DEMO_HOME:-${TMPDIR:-/tmp}/sparehand-demo}"
fi
STATE="$H/.sparehand-demo-window"

browser() { for b in Dia "Google Chrome" Safari; do pgrep -xq "$b" && { echo "$b"; return; }; done; echo Dia; }

if [[ "$1" == "teardown" ]]; then
  pkill -f "$APPBIN" 2>/dev/null
  if [[ -f "$STATE" ]]; then
    read -r app wid < "$STATE"
    osascript -e "tell application \"$app\" to close (every window whose id is \"$wid\")" >/dev/null 2>&1
  fi
  rm -f "$STATE"
  [[ "$H" == "$HOME" ]] && echo "demo window closed (files in this account are left as they are)" || { rm -rf "$H"; echo "demo cleaned up"; }
  exit 0
fi

(( BUILD )) && { swift build >/dev/null 2>&1 || { echo "build failed"; exit 1; }; }
pkill -f "$APPBIN" 2>/dev/null
[[ "$H" != "$HOME" ]] && rm -rf "$H"
mkdir -p "$H/Desktop" "$H/Downloads" "$H/Library/Application Support/Sparehand"

# Desktop: screenshots.
SPAREHAND_HOME="$H" "$CLI" demo-seed 80 >/dev/null

# Downloads: old installers (sparse files, so they take no real space).
i=0
for spec in "Zoom.pkg:140m" "Slack-4.41.105.dmg:190m" "Figma-125.4.9.dmg:270m" "Docker.dmg:1400m" "googlechrome.dmg:230m" "Notion-4.2.0.dmg:160m"; do
  name=${spec%%:*}; size=${spec##*:}
  mkfile -n $size "$H/Downloads/$name"
  touch -t $(date -v-$((30 + i * 17))d +%Y%m%d%H%M) "$H/Downloads/$name"
  i=$((i + 1))
done

# Browser: a window of its own with the trip tabs.
APP=$(browser)
URLS=(https://www.japan-guide.com/e/e2361.html https://www.japan-guide.com/e/e2158.html https://www.japan-guide.com/e/e2011.html
      https://www.japan-guide.com/e/e2164.html https://www.japan-guide.com/e/e2157.html)
if [[ "$APP" == "Safari" ]]; then
  SCRIPT="tell application \"Safari\"
  make new document with properties {URL:\"${URLS[1]}\"}
  set w to window 1"
  for u in "${URLS[@]:1}"; do SCRIPT+=$'\n'"  tell w to make new tab at end of tabs with properties {URL:\"$u\"}"; done
else
  SCRIPT="tell application \"$APP\"
  set w to make new window
  set URL of active tab of w to \"${URLS[1]}\""
  for u in "${URLS[@]:1}"; do SCRIPT+=$'\n'"  make new tab at end of tabs of w with properties {URL:\"$u\"}"; done
fi
SCRIPT+=$'\n'"  return id of w"$'\n'"end tell"
WID=$(osascript -e "$SCRIPT")
echo "$APP $WID" > "$STATE"

# The tabs have been open a few days (as Sparehand would have recorded if it had been running).
DB="$H/Library/Application Support/Sparehand/sparehand-v1.sqlite"
sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS tab_seen(url TEXT PRIMARY KEY, first_seen REAL NOT NULL);"
for u in "${URLS[@]}"; do sqlite3 "$DB" "INSERT OR REPLACE INTO tab_seen VALUES('$u', $(( $(date +%s) - 3 * 86400 )));"; done

echo "Demo scene ready in $H"
echo "  Desktop: 80 screenshots · Downloads: 6 old installers · $APP: a window with 5 Japan trip tabs"
[[ " $* " == *" --no-start "* ]] && exit 0
echo "Starting Sparehand on the Welcome screen…"
SPAREHAND_HOME="$H" exec "$APPBIN" --demo --welcome
