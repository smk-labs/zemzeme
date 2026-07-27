#!/usr/bin/env python3
"""Probes the two unknowns of the full-duplex endpoint before batch mode is designed.

1) speed   - does /up accept faster-than-real-time audio, and is the text still complete?
2) parallel - how many pair sessions does the shared Chromium key tolerate from one IP?

Both use the exact wire format the app uses: raw s16le/16k PCM over a chunked POST to /up,
length-prefixed protobuf frames back on /down. Pacing is done here (not with curl
--limit-rate) so a speed multiplier is exact.

  python3 probe_endpoint.py speed    <audio.raw> [lang]
  python3 probe_endpoint.py parallel <audio.raw> [lang] [n1,n2,...]
"""
import http.client
import json
import secrets
import statistics
import sys
import threading
import time

from down_reader import fields

KEY = "AIzaSyBOti4mM-6x9WDnZIjIeyEU21OpBXqWBgw"
HOST = "www.google.com"
BASE = "/speech-api/full-duplex/v1"


def decode_event(body):
    """-> (finals, interim); same field numbers as core.m / down_reader.py."""
    finals, interim = [], ""
    for f, w, v in fields(body):
        if f == 2 and w == 2:
            is_final, txt = False, ""
            for f2, w2, v2 in fields(v):
                if f2 == 1 and w2 == 2:
                    for f3, w3, v3 in fields(v2):
                        if f3 == 1 and w3 == 2 and not txt:
                            txt = v3.decode("utf-8", "replace")
                elif f2 == 2 and w2 == 0:
                    is_final = bool(v2)
            if is_final:
                finals.append(txt)
            else:
                interim = txt
    return finals, interim


class Session:
    """One up/down pair. feed() paces at speed x real time; result() waits for the tail."""

    def __init__(self, audio, lang, speed, tag=""):
        self.audio, self.lang, self.speed, self.tag = audio, lang, speed, tag
        self.pair = secrets.token_hex(8)
        self.finals, self.last_interim = [], ""
        self.frames = 0
        self.down_http = None
        self.up_http = None
        self.err = None
        self.first_at = None
        self.last_result_at = None      # wall seconds of the last frame carrying text
        self.t0 = time.time()
        self._down = threading.Thread(target=self._read_down, daemon=True)
        self._down.start()
        time.sleep(0.4)                 # down first, like the app

    def _url(self, what):
        if what == "up":
            return ("%s/up?key=%s&pair=%s&lang=%s&client=chromium&continuous&interim"
                    "&maxAlternatives=1&pFilter=0&output=pb" % (BASE, KEY, self.pair, self.lang))
        return "%s/down?key=%s&pair=%s&output=pb" % (BASE, KEY, self.pair)

    def _read_down(self):
        try:
            c = http.client.HTTPSConnection(HOST, timeout=600)
            c.request("GET", self._url("down"))
            r = c.getresponse()
            self.down_http = r.status
            buf = b""
            while True:
                chunk = r.read(4096)
                if not chunk:
                    break
                buf += chunk
                while len(buf) >= 4:
                    n = int.from_bytes(buf[:4], "big")
                    if n > 1_000_000 or len(buf) - 4 < n:
                        break
                    body, buf = buf[4:4 + n], buf[4 + n:]
                    self.frames += 1
                    fin, inter = decode_event(body)
                    now = time.time() - self.t0
                    if self.first_at is None:
                        self.first_at = now
                    if fin or inter:
                        self.last_result_at = now
                    self.finals += fin
                    if inter:
                        self.last_interim = inter
            c.close()
        except Exception as e:                                  # noqa: BLE001
            self.err = "down: %r" % e

    def feed(self):
        """Streams the whole file, sleeping only when ahead of the target rate."""
        try:
            c = http.client.HTTPSConnection(HOST, timeout=600)
            c.putrequest("POST", self._url("up"), skip_accept_encoding=True)
            c.putheader("Content-Type", "audio/l16; rate=16000")
            c.putheader("Transfer-Encoding", "chunked")
            c.endheaders()
            step = 3200                                        # 100 ms of audio, same as the app
            bps = 32000.0 * self.speed if self.speed else 0    # speed 0 = one burst, no pacing
            t = time.time()
            for off in range(0, len(self.audio), step):
                part = self.audio[off:off + step]
                c.send(b"%x\r\n" % len(part) + part + b"\r\n")
                if bps:
                    behind = (off + len(part)) / bps - (time.time() - t)
                    if behind > 0:
                        time.sleep(behind)
            c.send(b"0\r\n\r\n")
            r = c.getresponse()
            self.up_http = r.status
            r.read()
            c.close()
        except Exception as e:                                 # noqa: BLE001
            self.err = "up: %r" % e

    def result(self, drain=20.0):
        self._down.join(timeout=drain)
        return {
            "tag": self.tag, "pair": self.pair, "speed": self.speed,
            "up_http": self.up_http, "down_http": self.down_http, "err": self.err,
            "frames": self.frames, "finals": len(self.finals),
            "wall": round(time.time() - self.t0, 1),
            "last_result_at": self.last_result_at,
            "text": " ".join(self.finals + ([self.last_interim] if self.last_interim else [])),
        }


