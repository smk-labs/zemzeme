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
    for m in re.finditer(r"items?\s+(\d+)", low):
        n = int(m.group(1))
        out[n] = out.get(n, 0) + 1
    for m in re.finditer(r"items?\s+([a-z]+)", low):
        n = WORDNUM.get(m.group(1))
        if n:
            out[n] = out.get(n, 0) + 1
    return out


# The fixture's sentences share a skeleton ("the A B C beside the D in the E of that F year"),
# so only the content words carry identity. Matching on the skeleton would score a lost
# sentence as delivered because its neighbour supplies the same filler.
SKELETON = set("the beside in of that year item items a an and".split())


def content(words):
    return [w for w in words if w not in SKELETON and not w.isdigit()]


def sentences(src):
    """The fixture is one numbered sentence per 'item N.' — split on it."""
    parts = re.split(r"item\s+(\d+)\s*\.", src)
    out = []
    for i in range(1, len(parts) - 1, 2):
        out.append((int(parts[i]), norm(parts[i + 1])))
    return out


def delivered(src, got, floor=0.6):
    """A sentence counts as delivered when most of its words survive, in order.

    Blunter than the item index and much more honest: the recogniser often mangles the
    index word itself ("items 16", "item made") while every other word of the sentence
    is right there. Counting those as losses blames the seams for nothing.
    """
    b = content(norm(got))
    sents = [(n, content(w)) for n, w in sentences(src)]
    lost, weak = [], []
    for k, (n, words) in enumerate(sents):
        if not words:
            continue
        # Look only near where the sentence belongs. Searching the whole transcript makes
        # this metric lie whenever the material is repetitive: another sentence's words
        # rescue a genuinely lost one.
        mid = int(len(b) * (k + 0.5) / max(1, len(sents)))
        half = max(60, int(len(words) * 4))
        window = b[max(0, mid - half):mid + half]
        hit = lcs(words, window) / len(words)
        if hit < 0.35:
            lost.append(n)
        elif hit < floor:
            weak.append(n)
    return lost, weak


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
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
    lost, weak = delivered(src, got)
    total_s = len(sentences(src))
    print("sentences      : %d/%d delivered, %d partial, %d lost %s"
          % (total_s - len(lost) - len(weak), total_s, len(weak), len(lost),
             lost if lost else ""))
