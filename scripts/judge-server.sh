#!/bin/zsh
# Starts/stops the local judge: mlx_lm.server on 127.0.0.1:8765 with thinking switched off.
#   scripts/judge-server.sh start|stop|status
set -euo pipefail
MODEL="${SPAREHAND_JUDGE_MODEL:-mlx-community/Qwen3.5-4B-MLX-4bit}"
PORT="${SPAREHAND_JUDGE_PORT:-8765}"
DIR="${SPAREHAND_HOME:-$HOME}/Library/Application Support/Sparehand"
VENV="$DIR/judge-venv"
PID="$DIR/judge.pid"
LOG="$DIR/judge.log"
mkdir -p "$DIR"

running() { [[ -f "$PID" ]] && kill -0 "$(cat "$PID")" 2>/dev/null; }

case "${1:-status}" in
  start)
    if running; then echo "running (pid $(cat "$PID"))"; exit 0; fi
    if curl -s -o /dev/null "http://127.0.0.1:$PORT/v1/models"; then echo "already answering on port $PORT"; exit 0; fi
    if [[ ! -x "$VENV/bin/mlx_lm.server" ]]; then
      command -v uv >/dev/null || { echo "uv is required: brew install uv" >&2; exit 1; }
      uv venv -q "$VENV" --python 3.12
      uv pip install -q --python "$VENV/bin/python" "mlx-lm==0.32.2"
    fi
    nohup "$VENV/bin/mlx_lm.server" --model "$MODEL" --host 127.0.0.1 --port "$PORT" \
      --chat-template-args '{"enable_thinking":false}' > "$LOG" 2>&1 &
    echo $! > "$PID"
    for _ in {1..${SPAREHAND_JUDGE_WAIT:-120}}; do
      curl -s -o /dev/null "http://127.0.0.1:$PORT/v1/models" && { echo "started (pid $(cat "$PID"))"; exit 0; }
      sleep 1
    done
    echo "server did not answer in time; see $LOG" >&2; exit 1 ;;
  stop)
    if running; then kill "$(cat "$PID")"; rm -f "$PID"; echo "stopped"; else echo "not running"; fi ;;
  status)
    if running; then echo "running (pid $(cat "$PID"))"; else echo "not running"; fi ;;
  *) echo "usage: $0 start|stop|status" >&2; exit 2 ;;
esac
