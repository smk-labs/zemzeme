#!/bin/bash
# بیلد بدون Xcode با clang (ObjC).
# چرا سوئیفت نه؟ CLT این دستگاه (swiftlang-6.2.0.19.9) با ماژول‌های همه SDK های
# موجود ناسازگار است و هیچ import سوئیفتی (حتی Foundation) کامپایل نمی‌شود.
# پورت سوئیفت همین معماری در app/swift-port/ منتظر CLT سالم است:
#   sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install
# امضای ad-hoc با شناسه ثابت که اجازه‌های TCC با هر بیلد نپرند.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p .build
clang -fobjc-arc -O2 -Wall -Wno-unused-function \
  Sources-objc/*.m \
  -framework AppKit -framework AVFoundation -framework Carbon \
  -framework CoreText -framework ApplicationServices -framework QuartzCore \
  -framework AudioToolbox \
  -o .build/zemzeme

APP="../Zemzeme.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/zemzeme "$APP/Contents/MacOS/zemzeme"
cp Info.plist "$APP/Contents/Info.plist"
for f in "$HOME/Library/Fonts/Vazirmatn-Regular.ttf" "$HOME/Library/Fonts/Vazirmatn-Medium.ttf"; do
  [ -f "$f" ] && cp "$f" "$APP/Contents/Resources/" || true
done
codesign --force --sign - --identifier io.seyed.zemzeme "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true
echo "built: $(cd .. && pwd)/Zemzeme.app"
