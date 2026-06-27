#!/usr/bin/env bash
# ============================================================
# Codex GLM-5.2 Setup - Linux/macOS Installer
# ============================================================
# Usage:  bash install.sh
# ============================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

cyan()  { printf '\033[36m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
step()  { printf '[*] %s\n' "$1"; }
ok()    { printf '[+] %s\n' "$1"; }
die()   { red "[!] $1"; exit 1; }

cyan "Codex GLM-5.2 Setup"
echo  "    Repo:       $REPO_DIR"
echo  "    CODEX_HOME: $CODEX_HOME"
echo

# --- 1. Node.js ---
step "Checking Node.js..."
command -v node >/dev/null 2>&1 || die "Node.js not found. Install from https://nodejs.org"
ok "Node $(node -v) found."

# --- 2. Codex CLI ---
step "Checking Codex CLI..."
command -v codex >/dev/null 2>&1 || die "Codex CLI not found. Install OpenAI Codex first."
ok "Codex CLI found."

# --- 3. CODEX_HOME ---
mkdir -p "$CODEX_HOME"

# --- 4. Copy proxy ---
step "Installing proxy..."
cp "$REPO_DIR/proxy/zai-codex-responses-proxy.mjs" "$CODEX_HOME/zai-codex-responses-proxy.mjs"
ok "Proxy installed."

# --- 5. Copy profile ---
step "Installing glm52 profile..."
cp "$REPO_DIR/codex/profiles/glm52.config.toml" "$CODEX_HOME/glm52.config.toml"
ok "Profile installed."

# --- 6. Copy scripts + chmod ---
step "Installing scripts..."
for s in start-proxy.sh stop-proxy.sh start-codex-glm52.sh; do
  cp "$REPO_DIR/codex/scripts/$s" "$CODEX_HOME/$s"
  chmod +x "$CODEX_HOME/$s"
done
ok "Scripts installed."

# --- 7. API key ---
step "Checking ZAI_API_KEY..."
if [ -z "${ZAI_API_KEY:-}" ] && [ -z "${Z_AI_API_KEY:-}" ] && [ -z "${ZHIPUAI_API_KEY:-}" ]; then
  echo
  echo "    ZAI_API_KEY not found in environment."
  echo "    Get your key at: https://z.ai"
  read -rp "    Paste your ZAI_API_KEY (or Enter to skip): " KEY
  if [ -n "$KEY" ]; then
    # Persist to shell rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
      [ -f "$rc" ] && echo "export ZAI_API_KEY=\"$KEY\"" >> "$rc"
    done
    export ZAI_API_KEY="$KEY"
    ok "ZAI_API_KEY saved to shell rc."
  else
    echo "    Skipped. Set ZAI_API_KEY manually before use."
  fi
else
  ok "ZAI_API_KEY found."
fi

# --- 8. Done ---
echo
green "========================================"
ok "Setup complete!"
green "========================================"
echo
echo "Quick start:"
echo "  1. Start proxy + Codex with GLM-5.2:"
echo "     start-codex-glm52.sh"
echo
echo "  2. Or manually:"
echo "     start-proxy.sh"
echo "     codex --profile glm52"
echo