def words(s):
    return s.lower().replace(".", "").replace(",", "").split()


def coverage(base, got):
    """Fraction of the baseline words present, in order (crude LCS ratio)."""
    a, b = words(base), words(got)
    if not a:
        return 0.0
    # LCS length; the files are ~200 words so O(n*m) is fine
    prev = [0] * (len(b) + 1)
    for x in a:
        cur = [0]
        for j, y in enumerate(b):
            cur.append(prev[j] + 1 if x == y else max(cur[j], prev[j + 1]))
        prev = cur
    return prev[-1] / len(a)


def run_speed(audio, lang):
    out = []
    base_text = None
    for speed in (1, 2, 5, 20, 0):
        s = Session(audio, lang, speed, tag="x%s" % (speed or "burst"))
        s.feed()
        r = s.result(drain=45 if speed else 60)
        if base_text is None:
            base_text = r["text"]
        r["coverage_vs_1x"] = round(coverage(base_text, r["text"]), 3)
        r["words"] = len(words(r["text"]))
        out.append(r)
        print(json.dumps(r, ensure_ascii=False), flush=True)
        time.sleep(5)
    return out


def run_parallel(audio, lang, counts):
    out = []
    for n in counts:
        ss = [Session(audio, lang, 1, tag="n%d/%d" % (n, i)) for i in range(n)]
        ts = [threading.Thread(target=s.feed) for s in ss]
        for t in ts:
            t.start()
        for t in ts:
            t.join()
        rs = [s.result(drain=45) for s in ss]
        for r in rs:
            print(json.dumps(r, ensure_ascii=False), flush=True)
        base = max((r["text"] for r in rs), key=len)
        covs = [coverage(base, r["text"]) for r in rs]
        summary = {
            "concurrency": n,
            "http_ok": all(r["up_http"] == 200 and r["down_http"] == 200 for r in rs),
            "errors": [r["err"] for r in rs if r["err"]],
            "finals_min": min(r["finals"] for r in rs),
            "finals_max": max(r["finals"] for r in rs),
            "coverage_min": round(min(covs), 3),
            "coverage_mean": round(statistics.mean(covs), 3),
        }
        out.append(summary)
        print("SUMMARY " + json.dumps(summary, ensure_ascii=False), flush=True)
        time.sleep(10)
    return out


if __name__ == "__main__":
    mode = sys.argv[1]
    audio = open(sys.argv[2], "rb").read()
    lang = sys.argv[3] if len(sys.argv) > 3 else "en-US"
    print("probe: %s %.1fs audio lang=%s" % (mode, len(audio) / 32000.0, lang), flush=True)
    if mode == "speed":
        run_speed(audio, lang)
    else:
        counts = [int(x) for x in (sys.argv[4] if len(sys.argv) > 4 else "2,4,8").split(",")]
        run_parallel(audio, lang, counts)
