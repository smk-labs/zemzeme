#!/usr/bin/env python3
"""Static server for the dictation page + POST /paste:
copies text to clipboard, closes the frontmost (dictation) window with Cmd+W,
then pastes with Cmd+V into the app that regains focus."""
import http.server
import json
import queue
import subprocess
import threading
import time
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
SESSIONS = os.path.join(ROOT, "sessions")
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
            body = json.dumps({"age": time.time() - LAST_LIVE["t"]}).encode()
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
            with open(os.path.join(ROOT, "log.txt"), "a") as f:
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


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
