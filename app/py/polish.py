# دیمن گرم «پاس ویرایش» زمزمه: نرمال‌سازی + نیم‌فاصله + املای محافظه‌کارانه + نقطه‌گذاری.
# فقط اصلاح‌های قطعی و بی‌ریسک؛ هیچ LLM مولدی اینجا نیست و معنا هیچ‌وقت عوض نمی‌شود.
# اجرا: .venv/bin/python3 polish.py            (سرو روی 127.0.0.1:17636)
#        .venv/bin/python3 polish.py --check   (لود و چند نمونه و خروج)
#        .venv/bin/python3 polish.py --once "متن"
import json
import os
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(ROOT, "models")
PORT = 17636
MAX_CHARS = 4000          # تکه بلندتر از این پاس نمی‌خورد (تکه‌های دیکته کوتاه‌اند)
SPELL_GATE_MS = 120       # از این به بعد دیگر املای واژه جدید چک نمی‌شود
PUNCT_GATE_MS = 200       # از این به بعد مدل نقطه‌گذاری اجرا نمی‌شود

ZWNJ = "‌"
PERSIAN_RE = re.compile(r"[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]")
PUNCT_SET = "،؛؟!.:"
# برچسب‌های post مدل، مطابق models/config.yaml (پین‌شده با خود مدل)
POST_LABELS = ["<NULL>", "<ACRONYM>", ".", ",", "?", "？", "，", "。", "、", "・",
               "।", "؟", "،", ";", "።", "፣", "፧"]
# از کل برچسب‌ها فقط این سه علامت را در متن فارسی می‌پذیریم
ACCEPT_MARK = {".": ".", ",": "،", "،": "،", "?": "؟", "؟": "؟"}
# جداکننده بین دو رقم (ممیز و ساعت) را از دید piraye قایم می‌کنیم که «۲.۵» نشکند
SENT_DOT, SENT_COLON = "", ""

# پیشوند/پسوندهایی که با تایید دیکشنری به نیم‌فاصله می‌چسبند
JOIN_PREFIXES = ("می", "نمی")
JOIN_SUFFIXES = ("ها", "های", "هایی", "تر", "ترین")


