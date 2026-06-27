@echo off
setlocal
set "SCRIPT=%~dp0..\..\proxy\zai-codex-responses-proxy.mjs"
set "OUT=%USERPROFILE%\.codex\zai-codex-proxy.out.log"
set "ERR=%USERPROFILE%\.codex\zai-codex-proxy.err.log"
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$conn = Get-NetTCPConnection -LocalPort 11439 -State Listen -ErrorAction SilentlyContinue; if (-not $conn) { Start-Process -FilePath 'node' -ArgumentList @('%SCRIPT%') -RedirectStandardOutput '%OUT%' -RedirectStandardError '%ERR%' -WindowStyle Hidden }"
echo Proxy started on http://127.0.0.1:11439
endlocal
