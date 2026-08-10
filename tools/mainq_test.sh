#!/bin/bash
# تستِ طلاییِ «هیچ انتظاری روی صف اصلی»: کامپایل و اجرا در چند ثانیه، بی‌شبکه و
# بی‌پنجره. فقط Foundation، چون قاعده‌ای که می‌سنجد مالِ خودِ dispatch است نه AppKit.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-mainq-test"
clang -fobjc-arc -O1 -Wall -Werror \
  tools/mainq_test.m \
  -framework Foundation -o "$out"
"$out"
