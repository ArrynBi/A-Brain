@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ingest-library.ps1" %*
