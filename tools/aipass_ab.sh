#!/bin/bash
# محکِ پرامپتِ پاس هوش مصنوعی: یک متنِ خامِ واقعی، چند پرامپت، خروجی‌ها کنار هم.
#
# دلیل وجودش همان دلیلِ --livewav است: تا امروز «این پرامپت بهتر است» یعنی «یک بار
# امتحان کردم و خوب به نظر رسید»، و پرامپت دقیقا همان چیزی است که این‌طور خراب می‌شود.
# اینجا هر تغییرِ پرامپت روی همان ورودی و کنار بقیه دیده می‌شود، با ثانیه و شمارِ کلمه.
#
#   bash tools/aipass_ab.sh                          همه‌ی واریانت‌ها روی همه‌ی فیکسچرها
#   bash tools/aipass_ab.sh B-purpose                فقط یکی
#
# کلید Gemini لازم دارد (منوی زمزمه ← «کلید Gemini…»). بی کلید فقط همین را می‌گوید.
set -uo pipefail
cd "$(dirname "$0")/.."

BIN=app/.build/zemzeme
FIX=tools/fixtures/ai-pass
VAR="$FIX/variants"
LIVE=app/prompts/ai-pass.md            # همان فایلی که پاس واقعی می‌خواند
BACKUP="${TMPDIR:-/tmp}/ai-pass.md.bak"

[ -x "$BIN" ] || { echo "اول بیلد کن: bash app/build.sh"; exit 2; }
"$BIN" --checkkey >/dev/null 2>&1 || { echo "کلید Gemini نیست یا کار نمی‌کند. اول از منوی زمزمه بگذارش، بعد این را بزن."; exit 2; }

want=("$VAR"/*.md)
if [ $# -gt 0 ]; then want=("$VAR/$1.md"); fi

cp "$LIVE" "$BACKUP"
# پرامپتِ زنده سرِ هر خروج برمی‌گردد، حتی با Ctrl+C: نیمه‌کاره ماندنش یعنی اپ با
# پرامپتِ آزمایشی کار کند و هیچ‌کس نفهمد.
trap 'cp "$BACKUP" "$LIVE"' EXIT INT TERM

for rawfile in "$FIX"/*.raw.txt; do
  base=$(basename "$rawfile" .raw.txt)
  echo "════════ $base ════════"
  echo "── خام ($(wc -w < "$rawfile") کلمه) ──"
  cat "$rawfile"
  for v in "${want[@]}"; do
    name=$(basename "$v" .md)
    cp "$v" "$LIVE"
    echo
    echo "── $name ──"
    out=$("$BIN" --aipass "$rawfile" --lang fa-IR 2>"${TMPDIR:-/tmp}/ab.err")
    secs=$(grep -oE '[0-9.]+ ثانیه' "${TMPDIR:-/tmp}/ab.err" | tail -1)
    if [ -z "$out" ]; then
      echo "  (نشد) $(tail -2 "${TMPDIR:-/tmp}/ab.err" | tr '\n' ' ')"
    else
      printf '%s\n' "$out"
      echo "  [$(printf '%s' "$out" | wc -w | tr -d ' ') کلمه، ${secs:-؟}]"
    fi
  done
  echo
  if [ -f "$FIX/$base.want.md" ]; then
    echo "── معیار پذیرش: $FIX/$base.want.md ──"
  fi
done
