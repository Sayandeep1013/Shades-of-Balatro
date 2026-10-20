@echo off
title Shades of Balatro
rem Double-click: opens the Shades of Balatro menu (install / check / switch preset / uninstall).
rem Runs the latest shades.ps1 from GitHub. Extra arguments are passed through, e.g.
rem   Shades-Setup.bat install -Preset stacking
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/Sayandeep1013/Shades-of-Balatro/main/shades.ps1'))) %*"
pause