class Pipeline:
    def __init__(self):
        from piraye import NormalizerBuilder
        from spylls.hunspell import Dictionary
        import numpy as np
        import sentencepiece as spm
        import onnxruntime as ort

        self.np = np
        self.normalizer = (NormalizerBuilder()
                           .alphabet_fa().digit_fa().punctuation_fa()
                           .remove_extra_spaces().build())
        self.dic = Dictionary.from_files(os.path.join(MODELS, "fa-IR", "fa-IR"))
        self.sp = spm.SentencePieceProcessor(os.path.join(MODELS, "sp.model"))
        self.bos, self.eos = self.sp.bos_id(), self.sp.eos_id()
        onnx_path = os.path.join(MODELS, "model-int8.onnx")
        if not os.path.exists(onnx_path):
            onnx_path = os.path.join(MODELS, "model.onnx")
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 4
        self.ort = ort.InferenceSession(onnx_path, opts, providers=["CPUExecutionProvider"])
        self._spell_cache = {}
        self._lock = threading.Lock()
        self.polish("این یک متن نمونه است تا مدل گرم شود")  # warmup

    # ---------- لایه ۱: نرمال‌سازی ----------

    def normalize(self, t):
        # نقطه/دونقطه داخل توکن (۲.۵، ساعت ۱۲:۳۰، main.py) سنتینل می‌شود؛
        # piraye بعد از هر نقطه فاصله می‌گذارد و این‌ها نباید بشکنند
        t = re.sub(r"(?<=[A-Za-z0-9۰-۹])\.(?=[A-Za-z0-9۰-۹])", SENT_DOT, t)
        t = re.sub(r"(?<=[0-9۰-۹]):(?=[0-9۰-۹])", SENT_COLON, t)
        r = self.normalizer.normalize(t)
        t = r[0] if isinstance(r, tuple) else r
        # علامت پس از واژه فارسی: ? و ; به شکل فارسی
        t = re.sub(r"(?<=[؀-ۿ])\?", "؟", t)
        t = re.sub(r"(?<=[؀-ۿ]);", "؛", t)
        # فاصله قبل از علامت حذف، بعدش (چسبیده به حرف فارسی، نه رقم) اضافه
        t = re.sub(r" +([،؛؟!.])(?=[ ؀-ۿ]|$)", r"\1", t)
        t = re.sub(r"([،؛؟!])(?=[؀-ۿ0-9۰-۹])", r"\1 ", t)
        t = re.sub(r"(?<![0-9۰-۹])\.(?=[؀-ۯۺ-ۿ])", ". ", t)
        # سنتینل‌ها آخرِ کار برمی‌گردند که هیچ قاعده فاصله‌ای نبیندشان
        t = t.replace(SENT_DOT, ".").replace(SENT_COLON, ":")
        return re.sub(r"  +", " ", t).strip()

    # ---------- لایه ۱ب: نیم‌فاصله با تایید دیکشنری ----------

    def _split_edge_punct(self, w):
        m = re.match(r"^(.*?)([" + PUNCT_SET + r"]*)$", w)
        return (m.group(1), m.group(2)) if m else (w, "")

    def halfspace(self, t):
        words = t.split(" ")
        out, i = [], 0
        while i < len(words):
            w = words[i]
            nxt = words[i + 1] if i + 1 < len(words) else None
            joined = None
            if nxt:
                core, tail = self._split_edge_punct(nxt)
                if w in JOIN_PREFIXES and core and self.dic.lookup(w + ZWNJ + core):
                    joined = w + ZWNJ + core + tail
                elif core in JOIN_SUFFIXES and w and w[-1] not in PUNCT_SET \
                        and self.dic.lookup(w + ZWNJ + core):
                    joined = w + ZWNJ + core + tail
            if joined:
                out.append(joined)
                i += 2
            else:
                out.append(w)
                i += 1
        return " ".join(out)

    # ---------- لایه ۲: املای محافظه‌کارانه ----------
    # فقط جای خالی مد: ا↔آ با تایید دیکشنری و شرط «دقیقا یک شکل معتبر» (امدند → آمدند).
    # جایگزینی آزاد حروف ممنوع: واژه ناشناسِ دیکته تقریبا همیشه وام‌واژه یا محاوره
    # درست است نه غلط املایی (پلاگین، اونجا) و دست زدن بهش یعنی تغییر معنا.

    def _madda_fix(self, w):
        if w in self._spell_cache:
            return self._spell_cache[w]
        fix = None
        # سد محاوره: «اینه» = این + ه؛ اگر بدون های آخر واژه معتبر باشد، انقباض محاوره‌ای
        # است نه غلط املایی (وگرنه «اینه» آینه می‌شد). کوتاه‌تر از ۵ حرف هم دست نمی‌زنیم.
        if (5 <= len(w) <= 12 and ZWNJ not in w
                and ("ا" in w or "آ" in w)
                and not (w.endswith("ه") and self.dic.lookup(w[:-1]))
                and not re.search(r"[A-Za-z0-9۰-۹]", w)
                and not self.dic.lookup(w)):
            found = set()
            for k, ch in enumerate(w):
                if ch == "ا":
                    c = w[:k] + "آ" + w[k + 1:]
                elif ch == "آ":
                    c = w[:k] + "ا" + w[k + 1:]
                else:
                    continue
                if self.dic.lookup(c):
                    found.add(c)
                    if len(found) > 1:
                        break
            if len(found) == 1:
                fix = found.pop()
        if len(self._spell_cache) > 4096:
            self._spell_cache.clear()
        self._spell_cache[w] = fix
        return fix

    def spell(self, t, t0):
        words = t.split(" ")
        ops = []
        for i, w in enumerate(words):
            if (time.time() - t0) * 1000 > SPELL_GATE_MS:
                break
            core, tail = self._split_edge_punct(w)
            if not core or not PERSIAN_RE.search(core):
                continue
            fix = self._madda_fix(core)
            if fix:
                words[i] = fix + tail
                ops.append([core, fix])
        return " ".join(words), ops

    # ---------- لایه ۳: نقطه‌گذاری با مدل ----------

    def _has_sentence_marks(self, t):
        # نقطه بین دو رقم (۲.۵) علامت جمله نیست
        for i, c in enumerate(t):
            if c in "،؛؟!":
                return True
            if c == "." and not (0 < i < len(t) - 1 and t[i - 1].isdigit() and t[i + 1].isdigit()):
                return True
        return False

    def punctuate(self, t):
        # تکه‌ای که علامت دارد یک بار پاس خورده یا دست‌گذاشته خود کاربر است؛
        # مدل رویش دوباره اجرا نمی‌شود که پاس ایدمپوتنت بماند
        if self._has_sentence_marks(t):
            return t
        om = self.sp.encode_as_offset_mapping(t)
        ids, pieces, offs = om["ids"], om["pieces"], om["offsets"]
        if not ids or len(ids) > 250:
            return t
        arr = self.np.array([[self.bos] + list(ids) + [self.eos]], dtype=self.np.int64)
        _pre, post, _cap, _seg = self.ort.run(None, {"input_ids": arr})
        post = post[0][1:-1]
        inserts = []
        for k in range(len(ids)):
            idx = int(post[k])
            mark = ACCEPT_MARK.get(POST_LABELS[idx]) if 0 <= idx < len(POST_LABELS) else None
            if not mark:
                continue
            if k + 1 < len(pieces) and not pieces[k + 1].startswith("▁"):
                continue                                    # فقط انتهای واژه
            end = offs[k][1]
            if end < len(t) and t[end] != " ":
                continue                                    # وسط واژه یا قبل نیم‌فاصله ممنوع
            if end == 0 or not t[end - 1].isalnum():
                continue                                    # بعد از علامت موجود ممنوع
            rest = t[end:].lstrip()
            if rest and rest[0] in PUNCT_SET:
                continue                                    # علامت پشت علامت ممنوع
            if mark == "،" and end == len(t):
                continue                                    # ویرگول ته تکه بی‌معنی است
            inserts.append((end, mark))
        for pos, mark in reversed(inserts):
            t = t[:pos] + mark + t[pos:]
        return t

    # ---------- کل پاس ----------

    def polish(self, text):
        t0 = time.time()
        if not text or len(text) > MAX_CHARS or not PERSIAN_RE.search(text):
            return text, []
        with self._lock:
            t = self.normalize(text)
            t = self.halfspace(t)
            t, ops = self.spell(t, t0)
            if (time.time() - t0) * 1000 < PUNCT_GATE_MS:
                t = self.punctuate(t)
        t = re.sub(r"  +", " ", t).strip()
        return (t if t else text), ops


