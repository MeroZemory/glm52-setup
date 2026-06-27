# ============================================================
# Codex GLM-5.2 Setup — Windows Rollback (PowerShell)
# ============================================================
# Removes every trace of the GLM-5.2 integration from CODEX_HOME:
#   - Kills the proxy process on port 11439
#   - Removes proxy, profile, and scripts
#   - Restores config.toml from backup (or surgically strips
#     the [model_providers.zai_coding] block if no backup exists)
#
# Usage:  powershell -ExecutionPolicy Bypass -File rollback.ps1
# Safe to run multiple times.
# ============================================================
[CmdletBinding()]
param(
  [string]$CodexHome = $({ if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" } }.Invoke())
)

$ErrorActionPreference = "Stop"

function Step($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "[+] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }

Step "Codex GLM-5.2 Rollback"
Write-Host "    CODEX_HOME: $CodexHome`n"

# --- 1. Kill proxy on port 11439 ---
Step "Stopping proxy (port 11439)..."
$conn = Get-NetTCPConnection -LocalPort 11439 -State Listen -ErrorAction SilentlyContinue
if ($conn) {
    $conn | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
    Ok "Proxy process killed."
} else {
    Ok "Proxy not running."
}

# --- 2. Remove installed files ---
Step "Removing installed files..."
$filesToRemove = @(
    "zai-codex-responses-proxy.mjs",
    "glm52.config.toml",
    "start-proxy.cmd",
    "stop-proxy.cmd",
    "start-codex-glm52.cmd",
    "zai-codex-proxy.out.log",
    "zai-codex-proxy.err.log"
)

foreach ($f in $filesToRemove) {
    $path = Join-Path $CodexHome $f
    if (Test-Path $path) {
        Remove-Item $path -Force
        Ok "Removed: $f"
    }
}

# --- 3. Restore or patch config.toml ---
$configPath = Join-Path $CodexHome "config.toml"
$configBak = Join-Path $CodexHome "config.toml.pre-glm52.bak"

Step "Restoring config.toml..."

if (Test-Path $configBak) {
    # Restore from backup
    Copy-Item $configBak $configPath -Force
    Ok "config.toml restored from backup."
} elseif (Test-Path $configPath) {
    # Surgically remove the [model_providers.zai_coding] block
    $lines = Get-Content $configPath
    $result = @()
    $skip = $false

    foreach ($line in $lines) {
        if ($line -match '^\[model_providers\.zai_coding\]') {
            $skip = $true
            continue
        }
        if ($skip -and $line -match '^\[') {
            $skip = $false
        }
        if (-not $skip) {
            $result += $line
        }
    }

    # Clean up trailing empty lines that may result from removal
    while ($result.Count -gt 0 -and $result[-1] -match '^\s*$') {
        $result = $result[0..($result.Count - 2)]
    }

    $result | Set-Content $configPath -Encoding UTF8
    Ok "Removed [model_providers.zai_coding] block from config.toml."
} else {
    Warn "config.toml not found — nothing to patch."
}

# --- 4. Done ---
Write-Host "`n========================================" -ForegroundColor Green
Ok "Rollback complete!"
Write-Host "========================================`n" -ForegroundColor Green
Write-Host "GLM-5.2 integration fully removed. GPT-5.5 default is unaffected.`n"
