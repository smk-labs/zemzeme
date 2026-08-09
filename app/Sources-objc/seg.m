// برش‌زن: کجای صدا را ببریم.
//
// تنها بخشی از نسخه دو که باید درست باشد. همه‌ی کیفیت از همین‌جا می‌آید.
//
// چرا: اندازه‌گیری روی هشت ضبط واقعی (tools/fixtures/read-aloud/RESULTS.md) نشان داد
// موتور رایگان گوگل روی تکه‌ی بلند، بلوک‌های چندثانیه‌ای از گفتار عادی را می‌اندازد.
// همان صدا، همان خط لوله، فقط طولِ تکه عوض شد (برش ثابت، یعنی بدترین حالت):
//
//   طول تکه     ضبط ۰۷      ضبط ۰۲
//    ۲۰ ثانیه     ۳۷٪         ۳۷٪
//    ۱۰ ثانیه     ۶۲٪         ۵۷٪
//     ۷ ثانیه     ۷۷٪         ۷۰٪   <- قله
//     ۵ ثانیه     ۷۳٪         ۶۴٪
//
// منحنی قله دارد. کوتاه‌تر تا هفت ثانیه کمک می‌کند، از آن کوتاه‌تر بدتر: تکه‌ی خیلی
// کوتاه زمینه‌ی کافی برای مدل ندارد و مرزهای بیشتر یعنی کلمه‌های نصف‌شده‌ی بیشتر.
// نسخه یک هر ۲۰ تا ۲۴ ثانیه می‌بُرید، یعنی دقیقا در بدترین ناحیه‌ی همین منحنی، و بعد
// تمام آن کارِ هم‌پوشانی و درز و دوخت تلاش برای تعمیر همین بود.
//
// و آن عددها با برشِ **ثابت** گرفته شده‌اند، پس کف‌اند نه سقف: برش سر سکوت باید
// بهتر باشد، چون آن‌وقت هیچ کلمه‌ای دو نیم نمی‌شود.
//
// این فایل عمدا هیچ وابستگی‌ای جز Foundation ندارد و هیچ حالتی هم ندارد: یک تابع
// خالص روی یک بافر. پس تست طلایی‌اش (tools/seg_test.sh) تنهایی کامپایلش می‌کند و
// بی‌میکروفن و بی‌شبکه روی ضبط‌های واقعی می‌دواندش.
#import "zemzeme.h"

// توان یک فریم، صفر تا یک. نمونه‌برداری هر چهارم، مثل مسیر دسته‌ای نسخه یک: برای
// تشخیص سکوت به‌قدر کافی دقیق و چند برابر ارزان‌تر.
static float ZSegRMS(const int16_t *p, NSUInteger n) {
    float acc = 0;
    NSUInteger cnt = 0;
    for (NSUInteger i = 0; i < n; i += 4) {
        float v = p[i] / 32768.0f;
        acc += v * v;
        cnt++;
    }
    return sqrtf(acc / MAX(1u, (unsigned)cnt));
}

// امتیازِ یک مکث: چقدر باورکردنی است که اینجا حرف تمام شده.
//
// دو چیز، و عمدا فقط دو چیز: **طول** مکث و **عمقش**. جاذبه‌ای به هدفِ هفت ثانیه
// نیست، و این خودِ تصمیم است نه فراموشی. نسخه یک نزدیک‌ترین سکوت به هدف را برمی‌داشت
// و همین باعث می‌شد یک مکثِ کوتاه و نصفه‌ی نزدیکِ هدف، از یک نفسِ کاملِ دو ثانیه‌ای
// جلو بزند. تکه‌ی کوتاه روی مکث محکم هزینه‌ای ندارد: نه هم‌پوشانی‌ای هست نه ادغامی،
// و متن هم زودتر می‌رسد.
//
//   طول:  ۲۰۰ms تازه واجد شرایط است، ۵۰۰ms یعنی یک مکث حسابی. سقف ۲ که یک سکوتِ
//         خیلی طولانی (فکر کردن، قطع شدن حرف) کل پنجره را قبضه نکند.
//   عمق:  چقدر پایین‌تر از آستانه. نویزِ زمینه‌ی درست زیر آستانه با یک سکوتِ واقعی
//         یکی نیست.
static double ZSegPause(double runSec, float meanRMS) {
    double len = MIN(runSec / 0.5, 2.0);
    double depth = (kZSegRMS - meanRMS) / kZSegRMS;
    return len * MAX(depth, 0.0);
}

