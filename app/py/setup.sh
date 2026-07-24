#!/bin/bash
# راه‌اندازی یک‌باره «پاس ویرایش»: venv، دیکشنری لیلک، مدل نقطه‌گذاری ONNX.
# دانلود اولیه ~۱٫۱ گیگ است؛ بعد از کوانتیزه شدن همه‌چیز کاملا آفلاین کار می‌کند.
set -euo pipefail
cd "$(dirname "$0")"
PY=/opt/homebrew/bin/python3

[ -d .venv ] || $PY -m venv .venv
.venv/bin/pip -q install --upgrade pip
.venv/bin/pip -q install 'piraye==1.1.1' 'spylls==0.1.7' 'onnxruntime==1.27.0' 'sentencepiece==0.2.2'

mkdir -p models
HF=https://huggingface.co/1-800-BAD-CODE/xlm-roberta_punctuation_fullstop_truecase/resolve/main
[ -f models/sp.model ]    || curl -sL -o models/sp.model    "$HF/sp.model"
[ -f models/config.yaml ] || curl -sL -o models/config.yaml "$HF/config.yaml"
if [ ! -f models/fa-IR/fa-IR.dic ]; then
  curl -sL -o models/lilak.zip https://github.com/b00f/lilak/releases/download/v3.3/fa-IR.zip
  unzip -qo -d models models/lilak.zip
  rm -f models/lilak.zip
fi
if [ ! -f models/model-int8.onnx ]; then
  [ -f models/model.onnx ] || curl -L -C - -o models/model.onnx "$HF/model.onnx"
  .venv/bin/pip -q install onnx
  .venv/bin/python export_int8.py
  .venv/bin/pip -q uninstall -y onnx
  rm -f models/model.onnx    # فقط int8 لازم است؛ ~۸۰۰ مگ آزاد می‌شود
fi
# کش punkt برای piraye، که دیمن هیچ‌وقت محتاج شبکه نشود
.venv/bin/python -c "from piraye import NormalizerBuilder; NormalizerBuilder().alphabet_fa().build()" >/dev/null 2>&1 || true

.venv/bin/python polish.py --check
echo "polish setup: done"
