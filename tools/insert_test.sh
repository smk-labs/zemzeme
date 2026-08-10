#!/bin/bash
# تست طلاییِ روشِ درج: هر دو حالتِ سراسری امتحان می‌شود و در هر دو، Windows App باید
# پیست بگیرد. دو اجرا لازم است نه یکی: باگی که دو بار برگشت دقیقا همین بود که روشِ
# سراسریِ «تایپ» به ریموت هم سرایت می‌کرد.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-insert-test"
clang -fobjc-arc -O1 -Wall -Werror -I app/Sources-objc \
  app/Sources-objc/core.m tools/insert_test.m \
  -framework Foundation -framework AppKit -framework CoreText -o "$out"
"$out" -insertMode 0    # سراسری: تایپ
"$out" -insertMode 1    # سراسری: چسباندن

# و همان تنظیمِ کهنه‌ای که شبِ ۱۹ مرداد ۱۴۰۵ متن را در ریموت به «aaaa» تبدیل کرد: یک
# استثنای per-app روی دیسک که می‌گفت Windows App تایپ شود. کلید perApp دیگر خوانده
# نمی‌شود، و این اجرا نگهبانِ همان است: اگر روزی کسی دوباره استثنای per-app اضافه کند و
# جلوتر از قانونِ ریموت بنشاندش، همین‌جا قرمز می‌شود، نه سرِ دیکته‌ی کاربر.
"$out" -insertMode 0 -perApp '{"com.microsoft.rdc.macos" = 0;}'
"$out" -insertMode 1 -perApp '{"com.microsoft.rdc.macos" = 0;}'
echo "insert: تست طلایی سبز"