// و وزنِ طول: اگر اینجا ببُریم، تکه چقدر خوب تشخیص داده می‌شود.
//
// این جاذبه به هدف **نیست**. «نزدیک‌ترین مکث به هفت ثانیه» همان اشتباه نسخه یک بود.
// این خودِ منحنیِ اندازه‌گیری‌شده است: همان جدولِ RESULTS.md، نرمال‌شده روی قله‌اش.
// یعنی معیار «چقدر به عدد دلخواه نزدیکی» نیست، «چقدر متن سالم درمی‌آید» است.
//
// شکلش نامتقارن است و باید هم باشد: از قله به پایین رفتن ارزان است (۵ ثانیه ۷۳٪ در
// برابر ۷۷٪) ولی بالا رفتن گران (۱۰ ثانیه ۶۲٪). پس یک مکثِ محکم سر ثانیه‌ی ۵ راحت
// از یک مکثِ محکمِ ثانیه‌ی ۱۱ جلو می‌زند، و همین «کوتاه و مطمئن» است که خواسته بودیم.
// در عوض دو مکثِ هم‌قدرت سر ۵ و ۹ وزنشان تقریبا یکی است، پس آنجا قدرتِ خودِ مکث
// تصمیم می‌گیرد نه جایش.
static double ZSegLenWeight(double sec) {
    static const double t[] = {4.0, 5.0, 7.0, 10.0, 12.0};
    static const double w[] = {0.90, 0.95, 1.00, 0.81, 0.72};
    const int n = 5;
    if (sec <= t[0]) return w[0];
    for (int i = 1; i < n; i++) {
        if (sec > t[i]) continue;
        double f = (sec - t[i - 1]) / (t[i] - t[i - 1]);
        return w[i - 1] + f * (w[i] - w[i - 1]);
    }
    return w[n - 1];
}

ZSegCut ZSegFind(const void *pcm, NSUInteger len, BOOL eof) {
    ZSegCut r = {0};
    const NSUInteger frame = (NSUInteger)(0.020 * kZPcmBytesPerSec);   // ۲۰ms = ۶۴۰ بایت
    const NSUInteger lo = (NSUInteger)(kZSegMinSec * kZPcmBytesPerSec);
    const NSUInteger hi = (NSUInteger)(kZSegMaxSec * kZPcmBytesPerSec);
    const NSUInteger need = (NSUInteger)(kZSegQuietMs / 20.0);         // فریم‌های پیوسته‌ی لازم

    // هنوز به سقف نرسیده و صدا هم قطع نشده: تصمیم نگیر. چیزی روی صفحه نیست که
    // منتظرش باشد، پس صبر کردن تا پنجره‌ی کامل هیچ هزینه‌ای ندارد و در عوض
    // «بهترین مکث» واقعا بهترینِ کل پنجره است، نه بهترینِ چیزی که تا حالا دیده‌ایم.
    if (len < hi && !eof) return r;

    // آخرین تکه‌ی سشن: هرچه مانده همین است، کوتاه هم باشد.
    if (eof && len <= hi) {
        r.cut = len - (len % 2);
        r.tail = YES;
        return r;
    }

    const int16_t *s = (const int16_t *)pcm;
    const NSUInteger frames = MIN(len, hi) / frame;

    // یک گذر: دوره‌های پیوسته‌ی زیرِ آستانه را جمع کن و امتیازشان را بسنج. دوره‌ای
    // که وسطش داخل [lo, hi] بیفتد نامزد است، حتی اگر خودش از قبلِ lo شروع شده باشد:
    // مکثی که از ثانیه‌ی ۳٫۵ تا ۵ کشیده، وسطش ۴٫۲۵ است و برشِ عالی‌ای می‌دهد.
    NSUInteger runStart = 0;
    BOOL inRun = NO;
    double bestScore = 0;
    float sumRMS = 0;

    for (NSUInteger f = 0; f <= frames; f++) {
        BOOL quiet = NO;
        float rms = 1.0f;
        if (f < frames) {
            rms = ZSegRMS(s + (f * frame) / 2, frame / 2);
            quiet = rms <= kZSegRMS;
        }
        if (quiet) {
            if (!inRun) {
                inRun = YES;
                runStart = f;
                sumRMS = 0;
            }
            sumRMS += rms;
            continue;
        }
        if (!inRun) continue;
        inRun = NO;
        NSUInteger runFrames = f - runStart;
        if (runFrames < need) continue;

        NSUInteger midByte = (runStart + runFrames / 2) * frame;
        if (midByte < lo || midByte > hi) continue;

        double runSec = runFrames * 0.020;
        float mean = sumRMS / runFrames;
        double score = ZSegPause(runSec, mean) * ZSegLenWeight(midByte / kZPcmBytesPerSec);
        if (score <= bestScore) continue;
        bestScore = score;
        // وسط سکوت را ببر، نه لبه‌اش: هیچ کلمه‌ای دو نیم نمی‌شود.
        r.cut = midByte - (midByte % 2);
        r.score = score;
        r.quietSec = runSec;
        r.rms = mean;
    }
    if (r.cut) return r;

    // هیچ مکثِ واجد شرایطی در پنجره نبود (گفتار پیوسته‌ی دوازده ثانیه‌ای). آرام‌ترین
    // فریمِ ثانیه‌ی آخر را می‌بُریم و **صریحا** می‌گوییم که این برش تحمیلی بود.
    // هیچ‌وقت بی‌صدا سر تایمر نبُر: برشی که خودش را گزارش نکند، بعدا کسی نمی‌فهمد
    // چرا وسط یک کلمه افتاده.
    NSUInteger from = (NSUInteger)((kZSegMaxSec - 1.0) * kZPcmBytesPerSec) / frame;
    float quietest = 1.0f;
    NSUInteger at = frames ? frames - 1 : 0;
    for (NSUInteger f = from; f < frames; f++) {
        float rms = ZSegRMS(s + (f * frame) / 2, frame / 2);
        if (rms >= quietest) continue;
        quietest = rms;
        at = f;
    }
    NSUInteger cut = (at + 1) * frame;
    r.cut = MIN(cut, hi) - (MIN(cut, hi) % 2);
    r.rms = quietest;
    r.degraded = YES;
    return r;
}
