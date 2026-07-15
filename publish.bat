@echo off
setlocal enabledelayedexpansion
rem ============================================================
rem  Warmarked one-click publish:
rem   1) build web export into docs/
rem   2) git commit + push (GitHub Pages serves docs/)
rem   3) update and restart the VPS server
rem ============================================================

set GODOT="C:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set HOST=root@curuex.fvds.ru
set REMOTE=/root/warmarked
set RGODOT=/root/godot/Godot_v4.7-stable_linux.x86_64

cd /d "%~dp0"

echo.
echo ============================================================
echo   [1/3] BUILD web export into docs/
echo ============================================================
echo --- reimport resources ---
%GODOT% --headless --path . --import
echo --- export preset "Web" ---
%GODOT% --headless --path . --export-release "Web" "docs\index.html"
if errorlevel 1 (
	echo.
	echo [FAIL] Build failed - not committing, server untouched.
	goto :fail
)
echo [OK] docs/ built.

echo.
echo ============================================================
echo   [2/3] GIT commit + push
echo ============================================================
git add -A
set "MSG="
set /p "MSG=Commit message (Enter = timestamp): "
if "!MSG!"=="" set "MSG=build %date% %time%"
git commit -m "!MSG!"
if errorlevel 1 (
	echo [i] Nothing to commit - probably no changes. Continuing.
) else (
	echo [OK] Commit created.
)
echo --- push ---
git push
if errorlevel 1 (
	echo.
	echo [FAIL] git push failed - check network / GitHub access.
	goto :fail
)
echo [OK] Pushed. GitHub Pages updates in 1-2 minutes.

echo.
echo ============================================================
echo   [3/3] UPDATE server on VPS
echo ============================================================
echo --- clean staging ---
ssh %HOST% "rm -rf %REMOTE%/scripts_new %REMOTE%/addons_new %REMOTE%/project.godot.new"
echo --- copy scripts ---
scp -r scripts %HOST%:%REMOTE%/scripts_new
if errorlevel 1 (
	echo.
	echo [FAIL] scp failed - old server version is intact.
	goto :fail
)
echo --- copy addons + project.godot (needed for the godot-sqlite account system) ---
scp -r addons %HOST%:%REMOTE%/addons_new
if errorlevel 1 (
	echo.
	echo [FAIL] scp failed - old server version is intact.
	goto :fail
)
scp project.godot %HOST%:%REMOTE%/project.godot.new
if errorlevel 1 (
	echo.
	echo [FAIL] scp failed - old server version is intact.
	goto :fail
)
scp deploy_remote.sh %HOST%:%REMOTE%/deploy_remote.sh
if errorlevel 1 (
	echo.
	echo [FAIL] scp failed - old server version is intact.
	goto :fail
)
rem Delegated to deploy_remote.sh instead of one giant quoted multi-command ssh string -
rem that pattern silently broke once the command got long/complex enough (systemctl
rem stop/start stopped taking effect while every step still reported success).
echo --- run deploy_remote.sh on the server ---
ssh %HOST% "bash %REMOTE%/deploy_remote.sh"
if errorlevel 1 (
	echo.
	echo [FAIL] Remote deploy script failed - see output above ^(server may still be on the OLD version^).
	goto :fail
)

echo.
echo ============================================================
echo   DONE: web + server updated.
echo   Check above: [OK] build, push, and "[OK] restarted: PID X -^> Y" + port 8910.
echo ============================================================
goto :end

:fail
echo.
echo ======== ABORTED ON ERROR (see message above) ========

:end
echo.
pause
