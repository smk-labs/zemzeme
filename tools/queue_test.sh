#!/bin/bash
# تستِ طلاییِ صف: کامپایل و اجرا در چند ثانیه، بی‌میکروفن و بی‌شبکه. خودِ pipe.m و
# queue.m کامپایل می‌شوند (همان کدی که در محصول می‌دود) و فقط `ZGoogleStream` بدل
# است، پس مسیرِ واقعیِ تصمیم زیر تست است نه ادای آن.
#
# HOME جابه‌جا می‌شود که لاگِ واقعی کاربر با خط‌های تست کثیف نشود؛ خودِ اپ هم از همین
# مسیر می‌خواند (ZSupport)، پس مسیرِ زیرِ تست همان مسیرِ واقعی است.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-queue-test"
work="${TMPDIR:-/tmp}/zemzeme-queue-work"
clang -fobjc-arc -O1 -Wall -Werror -I app/Sources-objc \
  app/Sources-objc/core.m app/Sources-objc/seg.m app/Sources-objc/pipe.m \
  app/Sources-objc/queue.m tools/queue_test.m \
  -framework Foundation -framework AppKit -framework CoreText -o "$out"

rm -rf "$work"
mkdir -p "$work/home"
export HOME="$work/home" CFFIXED_USER_HOME="$work/home"
"$out"
