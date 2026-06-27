# ============================================================
# Codex GLM-5.2 Setup - Windows Installer (PowerShell)
# ============================================================
# Usage: powershell -ExecutionPolicy Bypass -File install.ps1
#
# Non-interactive: ZAI_API_KEY must be set in the environment
# before running this script. If missing, the script prints
# instructions and exits. AI agents should ask the user for
# the key, save it to the User environment variable, then run.
# ============================================================
[CmdletBinding()]
param(
  [string]$RepoDir
)

$ErrorActionPreference = "Stop"
if (-not $RepoDir) {
    $RepoDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
}

$CodexHome = $env:CODEX_HOME
if (-not $CodexHome) {
    $CodexHome = Join-Path $env:USERPROFILE ".codex"
}

function Step($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "[+] $msg" -ForegroundColor Green }
function Die($msg)  { Write-Host "[!] $msg" -ForegroundColor Red; exit 1 }

function Remove-ZaiProviderBlock($Path) {
    if (-not (Test-Path $Path)) { return $false }

    $lines = Get-Content $Path
    $result = @()
    $skip = $false
    $removed = $false

    foreach ($line in $lines) {
        if ($line -match '^\[model_providers\.zai_coding\]') {
            $skip = $true
            $removed = $true
            continue
        }
        if ($skip -and $line -match '^\[') {
            $skip = $false
        }
        if (-not $skip) {
            $result += $line
        }
    }

    if ($removed) {
        $result | Set-Content $Path -Encoding UTF8
    }

    return $removed
}

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

# --- 3. Check API key ---
Step "Checking ZAI_API_KEY..."
$apiKey = [Environment]::GetEnvironmentVariable("ZAI_API_KEY", "User")
if (-not $apiKey) { $apiKey = [Environment]::GetEnvironmentVariable("Z_AI_API_KEY", "User") }
if (-not $apiKey) { $apiKey = [Environment]::GetEnvironmentVariable("ZHIPUAI_API_KEY", "User") }
if (-not $apiKey) { $apiKey = $env:ZAI_API_KEY }
if (-not $apiKey) { $apiKey = $env:Z_AI_API_KEY }
if (-not $apiKey) { $apiKey = $env:ZHIPUAI_API_KEY }

if (-not $apiKey) {
    Write-Host ""
    Write-Host "ZAI_API_KEY is not set." -ForegroundColor Yellow
    Write-Host "AI agents: ask the user for their key, then run:" -ForegroundColor Yellow
    Write-Host "[Environment]::SetEnvironmentVariable('ZAI_API_KEY','<key>','User')" -ForegroundColor Yellow
    Write-Host "Then restart the shell and re-run this script." -ForegroundColor Yellow
    Write-Host "Manual setup: get a key at https://z.ai and run:" -ForegroundColor Yellow
    Write-Host "setx ZAI_API_KEY `"your-key-here`"" -ForegroundColor Yellow
    exit 1
}
Ok "ZAI_API_KEY found."

# --- 4. Ensure CODEX_HOME exists ---
if (-not (Test-Path $CodexHome)) {
    New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null
}

# --- 5. Backup config.toml ---
$configPath = Join-Path $CodexHome "config.toml"
$configBak = Join-Path $CodexHome "config.toml.pre-glm52.bak"
Step "Backing up config.toml..."
if ((Test-Path $configPath) -and -not (Test-Path $configBak)) {
    Copy-Item $configPath $configBak -Force
    Ok "Backup saved: config.toml.pre-glm52.bak"
} elseif (Test-Path $configBak) {
    Ok "Backup already exists (keeping original)."
} else {
    Ok "No config.toml yet; nothing to back up."
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
foreach ($scriptName in @("start-proxy.cmd", "stop-proxy.cmd", "start-codex-glm52.cmd")) {
    Copy-Item (Join-Path $RepoDir "codex\scripts\$scriptName") `
              (Join-Path $CodexHome $scriptName) -Force
}
Ok "Scripts installed."

# --- 9. Keep provider scoped to the glm52 profile ---
Step "Checking global config.toml..."
if (Remove-ZaiProviderBlock $configPath) {
    Ok "Removed stale global [model_providers.zai_coding] block."
} else {
    Ok "No global GLM provider block found."
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
