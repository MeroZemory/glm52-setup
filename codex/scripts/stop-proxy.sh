#!/usr/bin/env bash
# Stop the Z.ai Responses proxy (Linux/macOS)
set -euo pipefail
PORT="${ZAI_CODEX_PROXY_PORT:-11439}"

if command -v lsof >/dev/null 2>&1; then
  pids="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN -P -n 2>/dev/null || true)"
elif command -v ss >/dev/null 2>&1; then
  pids="$(ss -tlnp "sport = :$PORT" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | sort -u || true)"
else
  echo "Neither lsof nor ss available"; exit 1
fi

if [ -n "$pids" ]; then
  echo "$pids" | xargs -r kill -9 2>/dev/null || true
  echo "Proxy stopped."
else
  echo "Proxy not running."
fi