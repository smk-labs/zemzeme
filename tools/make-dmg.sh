#!/bin/bash
# دیسک‌ایمیج ریلیز: Zemzeme-<نسخه>.dmg در app/.build/.
#
# چرا اصلا وجود دارد، وقتی راه پیشنهادی install.sh است: کسی که فایل می‌خواهد فایل
# می‌خواهد. ولی این بسته با گواهی خودساخته امضا شده، پس مک بعد از دانلود قرنطینه‌اش
# می‌کند و باز نمی‌شود تا برچسب برداشته شود. همین یک دستور کافی است و در ریدمی هم
# نوشته شده:
#   xattr -dr com.apple.quarantine /Applications/Zemzeme.app
#
# اپِ ساخته‌شده را از app/.build/ برمی‌دارد؛ اگر نبود، اول بیلد را صدا می‌زند.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="app/.build/Zemzeme.app"
[ -d "$APP" ] || ZEMZEME_NO_LAUNCH=1 bash app/build.sh

VER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="app/.build/Zemzeme-$VER.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/Zemzeme.app"     # ditto نه cp: امضا سالم منتقل می‌شود
ln -s /Applications "$STAGE/Applications"

# پیام قرنطینه کنار خودِ اپ، نه فقط در ریدمی: کسی که dmg را باز می‌کند لزوما ریدمی
# را نخوانده، و «اپ خراب است» تنها چیزی است که مک به او می‌گوید.
cat > "$STAGE/بازش نشد؟ اینجا را بخوان.txt" <<'TXT'
اگر مک گفت «Zemzeme is damaged» یا اصلا باز نشد، اپ سالم است و مشکل امضا است:
این نسخه با گواهی اپل امضا نشده، پس مک بعد از دانلود قرنطینه‌اش می‌کند.

اول Zemzeme.app را به پوشه‌ی Applications بکش، بعد این یک خط را در Terminal بزن:

    xattr -dr com.apple.quarantine /Applications/Zemzeme.app

بعدش عادی باز می‌شود.

راه بی‌دردسرتر، که این مرحله را کلا ندارد (از سورس بیلد می‌کند):

    curl -fsSL https://raw.githubusercontent.com/smk-labs/zemzeme/main/install.sh | bash
TXT

rm -f "$DMG"
hdiutil create -volname "Zemzeme $VER" -srcfolder "$STAGE" \
  -ov -format UDZO -quiet "$DMG"

echo "dmg: $DMG ($(du -h "$DMG" | cut -f1))"
