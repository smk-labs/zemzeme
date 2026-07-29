#!/bin/bash
# تست طلاییِ نوبتِ پاس: کامپایل و اجرا در کمتر از یک ثانیه، بی‌کلید و بی‌شبکه و بی‌سهم.
# passlock.m عمدا هیچ وابستگی‌ای جز Foundation ندارد، پس اینجا تنهایی کامپایل می‌شود.
# همان قرارداد gate_test.sh و seam_test.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-passlock-test"
clang -fobjc-arc -O1 -Wall -Werror -I app/Sources-objc \
  app/Sources-objc/passlock.m tools/passlock_test.m \
  -framework Foundation -framework AppKit -o "$out"
"$out"
