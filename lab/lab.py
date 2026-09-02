# آزمایشگاه پاس نهایی زمزمه: چهار مسیر روی یک فایل صوتی، با یک پرامپت مشترک.
# فقط stdlib. هیچ چیزی از ریپوی zemzeme را عوض نمی‌کند و فقط CLI نصب‌شده را می‌خواند.
#
#   python3 lab.py voice.m4a                 چهار مسیر و گزارش
#   python3 lab.py voice.m4a --dry           همه‌ی مسیرها بدون تماس با API (تست خود هارنس)
#   python3 lab.py voice.m4a --arms A,C      فقط بعضی مسیرها
#   python3 lab.py --check                   فقط بررسی آمادگی
#
# مسیرها:
#   A  صدا تنها  ->  متن نهایی
#   B  متن خام تنها  ->  متن نهایی        (حس درونی سید: شاید همین بهتر باشد)
#   C  صدا + متن خام  ->  متن نهایی       (پیشنهاد من)
#   D  صدا -> رونویسی مو‌به‌مو            (برای سنجیدن شنوایی مدل در برابر نقطه‌ی گوگل)
import base64
import html
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "out")
BASE = "https://generativelanguage.googleapis.com"
ZEM = "/Applications/Zemzeme.app/Contents/MacOS/zemzeme"
MODEL = "gemini-3.6-flash"
KEYCHAIN_SERVICE = "zemzeme-gemini"
# قیمت رسمی 3.6 flash، دلار به ازای یک میلیون توکن
PRICE_IN, PRICE_OUT = 1.50, 7.50
# قالب‌هایی که هم جمینای می‌گیرد هم CLI زمزمه؛ بقیه با afconvert به FLAC می‌روند.
# ogg عمدا اینجا نیست: جمینای قبولش دارد ولی CLI زمزمه ردش می‌کند، و متن خام
# باید از همان مسیر تولید بیاید که اپ استفاده می‌کند.
OK_AUDIO = {".wav": "audio/wav", ".mp3": "audio/mpeg", ".aiff": "audio/aiff",
            ".aif": "audio/aiff", ".aac": "audio/aac", ".flac": "audio/flac"}


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# ---------- کلید ----------

def api_key():
    """کلید از محیط، وگرنه از Keychain. هیچ‌وقت چاپ نمی‌شود."""
    k = os.environ.get("GEMINI_API_KEY", "").strip()
    if k:
        return k
    try:
        out = subprocess.run(["security", "find-generic-password", "-s",
                              KEYCHAIN_SERVICE, "-w"],
                             capture_output=True, text=True, timeout=10)
        if out.returncode == 0:
            return out.stdout.strip()
    except Exception:
        pass
    return ""


# ---------- صدا ----------

def duration(path):
    try:
        out = subprocess.run(["afinfo", path], capture_output=True, text=True, timeout=30)
        m = re.search(r"estimated duration:\s*([\d.]+)", out.stdout)
        if m:
            return float(m.group(1))
    except Exception:
        pass
    return 0.0


