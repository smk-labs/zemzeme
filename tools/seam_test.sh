#!/bin/bash
# تست طلاییِ جوش درز: کامپایل و اجرا در کمتر از یک ثانیه، بی‌میکروفن و بی‌شبکه.
# seam.m عمدا هیچ وابستگی‌ای جز Foundation ندارد، پس اینجا تنهایی کامپایل می‌شود.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-seam-test"
clang -fobjc-arc -O1 -Wall -Werror -I app/Sources-objc \
  app/Sources-objc/seam.m tools/seam_test.m \
  -framework Foundation -framework AppKit -o "$out"
"$out"
