import sys
import socket
import threading
import time
import webview
from waitress import serve
from app import app
from database import init_db, migrate_db


def find_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def wait_for_server(port, timeout=10):
    import urllib.request
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            urllib.request.urlopen(f'http://127.0.0.1:{port}/', timeout=1)
            return True
        except Exception:
            time.sleep(0.1)
    return False


def start_server(port):
    serve(app, host='127.0.0.1', port=port, threads=4)


if __name__ == '__main__':
    init_db()
    migrate_db()

    port = find_free_port()

    server_thread = threading.Thread(target=start_server, args=(port,), daemon=True)
    server_thread.start()

    if not wait_for_server(port):
        print("Server failed to start", file=sys.stderr)
        sys.exit(1)

    window = webview.create_window(
        title='ComicArc',
        url=f'http://127.0.0.1:{port}/',
        width=1280,
        height=800,
        min_size=(900, 600),
        text_select=False,
    )
    webview.start(debug=False)
