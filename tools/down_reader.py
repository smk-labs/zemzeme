#!/usr/bin/env python3
"""Reads the full-duplex "down" stream (stdin, binary) and prints one line per frame.

Frame format (Chromium chunked_byte_buffer): 4-byte big-endian length + SpeechRecognitionEvent
protobuf. Fields: event{status=1 varint, result=2 msg, endpoint=4 varint},
result{alternative=1 msg, final=2 varint, stability=3 float}, alternative{transcript=1 str}.
Prints SUMMARY at EOF; the Swift engine uses the exact same framing, so this doubles as
a protocol check before the Swift port.
"""
import sys
import time
import struct


def varint(b, i):
    v = s = 0
    while True:
        x = b[i]
        i += 1
        v |= (x & 0x7F) << s
        if not x & 0x80:
            return v, i
        s += 7


def fields(b):
    i = 0
    while i < len(b):
        k, i = varint(b, i)
        f, w = k >> 3, k & 7
        if w == 0:
            v, i = varint(b, i)
        elif w == 2:
            n, i = varint(b, i)
            v = b[i:i + n]
            i += n
        elif w == 5:
            v = b[i:i + 4]
            i += 4
        elif w == 1:
            v = b[i:i + 8]
            i += 8
        else:
            raise ValueError("wire type %d" % w)
        yield f, w, v


def read_exact(stdin, n):
    d = b""
    while len(d) < n:
        c = stdin.read(n - len(d))
        if not c:
            return None
        d += c
    return d


def main():
    stdin = sys.stdin.buffer
    t0 = time.time()
    frames = finals = 0
    first_t = last_t = None
    max_gap = 0.0
    texts = []
    try:
        while True:
            hdr = read_exact(stdin, 4)
            if hdr is None:
                break
            (ln,) = struct.unpack(">I", hdr)
            if ln > 1_000_000:
                print("FRAMING-ERROR length=%d (assumption wrong?)" % ln, flush=True)
                break
            body = read_exact(stdin, ln)
            if body is None:
                print("TRUNCATED frame", flush=True)
                break
            now = time.time() - t0
            if first_t is None:
                first_t = now
            if last_t is not None:
                max_gap = max(max_gap, now - last_t)
            last_t = now
            frames += 1
            status = endpoint = None
            ev_finals, ev_interim = [], ""
            try:
                for f, w, v in fields(body):
                    if f == 1 and w == 0:
                        status = v
                    elif f == 4 and w == 0:
                        endpoint = v
                    elif f == 2 and w == 2:
                        is_final, txt = False, ""
                        for f2, w2, v2 in fields(v):
                            if f2 == 1 and w2 == 2:
                                for f3, w3, v3 in fields(v2):
                                    if f3 == 1 and w3 == 2 and not txt:
                                        txt = v3.decode("utf-8", "replace")
                            elif f2 == 2 and w2 == 0:
                                is_final = bool(v2)
                        if is_final:
                            ev_finals.append(txt)
                            finals += 1
                        else:
                            ev_interim = txt
            except Exception as e:  # noqa: BLE001 - log and keep reading
                print("%7.1fs frame=%dB PARSE-ERR %s hex=%s" % (now, ln, e, body[:32].hex()), flush=True)
                continue
            line = "%7.1fs frame=%dB" % (now, ln)
            if status is not None:
                line += " status=%d" % status
            if endpoint is not None:
                line += " endpoint=%d" % endpoint
            for t in ev_finals:
                texts.append(t)
                line += " FINAL='%s'" % t[:60]
            if ev_interim:
                line += " interim='%s'" % ev_interim[:40]
            print(line, flush=True)
    finally:
        print(
            "SUMMARY frames=%d finals=%d first=%s last=%s max_gap=%.1f"
            % (frames, finals,
               "%.1f" % first_t if first_t is not None else "none",
               "%.1f" % last_t if last_t is not None else "none",
               max_gap),
            flush=True,
        )
        if texts:
            print("TEXT: " + " | ".join(t[:50] for t in texts[-4:]), flush=True)


if __name__ == "__main__":
    main()
