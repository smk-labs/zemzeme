# کوانتیزه کردن مدل نقطه‌گذاری به int8: یک بار در setup.sh اجرا می‌شود.
# ورودی models/model.onnx (حدود ۱٫۱ گیگ fp32) و خروجی models/model-int8.onnx (حدود ۳۰۰ مگ).
import os
import sys

MODELS = os.environ.get("ZEMZEME_MODELS") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "models")
SRC = os.path.join(MODELS, "model.onnx")
DST = os.path.join(MODELS, "model-int8.onnx")

if os.path.exists(DST):
    print(f"already there: {DST}")
    sys.exit(0)

from onnxruntime.quantization import QuantType, quantize_dynamic

quantize_dynamic(SRC, DST, weight_type=QuantType.QInt8,
                 extra_options={"MatMulConstBOnly": True})
print(f"quantized: {DST} ({os.path.getsize(DST) // 2**20}MB)")
