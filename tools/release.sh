#!/bin/bash
# ریلیز، یک دستور: پیش‌پرواز، بیلد از صفر، dmg، تگ، و انتشار در گیت‌هاب.
#
#   bash tools/release.sh                 فقط بگو آماده‌ایم یا نه (هیچ‌چیز عوض نمی‌شود)
#   bash tools/release.sh 2.1.0           آماده کن و بایست: نسخه، بیلد، dmg
#   bash tools/release.sh 2.1.0 --publish و منتشر کن: کامیت نسخه، تگ، پوش، ریلیز
#
# چرا این فایل هست: ریلیزِ ۲٫۰٫۰ منتشر شد و یازده کامیت بعد، Info.plist هنوز همان
# ۲٫۰٫۰ را می‌گفت. یعنی dmg تازه هم‌نامِ dmg منتشرشده درمی‌آمد و کاربر هیچ راهی نداشت
# بفهمد کدام را دارد، در حالی که یکی‌شان باگِ گم شدن بی‌صدای متن را داشت. آن اشتباه با
# دقتِ بیشتر جلوگیری نمی‌شود، با گارد جلوگیری می‌شود؛ هر گاردِ پایین یک بار لازم شده.
set -uo pipefail
cd "$(dirname "$0")/.."

REPO="smk-labs/zemzeme"
PLIST="app/Info.plist"
BRANCH="main"

want="${1:-}"
publish=0
[ "${2:-}" = "--publish" ] && publish=1

die() { printf '✗ %s\n' "$1" >&2; exit 1; }
ok()  { printf '✓ %s\n' "$1"; }

plist_get() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }

cur=$(plist_get CFBundleShortVersionString)
last=$(git tag --list 'v[0-9]*' | sort -V | tail -1)
echo "نسخه‌ی فعلی در Info.plist: $cur ﹒ آخرین تگ: ${last:-هیچ}"
echo

# ---------- پیش‌پرواز ----------
# همه‌ی گاردها همیشه اجرا می‌شوند، حتی در حالتِ فقط-گزارش: کسی که می‌پرسد «آماده‌ایم؟»
# باید جوابِ کامل بگیرد، نه جوابی که فقط سرِ انتشار کشف می‌شود.
fail=0
check() { if eval "$2"; then ok "$1"; else printf '✗ %s\n' "$1" >&2; fail=1; fi; }

check "درخت کاری تمیز است" '[ -z "$(git status --porcelain)" ]'
check "روی شاخه‌ی $BRANCH هستیم" '[ "$(git rev-parse --abbrev-ref HEAD)" = "$BRANCH" ]'
git fetch -q origin 2>/dev/null
check "با origin/$BRANCH برابریم" '[ "$(git rev-list --left-right --count origin/$BRANCH...HEAD)" = "$(printf "0\t0")" ]'
check "gh لاگین است" 'gh auth status >/dev/null 2>&1'

