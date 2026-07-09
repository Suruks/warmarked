#!/usr/bin/env python3
"""Раздаёт веб-экспорт Godot по http с заголовками COOP/COEP (нужны для SharedArrayBuffer).
Godot-веб НЕЛЬЗЯ открывать двойным кликом (file://) — только так.

Автоматически находит экспорт: build/web/, build/ или корень проекта (Warmarked.html).
Запуск:  python serve_web.py    → открой напечатанный URL в двух вкладках."""
import http.server
import socketserver
import os

PORT = 8060
HERE = os.path.dirname(os.path.abspath(__file__))


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

    def log_message(self, fmt, *args):
        pass  # тише в консоли


def find_export():
    for d in [os.path.join(HERE, "build", "web"), os.path.join(HERE, "build"), HERE]:
        if not os.path.isdir(d):
            continue
        if os.path.exists(os.path.join(d, "index.html")):
            return d, "index.html"
        htmls = sorted(f for f in os.listdir(d) if f.lower().endswith(".html"))
        if htmls:
            return d, htmls[0]
    return None, None


if __name__ == "__main__":
    root, html = find_export()
    if root is None:
        raise SystemExit("Не нашёл экспортированный .html (build/web/, build/ или корень).")
    os.chdir(root)
    # allow_reuse_address НЕ включаем: на Windows это разрешает двойное связывание порта,
    # из-за чего старый зомби-сервер мог перехватывать запросы (→ ложный 404).
    # Без него второй запуск честно падает с "address already in use".
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        print("Раздаю: %s" % root)
        print("Открой в браузере (в двух вкладках):")
        print("    http://localhost:%d/%s" % (PORT, html))
        print("Ctrl+C — стоп.")
        httpd.serve_forever()
