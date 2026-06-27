#!/usr/bin/env bash
# ============================================================
# Codex GLM-5.2 Setup - Linux/macOS Installer
# ============================================================
# ⚠️  NOTE: Linux/macOS scripts are UNTESTED.
#     Tested and verified on Windows only. Use at your own risk
#     and verify each step manually. Bug reports welcome.
# ============================================================
# Usage:  bash install.sh
# ============================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

cyan()  { printf '\033[36m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }
step()  { printf '[*] %s\n' "$1"; }
ok()    { printf '[+] %s\n' "$1"; }
die()   { red "[!] $1"; exit 1; }

cyan "Codex GLM-5.2 Setup"
echo  "    Repo:       $REPO_DIR"
echo  "    CODEX_HOME: $CODEX_HOME"
echo
yellow "⚠️  Linux/macOS scripts are UNTESTED. Verify manually."
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

# --- 4. Backup config.toml (for rollback) ---
config_path="$CODEX_HOME/config.toml"
config_bak="$CODEX_HOME/config.toml.pre-glm52.bak"
step "Backing up config.toml..."
if [ -f "$config_path" ] && [ ! -f "$config_bak" ]; then
  cp "$config_path" "$config_bak"
  ok "Backup saved: config.toml.pre-glm52.bak"
elif [ -f "$config_bak" ]; then
  ok "Backup already exists (keeping original)."
else
  ok "No config.toml yet."
fi

# --- 5. Copy proxy ---
step "Installing proxy..."
cp "$REPO_DIR/proxy/zai-codex-responses-proxy.mjs" "$CODEX_HOME/zai-codex-responses-proxy.mjs"
ok "Proxy installed."

# --- 6. Copy profile ---
step "Installing glm52 profile..."
cp "$REPO_DIR/codex/profiles/glm52.config.toml" "$CODEX_HOME/glm52.config.toml"
ok "Profile installed."

# --- 7. Copy scripts + chmod ---
step "Installing scripts..."
for s in start-proxy.sh stop-proxy.sh start-codex-glm52.sh; do
  cp "$REPO_DIR/codex/scripts/$s" "$CODEX_HOME/$s"
  chmod +x "$CODEX_HOME/$s"
done
ok "Scripts installed."

# --- 8. Patch config.toml ---
step "Patching config.toml..."
if [ -f "$config_path" ]; then
  if grep -q '\[model_providers\.zai_coding\]' "$config_path"; then
    ok "[model_providers.zai_coding] already present."
  else
    cat >> "$config_path" << 'PATCH'

[model_providers.zai_coding]
name = "Z.ai GLM Coding Plan via local Responses proxy"
base_url = "http://127.0.0.1:11439"
PATCH
    ok "Added [model_providers.zai_coding] to config.toml."
  fi
else
  die "config.toml not found at $config_path. Run Codex at least once first."
fi

# --- 9. API key ---
step "Checking ZAI_API_KEY..."
if [ -z "${ZAI_API_KEY:-}" ] && [ -z "${Z_AI_API_KEY:-}" ] && [ -z "${ZHIPUAI_API_KEY:-}" ]; then
  echo
  echo "    ZAI_API_KEY not found in environment."
  echo "    Get your key at: https://z.ai"
  read -rp "    Paste your ZAI_API_KEY (or Enter to skip): " KEY
  if [ -n "$KEY" ]; then
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

# --- 10. Done ---
echo
green "========================================"
ok "Setup complete!"
green "========================================"
echo
echo "Quick start:"
echo "  start-codex-glm52.sh     (starts proxy + Codex with GLM-5.2)"
echo
echo "To roll back:"
echo "  bash rollback.sh"
echo
