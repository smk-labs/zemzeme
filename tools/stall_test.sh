#!/bin/bash
# تست طلاییِ ساعتِ گیر کردن: کامپایل و اجرا در کمتر از یک ثانیه، بی‌میکروفن و بی‌شبکه.
# تصمیم یک تابعِ خالص در هدر است (ZStallSeconds)، پس هیچ فایلی از اپ لازم نیست.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-stall-test"
clang -fobjc-arc -O1 -Wall -Werror -I app/Sources-objc \
  tools/stall_test.m \
  -framework Foundation -framework AppKit -framework AVFoundation -o "$out"
"$out"
