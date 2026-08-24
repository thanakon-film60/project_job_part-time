@echo off
REM ยกสิทธิ์เป็น Administrator เอง (จะมีหน้าต่าง UAC ขึ้นมาให้กด Yes)
REM แล้วรัน BUILD_DEPLOY.ps1 ซึ่ง build React + copy ขึ้น IIS + restart backend
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"%~dp0BUILD_DEPLOY.ps1\"'"