# تست‌ها: همه‌ی تست‌های طلایی. اگر یکی قرمز است، ریلیز حتی شروع هم نمی‌شود.
#
# فهرست از خودِ پوشه درمی‌آید، نه از یک لیستِ دستی. لیستِ دستی دو بار بی‌صدا شکست و
# هر دو بارش را کسی ندید: `hole_test` سرِ کامیت 5cabba1 حذف شد و جایش `queue_test`
# آمد، ولی اسمِ مرده در لیست ماند. یعنی این گارد روی فایلی که وجود ندارد `bash` صدا
# می‌زد، ۱۲۷ می‌گرفت، و ریلیز **همیشه** قرمز بود؛ و در همان حال بزرگ‌ترین تستِ ریپو
# (۵۷۲ خط) اصلا در گارد نبود. با گلاب، تستِ تازه خودش وارد می‌شود و تستِ حذف‌شده خودش
# بیرون می‌رود، پس این کلاس اشتباه دیگر تکرارشدنی نیست.
#
# و خروجیِ تستِ قرمز چاپ می‌شود، نه اینکه به /dev/null برود. قبلا می‌رفت، و ۲۲ آگوست
# ۲۰۲۶ هزینه‌اش را داد: یک تست قرمز شد و تمامِ چیزی که اپراتور دید یک خطِ «✗» بود، بی
# هیچ نشانی از اینکه کدام ادعا شکست. تشخیص شد اجرای دوباره و امید به تکرارِ خرابی.
# گاردی که شاهدِ خودش را دور بریزد، نیمی از کارش را نکرده.
shopt -s nullglob
tests=(tools/*_test.sh)
[ "${#tests[@]}" -gt 0 ] || die "هیچ تست طلایی‌ای پیدا نشد (tools/*_test.sh): گاردِ تست بی‌معنا می‌شود"
tlog=$(mktemp)
for f in "${tests[@]}"; do
  t=$(basename "$f" _test.sh)
  if bash "$f" > "$tlog" 2>&1; then
    ok "تست $t سبز است"
  else
    printf '✗ %s\n' "تست $t سبز است" >&2
    tail -20 "$tlog" | sed 's/^/    /' >&2   # خطِ شکسته در این ریپو ته خروجی است
    fail=1
  fi
done
rm -f "$tlog"

if [ -z "$want" ]; then
  echo
  # چند کامیت از آخرین تگ عقب‌تریم: همان عددی که امروز یازده بود و کسی نگاهش نکرد
  if [ -n "$last" ]; then
    n=$(git rev-list --count "$last"..HEAD)
    echo "از $last تا اینجا: $n کامیت"
    [ "$n" -gt 0 ] && [ "$cur" = "${last#v}" ] && \
      printf '⚠ %s\n' "نسخه دست‌نخورده مانده ($cur) در حالی که $n کامیت آمده. برای ریلیز باید بالا برود."
  fi
  [ "$fail" = 0 ] && echo && echo "آماده. نسخه‌ی بعدی را بده: bash tools/release.sh <نسخه>"
  exit "$fail"
fi

[ "$fail" = 0 ] || die "پیش‌پرواز رد شد؛ تا این‌ها سبز نشوند ریلیزی در کار نیست."

# ---------- گاردهای نسخه ----------
echo
[[ "$want" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "نسخه باید مثل 2.1.0 باشد، این را گرفتم: $want"

# **گاردِ اصلی، همان که امروز نبود.** نسخه‌ای که تگ یا ریلیز دارد، دوباره منتشر
# نمی‌شود: دو بایتِ متفاوت زیر یک شماره، یعنی کاربر نمی‌تواند بفهمد چه دارد.
git rev-parse -q --verify "refs/tags/v$want" >/dev/null && die "تگ v$want از قبل هست. نسخه را بالا ببر."
gh release view "v$want" -R "$REPO" >/dev/null 2>&1 && die "ریلیز v$want از قبل منتشر شده. نسخه را بالا ببر."

# و رو به جلو، نه عقب: کسی که اشتباهی عددِ کوچک‌تر بدهد، ریلیزِ قبلی را در فهرست
# «آخرین» جابه‌جا می‌کند و همان بدترین حالتِ گیج‌کننده است.
if [ -n "$last" ]; then
  top=$(printf '%s\n%s\n' "${last#v}" "$want" | sort -V | tail -1)
  [ "$top" = "$want" ] || die "v$want از $last عقب‌تر است."
fi
ok "v$want تازه است و رو به جلو"

# ---------- نسخه، بیلد، dmg ----------
if [ "$cur" != "$want" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $want" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(( $(plist_get CFBundleVersion) + 1 ))" "$PLIST"
  # ریدمی نام فایل dmg را می‌گوید؛ جا ماندنش یعنی سند به فایلی اشاره کند که نیست.
  # **هر دو ریدمی**، و این «هر دو» را با هزینه یاد گرفتیم: تا امروز فقط README.md
  # اینجا بود، پس README.en.md روی ۲٫۰٫۰ ماند تا سه ریلیز بعد کسی دستی پیدایش کرد.
  # گاردی که یکی از دو نسخه را بپوشاند، همان باگ را در نسخه‌ی دیگر تضمین می‌کند.
  for r in README.md README.en.md; do
    sed -i '' -E "s/\`Zemzeme-[0-9]+\.[0-9]+\.[0-9]+\.dmg\`/\`Zemzeme-$want.dmg\`/" "$r"
  done
  ok "نسخه شد $want (و CFBundleVersion یکی جلو رفت)"
else
  ok "نسخه از قبل $want است"
fi

rm -rf app/.build/Zemzeme.app app/.build/zemzeme
ZEMZEME_NO_LAUNCH=1 bash app/build.sh >/dev/null || die "بیلد شکست"
built=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' app/.build/Zemzeme.app/Contents/Info.plist)
[ "$built" = "$want" ] || die "بسته $built درآمد نه $want"
codesign -v --strict app/.build/Zemzeme.app 2>/dev/null || die "امضای بسته سالم نیست"
ok "بیلد از صفر، امضا سالم، نسخه‌ی بسته $built"

bash tools/make-dmg.sh >/dev/null || die "ساخت dmg شکست"
DMG="app/.build/Zemzeme-$want.dmg"
[ -f "$DMG" ] || die "$DMG ساخته نشد"
ok "dmg آماده: $DMG ($(du -h "$DMG" | cut -f1))"

# ---------- یادداشت ریلیز ----------
# از عنوانِ کامیت‌ها. عنوان‌ها در این ریپو خودشان یک‌خطیِ فارسیِ خوانا هستند، پس
# یادداشتِ دستی فقط دوباره‌نویسیِ همان‌ها می‌شد.
NOTES=$(mktemp)
{
  echo "## چه چیزی عوض شد"
  echo
  if [ -n "$last" ]; then git log --format='- %s' "$last"..HEAD; else git log --format='- %s' -20; fi
  echo
  echo "نصب از سورس (پیشنهادی، بی مرحله‌ی قرنطینه):"
  echo '```bash'
  echo "curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash"
  echo '```'
} > "$NOTES"

if [ "$publish" = 0 ]; then
  echo
  echo "آماده است و هیچ‌چیز منتشر نشد. یادداشت ریلیز:"
  echo
  sed 's/^/    /' "$NOTES"
  echo
  echo "برای انتشار: bash tools/release.sh $want --publish"
  rm -f "$NOTES"
  exit 0
fi

# ---------- انتشار ----------
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -q -m "نسخه $want"
  git push -q origin "$BRANCH" || die "پوشِ شاخه شکست"
  ok "کامیت نسخه و پوش شد"
fi
git tag "v$want" && git push -q origin "v$want" || die "تگ یا پوشِ تگ شکست"
ok "تگ v$want پوش شد"
gh release create "v$want" "$DMG" -R "$REPO" -t "زمزمه $want" -F "$NOTES" || die "ساخت ریلیز شکست"
rm -f "$NOTES"
echo
ok "منتشر شد: https://github.com/$REPO/releases/tag/v$want"
