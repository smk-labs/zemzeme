#!/bin/bash
# تست طلاییِ برش‌زن: کامپایل و اجرا در چند ثانیه، بی‌میکروفن و بی‌شبکه.
# seg.m عمدا هیچ وابستگی‌ای جز Foundation ندارد، پس اینجا تنهایی کامپایل می‌شود.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-seg-test"
clang -fobjc-arc -O1 -Wall -Werror -I app/Sources-objc \
  app/Sources-objc/seg.m tools/seg_test.m \
  -framework Foundation -framework AppKit -o "$out"
"$out"
