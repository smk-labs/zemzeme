#!/bin/bash
# تستِ طلاییِ فلیکِ پنجره‌ی کلید: کامپایل و اجرا در چند ثانیه، بی‌کلید و بی‌شبکه.
# flick.m عمدا هیچ وابستگی‌ای جز AppKit ندارد، پس اینجا تنهایی کامپایل می‌شود.
# نکته: پنجره‌ی واقعی باز می‌کند، پس در یک سشن گرافیکی زنده معنا دارد (نه در SSH خالی).
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-flick-test"
clang -fobjc-arc -O1 -Wall -Werror -I app/Sources-objc \
  app/Sources-objc/flick.m tools/flick_test.m \
  -framework Foundation -framework AppKit -o "$out"
"$out"
