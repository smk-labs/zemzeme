#!/bin/bash
# تستِ طلاییِ «رشته‌ی زنده»: کامپایل و اجرا در چند ثانیه، بی‌کلید و بی‌شبکه.
# NSTextView واقعی می‌سازد (نه ادای آن)، چون قاعده‌ای که می‌سنجد مالِ خودِ AppKit است.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-livestring-test"
clang -fobjc-arc -O1 -Wall -Werror \
  tools/livestring_test.m \
  -framework Foundation -framework AppKit -o "$out"
"$out"
