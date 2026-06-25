@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0diary-event.ps1" %*
