#!/usr/bin/env bash
# Серверная половина деплоя Warmarked. Живёт в репозитории, копируется на VPS и
# выполняется там ОДНОЙ простой командой (`ssh HOST "bash REMOTE/deploy_remote.sh"`),
# вместо того чтобы гонять длинную многокомандную строку через cmd.exe -> ssh.exe ->
# удалённый bash — вложенные кавычки/&&/;/{} в одной строке слишком хрупкие для этого
# пути (см. deploy_server.bat/publish.bat: раньше именно так и деплоили, и в какой-то
# момент цепочка стала молча обрываться до systemctl stop/start, сервис не
# перезапускался, а скрипт при этом рапортовал успех).
set -euo pipefail

REMOTE=/root/warmarked
RGODOT=/root/godot/Godot_v4.7-stable_linux.x86_64

echo "--- kill stray --import (lock deadlock guard) ---"
pkill -9 -f 'Godot.*--import' || true
sleep 1

echo "--- swap in staged scripts/addons/project.godot ---"
rm -rf "$REMOTE/scripts" "$REMOTE/addons"
mv "$REMOTE/scripts_new" "$REMOTE/scripts"
mv "$REMOTE/addons_new" "$REMOTE/addons"
mv "$REMOTE/project.godot.new" "$REMOTE/project.godot"

echo "--- restart warmarked.service ---"
OLD_PID="$(systemctl show warmarked -p MainPID --value)"
systemctl stop warmarked
# Импорт под timeout и с `|| echo`, чтобы даже зависший/упавший --import НЕ оставил сервер
# остановленным: при set -e голый сбой прервал бы скрипт до systemctl start (сервис лежит),
# а зависший --import висел бы вечно. Так start выполняется в любом случае.
timeout 180 "$RGODOT" --headless --path "$REMOTE" --import || echo "[warn] --import failed or timed out - starting server anyway"
systemctl start warmarked
sleep 4

echo "--- STATUS ---"
systemctl status warmarked --no-pager -l | head -6
NEW_PID="$(systemctl show warmarked -p MainPID --value)"
if [ "$NEW_PID" = "$OLD_PID" ] || [ "$NEW_PID" = "0" ]; then
	echo "[FAIL] Main PID did not change (was $OLD_PID, still $NEW_PID) - service did NOT actually restart."
	exit 1
fi
echo "[OK] restarted: PID $OLD_PID -> $NEW_PID"
ss -ltnp | grep 8910 || echo '(port 8910 not shown yet - check manually)'
