#!/bin/bash
# بیلد بدون Xcode با clang (ObjC)، بعد امضا، بعد نصب در /Applications و اجرای دوباره.
# یک دستور، از سورس تا اپِ به‌روزِ در حال اجرا. رمز لازم نیست: /Applications برای
# گروه admin نوشتنی است.
#
# چرا سوئیفت نه؟ CLT این دستگاه (swiftlang-6.2.0.19.9) با ماژول‌های همه SDK های
# موجود ناسازگار است و هیچ import سوئیفتی (حتی Foundation) کامپایل نمی‌شود.
# پورت سوئیفت همین معماری در app/swift-port/ منتظر CLT سالم است:
#   sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

DEST="/Applications/Zemzeme.app"
APP=".build/Zemzeme.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

bash ../tools/make-cert.sh

mkdir -p .build
# سینک‌تینگ وقتی دو دستگاه یک فایل را با هم عوض کنند، نسخه‌ی دوم را کنارِ اصلی
# می‌گذارد و در نامش sync-conflict می‌آورد. ستاره‌ی بالا آن را هم برمی‌داشت، یعنی
# کلاس‌های تکراری و یک بیلدِ شکسته (یک بار همین شد و ۱۲ فایلِ جامانده جلوی بیلد را
# گرفته بود). حالا از لیست بیرون‌اند، ولی بی‌صدا نه: فایلِ جامانده یعنی یک ویرایش
# جایی گم شده و باید دیده شود.
SRC=()
for f in Sources-objc/*.m; do
  case "$f" in
    *sync-conflict*) echo "warn: بیرون از بیلد ماند (نسخه‌ی جامانده‌ی سینک): $f" ;;
    *) SRC+=("$f") ;;
  esac
done
clang -fobjc-arc -O2 -Wall -Wno-unused-function \
  "${SRC[@]}" \
  -framework AppKit -framework AVFoundation -framework Carbon \
  -framework CoreText -framework ApplicationServices -framework QuartzCore \
  -framework AudioToolbox -framework CoreMedia -framework Security \
  -framework ServiceManagement -framework CoreAudio \
  -o .build/zemzeme

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/zemzeme "$APP/Contents/MacOS/zemzeme"
cp Info.plist "$APP/Contents/Info.plist"
# پرامپت‌ها: فایل‌اند نه رشته‌ی هاردکد، چون هر دو روی متن واقعی تیون شده‌اند و باید
# بی‌بیلد قابل ویرایش باشند. یکی‌شان (enhance) مالِ بهبود پرامپت است، نه پاس نهایی.
mkdir -p "$APP/Contents/Resources/prompts"
cp prompts/ai-pass.md prompts/ai-pass-two.md prompts/ai-pass-append.md "$APP/Contents/Resources/prompts/"

# آیکون بسته از خود باینری تازه می‌آید (نشان یک بار در mark.m تعریف شده، بیت‌مپی در
# ریپو نیست) و iconutil سیستم به icns تبدیلش می‌کند. قبل از امضا، چون داخل بسته است.
rm -rf .build/icon.iconset
.build/zemzeme --appicon .build/icon.iconset
iconutil -c icns .build/icon.iconset -o "$APP/Contents/Resources/Zemzeme.icns"
# فونت از داخل ریپو، نه از پوشه‌ی فونتِ دستگاهِ بیلد. قبلا از ~/Library/Fonts خوانده
# می‌شد و روی مکِ کسی که وزیرمتن نصب ندارد بی‌صدا به فونت سیستم می‌افتاد، یعنی کل
# رابطِ فارسی روی نصبِ تازه بدریخت می‌شد و هیچ‌جا هم گزارش نمی‌شد. وزیرمتن با پروانه‌ی
# SIL OFL منتشر می‌شود (app/fonts/OFL.txt) و بازتوزیعش آزاد است، پس دو فایل ۱۲۰
# کیلوبایتی داخل ریپو می‌نشینند و بیلد از هر دستگاهی یک نتیجه می‌دهد.
cp fonts/Vazirmatn-Regular.ttf fonts/Vazirmatn-Medium.ttf "$APP/Contents/Resources/"

# امضا با گواهی ثابت، نه ad-hoc: شرطی که TCC ذخیره می‌کند «شناسه + گواهی» است،
# پس اجازه اکسسبیلیتی و میکروفن از هر بیلد جان سالم می‌برد.
codesign --force --sign "Zemzeme Dev" --identifier io.seyed.zemzeme "$APP"

# نسخه قدیمی داخل پوشه پروژه اگر مانده باشد: یک بسته، یک جا
if [ -d ../Zemzeme.app ]; then
  "$LSREGISTER" -u ../Zemzeme.app >/dev/null 2>&1 || true
  rm -rf ../Zemzeme.app
fi

# جایگزینی روی اپِ باز کار نصفه می‌دهد، پس اول بسته شود. خروج نرم با پیام quit، نه
# kill: مسیر terminate اپ سشن بازِ دیکته را تمام می‌کند و متنش را نگه می‌دارد.
# با pkill (سیگنال) آن مسیر اجرا نمی‌شود و هرچه گفته شده بی‌صدا دور می‌ریزد.
WAS_RUNNING=0
if pgrep -x zemzeme >/dev/null; then
  WAS_RUNNING=1
  open -g 'zemzeme://quit' >/dev/null 2>&1 || true
  for _ in $(seq 40); do pgrep -x zemzeme >/dev/null || break; sleep 0.1; done
  if pgrep -x zemzeme >/dev/null; then
    echo "warn: نرم بیرون نرفت، kill می‌شود (متن سشن باز از دست می‌رود)"
    pkill -x zemzeme >/dev/null 2>&1 || true
    for _ in $(seq 20); do pgrep -x zemzeme >/dev/null || break; sleep 0.1; done
  fi
fi

rm -rf "$DEST"
ditto "$APP" "$DEST"          # ditto نه cp: امضا و ویژگی‌های فایل سالم منتقل می‌شوند
"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
# اجازه‌ی کی‌چین برای همین بیلد. مسئله این است: کی‌چینِ فایلی هر آیتم را به cdhash
# پروسه‌ی سازنده می‌بندد (فهرست Partition)، و امضای ما گواهی خودی است و Team ID
# ندارد، پس مک چیزی جز cdhash ندارد که بنویسد. cdhash با هر بیلد عوض می‌شود، یعنی
# هر بیلدِ تازه از نظر کی‌چین یک اپِ **دیگر** است و «همیشه اجازه بده»‌ی بیلد قبلی به
# آن نمی‌رسد. نتیجه‌اش را کاربر این‌طور می‌دید: پنجره‌ی رمز مک، وسطِ کار، بعد از هر
# به‌روزرسانی، هر بار با اینکه کلید سر جایش بود.
#
# پس اجازه همین‌جا تازه می‌شود، نه وسط دیکته. رمز یک بار در ترمینال پرسیده می‌شود،
# آن هم فقط وقتی واقعا لازم باشد: اگر کلیدی ذخیره نشده یا بیلد تازه از قبل اجازه
# دارد، هیچ پرسشی در کار نیست. راه همیشگی‌اش گواهی Developer ID است (آن‌وقت
# Partition به جای cdhash می‌شود teamid: و از هر بیلدی جان سالم می‌برد).
KSVC="zemzeme-gemini"
if security find-generic-password -s "$KSVC" >/dev/null 2>&1 \
   && ! "$DEST/Contents/MacOS/zemzeme" --keyacl >/dev/null 2>&1; then
  CDHASH=$(codesign -d --verbose=4 "$DEST" 2>&1 | awk -F= '/^CDHash=/{print $2}')
  if [ -n "$CDHASH" ]; then
    echo "کلید Gemini برای بیلد تازه اجازه‌ی کی‌چین می‌خواهد. رمزِ ورودِ همین مک را"
    echo "بنویس (تایپ دیده نمی‌شود). اگر رد کنی فقط «تمیز کردن متن» یک بار رمز می‌پرسد."
    # فقط stdout به سطل: خروجی‌اش دامپِ خودِ آیتم است. stderr باید بماند، چون
    # پرسشِ رمز از همان‌جا می‌آید و اگر خفه شود کاربر پشت یک ترمینالِ ساکت منتظر می‌ماند.
    security set-generic-password-partition-list \
      -s "$KSVC" -a "$(id -un)" -S "apple:,apple-tool:,cdhash:$CDHASH" >/dev/null || true
    if "$DEST/Contents/MacOS/zemzeme" --keyacl >/dev/null 2>&1; then
      echo "اجازه تازه شد: زمزمه دیگر برای این کلید رمز نمی‌پرسد"
    else
      echo "warn: اجازه تازه نشد. زمزمه سرِ «تمیز کردن متن» یک بار رمز می‌پرسد،"
      echo "      یا از منو «کلید Gemini…» کلید را دوباره بگذار تا صاحبش خودِ این بیلد شود"
    fi
  fi
fi

[ "${ZEMZEME_NO_LAUNCH:-0}" = "1" ] || open "$DEST"

echo "installed: $DEST (was_running=$WAS_RUNNING)"
