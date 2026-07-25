#!/usr/bin/env python3
"""Scores a batch transcript against the text that was spoken.

The fixture numbers every sentence ("item 1 ... item 200"), so a lost word at a seam and a
word emitted twice are both visible: a missing index is loss, a repeated index is a
duplicate. Word-level coverage catches everything between the indices.

  python3 check_transcript.py <spoken.txt> <transcript.txt> [expected_items]
"""
import re
import sys


def norm(s):
    s = s.lower().replace("،", " ").replace(".", " ").replace(",", " ")
    return [w for w in s.split() if w]


def lcs(a, b):
    prev = [0] * (len(b) + 1)
    for x in a:
        cur = [0]
        for j, y in enumerate(b):
            cur.append(prev[j] + 1 if x == y else max(cur[j], prev[j + 1]))
        prev = cur
    return prev[-1]


# the recogniser spells small numbers as words, and homophones of them: "item won",
# "item to", "item for". Counting those as losses would blame the seams for nothing.
WORDNUM = {"one": 1, "won": 1, "two": 2, "to": 2, "too": 3, "three": 3, "four": 4, "for": 4,
           "five": 5, "six": 6, "seven": 7, "eight": 8, "ate": 8, "nine": 9, "ten": 10}


def items(text):
    out = {}
    low = text.lower()
    for m in re.finditer(r"item\s+(\d+)", low):
        n = int(m.group(1))
        out[n] = out.get(n, 0) + 1
    for m in re.finditer(r"item\s+([a-z]+)", low):
        n = WORDNUM.get(m.group(1))
        if n:
            out[n] = out.get(n, 0) + 1
    return out


if __name__ == "__main__":
    src = open(sys.argv[1]).read()
    got = open(sys.argv[2]).read()
    total = int(sys.argv[3]) if len(sys.argv) > 3 else max(items(src) or [0])
    a, b = norm(src), norm(got)
    common = lcs(a, b)
    si, gi = items(src), items(got)
    expect = sorted(si) if not total else list(range(1, total + 1))
    missing = [n for n in expect if n not in gi]
    dupes = {n: c for n, c in gi.items() if c > 1}
    print("spoken words   : %d" % len(a))
    print("transcript     : %d words" % len(b))
    print("coverage       : %.1f%% of spoken words, in order" % (100.0 * common / max(1, len(a))))
    print("extra words    : %d (transcript words not on the in-order match)" % (len(b) - common))
    print("items present  : %d/%d" % (len(expect) - len(missing), len(expect)))
    print("items missing  : %s" % (missing if missing else "none"))
    print("items repeated : %s" % (dupes if dupes else "none"))
