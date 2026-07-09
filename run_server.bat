@echo off
setlocal
REM Launch the Warmarked authoritative server (headless).
REM If Godot is elsewhere, fix the path below.
set "GODOT=C:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

REM Project dir = folder of this .bat, without trailing backslash
set "PROJECT=%~dp0"
if "%PROJECT:~-1%"=="\" set "PROJECT=%PROJECT:~0,-1%"

echo Starting Warmarked server (ws://0.0.0.0:8910)...
"%GODOT%" --headless --path "%PROJECT%" -- server
pause
