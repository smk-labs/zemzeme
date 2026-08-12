#!/bin/bash
# تستِ طلاییِ «میکروفن کر»: کامپایل و اجرا در چند ثانیه، بی‌میکروفن و بی‌اجازه.
# فقط Foundation، چون قاعده‌ای که می‌سنجد مالِ dispatch و متنِ سورس است، نه AVFoundation.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-deafmic-test"
clang -fobjc-arc -O1 -Wall -Werror \
  tools/deafmic_test.m \
  -framework Foundation -o "$out"
"$out"
