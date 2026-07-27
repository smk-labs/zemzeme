#!/bin/bash
# تست جدولِ «پاس نهایی شدنی است یا نه». ZFinalPassPossible یک static inline در هدر است،
# پس بی هیچ فایلِ دیگری از اپ کامپایل می‌شود: نه شبکه، نه کلید، نه میکروفن.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-finalgate-test"
clang -fobjc-arc -O1 -Wall -Werror -I app/Sources-objc \
  tools/finalgate_test.m \
  -framework Foundation -framework AppKit -o "$out"
"$out"
