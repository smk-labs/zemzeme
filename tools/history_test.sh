#!/bin/bash
# تست طلاییِ تاریخچه: ادعا این است که یک دیکته‌ی تمام‌شده دیگر گم نمی‌شود، و تنها
# راهِ ثابت کردنش این است که نویسنده بمیرد و **یک پروسه‌ی دیگر** فایل را سرد باز کند.
# برای همین هر فاز یک اجرای جداست، نه یک main بلند.
#
# HOME جابه‌جا می‌شود که نه لاگ و نه تاریخچه‌ی واقعی کاربر دست نخورد؛ خودِ اپ هم از
# همین مسیر می‌خواند (ZSupport)، پس مسیرِ زیرِ تست همان مسیرِ واقعی است.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/zemzeme-history-test"
work="${TMPDIR:-/tmp}/zemzeme-history-work"
clang -fobjc-arc -O1 -Wall -Werror -I app/Sources-objc \
  app/Sources-objc/core.m app/Sources-objc/history.m tools/history_test.m \
  -framework Foundation -framework AppKit -framework CoreText -o "$out"

rm -rf "$work"
mkdir -p "$work/home" "$work/plain" "$work/many" "$work/sweep" "$work/dedupe" "$work/junk"
export HOME="$work/home" CFFIXED_USER_HOME="$work/home"

N=250

# ۱) نوشتن، مرگ، و خواندنِ سرد. متن‌ها عمدا خط جدید و گیومه و بک‌اسلش دارند.
"$out" write "$work/plain" $N
"$out" read  "$work/plain" $N

# «یک رکورد، یک خط» ادعای کلِ فرمت است، پس با ابزار بیرونی سنجیده می‌شود نه با
# خودِ کد: شمارِ خط باید دقیقا شمارِ رکورد باشد، با اینکه هر متن چند خط دارد.
lines=$(wc -l < "$work/plain/history.jsonl" | tr -d ' ')
[ "$lines" = "$N" ] || { echo "history: هر رکورد یک خط نیست ($lines خط برای $N رکورد)"; exit 1; }
# و بی‌اپ خواندنی: آخرین خط باید تنهایی یک JSON کامل باشد
tail -n 1 "$work/plain/history.jsonl" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' \
  || { echo "history: خطِ آخر بی‌اپ خوانده نشد"; exit 1; }

# ۲) کرشِ وسطِ نوشتن: رکوردِ آخر از وسط بریده می‌شود. بقیه باید کامل بمانند…
"$out" tear   "$work/plain"
"$out" read   "$work/plain" $((N - 1))
# …و اپ که دوباره بالا آمد، رکوردِ تازه هم باید سالم بنشیند، نه اینکه به دُمِ نصفه
# بچسبد و با آن بسوزد. این همان چیزی است که بی زخم‌بندیِ history.m رد می‌شد.
"$out" append "$work/plain" $((N - 1))
"$out" read   "$work/plain" $N

# ۳) چهارصد نوشتنِ هم‌زمان از چند نخ: هیچ‌کدام نباید در هم بروند یا گم شوند.
# اینجا ترتیب ادعا نمی‌شود ــ نوشتنِ موازی ترتیبی ندارد ــ ولی **کامل بودن** چرا.
"$out" hammer  "$work/many" 400
"$out" readset "$work/many" 400
lines=$(wc -l < "$work/many/history.jsonl" | tr -d ' ')
[ "$lines" = "400" ] || { echo "history: نوشتنِ هم‌زمان خط‌ها را در هم برد ($lines خط)"; exit 1; }

# ۴) جاروی شصت‌روزه، ۵) یک سشن با چند تحویل، ۶) فایلِ خالی و آشغال
"$out" sweep  "$work/sweep"
"$out" dedupe "$work/dedupe"
"$out" junk   "$work/junk"

echo "history: تست طلایی سبز"
