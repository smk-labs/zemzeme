#!/usr/bin/env python3
# ست طلایی «پاس ویرایش»: فقط stdlib؛ با دیمن polish.py حرف می‌زند (نبود، خودش بالا می‌آورد).
# اجرا: python3 tools/polish_test.py
#
# سه جور چک:
#   core:  مقایسه دقیق بعد از حذف علائم درجی (نتیجه نرمال‌سازی/نیم‌فاصله/املا قطعی است،
#            جای علائمِ مدل قطعی نیست؛ علامت بین دو رقم مثل ۲.۵ حساب نمی‌شود)
#   invariant: روی همه کیس‌ها: اسکلت معنایی این/اوت یکی باشد (با احتساب اصلاح‌های املایی
#            گزارش‌شده)، پاسِ دوباره no-op باشد (ایدمپوتنت)، علامت چسبیده به علامت نباشد
#   soft:  انتظار نقطه‌گذاری؛ رد شدنش فقط WARN است نه FAIL
import json
import os
import re
import statistics
import subprocess
import sys
import time
import unicodedata
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = "http://127.0.0.1:17636"
MARKS = "،؛؟!.:"

CASES = [
    # --- مصنوعی: نرمال‌سازی و نیم‌فاصله و املا ---
    {"id": "halfspace-mi", "in": "این کار می شود و پلاگین می ترکید",
     "core": "این کار می‌شود و پلاگین می‌ترکید"},
    {"id": "digits-decimal", "in": "قیمت 2.5 دلار و 24 درصد شد",
     "core": "قیمت ۲.۵ دلار و ۲۴ درصد شد"},
    {"id": "digits-time", "in": "ساعت 12:30 قرار داریم",
     "core": "ساعت ۱۲:۳۰ قرار داریم"},
    {"id": "arabic-chars", "in": "كتاب هاي عربي",
     "core": "کتاب‌های عربی"},
    {"id": "extra-spaces", "in": "سلام   دنیا  چطوری",
     "core": "سلام دنیا چطوری"},
    {"id": "spell-one-edit", "in": "دیروز 24 نفر امدند",
     "core": "دیروز ۲۴ نفر آمدند"},
    {"id": "english-untouched", "in": "hello world this is a test 2.5 ok",
     "exact": "hello world this is a test 2.5 ok"},
    {"id": "mixed-latin-kept", "in": "فایل main.py رو با VS Code باز کن",
     "core": "فایل main.py رو با VS Code باز کن"},
    {"id": "existing-punct-kept", "in": "سلام، خوبی؟ ممنون.",
     "core": "سلام، خوبی؟ ممنون."},
    {"id": "comma-unify", "in": "این متن تست است , حله",
     "core": "این متن تست است، حله"},
    {"id": "no-period-sentence", "in": "من امروز به بازار رفتم و میوه خریدم",
     "soft_endswith": ".", "core": "من امروز به بازار رفتم و میوه خریدم"},
    {"id": "question-mark", "in": "اسم تو چیست",
     "soft_endswith": "؟", "core": "اسم تو چیست"},
    # --- محافظه‌کاری: این‌ها نباید عوض شوند ---
    {"id": "colloquial-guard-1", "in": "چه خبر چیکارا داریم",
     "core": "چه خبر چیکارا داریم"},
    {"id": "colloquial-guard-2", "in": "باید چیزای خیلی خوبی بزاره اونجا",
     "core": "باید چیزای خیلی خوبی بزاره اونجا"},
    {"id": "colloquial-guard-3", "in": "نمی‌تونه پیدا کنه یا چنین مشکلی",
     "core": "نمی‌تونه پیدا کنه یا چنین مشکلی"},
    {"id": "typo-guard", "in": "یه خواحش دارم ازت",
     "core": "یه خواحش دارم ازت"},   # غلط تایپی کلاسیک؛ عمدا خارج از اسکوپ (STT چنین غلطی نمی‌سازد)
    {"id": "hearing-error-out-of-scope", "in": "رفتم مغازه اکاسی",
     "core": "رفتم مغازه اکاسی"},    # خطای شنیداری؛ عمدا دست نمی‌خورد
    # --- واقعی از sessions/*.txt (خطاها و لحن واقعی STT) ---
    {"id": "real-1", "in": "ببین اینی که گفتی بهتر بود یعنی بهتره که حتی اگه پنجره لازم اون بالا بیاد من وقتی حرفام از حالت خاکستری به سفید تبدیل می‌شه خود به خود بشینه داخل کرسر یا اون فضایی که دارم صحبت می‌کنم توش"},
    {"id": "real-2", "in": "یعنی تو اینپوت ویس بشینه"},
    {"id": "real-3", "in": "فقط نکته"},
    {"id": "real-4", "in": "اینه که چون پی در پی با پاز و ادیت و غیره دارم صحبت می‌کنم عملاً نباید که مشکلی این وسط پیش بیاد"},
    {"id": "real-5", "in": "این بازخوردی که دارم استریم حرف زدنم رو می‌بینم به صورت خاکستری و بعد سفید می‌شه خیلی خیلی خوبه"},
    {"id": "real-6", "in": "حالا چطوری می‌تونیم همینو داخل"},
    {"id": "real-7", "in": "ضمناً هنوز اون باگی که وقتی یهو گیر می‌کنه یه کمی از کلمات رو بپرونه و دیگه هم به جز با توقف و ادامه مجدد راه نیفته هست"},
    {"id": "real-8", "in": "اینکه چطوری باید طراحی کنیم که واقعاً بهترین تجربه کاربری ممکن با کمترین اصطکاک باشه هنوز برای خودم خیلی سوال"},
    {"id": "real-9", "in": "یه مشکل دیگه هم اینه که انگار به محض اینکه سریع حرف می‌زنم یه خورده بیشتر قاطی می‌کنه و گیج می‌زنه"},
    {"id": "real-10", "in": "چند تا نکته مهم داره این کار اولاً اینکه نباید چیزهای بدیهی که خودش ممکنه بتونه انجام بده یا خیلی خیلی ساده است"},
    {"id": "real-11", "in": "اتوماتیک این کارو بکنه باید واقعاً چیزی باشه که مطمئن باشه یه کار مهم لازمی از سمت منه وگرنه باید توسط یه فرمان از سمت من تریگر بشه"},
    {"id": "real-12", "in": "با یه کامند یا اسکیل خیلی ساده و راحت در حالی که تکراری هم نباشه"},
    {"id": "real-13", "in": "پیشنهاد خوب برای اسمش بده"},
    {"id": "real-14", "in": "تو این نقل و انتقالات به نظر پلاگین می ترکید"},
    {"id": "real-15", "in": "کلاد دسکتاپ کانفیگ ردیف کن"},
    {"id": "real-16", "in": "خوب واقعیتش اینه که نیازی به لایه دوم نداریم فعلاً همون لایه اولو یه پرانت خیلی خوب و حرفه‌ای براش درآر"},
    {"id": "real-17", "in": "نکته مهم دیگه اینکه تو صفحه طلوع من باید چیزای خیلی خوبی بزاره و خیلی تر تمیز و مینیمال در عین حال بخش‌بندی شده بر اساس پروژه‌ها"},
    {"id": "real-18", "in": "یه چت جدیدو باز کردم گفتم چه خبر چیکارا داریم اون بدونه که الان چی با اولویته و چی مهمه که من برم انجام بدم و بسم اللهشو بگم"},
]


