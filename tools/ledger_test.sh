#!/bin/bash
# تست دفتر متن: کامپایل و اجرا در کمتر از یک ثانیه، بی‌میکروفن و بی‌شبکه.
# فقط ledger.m و seam.m لینک می‌شوند؛ ZLog را خود تست تعریف می‌کند، پس نه پوشه‌ی
# داده لازم است نه NSApplication.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-ledger-test"
clang -fobjc-arc -O1 -Wall -Werror -I app/Sources-objc \
  app/Sources-objc/ledger.m app/Sources-objc/seam.m tools/ledger_test.m \
  -framework Foundation -framework AppKit -o "$out"
"$out"
