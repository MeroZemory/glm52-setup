# ============================================================
# Codex GLM-5.2 Setup - Windows Installer (PowerShell)
# ============================================================
# Usage:  powershell -ExecutionPolicy Bypass -File install.ps1
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

# --- 3. Ensure CODEX_HOME exists ---
if (-not (Test-Path $CodexHome)) { New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null }

# --- 4. Backup config.toml (for rollback) ---
$configPath = Join-Path $CodexHome "config.toml"
$configBak = Join-Path $CodexHome "config.toml.pre-glm52.bak"
Step "Backing up config.toml..."
if ((Test-Path $configPath) -and -not (Test-Path $configBak)) {
    Copy-Item $configPath $configBak -Force
    Ok "Backup saved: config.toml.pre-glm52.bak"
} elseif (Test-Path $configBak) {
    Ok "Backup already exists (keeping original)."
} else {
    Ok "No config.toml yet — will patch after creation."
}

# --- 5. Copy proxy ---
Step "Installing proxy..."
Copy-Item (Join-Path $RepoDir "proxy\zai-codex-responses-proxy.mjs") `
          (Join-Path $CodexHome "zai-codex-responses-proxy.mjs") -Force
Ok "Proxy installed."

# --- 6. Copy profile ---
Step "Installing glm52 profile..."
Copy-Item (Join-Path $RepoDir "codex\profiles\glm52.config.toml") `
          (Join-Path $CodexHome "glm52.config.toml") -Force
Ok "Profile installed."

# --- 7. Copy scripts ---
Step "Installing scripts..."
foreach ($s in @("start-proxy.cmd","stop-proxy.cmd","start-codex-glm52.cmd")) {
    Copy-Item (Join-Path $RepoDir "codex\scripts\$s") (Join-Path $CodexHome $s) -Force
}
Ok "Scripts installed."

# --- 8. Patch config.toml: add [model_providers.zai_coding] ---
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

# --- 9. API key ---
Step "Checking ZAI_API_KEY..."
$apiKey = [Environment]::GetEnvironmentVariable("ZAI_API_KEY","User")
if (-not $apiKey) {
    $apiKey = [Environment]::GetEnvironmentVariable("Z_AI_API_KEY","User")
}
if (-not $apiKey) {
    $apiKey = [Environment]::GetEnvironmentVariable("ZHIPUAI_API_KEY","User")
}
if (-not $apiKey) {
    Write-Host "`n    ZAI_API_KEY not found in environment." -ForegroundColor Yellow
    Write-Host "    Get your key at: https://z.ai" -ForegroundColor Yellow
    $key = Read-Host "    Paste your ZAI_API_KEY (or Enter to skip)"
    if ($key) {
        [Environment]::SetEnvironmentVariable("ZAI_API_KEY",$key,"User")
        $env:ZAI_API_KEY = $key
        Ok "ZAI_API_KEY saved to user environment."
    } else {
        Write-Host "    Skipped. Set ZAI_API_KEY manually before use." -ForegroundColor Yellow
    }
} else {
    Ok "ZAI_API_KEY found."
}

# --- 10. Done ---
Write-Host "`n========================================" -ForegroundColor Green
Ok "Setup complete!"
Write-Host "========================================`n" -ForegroundColor Green
Write-Host "Quick start:"
Write-Host ""
Write-Host "  start-codex-glm52.cmd     (starts proxy + Codex with GLM-5.2)"
Write-Host ""
Write-Host "To roll back (removes everything, restores config):"
Write-Host "  powershell -ExecutionPolicy Bypass -File rollback.ps1"
Write-Host ""
