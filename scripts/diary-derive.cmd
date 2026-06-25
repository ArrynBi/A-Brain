@echo off
setlocal
for %%I in ("%~f0") do (
  set "SCRIPT_DIR=%%~dpI"
  set "SCRIPT_NAME=%%~nI"
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%%SCRIPT_NAME%.ps1" %*
