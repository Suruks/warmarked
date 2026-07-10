@echo off
setlocal
rem === Deploy Warmarked server logic to the VPS ===
rem Copies the scripts folder, reimports the project, restarts the service.
rem Double-click = full server update.

set HOST=root@curuex.fvds.ru
set REMOTE=/root/warmarked
set RGODOT=/root/godot/Godot_v4.7-stable_linux.x86_64

cd /d "%~dp0"

echo.
echo === [1/3] Clean staging folder on server ===
ssh %HOST% "rm -rf %REMOTE%/scripts_new"

echo.
echo === [2/3] Copy scripts (staging) ===
scp -r scripts %HOST%:%REMOTE%/scripts_new
if errorlevel 1 (
	echo.
	echo [FAIL] scp failed - old server version is intact.
	pause
	exit /b 1
)

echo.
echo === [3/3] Swap, import resources, restart ===
ssh %HOST% "rm -rf %REMOTE%/scripts && mv %REMOTE%/scripts_new %REMOTE%/scripts && systemctl stop warmarked && %RGODOT% --headless --path %REMOTE% --import && systemctl start warmarked && sleep 4 && echo --- STATUS --- && systemctl is-active warmarked && { ss -ltnp | grep 8910 || echo '(port 8910 not shown yet - check manually)'; }"

echo.
echo === Done. Check above: active + line with port 8910 ===
pause
