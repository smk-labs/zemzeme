#!/bin/bash
# تستِ طلاییِ «نشستنِ متن»، باگ B7. شرحِ هر ادعا سرِ tools/landing_test.m است.
# فقط Foundation: قاعده‌ای که می‌سنجد مالِ ترتیبِ صف و متنِ سورس است، نه AppKit.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-landing-test"
clang -fobjc-arc -O1 -Wall -Werror \
  tools/landing_test.m \
  -framework Foundation -o "$out"
"$out"
