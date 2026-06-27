#!/usr/bin/env bash
# ============================================================
# Codex GLM-5.2 Setup — Linux/macOS Rollback
# ============================================================
# Removes every trace of the GLM-5.2 integration from CODEX_HOME:
#   - Kills the proxy process on port 11439
#   - Removes proxy, profile, and scripts
#   - Restores config.toml from backup (or surgically strips
#     the [model_providers.zai_coding] block if no backup exists)
#
# Usage:  bash rollback.sh
# Safe to run multiple times.
# ============================================================
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
PORT="${ZAI_CODEX_PROXY_PORT:-11439}"

cyan()  { printf '\033[36m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }
step()  { printf '[*] %s\n' "$1"; }
ok()    { printf '[+] %s\n' "$1"; }

cyan "Codex GLM-5.2 Rollback"
echo  "    CODEX_HOME: $CODEX_HOME"
echo

# --- 1. Kill proxy on port 11439 ---
step "Stopping proxy (port $PORT)..."
if command -v lsof >/dev/null 2>&1; then
  pids="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN -P -n 2>/dev/null || true)"
elif command -v ss >/dev/null 2>&1; then
  pids="$(ss -tlnp "sport = :$PORT" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | sort -u || true)"
else
  pids=""
fi

if [ -n "$pids" ]; then
  echo "$pids" | xargs -r kill -9 2>/dev/null || true
  ok "Proxy process killed."
else
  ok "Proxy not running."
fi

# --- 2. Remove installed files ---
step "Removing installed files..."
files=(
  "zai-codex-responses-proxy.mjs"
  "glm52.config.toml"
  "start-proxy.sh"
  "stop-proxy.sh"
  "start-codex-glm52.sh"
  "zai-codex-proxy.out.log"
  "zai-codex-proxy.err.log"
)

for f in "${files[@]}"; do
  path="$CODEX_HOME/$f"
  if [ -f "$path" ]; then
    rm -f "$path"
    ok "Removed: $f"
  fi
done

# --- 3. Restore or patch config.toml ---
config_path="$CODEX_HOME/config.toml"
config_bak="$CODEX_HOME/config.toml.pre-glm52.bak"

step "Restoring config.toml..."

if [ -f "$config_bak" ]; then
  cp "$config_bak" "$config_path"
  ok "config.toml restored from backup."
elif [ -f "$config_path" ]; then
  # Surgically remove the [model_providers.zai_coding] block
  # Uses awk to skip from the section header to the next section
  tmp="$(mktemp)"
  awk '
    /^\[model_providers\.zai_coding\]/ { skip=1; next }
    /^\[/ { skip=0 }
    !skip { print }
  ' "$config_path" > "$tmp"

  # Trim trailing blank lines
  sed -i -e :a -e '/^\n*$/{$d;N;ba}' "$tmp" 2>/dev/null || true

  mv "$tmp" "$config_path"
  ok "Removed [model_providers.zai_coding] block from config.toml."
else
  yellow "[!] config.toml not found — nothing to patch."
fi

# --- 4. Done ---
echo
green "========================================"
ok "Rollback complete!"
green "========================================"
echo
echo "GLM-5.2 integration fully removed. GPT-5.5 default is unaffected."
echo
