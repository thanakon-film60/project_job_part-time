@echo off
REM ===================================================================
REM  Double-click this file to open the MARDODI check-in control panel.
REM  The panel is a real Windows window (WinForms) so Thai text shows
REM  correctly - the console font cannot render Thai.
REM ===================================================================
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0deploy\gui.ps1"
