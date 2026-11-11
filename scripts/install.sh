#!/bin/zsh
# Installs Sparehand for this macOS user: the app into ~/Applications and the on-device model, then opens it.
# Run from the repo (builds first) or from a folder that already holds Sparehand.app.
set -e
HERE="${0:A:h}"
if [[ -d "$HERE/Sparehand.app" ]]; then SRC="$HERE/Sparehand.app"
else cd "$HERE/.."; ./scripts/bundle-app.sh; SRC="$PWD/dist/Sparehand.app"; fi
command -v uv >/dev/null || { echo "Sparehand needs uv for its on-device model: brew install uv"; exit 1; }
if ! command -v claude >/dev/null && [[ -x "$HERE/bin/claude" ]]; then   # a kit can carry Claude Code along
  mkdir -p ~/.local/bin && ln -sf "$HERE/bin/claude" ~/.local/bin/claude
fi
command -v claude >/dev/null || [[ -x ~/.local/bin/claude ]] || echo "Note: research notes use Claude Code when you connect with a subscription token. With an API key nothing else is needed."
mkdir -p ~/Applications
rm -rf ~/Applications/Sparehand.app
cp -R "$SRC" ~/Applications/
echo "Setting up the on-device model (the first time downloads about 2.5 GB)…"
SPAREHAND_JUDGE_WAIT=1200 ~/Applications/Sparehand.app/Contents/Resources/judge-server.sh start
echo "Installed. Opening Sparehand…"
open ~/Applications/Sparehand.app
