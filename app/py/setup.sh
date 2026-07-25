#!/bin/bash
# راه‌اندازی یک‌باره «پاس ویرایش»: venv، دیکشنری لیلک، مدل نقطه‌گذاری ONNX.
# دانلود اولیه ~۱٫۱ گیگ است؛ بعد از کوانتیزه شدن همه‌چیز کاملا آفلاین کار می‌کند.
# venv و مدل‌ها بیرون بسته اپ و بیرون پوشه پروژه می‌نشینند: هم بسته سبک می‌ماند
# (هر بیلد از نو امضا می‌شود) هم ~۵۰۰ مگ داده از گیت دور می‌ماند.
set -euo pipefail
cd "$(dirname "$0")"
PY=/opt/homebrew/bin/python3

PYDIR="$HOME/Library/Application Support/Zemzeme/py"
MODELS="$PYDIR/models"
VENV="$PYDIR/.venv"
VPY="$VENV/bin/python3"
mkdir -p "$PYDIR"

# مهاجرت یک‌باره از پوشه پروژه، بدون دانلود دوباره
[ -d .venv ]  && [ ! -d "$VENV" ]   && mv .venv  "$VENV"   && echo "moved: .venv"  || true
[ -d models ] && [ ! -d "$MODELS" ] && mv models "$MODELS" && echo "moved: models" || true

# همه‌جا python -m pip، نه bin/pip: شبنگ اسکریپت‌های venv جابه‌جایی را دوست ندارد
[ -x "$VPY" ] || $PY -m venv "$VENV"
"$VPY" -m pip -q install --upgrade pip
"$VPY" -m pip -q install 'piraye==1.1.1' 'spylls==0.1.7' 'onnxruntime==1.27.0' 'sentencepiece==0.2.2'

mkdir -p "$MODELS"
HF=https://huggingface.co/1-800-BAD-CODE/xlm-roberta_punctuation_fullstop_truecase/resolve/main
[ -f "$MODELS/sp.model" ]    || curl -sL -o "$MODELS/sp.model"    "$HF/sp.model"
[ -f "$MODELS/config.yaml" ] || curl -sL -o "$MODELS/config.yaml" "$HF/config.yaml"
if [ ! -f "$MODELS/fa-IR/fa-IR.dic" ]; then
  curl -sL -o "$MODELS/lilak.zip" https://github.com/b00f/lilak/releases/download/v3.3/fa-IR.zip
  unzip -qo -d "$MODELS" "$MODELS/lilak.zip"
  rm -f "$MODELS/lilak.zip"
fi
if [ ! -f "$MODELS/model-int8.onnx" ]; then
  [ -f "$MODELS/model.onnx" ] || curl -L -C - -o "$MODELS/model.onnx" "$HF/model.onnx"
  "$VPY" -m pip -q install onnx
  ZEMZEME_MODELS="$MODELS" "$VPY" export_int8.py
  "$VPY" -m pip -q uninstall -y onnx
  rm -f "$MODELS/model.onnx"    # فقط int8 لازم است؛ ~۸۰۰ مگ آزاد می‌شود
fi
# کش punkt برای piraye، که دیمن هیچ‌وقت محتاج شبکه نشود
"$VPY" -c "from piraye import NormalizerBuilder; NormalizerBuilder().alphabet_fa().build()" >/dev/null 2>&1 || true

ZEMZEME_MODELS="$MODELS" "$VPY" polish.py --check
echo "polish setup: done ($PYDIR)"
