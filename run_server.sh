#!/usr/bin/env bash
# Запуск авторитетного сервера Warmarked (headless) на Linux/VPS.
# Godot 4.7 Linux-бинарь: укажи путь в переменной GODOT (или положи в PATH как `godot`).
#   GODOT=/opt/godot/godot.x11.opt.tools.64 ./run_server.sh
set -euo pipefail
GODOT="${GODOT:-godot}"
PROJECT="$(cd "$(dirname "$0")" && pwd)"
echo "Starting Warmarked server (ws://0.0.0.0:8910)..."
exec "$GODOT" --headless --path "$PROJECT" -- server
