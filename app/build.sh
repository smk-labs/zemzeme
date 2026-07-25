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
clang -fobjc-arc -O2 -Wall -Wno-unused-function \
  Sources-objc/*.m \
  -framework AppKit -framework AVFoundation -framework Carbon \
  -framework CoreText -framework ApplicationServices -framework QuartzCore \
  -framework AudioToolbox \
  -o .build/zemzeme

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/zemzeme "$APP/Contents/MacOS/zemzeme"
cp Info.plist "$APP/Contents/Info.plist"
# اسکریپت‌های همراه داخل بسته: نسخه‌دار، خواندنی، هرجا اپ برود با آن می‌روند.
# venv و مدل‌ها (~۵۰۰ مگ) عمدا بیرون می‌مانند؛ setup.sh آن‌ها را در
# ~/Library/Application Support/Zemzeme/py می‌گذارد.
cp ../serve.py ../index.html py/polish.py "$APP/Contents/Resources/"
for f in "$HOME/Library/Fonts/Vazirmatn-Regular.ttf" "$HOME/Library/Fonts/Vazirmatn-Medium.ttf"; do
  [ -f "$f" ] && cp "$f" "$APP/Contents/Resources/" || true
done

# امضا با گواهی ثابت، نه ad-hoc: شرطی که TCC ذخیره می‌کند «شناسه + گواهی» است،
# پس اجازه اکسسبیلیتی و میکروفن از هر بیلد جان سالم می‌برد.
codesign --force --sign "Zemzeme Dev" --identifier io.seyed.zemzeme "$APP"

# نسخه قدیمی داخل پوشه پروژه اگر مانده باشد: یک بسته، یک جا
if [ -d ../Zemzeme.app ]; then
  "$LSREGISTER" -u ../Zemzeme.app >/dev/null 2>&1 || true
  rm -rf ../Zemzeme.app
fi

# جایگزینی روی اپِ باز کار نصفه می‌دهد، پس اول بسته شود
WAS_RUNNING=0
pgrep -x zemzeme >/dev/null && WAS_RUNNING=1 || true
pkill -x zemzeme >/dev/null 2>&1 || true
for _ in $(seq 30); do pgrep -x zemzeme >/dev/null || break; sleep 0.1; done

rm -rf "$DEST"
ditto "$APP" "$DEST"          # ditto نه cp: امضا و ویژگی‌های فایل سالم منتقل می‌شوند
"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
[ "${ZEMZEME_NO_LAUNCH:-0}" = "1" ] || open "$DEST"

echo "installed: $DEST (was_running=$WAS_RUNNING)"
