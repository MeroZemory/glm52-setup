#!/usr/bin/env bash
# Start the Z.ai Responses-to-Chat proxy in the background (Linux/macOS)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_MJS="$SCRIPT_DIR/../../proxy/zai-codex-responses-proxy.mjs"
PORT="${ZAI_CODEX_PROXY_PORT:-11439}"
OUT="${CODEX_HOME:-$HOME/.codex}/zai-codex-proxy.out.log"
ERR="${CODEX_HOME:-$HOME/.codex}/zai-codex-proxy.err.log"

# Already running?
if command -v lsof >/dev/null 2>&1 && lsof -iTCP:"$PORT" -sTCP:LISTEN -P -n >/dev/null 2>&1; then
  echo "Proxy already running on port $PORT"
  exit 0
fi

nohup node "$PROXY_MJS" >"$OUT" 2>"$ERR" &
echo "Proxy started on http://127.0.0.1:$PORT (pid $!)"