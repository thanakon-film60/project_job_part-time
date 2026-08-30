@echo off
REM ===================================================================
REM  Double-click once to make the whole system start with Windows:
REM    IIS website        -> Automatic service
REM    FastAPI backend    -> AtStartup scheduled task
REM    Cloudflare Tunnel  -> Automatic service
REM    Control panel GUI  -> AtLogOn scheduled task (also starts Production)
REM  Auto-elevates to Administrator.
REM ===================================================================
chcp 65001 >nul
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy\windows-server\install-autostart.ps1"
pause