def prep_audio(path):
    """قالب پشتیبانی‌شده را دست نمی‌زند؛ بقیه را به FLAC مونو ۱۶ کیلوهرتز می‌برد."""
    ext = os.path.splitext(path)[1].lower()
    if ext in OK_AUDIO:
        return path, OK_AUDIO[ext]
    dst = os.path.join(OUT, os.path.splitext(os.path.basename(path))[0] + ".16k.flac")
    log(f"تبدیل به FLAC: {os.path.basename(dst)}")
    r = subprocess.run(["afconvert", "-f", "flac", "-d", "flac@16000", "-c", "1",
                        path, dst], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(dst):
        raise SystemExit(f"afconvert نشد: {r.stderr.strip()[:400]}")
    return dst, "audio/flac"


# ---------- متن خام از خود زمزمه ----------

def draft_text(path, lang, jobs):
    """رونویسی خام با همان نقطه‌ی مجانی گوگل که اپ استفاده می‌کند."""
    # کش به نام همان فایل بسته است، نه یک نام ثابت: وگرنه اجرای بعدی بی‌صدا
    # متن خامِ فایل قبلی را می‌خواند و همه‌ی عددها بی‌معنا می‌شدند.
    cached = os.path.join(OUT, "draft-" + os.path.basename(path) + ".txt")
    if os.path.exists(cached) and os.path.getsize(cached) > 0:
        log(f"متن خام از کش خوانده شد ({os.path.basename(cached)}). برای گرفتن تازه پاکش کن.")
        return open(cached, encoding="utf8").read().strip()
    if not os.path.exists(ZEM):
        raise SystemExit(f"زمزمه نصب نیست: {ZEM}")
    log(f"رونویسی خام با زمزمه (lang={lang}, jobs={jobs})...")
    t0 = time.time()
    r = subprocess.run([ZEM, "--transcribe", path, "--lang", lang,
                        "--jobs", str(jobs), "--out", OUT],
                       capture_output=True, text=True)
    txt = ""
    guess = os.path.join(OUT, os.path.splitext(os.path.basename(path))[0] + ".txt")
    for cand in [l.strip() for l in r.stdout.splitlines() if l.strip().endswith(".txt")] + [guess]:
        if os.path.exists(cand):
            txt = open(cand, encoding="utf8").read().strip()
            break
    if not txt:
        raise SystemExit("رونویسی خام چیزی نداد:\n" + (r.stderr or "")[-800:])
    open(cached, "w", encoding="utf8").write(txt)
    log(f"متن خام آمد: {len(txt.split())} کلمه در {time.time() - t0:.0f} ثانیه")
    return txt


# ---------- تماس با جمینای ----------

def http(url, data=None, headers=None, method=None, timeout=600, tries=3):
    """قطع شدن وسط کار یک بار دیده شد و کل اجرا را کشت، پس تلاش دوباره دارد.
    خطای HTTP برگردانده می‌شود (خودش خبر است)، ولی قطعِ شبکه دوباره امتحان می‌شود."""
    for i in range(tries):
        req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, dict(r.headers), r.read()
        except urllib.error.HTTPError as e:
            return e.code, dict(e.headers), e.read()
        except Exception as e:
            if i == tries - 1:
                raise
            log(f"شبکه قطع شد ({type(e).__name__})، تلاش {i + 2} از {tries}...")
            time.sleep(3 * (i + 1))


def upload_file(path, mime, key):
    """آپلود با Files API (سه مرحله). برمی‌گرداند uri. تا ۴۸ ساعت زنده می‌ماند."""
    size = os.path.getsize(path)
    log(f"آپلود صدا ({size / 1e6:.1f} مگابایت)...")
    st, hd, body = http(
        f"{BASE}/upload/v1beta/files",
        data=json.dumps({"file": {"display_name": os.path.basename(path)}}).encode(),
        headers={"x-goog-api-key": key, "Content-Type": "application/json",
                 "X-Goog-Upload-Protocol": "resumable",
                 "X-Goog-Upload-Command": "start",
                 "X-Goog-Upload-Header-Content-Length": str(size),
                 "X-Goog-Upload-Header-Content-Type": mime})
    if st != 200:
        raise SystemExit(f"شروع آپلود نشد ({st}): {body[:500].decode('utf8', 'replace')}")
    up = hd.get("X-Goog-Upload-URL") or hd.get("x-goog-upload-url")
    if not up:
        raise SystemExit("آدرس آپلود در هدرها نبود: " + json.dumps(hd)[:500])
    st, _, body = http(up, data=open(path, "rb").read(),
                       headers={"Content-Length": str(size),
                                "X-Goog-Upload-Offset": "0",
                                "X-Goog-Upload-Command": "upload, finalize"})
    if st != 200:
        raise SystemExit(f"آپلود نشد ({st}): {body[:500].decode('utf8', 'replace')}")
    f = json.loads(body).get("file", {})
    uri, name = f.get("uri"), f.get("name", "")
    # صدا ممکن است لحظه‌ای در حال پردازش بماند؛ تا ACTIVE صبر می‌کنیم
    for _ in range(60):
        if f.get("state") in (None, "ACTIVE"):
            break
        time.sleep(2)
        st, _, body = http(f"{BASE}/v1beta/{name}", headers={"x-goog-api-key": key})
        f = json.loads(body) if st == 200 else {"state": "ACTIVE"}
    log(f"آپلود شد: {uri}")
    return uri


def walk_text(node, acc):
    """متن را از هر شکلی از پاسخ بیرون می‌کشد؛ تکه‌های thinking را رد می‌کند."""
    if isinstance(node, dict):
        if node.get("thought") is True:
            return
        for k, v in node.items():
            if k in ("text", "output_text") and isinstance(v, str):
                acc.append(v)
            else:
                walk_text(v, acc)
    elif isinstance(node, list):
        for v in node:
            walk_text(v, acc)


def walk_usage(node, acc):
    if isinstance(node, dict):
        for k, v in node.items():
            if isinstance(v, int) and ("token" in k.lower() or "Token" in k):
                acc[k] = v
            else:
                walk_usage(v, acc)
    elif isinstance(node, list):
        for v in node:
            walk_usage(v, acc)


def ask(key, system, parts, label, thinking=None):
    """یک تماس. اول Interactions API، اگر نپذیرفت همان درخواست با generateContent."""
    body = {"model": MODEL, "system_instruction": system, "input": parts}
    if thinking:
        body["generation_config"] = {"thinking_level": thinking}
    t0 = time.time()
    st, _, raw = http(f"{BASE}/v1beta/interactions",
                      data=json.dumps(body, ensure_ascii=False).encode(),
                      headers={"x-goog-api-key": key, "Content-Type": "application/json"})
    api = "interactions"
    if st != 200:
        log(f"[{label}] interactions جواب {st} داد، generateContent را امتحان می‌کنم")
        open(os.path.join(OUT, f"raw-{label}-interactions-{st}.json"), "wb").write(raw)
        st, _, raw = http(
            f"{BASE}/v1beta/models/{MODEL}:generateContent",
            data=json.dumps(to_generate_content(system, parts, thinking),
                            ensure_ascii=False).encode(),
            headers={"x-goog-api-key": key, "Content-Type": "application/json"})
        api = "generateContent"
    dt = time.time() - t0
    open(os.path.join(OUT, f"raw-{label}.json"), "wb").write(raw)
    if st != 200:
        return {"ok": False, "err": f"{st}: {raw[:600].decode('utf8', 'replace')}",
                "sec": dt, "api": api, "text": "", "usage": {}}
    doc = json.loads(raw)
    acc, usage = [], {}
    walk_text(doc, acc)
    walk_usage(doc, usage)
    return {"ok": True, "err": "", "sec": dt, "api": api,
            "text": "".join(acc).strip(), "usage": usage}


def to_generate_content(system, parts, thinking):
    """همان درخواست به شکل قدیمی، برای وقتی که اندپوینت تازه شکل دیگری می‌خواهد."""
    ps = []
    for p in parts:
        if p.get("type") == "text":
            ps.append({"text": p["text"]})
        elif "uri" in p:
            ps.append({"file_data": {"mime_type": p["mime_type"], "file_uri": p["uri"]}})
        elif "data" in p:
            ps.append({"inline_data": {"mime_type": p["mime_type"], "data": p["data"]}})
    body = {"contents": [{"role": "user", "parts": ps}],
            "system_instruction": {"parts": [{"text": system}]}}
    if thinking:
        body["generationConfig"] = {"thinkingConfig": {"thinkingLevel": thinking}}
    return body


# ---------- سنجه‌ها ----------
# هدف یک عدد نیست، جواب دادن به یک سوال است: چه چیزی از متن خام جا افتاد.

# نیم‌فاصله به فاصله تبدیل می‌شود، نه حذف: وگرنه «می‌شود» و «می شود» دو چیز
# متفاوت شمرده می‌شدند و پاس درست، جاافتادگی الکی نشان می‌داد.
DROP = dict.fromkeys(map(ord, "ـًٌٍَُِّْ"), None)
SPLIT = dict.fromkeys(map(ord, "‌‍‎‏"), " ")
FA_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
STOP = set("""و که را به از در این آن با هم برای ولی اما یا اگر تا هر بر می نمی
یه یک خب دیگه خیلی چون پس البته مثل مثلا یعنی هست هستش بود شد شده کرد کردن
من تو او ما شما آنها اون اینا چه چی کی کجا بله نه آره اوکی
ببخشید منظورم اوم اه ام آم""".split())


def norm(t):
    t = t.translate(DROP).translate(SPLIT).translate(FA_DIGITS)
    return t.replace("ي", "ی").replace("ك", "ک").replace("أ", "ا").replace("إ", "ا")


def tokens(t):
    # [^\W\d_] یعنی «هر حرفی، هر خطی»: علائم فارسی (، ؛ ؟) بیرون می‌مانند.
    return re.findall(r"[^\W\d_]+|\d+", norm(t))


def measure(draft, out):
    dt, ot = tokens(draft), tokens(out)
    oset, dset = set(ot), set(dt)
    # مرزِ واژه بین دو متن یکی نیست: متن خام «میکنه» را سرهم می‌نویسد و پاس
    # «می‌کنه» را با نیم‌فاصله، و نیم‌فاصله اینجا فاصله شمرده می‌شود. پس علاوه بر
    # تطبیق توکن، داخل رشته‌ی بی‌فاصله هم می‌گردیم، وگرنه هر نیم‌فاصله‌ی درست
    # «واژه‌ی جاافتاده» شمرده می‌شد. اندازه‌گیری: بیشترِ فهرست جاافتاده‌ها همین بود.
    joined_out, joined_draft = "".join(ot), "".join(dt)
    have = lambda w, s, j: w in s or w in j
    content = [w for w in dict.fromkeys(dt) if w not in STOP and len(w) > 1]
    missing = [w for w in content if not have(w, oset, joined_out)]
    fresh = [w for w in dict.fromkeys(ot)
             if not have(w, dset, joined_draft) and w not in STOP and len(w) > 1]
    dnum = {w for w in dt if w.isdigit()}
    dlat = {w for w in dt if re.match(r"^[A-Za-z]", w)}
    return {
        "words_draft": len(dt), "words_out": len(ot),
        "coverage": round(100 * (1 - len(missing) / max(1, len(content))), 1),
        "missing": missing, "fresh": fresh,
        "lost_numbers": sorted(dnum - oset), "lost_latin": sorted(dlat - oset),
        "bullets": len(re.findall(r"(?m)^\s*[-*••\d]+[.)\s]", out)),
        "paragraphs": len([p for p in out.split("\n\n") if p.strip()]),
    }


def cost(u):
    """توکن فکر کردن جدا شمرده می‌شود ولی مثل خروجی پول می‌گیرد، و اندازه‌گیری
    نشان داد بیشترِ هزینه همان است (۶۱۰۰ توکن فکر در برابر ۱۶۵۴ توکن متن)."""
    g = lambda *names: next((u[n] for n in names if n in u), 0)
    i = g("total_input_tokens", "promptTokenCount", "prompt_tokens", "input_tokens")
    o = g("total_output_tokens", "candidatesTokenCount", "output_tokens")
    th = g("total_thought_tokens", "thoughtsTokenCount")
    return i, o + th, round(i * PRICE_IN / 1e6 + (o + th) * PRICE_OUT / 1e6, 4)


# ---------- گزارش ----------

def report(meta, draft, arms):
    rows = []
    for a in arms:
        m, r = a["metrics"], a["res"]
        i, o, c = cost(r.get("usage", {}))
        rows.append(f"""<tr><td><b>{a['id']}</b> {html.escape(a['name'])}</td>
<td>{'خطا' if not r['ok'] else str(m['words_out']) + ' کلمه'}</td>
<td>{m['coverage']}%</td><td>{len(m['missing'])}</td>
<td>{len(m['lost_numbers']) + len(m['lost_latin'])}</td>
<td>{m['bullets']} / {m['paragraphs']}</td>
<td>{r['sec']:.1f}s</td><td>{i}+{o}</td><td>${c}</td></tr>""")
    blocks = [f"""<section><h2>متن خام زمزمه</h2>
<div class="meta">{len(tokens(draft))} کلمه، مرجع کامل بودن</div>
<pre>{html.escape(draft)}</pre></section>"""]
    for a in arms:
        m, r = a["metrics"], a["res"]
        extra = ""
        if r["ok"]:
            if m["missing"]:
                extra += f'<div class="warn">جا افتاد ({len(m["missing"])}): ' \
                         + html.escape("، ".join(m["missing"][:60])) + "</div>"
            if m["lost_numbers"] or m["lost_latin"]:
                extra += '<div class="bad">عدد یا لاتینِ گم‌شده: ' \
                         + html.escape("، ".join(m["lost_numbers"] + m["lost_latin"])) + "</div>"
            if m["fresh"]:
                extra += f'<div class="ok">تازه، نبود در متن خام ({len(m["fresh"])}): ' \
                         + html.escape("، ".join(m["fresh"][:60])) + "</div>"
        body = html.escape(r["text"]) if r["ok"] else html.escape(r["err"])
        blocks.append(f"""<section><h2>{a['id']}. {html.escape(a['name'])}</h2>
<div class="meta">{html.escape(a['what'])} | {r['api']} | {r['sec']:.1f} ثانیه</div>
{extra}<pre>{body}</pre></section>""")
    return f"""<title>آزمایش پاس نهایی زمزمه</title>
<style>
:root{{color-scheme:light dark}}
body{{font:16px/1.9 -apple-system,'Vazirmatn',sans-serif;direction:rtl;
max-width:1000px;margin:2rem auto;padding:0 1.2rem}}
h1{{font-size:1.5rem}} h2{{font-size:1.15rem;margin:2rem 0 .4rem}}
pre{{white-space:pre-wrap;background:color-mix(in srgb,canvas 92%,canvastext);
padding:1rem;border-radius:8px;font:15px/2 inherit;direction:rtl}}
table{{border-collapse:collapse;width:100%;font-size:14px}}
th,td{{border:1px solid color-mix(in srgb,canvas 75%,canvastext);padding:.45rem .6rem;text-align:right}}
.meta{{font-size:13px;opacity:.7;margin-bottom:.5rem}}
.warn,.bad,.ok{{font-size:13px;padding:.5rem .7rem;border-radius:6px;margin:.35rem 0}}
.warn{{background:#f5a62333}} .bad{{background:#e5484d33}} .ok{{background:#30a46c33}}
</style>
<h1>آزمایش پاس نهایی</h1>
<div class="meta">{html.escape(meta)}</div>
<table><thead><tr><th>مسیر</th><th>طول</th><th>پوشش</th><th>واژه‌ی جاافتاده</th>
<th>عدد/لاتین گم</th><th>بولت/پاراگراف</th><th>زمان</th><th>توکن</th><th>هزینه</th></tr></thead>
<tbody>{''.join(rows)}</tbody></table>
<p class="meta">پوشش یعنی چند درصد واژه‌های محتوایی متن خام در خروجی هست. «تازه» بد نیست:
در مسیرهای صوتی می‌تواند همان تصحیح درست باشد. قضاوت نهایی چشم آدم است، نه این جدول.</p>
{''.join(blocks)}"""


# ---------- اجرا ----------

# (نام، شرح ورودی، صدا لازم است؟، متن خام از کجا: None یا raw یا شناسه‌ی مسیر دیگر)
ARMS = {
    "A": ("صدا تنها", "فقط صدا را داری. متن خامی وجود ندارد.", True, None),
    "B": ("متن خام تنها", "فقط متن خام تشخیص گفتار را داری و صدا را نداری. "
          "جای مشکوک را از روی معنای جمله درست کن.", False, "raw"),
    # اندازه‌گیری دور اول: متن خام سقف شد نه لنگر. مدل فقط ۳ تا از ۱۱ چیزی را که
    # متن خام انداخته بود برگرداند، در حالی که «صدا تنها» ۹ تا را برگرداند. پس
    # جمله‌ی «متن خام ناقص است» صریح شد تا ببینیم لنگر شدن، عیب پرامپت است یا ذاتی.
    "C": ("صدا + متن خام", "هم صدا را داری هم متن خام تشخیص گفتار. متن خام "
          "**ناقص** است: جاهایی کلمه و حتی جمله‌ی کامل را نشنیده و انداخته. "
          "مرجع اصلی صداست؛ هر چه در صدا هست باید در خروجی بیاید، حتی اگر در "
          "متن خام نباشد. متن خام فقط کمکی است برای خواندن کلمه‌های سخت.", True, "raw"),
    "D": ("رونویسی مو‌به‌مو از صدا", "فقط صدا.", True, None),
    # مسیری که حس درونی سید توصیف می‌کرد، ولی با یک STT خوب: اول رونویسی
    # مو‌به‌مو از خود مدل، بعد پاس متنی روی همان. صدا در مرحله‌ی دوم نیست.
    "E": ("رونویسی مو‌به‌مو، بعد پاس", "فقط متن رونویسی مو‌به‌موی همین صدا را داری. "
          "این متن کامل است ولی خام و پر از فیلر؛ صدا را نداری.", False, "D"),
}


def main():
    args = [a for a in sys.argv[1:]]
    flag = lambda n, d=None: (args[args.index(n) + 1] if n in args else d)
    dry, check = "--dry" in args, "--check" in args
    lang = flag("--lang", "fa-IR")
    jobs = flag("--jobs", "2")
    thinking = flag("--thinking")
    want = (flag("--arms") or "A,B,C,D").upper().split(",")
    src = next((a for a in args if not a.startswith("--")
                and os.path.exists(a) and not a.isdigit()), None)
    os.makedirs(OUT, exist_ok=True)
    key = api_key()

    # سنجه‌ها را که عوض می‌کنیم نباید دوباره پول و وقت خرج تماس شود
    if "--rerender" in args:
        d = json.load(open(os.path.join(OUT, "report.json"), encoding="utf8"))
        for a in d["arms"]:
            a["metrics"] = measure(d["draft"], a["res"]["text"] if a["res"]["ok"] else "")
        path = os.path.join(OUT, "report.html")
        open(path, "w", encoding="utf8").write(report(d["meta"], d["draft"], d["arms"]))
        json.dump(d, open(os.path.join(OUT, "report.json"), "w", encoding="utf8"),
                  ensure_ascii=False, indent=1)
        print(path)
        return

    if check or not src:
        print("زمزمه نصب:", "بله" if os.path.exists(ZEM) else "نه " + ZEM)
        print("afconvert:", "بله" if subprocess.run(["which", "afconvert"],
              capture_output=True).returncode == 0 else "نه")
        print("کلید جمینای:", "پیدا شد" if key else
              f"نه. بگذارش در Keychain: security add-generic-password -a $USER -s {KEYCHAIN_SERVICE} -w")
        print("پرامپت‌ها:", ", ".join(sorted(os.listdir(os.path.join(ROOT, "prompts")))))
        if not src:
            print("\nاجرا: python3 lab.py <فایل صوتی> [--dry] [--arms A,C] [--lang fa-IR]")
        return

    polish = open(os.path.join(ROOT, "prompts", "polish.md"), encoding="utf8").read().strip()
    verbatim = open(os.path.join(ROOT, "prompts", "verbatim.md"), encoding="utf8").read().strip()
    audio, mime = prep_audio(src)
    dur = duration(audio)
    given = flag("--draft")
    draft = (open(given, encoding="utf8").read().strip() if given
             else draft_text(audio, lang, jobs))

    uri = None
    if not dry and any(ARMS[a][2] for a in want if a in ARMS):
        if not key:
            raise SystemExit("کلید نیست. اول --check را بزن.")
        uri = upload_file(audio, mime, key)

    arms, done = [], {}
    for aid in want:
        if aid not in ARMS:
            continue
        name, what, needs_audio, from_draft = ARMS[aid]
        system = verbatim if aid == "D" else polish
        parts = [{"type": "text", "text": what}]
        if from_draft == "raw":
            parts.append({"type": "text", "text": "متن خام تشخیص گفتار:\n\n" + draft})
        elif from_draft:
            prev = done.get(from_draft)
            if not prev:  # از اجرای قبلی روی دیسک
                p = os.path.join(OUT, f"arm-{from_draft}.txt")
                prev = open(p, encoding="utf8").read().strip() if os.path.exists(p) else ""
            if not prev:
                log(f"[{aid}] رد شد: مسیر {from_draft} خروجی نداشت")
                continue
            parts.append({"type": "text", "text": "متن رونویسی مو‌به‌مو:\n\n" + prev})
        if needs_audio:
            parts.append({"type": "audio", "uri": uri, "mime_type": mime})
        if dry:
            res = {"ok": True, "err": "", "sec": 0.0, "api": "dry",
                   "text": draft, "usage": {}}
        else:
            log(f"[{aid}] {name}...")
            res = ask(key, system, parts, aid, thinking)
        m = measure(draft, res["text"]) if res["ok"] else measure(draft, "")
        done[aid] = res["text"] if res["ok"] else ""
        arms.append({"id": aid, "name": name, "what": what, "res": res, "metrics": m})
        if res["ok"]:
            open(os.path.join(OUT, f"arm-{aid}.txt"), "w", encoding="utf8").write(res["text"])
            log(f"[{aid}] پوشش {m['coverage']}% ، {m['words_out']} کلمه، {res['sec']:.1f}s")
        else:
            log(f"[{aid}] خطا: {res['err'][:300]}")

    meta = (f"{os.path.basename(src)} | {dur:.0f} ثانیه | {MODEL}"
            f"{' | thinking=' + thinking if thinking else ''} | {time.strftime('%Y-%m-%d %H:%M')}")
    path = os.path.join(OUT, "report.html")
    open(path, "w", encoding="utf8").write(report(meta, draft, arms))
    json.dump({"meta": meta, "draft": draft,
               "arms": [{k: v for k, v in a.items()} for a in arms]},
              open(os.path.join(OUT, "report.json"), "w", encoding="utf8"),
              ensure_ascii=False, indent=1)
    print(path)


if __name__ == "__main__":
    main()
