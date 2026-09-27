@echo off
title League of Legends - Fast Multi-Threaded Updater
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0update_lol.ps1"
echo.
pause
