#!/usr/bin/env python3
"""Static server for the dictation page + POST /paste:
copies text to clipboard, closes the frontmost (dictation) window with Cmd+W,
then pastes with Cmd+V into the app that regains focus."""
import http.server
import json
import subprocess
import threading
import time
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
SESSIONS = os.path.join(ROOT, "sessions")
os.makedirs(SESSIONS, exist_ok=True)
PORT = 17635


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
        else:
            self.send_response(404)
            self.end_headers()


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
