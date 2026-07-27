#!/bin/bash
# تست طلاییِ دروازه‌ی کامل بودن: کامپایل و اجرا در کمتر از یک ثانیه، بی‌کلید و بی‌شبکه.
# gate.m عمدا هیچ وابستگی‌ای جز Foundation ندارد، پس اینجا تنهایی کامپایل می‌شود.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-gate-test"
clang -fobjc-arc -O1 -Wall -Werror -I app/Sources-objc \
  app/Sources-objc/gate.m tools/gate_test.m \
  -framework Foundation -framework AppKit -o "$out"
"$out"
