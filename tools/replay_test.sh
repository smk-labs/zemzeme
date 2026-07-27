#!/bin/bash
# کورپوس طلایی: هر باگِ ثبت‌شده‌ی این چند روز، یک فایل رویداد.
# بی‌میکروفن، بی‌شبکه، قطعی. هر فیکسچر دو بار می‌دود: یک بار حالت کنار کرسر
# (دُم ناپایدار هم نوشته می‌شود) و یک بار حالت درج زنده (فقط متن قطعی).
set -uo pipefail
cd "$(dirname "$0")/.."
BIN="app/.build/zemzeme"
[ -x "$BIN" ] || { echo "build first: bash app/build.sh"; exit 2; }
fail=0
for f in tools/fixtures/*.events.jsonl; do
  for mode in "" "--live"; do
    if ! "$BIN" --replay "$f" $mode; then fail=$((fail+1)); fi
  done
done
echo
[ "$fail" -eq 0 ] && echo "all replay fixtures passed" || echo "FAILED ($fail)"
exit $fail
