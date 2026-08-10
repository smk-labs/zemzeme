#!/bin/bash
# نصب زمزمه با یک خط: سورس را می‌گیرد، کامپایل می‌کند، در /Applications می‌گذارد.
#
#   curl -fsSL https://raw.githubusercontent.com/smk-labs/zemzeme/main/install.sh | bash
#
# چرا از سورس و نه یک .app آماده: اپ با گواهی خودساخته امضا می‌شود، پس هر .app که
# دانلود شود برچسب قرنطینه می‌خورد و مک جلویش را می‌گیرد. بیلد روی خودِ دستگاه این
# مسئله را از ریشه ندارد، و یک سود دیگر هم دارد: گواهی مالِ همین مک می‌شود، پس
# اجازه‌های اکسسبیلیتی و میکروفن از بیلدِ بعدی هم جان سالم می‌برند. کل کار یک
# فراخوان clang است و چند ثانیه طول می‌کشد.
#
# خروجی عمدا انگلیسی است، برخلاف بقیه‌ی اپ: ترمینال متن راست‌به‌چپ را قاطی می‌کند و
# یک پیام خطای درهم‌ریخته بدتر از نبودنش است. کامنت‌ها فارسی می‌مانند.
set -euo pipefail

REPO="${ZEMZEME_REPO:-smk-labs/zemzeme}"
REF="${ZEMZEME_REF:-main}"

die() { printf '\nzemzeme: %s\n' "$1" >&2; exit 1; }
say() { printf 'zemzeme: %s\n' "$1"; }

[ "$(uname -s)" = "Darwin" ] || die "macOS only. This app is built on AppKit."

# ۱۳ سقفِ LSMinimumSystemVersion در Info.plist است. پایین‌تر کامپایل می‌شود ولی
# SMAppService (اجرای خودکار در ورود) اصلا وجود ندارد و اپ سر لانچ می‌افتد.
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 13 ] 2>/dev/null || die "needs macOS 13 or newer (found $(sw_vers -productVersion))."

# clang از Command Line Tools می‌آید. نصبش را خودمان شروع نمی‌کنیم: پنجره‌ی اپل
# رمز می‌خواهد و داخل یک لوله‌ی curl|bash جایی برای پرسیدن نیست.
xcrun --find clang >/dev/null 2>&1 || die "Xcode Command Line Tools are missing. Run this, then try again:
  xcode-select --install"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

say "downloading $REPO@$REF"
# --strip-components=1 پوشه‌ی سرِ آرشیو را برمی‌دارد، پس مسیر همیشه ثابت است.
# بی این باید حدس می‌زدیم گیت‌هاب پوشه را چه نامیده (zemzeme-main برای شاخه،
# zemzeme-2.0.0 برای تگ) و با find دنبالش می‌گشتیم؛ حدس نزدن از درست حدس زدن بهتر است.
curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" | tar xz -C "$TMP" --strip-components=1 \
  || die "download failed. Check the network, or clone the repo and run: bash app/build.sh"

[ -f "$TMP/app/build.sh" ] || die "the downloaded archive does not look like the zemzeme repo."

say "building (one clang call, no dependencies)"
bash "$TMP/app/build.sh"

cat <<'EOF'

zemzeme: installed at /Applications/Zemzeme.app

Next, in this order:
  1. macOS will ask for Accessibility permission. Grant it, or Zemzeme cannot
     write text at your cursor.
  2. Double-tap the RIGHT Command key and start talking. Nothing is shown while
     you speak, on purpose. The green dot means it is listening.
  3. Tap right Command once when you are done. The text arrives all at once.
  4. Right Command + H opens the full shortcut card.

Dictation and file transcription are free: no account, no key, no quota.
EOF
