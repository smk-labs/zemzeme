#!/bin/bash
# تستِ طلاییِ لایه‌ی بازنویسی، و گاردِ باگِ C1: کامپایل و اجرا در چند ثانیه، بی‌شبکه
# و بی‌میکروفن. session.m و rewrite.m خودشان کامپایل می‌شوند (همان کدی که در محصول
# می‌دود) و فقط لبه‌ها بدل‌اند، پس مسیرِ واقعیِ تحویل زیر تست است نه ادای آن.
#
# هر سناریو یک اجرای جداست، نه یک main بلند. دو دلیل: تاریخچه با sid جمع می‌کند و دو
# سشن در یک ثانیه یک sid می‌گیرند، و تنظیمات تک‌نمونه است و از سناریو نشت می‌کند.
#
# HOME جابه‌جا می‌شود که تاریخچه و لاگ و سشن‌های واقعی کاربر دست نخورند؛ خودِ اپ هم از
# همین مسیر می‌خواند (ZSupport)، پس مسیرِ زیرِ تست همان مسیرِ واقعی است.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-rewrite-test"
work="${TMPDIR:-/tmp}/zemzeme-rewrite-work"
clang -fobjc-arc -O1 -Wall -Werror -I app/Sources-objc \
  app/Sources-objc/core.m app/Sources-objc/history.m app/Sources-objc/rewrite.m \
  app/Sources-objc/session.m app/Sources-objc/warn.m tools/rewrite_test.m \
  -framework Foundation -framework AppKit -framework CoreText -o "$out"

rm -rf "$work"
for phase in c1 gap pass pure; do
  mkdir -p "$work/$phase"
  HOME="$work/$phase" CFFIXED_USER_HOME="$work/$phase" "$out" "$phase"
done
echo "rewrite: تست طلایی سبز"
