#!/bin/bash
# گواهی امضای کد خودساخته «Zemzeme Dev» در کی‌چین لاگین. یک بار لازم است، بعد فراموشش کن.
#
# چرا: امضای ad-hoc گواهی ندارد، پس مک اپ را با اثر انگشت بایت‌های فایل اجرایی
# (cdhash) به یاد می‌آورد. هر بیلد تازه یعنی cdhash تازه یعنی اپ ناشناس تازه،
# پس اکسسبیلیتی و میکروفن از نو پرسیده می‌شوند. با گواهی، شرطی که مک ذخیره می‌کند
# این است و از هر بیلد جان سالم می‌برد:
#   designated => identifier "io.seyed.zemzeme" and certificate leaf = H"..."
#
# گواهی مورد اعتماد سیستم نیست و لازم هم نیست: امضا کردن و تطبیق شرط بی‌اعتماد هم
# کار می‌کند (تنها چیزی که رد می‌شود spctl است، و آن فقط به اپ دانلودی کار دارد).
#
# اگر روزی این گواهی را از کی‌چین پاک کنی، اجازه‌ها یک بار دیگر پرسیده می‌شوند.
set -euo pipefail

NAME="Zemzeme Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -sha256 -days 7300 -nodes \
  -keyout "$TMP/k.pem" -out "$TMP/c.pem" -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# رمز خالی را security نمی‌پذیرد؛ این رمز فقط برای همین چند خط انتقال است
openssl pkcs12 -export -inkey "$TMP/k.pem" -in "$TMP/c.pem" -out "$TMP/c.p12" \
  -passout pass:zemzeme -name "$NAME"

# -A تا codesign در هر بیلد بی‌پرسش به کلید دسترسی داشته باشد
security import "$TMP/c.p12" -k "$KEYCHAIN" -P zemzeme -A -T /usr/bin/codesign >/dev/null

echo "cert: «$NAME» ساخته شد (یک بار برای همیشه)"
