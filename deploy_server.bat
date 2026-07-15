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
echo === [3/4] Copy addons + project.godot (staging) ===
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

echo.
echo === [4/4] Swap, import resources, restart ===
ssh %HOST% "pkill -9 -f 'Godot.*--import'; sleep 1; rm -rf %REMOTE%/scripts %REMOTE%/addons && mv %REMOTE%/scripts_new %REMOTE%/scripts && mv %REMOTE%/addons_new %REMOTE%/addons && mv %REMOTE%/project.godot.new %REMOTE%/project.godot && systemctl stop warmarked && %RGODOT% --headless --path %REMOTE% --import && systemctl start warmarked && sleep 4 && echo --- STATUS --- && systemctl is-active warmarked && { ss -ltnp | grep 8910 || echo '(port 8910 not shown yet - check manually)'; }"

echo.
echo === Done. Check above: active + line with port 8910 ===
pause
