#!/bin/bash
# تستِ طلاییِ «یک صفِ درج برای کلِ اپ»: کامپایل و اجرا در چند ثانیه، بی‌پنجره و بی‌رویداد.
# فقط Foundation، چون قاعده‌ای که می‌سنجد مالِ خودِ dispatch است، نه AppKit.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-injectq-test"
clang -fobjc-arc -O1 -Wall -Werror \
  tools/injectq_test.m \
  -framework Foundation -o "$out"
"$out"
