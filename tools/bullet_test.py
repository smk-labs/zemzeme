# قاعده‌ی بولت، هر دو جهت. شکل خروجیِ پاس نهایی با تنظیم تعیین نمی‌شود، با پرامپت
# تعیین می‌شود: گفتار شمرده باید بولت شود و روایت باید پاراگراف بماند.
#
# چرا تست جدا دارد: جهتِ منفی (روایت بولت نشود) از اول درست بود، ولی جهتِ مثبت
# **غلط بود و کسی ندیده بود**. گفتار شمرده یک پاراگراف برمی‌گشت، چون قاعده‌ی ۹ در
# برابر قاعده‌ی ۲ («چیزی اضافه نمی‌شود») می‌باخت. با صریح کردنِ اینکه بولت کردنِ
# فهرستِ واقعا گفته‌شده «اضافه کردن» نیست، هر دو جهت درست شد.
#
# برخلاف gate_test، این یکی به کلید و شبکه احتیاج دارد و **۲ درخواست** خرج می‌کند
# (سهم مجانی ۲۰ در روز است). فقط وقتی بزنش که پرامپت را عوض کرده باشی.
#
#   python3 tools/bullet_test.py
import json, os, re, subprocess, sys, urllib.request, urllib.error
KEY = os.environ.get("GEMINI_API_KEY") or subprocess.run(
    ["security", "find-generic-password", "-s", "zemzeme-gemini", "-w"],
    capture_output=True, text=True).stdout.strip()
MODEL = os.environ.get("ZEMZEME_FINAL_MODEL", "gemini-3.6-flash")
THINK = os.environ.get("ZEMZEME_FINAL_THINKING", "minimal")
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app", "prompts")
polish = open(os.path.join(ROOT, "polish.md"), encoding="utf8").read().strip()

COUNTED = ("خب ببین سه تا کار مونده تا ریلیز. اولیش اینه که حالت یادداشت رو اِ باید تموم کنیم و "
           "تست بشه. دومیش نوشتن بخش ریدمی هست که خب مهمه. سومی هم اینکه روی یه ویس واقعی "
           "امتحانش کنیم. جلسه هم ساعت ده و نیم چهارشنبه، نه ببخشید پنجشنبه‌ست. پورت هفده هزار "
           "و ششصد و سی و شش، بودجه هم دویست و پنجاه میلیون.")
NARRATIVE = ("دیروز رفتم دفتر و با تیم فنی نشستیم و کلی درباره‌ی معماری تازه حرف زدیم، یعنی خب "
             "قرار شد تا آخر هفته یه نمونه‌ی کوچیک بسازیم و بعدش تصمیم بگیریم که چطور باید "
             "بقیه‌ی سامانه رو هم به همون شکل ببریم و مهاجرت رو شروع کنیم دیگه، فقط علیرضا "
             "می‌گفت اِ باید اول با پایاداد هم حرف بزنیم که ببینیم اپ اسنپ چیکار کرده.")


def call(text):
    body = {"model": MODEL, "system_instruction": polish,
            "input": [{"type": "text", "text": "فقط متن رونویسی مو‌به‌موی همین صدا را داری. "
                       "این متن کامل است ولی خام و پر از فیلر؛ صدا را نداری."},
                      {"type": "text", "text": "متن رونویسی مو‌به‌مو:\n\n" + text}],
            "generation_config": {"thinking_level": THINK}}
    req = urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/interactions",
                                 data=json.dumps(body, ensure_ascii=False).encode(),
                                 headers={"x-goog-api-key": KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            doc = json.loads(r.read())
    except urllib.error.HTTPError as e:
        return "HTTP %d: %s" % (e.code, e.read()[:200].decode("utf8", "replace"))
    acc = []
    for st in doc.get("steps", []):
        if st.get("type") == "thought":
            continue
        for c in st.get("content", []):
            if isinstance(c.get("text"), str):
                acc.append(c["text"])
    return "".join(acc).strip()


fail = 0
for name, text, want_bullets in [("شمرده", COUNTED, True), ("روایی", NARRATIVE, False)]:
    out = call(text)
    n = len(re.findall(r"(?m)^\s*(?:[-*•‣]|\d+[.)]|[۰-۹]+[.)])\s", out))
    ok = (n > 0) == want_bullets
    fail += 0 if ok else 1
    print(f"[{'OK  ' if ok else 'FAIL'}] {name}: {n} بولت (انتظار {'بولت' if want_bullets else 'پاراگراف'})")
    print("   " + out.replace("\n", "\n   ")[:700])
sys.exit(1 if fail else 0)
