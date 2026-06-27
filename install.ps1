# ============================================================
# Codex GLM-5.2 Setup - Windows Installer (PowerShell)
# ============================================================
# Usage:  powershell -ExecutionPolicy Bypass -File install.ps1
#
# Non-interactive: ZAI_API_KEY must be set in the environment
# BEFORE running this script. If missing, the script prints
# instructions and exits. AI agents should ask the user for
# the key, save it to the User environment variable, then run.
# ============================================================
[CmdletBinding()]
param(
  [string]$RepoDir = $(Split-Path -Parent $MyInvocation.MyCommand.Path)
)

$ErrorActionPreference = "Stop"
$CodexHome = $env:CODEX_HOME; if (-not $CodexHome) { $CodexHome = Join-Path $env:USERPROFILE ".codex" }

function Step($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "[+] $msg" -ForegroundColor Green }
function Die($msg)  { Write-Host "[!] $msg" -ForegroundColor Red; exit 1 }

Step "Codex GLM-5.2 Setup"
Write-Host "    Repo:       $RepoDir"
Write-Host "    CODEX_HOME: $CodexHome`n"

# --- 1. Node.js ---
Step "Checking Node.js..."
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Die "Node.js not found. Install from https://nodejs.org then re-run."
}
Ok "Node $(node -v) found."

# --- 2. Codex CLI ---
Step "Checking Codex CLI..."
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    Die "Codex CLI not found. Install OpenAI Codex first."
}
Ok "Codex CLI found."

# --- 3. Check API key (NON-INTERACTIVE) ---
Step "Checking ZAI_API_KEY..."
$apiKey = [Environment]::GetEnvironmentVariable("ZAI_API_KEY","User")
if (-not $apiKey) { $apiKey = [Environment]::GetEnvironmentVariable("Z_AI_API_KEY","User") }
if (-not $apiKey) { $apiKey = [Environment]::GetEnvironmentVariable("ZHIPUAI_API_KEY","User") }

if (-not $apiKey) {
    Write-Host ""
    Write-Host "  ┌──────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "  │  ZAI_API_KEY is not set.                        │" -ForegroundColor Yellow
    Write-Host "  │                                                  │" -ForegroundColor Yellow
    Write-Host "  │  AI agents: Ask the user for their key, then:    │" -ForegroundColor Yellow
    Write-Host "  │  [Environment]::SetEnvironmentVariable(          │" -ForegroundColor Yellow
    Write-Host "  │    'ZAI_API_KEY','<key>','User')                 │" -ForegroundColor Yellow
    Write-Host "  │  Then restart the shell and re-run this script.  │" -ForegroundColor Yellow
    Write-Host "  │                                                  │" -ForegroundColor Yellow
    Write-Host "  │  Manual: Get a key at https://z.ai and set it:   │" -ForegroundColor Yellow
    Write-Host "  │  setx ZAI_API_KEY \"your-key-here\"                │" -ForegroundColor Yellow
    Write-Host "  └──────────────────────────────────────────────────┘" -ForegroundColor Yellow
    exit 1
}
Ok "ZAI_API_KEY found."

# --- 4. Ensure CODEX_HOME exists ---
if (-not (Test-Path $CodexHome)) { New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null }

# --- 5. Backup config.toml (for rollback) ---
$configPath = Join-Path $CodexHome "config.toml"
$configBak = Join-Path $CodexHome "config.toml.pre-glm52.bak"
Step "Backing up config.toml..."
if ((Test-Path $configPath) -and -not (Test-Path $configBak)) {
    Copy-Item $configPath $configBak -Force
    Ok "Backup saved: config.toml.pre-glm52.bak"
} elseif (Test-Path $configBak) {
    Ok "Backup already exists (keeping original)."
} else {
    Ok "No config.toml yet — nothing to back up."
}

# --- 6. Copy proxy ---
Step "Installing proxy..."
Copy-Item (Join-Path $RepoDir "proxy\zai-codex-responses-proxy.mjs") `
          (Join-Path $CodexHome "zai-codex-responses-proxy.mjs") -Force
Ok "Proxy installed."

# --- 7. Copy profile ---
Step "Installing glm52 profile..."
Copy-Item (Join-Path $RepoDir "codex\profiles\glm52.config.toml") `
          (Join-Path $CodexHome "glm52.config.toml") -Force
Ok "Profile installed."

# --- 8. Copy scripts ---
Step "Installing scripts..."
foreach ($s in @("start-proxy.cmd","stop-proxy.cmd","start-codex-glm52.cmd")) {
    Copy-Item (Join-Path $RepoDir "codex\scripts\$s") (Join-Path $CodexHome $s) -Force
}
Ok "Scripts installed."

# --- 9. Patch config.toml: add [model_providers.zai_coding] ---
Step "Patching config.toml..."
if (Test-Path $configPath) {
    $content = Get-Content $configPath -Raw
    if ($content -match '\[model_providers\.zai_coding\]') {
        Ok "[model_providers.zai_coding] already present."
    } else {
        $block = @"

[model_providers.zai_coding]
name = "Z.ai GLM Coding Plan via local Responses proxy"
base_url = "http://127.0.0.1:11439"
"@
        Add-Content -Path $configPath -Value $block -Encoding UTF8
        Ok "Added [model_providers.zai_coding] to config.toml."
    }
} else {
    Die "config.toml not found at $configPath. Run Codex at least once first."
}

# --- 10. Done ---
Write-Host "`n========================================" -ForegroundColor Green
Ok "Setup complete!"
Write-Host "========================================`n" -ForegroundColor Green
Write-Host "Quick start:"
Write-Host "  start-codex-glm52.cmd     (starts proxy + Codex with GLM-5.2)"
Write-Host ""
Write-Host "To roll back:"
Write-Host "  powershell -ExecutionPolicy Bypass -File rollback.ps1"
Write-Host ""
