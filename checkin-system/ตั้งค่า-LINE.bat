@echo off
REM ===================================================================
REM  Double-click to configure LINE notifications.
REM  Auto-elevates to Administrator (needed to restart the backend).
REM ===================================================================
chcp 65001 >nul
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy\line\set-line-config.ps1"
pause
