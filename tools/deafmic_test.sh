#!/bin/bash
# تستِ طلاییِ «میکروفن کر»، دو نسل از یک باگ:
#
#   • نسلِ اول، صفر بایت: تورِ ایمنیِ dispatch در audio.m و قاعده‌های ریشه‌اش روی
#     متنِ سورس. برای این بخش Foundation بس بود.
#   • نسلِ دوم (B9)، بایت می‌آید ولی هیچ حرفی در آن نیست: تصمیمش در warn.m است و
#     آستانه دارد، پس روی **کدِ واقعی** می‌دود نه روی متن. خودِ pipe.m و queue.m
#     کامپایل می‌شوند و فقط `ZGoogleStream` بدل است، مثل queue_test.
#
# صدا هم واقعی است، نه موجِ مربعی: آرام‌ترین ضبطِ ریپو (پچ‌پچ) با `ZDecodePCMRange`
# خوانده می‌شود، چون تنها مثبتِ کاذبی که این آستانه را بی‌ارزش می‌کند همین است.
#
# HOME جابه‌جا می‌شود که لاگِ واقعی کاربر با خط‌های تست کثیف نشود؛ خودِ اپ هم از همین
# مسیر می‌خواند (ZSupport)، پس مسیرِ زیرِ تست همان مسیرِ واقعی است.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-deafmic-test"
work="${TMPDIR:-/tmp}/zemzeme-deafmic-work"
clang -fobjc-arc -O1 -Wall -Werror -I app/Sources-objc \
  app/Sources-objc/core.m app/Sources-objc/seg.m app/Sources-objc/pipe.m \
  app/Sources-objc/queue.m app/Sources-objc/flac.m app/Sources-objc/record.m \
  app/Sources-objc/decode.m app/Sources-objc/history.m app/Sources-objc/rewrite.m \
  app/Sources-objc/warn.m \
  tools/deafmic_test.m \
  -framework Foundation -framework AppKit -framework CoreText \
  -framework AVFoundation -framework AudioToolbox -framework CoreMedia -o "$out"

rm -rf "$work"
mkdir -p "$work/home"
export HOME="$work/home" CFFIXED_USER_HOME="$work/home"
"$out"
