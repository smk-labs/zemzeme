#!/usr/bin/env python3
"""Static server for the dictation page + POST /paste:
copies text to clipboard, closes the frontmost (dictation) window with Cmd+W,
then pastes with Cmd+V into the app that regains focus."""
import errno
import http.client
import http.server
import json
import os
import queue
import subprocess
import sys
import threading
import time

# realpath نه abspath: این مسیر هویت سرور است (در /alive برمی‌گردد و اپ با آن
# «سرور خودمان» را از پروسه جامانده تشخیص می‌دهد)، پس باید بدون سیم‌لینک و پایدار باشد
ROOT = os.path.dirname(os.path.realpath(__file__))   # صفحه از همین‌جا سرو می‌شود
# بسته اپ خواندنی است، پس داده جای دیگری می‌نشیند؛ اپ مسیر را با ZEMZEME_DATA می‌دهد
DATA = os.environ.get("ZEMZEME_DATA") or ROOT
SESSIONS = os.path.join(DATA, "sessions")
os.makedirs(SESSIONS, exist_ok=True)
PORT = 17635

CLIENTS = set()          # open SSE queues, one per connected /events client
CLIENTS_LOCK = threading.Lock()
LAST_LIVE = {"t": 0.0}   # time.time() of the last /live POST, for /alive


def keystroke(key):
    subprocess.run([
        "osascript", "-e",
        f'tell application "System Events" to keystroke "{key}" using command down',
    ])


def finish(text):
    subprocess.run("pbcopy", input=text.encode())
    time.sleep(0.2)
    keystroke("w")   # close dictation window; focus returns to previous app
    time.sleep(0.5)  # give Windows App clipboard sync a moment too
    keystroke("v")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path.startswith("/events"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            q = queue.Queue()
            with CLIENTS_LOCK:
                CLIENTS.add(q)
            while True:
                try:
                    try:
                        item = q.get(timeout=15)
                        self.wfile.write(b"data: " + item + b"\n\n")
                    except queue.Empty:
                        self.wfile.write(b": hb\n\n")  # comment line keeps the connection alive
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError, OSError):
                    with CLIENTS_LOCK:
                        CLIENTS.discard(q)
                    return
        elif self.path.startswith("/alive"):
            # هویت، نه فقط زنده‌بودن: root و pid می‌گویند «کدام» سرور جواب می‌دهد.
            # اپ (engines.m) فقط جواب با root همخوان را سرور خودش می‌داند.
            body = json.dumps({"age": time.time() - LAST_LIVE["t"],
                               "root": ROOT, "pid": os.getpid()}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)
        else:
            return super().do_GET()

    def do_POST(self):
        if self.path == "/save":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode("utf-8", "replace")
            sid, _, chunk = body.partition("\t")
            sid = "".join(c for c in sid if c.isalnum() or c in "-_")[:40] or "session"
            with open(os.path.join(SESSIONS, sid + ".txt"), "a") as f:
                f.write(chunk + "\n")
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
        elif self.path == "/log":
            length = int(self.headers.get("Content-Length", 0))
            line = self.rfile.read(length).decode("utf-8", "replace")
            with open(os.path.join(DATA, "log.txt"), "a") as f:
                f.write(time.strftime("%H:%M:%S ") + line + "\n")
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
        elif self.path == "/paste":
            length = int(self.headers.get("Content-Length", 0))
            text = json.loads(self.rfile.read(length) or b"{}").get("text", "").strip()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
            if text:
                threading.Thread(target=finish, args=(text,), daemon=True).start()
        elif self.path == "/live":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            LAST_LIVE["t"] = time.time()
            with CLIENTS_LOCK:
                for q in CLIENTS:
                    q.put(body)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
        else:
            self.send_response(404)
            self.end_headers()


# bind شکست‌خورده باید بلند بمیرد، نه بی‌صدا: پورت گرفته یعنی یک نسخه دیگر (معمولا
# جامانده از سشن قبل) دارد جواب می‌دهد و این پروسه هیچ کاره است. از /alive خودش
# می‌پرسیم کیست تا پیام، مقصر را با pid و مسیر نام ببرد.
try:
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
except OSError as e:
    if e.errno != errno.EADDRINUSE:
        sys.exit(f"zemzeme serve.py: bind 127.0.0.1:{PORT} failed: {e}")
    who = ""
    try:
        conn = http.client.HTTPConnection("127.0.0.1", PORT, timeout=1)
        conn.request("GET", "/alive")
        info = json.loads(conn.getresponse().read())
        if info.get("root") == ROOT:
            sys.exit(f"zemzeme serve.py: already running for {ROOT} "
                     f"(pid {info.get('pid', '?')})")
        who = f" by pid {info.get('pid', '?')} serving {info.get('root', 'unknown root')}"
    except Exception:
        pass  # صاحب پورت HTTP نیست یا /alive ندارد؛ پیام عمومی کافی است
    sys.exit(f"zemzeme serve.py: port {PORT} is taken{who}; free it (lsof -i :{PORT})")
server.serve_forever()
