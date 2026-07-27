#!/bin/bash
# تست طلاییِ دروازه‌ی بهبود پرامپت: کامپایل و اجرا در کمتر از یک ثانیه، بی‌کلید و بی‌شبکه.
# enhgate.m عمدا فقط به gate.m وابسته است (و آن هم فقط به Foundation)، پس این دو
# تنهایی کامپایل می‌شوند. همان قرارداد gate_test.sh و seam_test.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-enhance-gate-test"
clang -fobjc-arc -O1 -Wall -Werror -I app/Sources-objc \
  app/Sources-objc/gate.m app/Sources-objc/enhgate.m tools/enhance_gate_test.m \
  -framework Foundation -framework AppKit -o "$out"
"$out"
