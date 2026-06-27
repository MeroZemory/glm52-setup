@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$conn = Get-NetTCPConnection -LocalPort 11439 -State Listen -ErrorAction SilentlyContinue; if ($conn) { $conn | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force } }"
echo Proxy stopped.