def post(path, obj, timeout=10):
    req = urllib.request.Request(BASE + path, data=json.dumps(obj, ensure_ascii=False).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def alive(timeout=1.5):
    try:
        with urllib.request.urlopen(BASE + "/alive", timeout=timeout) as r:
            return json.loads(r.read())
    except (urllib.error.URLError, OSError, ValueError):
        return None


def ensure_daemon():
    st = alive()
    if st is None:
        support = Path.home() / "Library/Application Support/Zemzeme"
        py = support / "py/.venv/bin/python3"
        script = ROOT / "app/py/polish.py"   # تست همیشه سورس را می‌سنجد، نه نسخه بسته
        if not py.exists():
            sys.exit("venv نیست؛ اول: bash app/py/setup.sh")
        env = {**os.environ, "ZEMZEME_MODELS": str(support / "py/models")}
        subprocess.Popen([str(py), str(script)], cwd=ROOT, env=env,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    t0 = time.time()
    while time.time() - t0 < 180:
        st = alive()
        if st and st.get("ready"):
            return
        if st and st.get("err"):
            sys.exit(f"دیمن بالا آمد ولی لود مدل شکست: {st['err']}")
        time.sleep(1)
    sys.exit("دیمن آماده نشد (۱۸۰ ثانیه)")


def skeleton(s, spell_ops=()):
    # اسکلت معنایی: بی‌اعتنا به فاصله/نیم‌فاصله/علائم/شکل رقم و نویسه‌های هم‌ارز
    for a, b in spell_ops:
        s = s.replace(a, b, 1)
    s = unicodedata.normalize("NFKC", s)
    table = str.maketrans("يىكة" + "۰۱۲۳۴۵۶۷۸۹" + "٠١٢٣٤٥٦٧٨٩",
                          "ییکه" + "0123456789" + "0123456789")
    s = s.translate(table)
    return "".join(c for c in s if unicodedata.category(c)[0] in "LN")


def core(s):
    # حذف علائم درجی (علامت چسبیده به رقم از دو طرف مثل ۲.۵ می‌ماند)
    out = []
    for i, c in enumerate(s):
        if c in MARKS:
            prev_digit = i > 0 and s[i - 1].isdigit()
            next_digit = i + 1 < len(s) and s[i + 1].isdigit()
            if not (prev_digit and next_digit):
                continue
        out.append(c)
    return re.sub(r"  +", " ", "".join(out)).strip()


def main():
    ensure_daemon()
    post("/polish", {"text": "گرم شو برای تست", "lang": "fa-IR"})  # گرم‌کن

    fails, warns, lat_wall, lat_srv = [], [], [], []
    for c in CASES:
        t0 = time.time()
        r = post("/polish", {"text": c["in"], "lang": "fa-IR"})
        wall = (time.time() - t0) * 1000
        out, ops = r["text"], r.get("spell", [])
        lat_wall.append(wall)
        lat_srv.append(r.get("ms", 0))

        problems = []
        if "exact" in c and out != c["exact"]:
            problems.append(f"exact: {out!r}")
        if "core" in c and core(out) != core(c["core"]):
            problems.append(f"core: {core(out)!r} != {core(c['core'])!r}")
        if "core_any" in c and core(out) not in [core(x) for x in c["core_any"]]:
            problems.append(f"core_any: {core(out)!r}")
        # ناوردايی معنا
        if skeleton(c["in"], ops) != skeleton(out):
            problems.append(f"skeleton: {skeleton(c['in'], ops)!r} != {skeleton(out)!r}")
        # علامت پشت علامت (ممیز رقمی مستثنا)
        if re.search(r"[،؛؟!.:] ?[،؛؟!:]|[،؛؟!:] ?\.", out):
            problems.append(f"adjacent-marks: {out!r}")
        # ایدمپوتنت
        r2 = post("/polish", {"text": out, "lang": "fa-IR"})
        if r2["text"] != out:
            problems.append(f"not idempotent: {r2['text']!r}")

        if "soft_endswith" in c and not out.endswith(c["soft_endswith"]):
            warns.append(f"{c['id']}: انتظار پایان {c['soft_endswith']!r} بود: {out!r}")

        status = "FAIL" if problems else "ok"
        if problems:
            fails.append((c["id"], problems))
        changed = "≠" if out != c["in"] else "="
        print(f"[{status}] {c['id']} ({int(wall)}ms) {changed}")
        if out != c["in"]:
            print(f"   < {c['in']}\n   > {out}")
        for p in problems:
            print(f"   !! {p}")

    print(f"\nتاخیر (wall): میانگین {statistics.mean(lat_wall):.0f}ms، "
          f"میانه {statistics.median(lat_wall):.0f}ms، بدترین {max(lat_wall):.0f}ms")
    print(f"تاخیر (سرور): میانگین {statistics.mean(lat_srv):.0f}ms، بدترین {max(lat_srv):.0f}ms")
    for w in warns:
        print(f"WARN {w}")
    if statistics.mean(lat_wall) > 150:
        fails.append(("latency", [f"میانگین {statistics.mean(lat_wall):.0f}ms > 150"]))
    print(f"\n{len(CASES) - len(fails)}/{len(CASES)} گذشت، {len(warns)} هشدار")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
