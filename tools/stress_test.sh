#!/bin/bash
# استرس‌تست کلید Chromium روی speech-api/full-duplex/v1.
# اول یه سشن دودی ۲۰ ثانیه‌ای (تایید فرمت)، بعد ۳ سشن ~۵ دقیقه‌ای پشت هم و یه سشن کوتاه چهارم.
# صدا با say ساخته می‌شه و با سرعت واقعی (۳۲KB/s = l16@16kHz) استریم می‌شه.
# خروجی: tools/stress-<timestamp>.log با خط VERDICT در انتها.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
KEY="AIzaSyBOti4mM-6x9WDnZIjIeyEU21OpBXqWBgw"
BASE="https://www.google.com/speech-api/full-duplex/v1"
TS=$(date +%Y%m%d-%H%M%S)
LOG="$DIR/stress-$TS.log"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

log() { echo "$(date +%H:%M:%S) $*" >> "$LOG"; }

log "=== stress test start (l16 16kHz mono, real-time pacing) ==="

# ~40s of varied speech as the loop unit
say -o "$WORK/base.aiff" "The quick brown fox jumps over the lazy dog. \
Testing continuous dictation over a long streaming session. \
This audio repeats to simulate five minutes of natural speech, \
with pauses, and sentences of different lengths. \
Numbers like one, two, three, four, five, help checking partial results. \
The weather today is clear, and the meeting starts at nine thirty." || { log "say FAILED"; exit 1; }
afconvert "$WORK/base.aiff" -f WAVE -d LEI16@16000 -c 1 "$WORK/base.wav" || { log "afconvert FAILED"; exit 1; }
python3 - "$WORK/base.wav" "$WORK/base.raw" <<'EOF'
import sys, wave
w = wave.open(sys.argv[1])
open(sys.argv[2], "wb").write(w.readframes(w.getnframes()))
EOF
log "base audio: $(stat -f%z "$WORK/base.raw") bytes raw"

# make_session_audio <seconds> -> $WORK/sess.raw (base + 0.5s silence, looped, cut to size)
make_session_audio() {
  python3 - "$WORK/base.raw" "$WORK/sess.raw" "$1" <<'EOF'
import sys
base = open(sys.argv[1], "rb").read()
need = int(sys.argv[3]) * 32000
sil = b"\x00" * 16000
buf = bytearray()
while len(buf) < need:
    buf += base + sil
open(sys.argv[2], "wb").write(buf[:need])
EOF
}

# run_session <name> <seconds>  -> appends per-frame log + SESSION-RESULT line
run_session() {
  NAME=$1; SECS=$2
  PAIR=$(python3 -c "import secrets;print(secrets.token_hex(8))")
  make_session_audio "$SECS"
  UP="$BASE/up?key=$KEY&pair=$PAIR&lang=en-US&client=chromium&continuous&interim&maxAlternatives=1&pFilter=0&output=pb"
  DOWN="$BASE/down?key=$KEY&pair=$PAIR&output=pb"
  log "--- session $NAME: ${SECS}s pair=$PAIR"
  T0=$(date +%s)
  curl -s -N --http1.1 --max-time $((SECS + 90)) -D "$WORK/down.h" "$DOWN" \
    | python3 "$DIR/down_reader.py" >> "$LOG" 2>&1 &
  DPID=$!
  sleep 0.5
  UPCODE=$(curl -s -o "$WORK/up.body" -w '%{http_code}' --http1.1 --max-time $((SECS + 90)) \
    --limit-rate 32000 -X POST -H "Content-Type: audio/l16; rate=16000" \
    --data-binary "@$WORK/sess.raw" "$UP")
  wait $DPID 2>/dev/null
  T1=$(date +%s)
  DOWNCODE=$(head -1 "$WORK/down.h" 2>/dev/null | awk '{print $2}')
  log "SESSION-RESULT name=$NAME up_http=$UPCODE down_http=${DOWNCODE:-none} wall=$((T1 - T0))s up_body=$(head -c 200 "$WORK/up.body" 2>/dev/null | tr '\n' ' ')"
}

run_session smoke 20

# gate on the smoke session: need frames and at least one final
if ! grep -q "FINAL=" "$LOG"; then
  log "VERDICT: SMOKE-FAIL (no finals; check codes/params above)"
  exit 1
fi
log "smoke OK, starting 3x ~5min sessions back to back"

run_session long1 290
run_session long2 290
run_session long3 290
run_session short4 30

python3 - "$LOG" <<'EOF'
import re, sys
txt = open(sys.argv[1]).read()
sums = re.findall(r"SUMMARY frames=(\d+) finals=(\d+) first=([\d.]+|none) last=([\d.]+|none) max_gap=([\d.]+)", txt)
codes = re.findall(r"SESSION-RESULT name=(\S+) up_http=(\d+) down_http=(\d+)", txt)
ok = len(sums) >= 5
reasons = []
for name, up, down in codes:
    if up != "200" or down != "200":
        ok = False
        reasons.append("%s http up=%s down=%s" % (name, up, down))
for i, (fr, fi, first, last, gap) in enumerate(sums[1:4], 1):  # the three long sessions
    if int(fi) < 5:
        ok = False
        reasons.append("long%d finals=%s" % (i, fi))
    if last == "none" or float(last) < 240:
        ok = False
        reasons.append("long%d died early last=%s" % (i, last))
    if float(gap) > 30:
        reasons.append("long%d gap=%s (warn)" % (i, gap))
with open(sys.argv[1], "a") as f:
    f.write("VERDICT: %s %s\n" % ("PASS" if ok else "FAIL", "; ".join(reasons)))
EOF
log "=== done ==="
