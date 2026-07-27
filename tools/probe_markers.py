#!/usr/bin/env python3
"""Finds where one session stops recognising, with a spoken counter as the ruler.

The fixture says "marker one ... marker sixty", one every ~3.6 s. Which markers come back
tells us exactly how many seconds of audio a single session digests, and whether the limit
follows audio seconds or wall clock (feed the same file at 1x and in one burst and compare).

  python3 probe_markers.py <audio.raw> <lang> <speed|burst> [markers_total]
"""
import re
import sys
import time

from probe_endpoint import Session

NUM = ("zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen "
       "fifteen sixteen seventeen eighteen nineteen twenty").split()


def to_int(phrase):
    parts = phrase.split()
    if parts[0] in NUM:
        n = NUM.index(parts[0])
        return n + (NUM.index(parts[1]) if len(parts) > 1 and parts[1] in NUM else 0)
    tens = {"twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60}
    if parts[0] in tens:
        return tens[parts[0]] + (NUM.index(parts[1]) if len(parts) > 1 and parts[1] in NUM else 0)
    return None


def markers_in(text):
    """Digits and words both; the recogniser writes 'marker 21' as often as 'marker twenty one'."""
    found = set()
    low = text.lower()
    for m in re.finditer(r"marker\s+(\d+)", low):
        found.add(int(m.group(1)))
    for m in re.finditer(r"marker\s+([a-z]+(?:\s+[a-z]+)?)", low):
        n = to_int(m.group(1))
        if n:
            found.add(n)
    return found


if __name__ == "__main__":
    path, lang, sp = sys.argv[1], sys.argv[2], sys.argv[3]
    total = int(sys.argv[4]) if len(sys.argv) > 4 else 60
    audio = open(path, "rb").read()
    speed = 0 if sp == "burst" else float(sp)
    dur = len(audio) / 32000.0
    s = Session(audio, lang, speed)
    t0 = time.time()
    s.feed()
    r = s.result(drain=90)
    got = markers_in(r["text"])
    missing = sorted(set(range(1, total + 1)) - got)
    print("audio=%.0fs speed=%s wall=%.0fs finals=%d frames=%d up=%s down=%s"
          % (dur, sp, time.time() - t0, r["finals"], r["frames"], r["up_http"], r["down_http"]))
    print("markers found=%d/%d  highest=%s  missing=%s"
          % (len(got), total, max(got) if got else "-", missing))
    print("last_result_at=%.1fs  words=%d" % (r["last_result_at"] or -1, len(r["text"].split())))
    print("TEXT: " + r["text"])
