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

# `--import` поднимает РЕДАКТОР, а тот перед выходом восстанавливает сохранённую UI-сессию:
# доки, открытые вкладки сцен, окна плагинов (.godot/editor/editor_layout.cfg и
# main.tscn-editstate-*.cfg). На сервере без дисплея этот шаг («Loading plugin window layout»)
# не возвращается НИКОГДА: импорт давно закончен, кэш классов записан, а процесс висит, пока его
# не убьёт timeout ниже — отсюда и `[warn] --import failed or timed out`, и три минуты простоя
# сервиса на каждый деплой (stop -> 180с -> start).
# Сама сессия на сервере бессмысленна (редактором тут никто не пользуется), а сохраняет её только
# интерактивный запуск — headless-импорт её не пишет. Поэтому сносим её перед импортом: без неё
# восстанавливать нечего, и --import честно отрабатывает за ~15с с кодом 0.
echo "--- drop editor UI session (headless import hangs restoring it) ---"
rm -rf "$REMOTE/.godot/editor"

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

# Сменившегося PID мало: процесс живёт и с несобравшимися скриптами (напр. кэш классов отстал от
# нового scripts/ -> автолоад Net не создаётся -> start_server не вызывается). Тогда сервис
# «active», PID новый, деплой рапортует [OK] — а порт не слушает никто, и игроки видят 502.
# Единственный честный признак «сервер поднялся» — открытый 8910, по нему и судим.
if ! ss -ltn | grep -q ':8910'; then
	echo "[FAIL] Порт 8910 не слушает - сервер запустился, но не работает."
	echo "       Смотри ошибки скриптов: journalctl -u warmarked -n 30 --no-pager"
	exit 1
fi
ss -ltnp | grep 8910
echo "[OK] порт 8910 слушает - сервер действительно поднялся"
