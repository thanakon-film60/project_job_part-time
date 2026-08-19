@echo off
REM Open the PART-TIME server control panel.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0deploy\gui.ps1"
