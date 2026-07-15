@echo off
setlocal
rem === Deploy Warmarked server logic to the VPS ===
rem Copies scripts + addons + project.godot, reimports the project, restarts the service.
rem addons/ and project.godot are included because the account system (login/register/
rem loadout/difficulty) depends on the godot-sqlite GDExtension declared there - without
rem it the server can't open PlayerDB and auth RPCs just hang on the client forever.
rem Double-click = full server update.

set HOST=root@curuex.fvds.ru
set REMOTE=/root/warmarked
set RGODOT=/root/godot/Godot_v4.7-stable_linux.x86_64

cd /d "%~dp0"

echo.
echo === [1/4] Clean staging folders on server ===
ssh %HOST% "rm -rf %REMOTE%/scripts_new %REMOTE%/addons_new %REMOTE%/project.godot.new"

echo.
echo === [2/4] Copy scripts (staging) ===
scp -r scripts %HOST%:%REMOTE%/scripts_new
if errorlevel 1 (
	echo.
	echo [FAIL] scp failed - old server version is intact.
	pause
	exit /b 1
)

echo.
echo === [3/4] Copy addons + project.godot + remote deploy script (staging) ===
scp -r addons %HOST%:%REMOTE%/addons_new
if errorlevel 1 (
	echo.
	echo [FAIL] scp failed - old server version is intact.
	pause
	exit /b 1
)
scp project.godot %HOST%:%REMOTE%/project.godot.new
if errorlevel 1 (
	echo.
	echo [FAIL] scp failed - old server version is intact.
	pause
	exit /b 1
)
scp deploy_remote.sh %HOST%:%REMOTE%/deploy_remote.sh
if errorlevel 1 (
	echo.
	echo [FAIL] scp failed - old server version is intact.
	pause
	exit /b 1
)

rem === [4/4] Swap, import resources, restart ===
rem Delegated to deploy_remote.sh (checked into the repo, always in sync with this .bat)
rem instead of one giant quoted multi-command ssh string - that pattern silently broke
rem once the command got long/complex enough (systemctl stop/start stopped taking effect
rem while every step still reported success). One plain "bash script.sh" call has nothing
rem for cmd.exe/ssh.exe quoting to mangle.
echo.
echo === [4/4] Run deploy_remote.sh on the server ===
ssh %HOST% "bash %REMOTE%/deploy_remote.sh"
if errorlevel 1 (
	echo.
	echo [FAIL] Remote deploy script failed - see output above ^(server may still be on the OLD version^).
	pause
	exit /b 1
)

echo.
echo === Done. Check above: [OK] restarted: PID X -^> Y, and the port 8910 line ===
pause
