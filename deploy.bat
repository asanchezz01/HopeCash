@echo off
setlocal

set "ROOT=%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\deploy-server.ps1" -WebPort 8092 -ApiPort 3001 -MysqlPort 3306 %*
exit /b %ERRORLEVEL%