PIPE = None
READY = threading.Event()
BOOT_ERR = [None]


def load_pipeline():
    global PIPE
    try:
        PIPE = Pipeline()
        READY.set()
    except Exception as e:  # noqa: BLE001 — دیمن بدون مدل هم باید passthrough بماند
        BOOT_ERR[0] = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"polish: load failed: {BOOT_ERR[0]}\n")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path.startswith("/alive"):
            self._send(200, {"ready": READY.is_set(), "err": BOOT_ERR[0]})
        else:
            self._send(404, {"err": "not found"})

    def do_POST(self):
        if self.path != "/polish":
            self._send(404, {"err": "not found"})
            return
        try:
            n = int(self.headers.get("Content-Length", 0))
            req = json.loads(self.rfile.read(n) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._send(400, {"err": "bad json"})
            return
        text = req.get("text", "")
        lang = req.get("lang", "fa-IR")
        t0 = time.time()
        if not isinstance(text, str) or not READY.is_set() or str(lang).startswith("en"):
            self._send(200, {"text": text, "ready": READY.is_set(), "ms": 0, "spell": []})
            return
        try:
            out, ops = PIPE.polish(text)
        except Exception:  # noqa: BLE001 — هر خطایی یعنی همان متن خام برگردد
            out, ops = text, []
        self._send(200, {"text": out, "ready": True,
                         "ms": int((time.time() - t0) * 1000), "spell": ops})


def main():
    if "--check" in sys.argv or "--once" in sys.argv:
        t0 = time.time()
        load_pipeline()
        if BOOT_ERR[0]:
            print(f"load FAILED: {BOOT_ERR[0]}")
            return 1
        print(f"load: {time.time() - t0:.1f}s")
        samples = ["سلام دنیا چطوری امروز می شود 24 نفر آمدند",
                   "این یک ازمایش ساده است که ببینیم چه می کند",
                   "hello this is english and must not change"]
        if "--once" in sys.argv:
            samples = [sys.argv[sys.argv.index("--once") + 1]]
        for s in samples:
            t1 = time.time()
            out, ops = PIPE.polish(s)
            print(f"  {int((time.time() - t1) * 1000)}ms spell={ops}\n  < {s}\n  > {out}")
        return 0
    threading.Thread(target=load_pipeline, daemon=True).start()
    try:
        srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    except OSError:
        sys.stderr.write("polish: port busy, another daemon is up\n")
        return 0
    srv.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
