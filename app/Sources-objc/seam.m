// جوش درز: چطور دو تشخیصِ جدا از یک صدا به هم دوخته می‌شوند.
//
// سه جا همین یک پرسش را دارند و هر سه از اینجا می‌خوانند، وگرنه سه رفتار واگرا
// می‌شد: درزِ چرخشِ سشن در مسیر زنده، درزِ دو پاره‌ی هم‌پوشانِ رونویسی فایل، و نجاتِ
// interim های یک استریم. عمدا هیچ وابستگی‌ای جز Foundation ندارد، پس تست‌های طلایی
// می‌توانند تنهایی کامپایلش کنند و رفتارش را بی‌میکروفن و بی‌شبکه بسنجند.
#import <Foundation/Foundation.h>
#import "zemzeme.h"

// چطور دو تکه متن به هم می‌چسبند. یک تابع، چون اگر موتور و دفتر جداگانه بچسبانند
// همان یک فاصله‌ی اختلاف دیفِ پیشوندی را می‌شکند و یک عملیات مخربِ الکی می‌سازد.
NSString *ZJoinText(NSString *a, NSString *b) {
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString *x = [(a ?: @"") stringByTrimmingCharactersInSet:ws];
    NSString *y = [(b ?: @"") stringByTrimmingCharactersInSet:ws];
    if (!x.length) return y;
    if (!y.length) return x;
    return [NSString stringWithFormat:@"%@ %@", x, y];
}

// ---------- ادغام دقیق: دو interim از یک استریم ----------
// گوگل گاهی پیشوند تثبیت‌شده را از interim های بعدی می‌اندازد؛ موقع نجات، بلندترین
// نسخه با دم فعلی ادغام می‌شود که کلمه‌ای گم نشود.
// اینجا تطبیق **دقیق** است و باید بماند: هر دو طرف از یک تشخیصِ واحد می‌آیند، پس اگر
// نویسه‌ای فرق کرده یعنی واقعا کلمه عوض شده، نه اینکه بد شنیده شده باشد.
NSString *ZMergeInterim(NSString *best, NSString *cur) {
    best = [best stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    cur = [cur stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!best.length) return cur;
    if (!cur.length) return best;
    if ([best containsString:cur]) return best;
    NSArray *a = [best componentsSeparatedByString:@" "];
    NSArray *b = [cur componentsSeparatedByString:@" "];
    NSUInteger maxK = MIN(a.count, b.count);
    for (NSUInteger k = maxK; k > 0; k--) {
        NSArray *tailA = [a subarrayWithRange:NSMakeRange(a.count - k, k)];
        NSArray *headB = [b subarrayWithRange:NSMakeRange(0, k)];
        if ([tailA isEqualToArray:headB]) {
            NSArray *rest = [b subarrayWithRange:NSMakeRange(k, b.count - k)];
            return rest.count
                ? [best stringByAppendingFormat:@" %@", [rest componentsJoinedByString:@" "]]
                : best;
        }
    }
    return [NSString stringWithFormat:@"%@ %@", best, cur];
}

// ---------- جوش بامدارا: دو تشخیصِ جدا از یک صدا ----------

// یک شکلِ نوشتاری از یک توکن، پیش از مقایسه. دو تشخیصِ جدا از یک صدا اغلب فقط در
// همین‌ها فرق می‌کنند و بی نرمال‌سازی، تفاوتِ صفرِ معنایی به اختلافِ نویسه ترجمه می‌شد:
// نیم‌فاصله (گوگل «می‌شود» و «میشود» هر دو را می‌دهد)، یای و کافِ عربی در برابر فارسی،
// اعرابِ پراکنده، و کشیدهٔ تزیینی.
static NSString *ZSeamNorm(NSString *t) {
    static NSCharacterSet *punct;
    static NSDictionary *fold;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        punct = [NSCharacterSet characterSetWithCharactersInString:@".,!?؟،؛:\"'«»…"];
        fold = @{@"‌": @"", @"‏": @"", @"‎": @"", @"ـ": @"",
                 @"ي": @"ی", @"ى": @"ی", @"ك": @"ک",
                 @"ة": @"ه", @"أ": @"ا", @"إ": @"ا",
                 @"آ": @"ا",
                 @"ً": @"", @"ٌ": @"", @"ٍ": @"", @"َ": @"",
                 @"ُ": @"", @"ِ": @"", @"ّ": @"", @"ْ": @""};
    });
    NSString *trimmed = [t stringByTrimmingCharactersInSet:punct];
    if (!trimmed.length) return @"";
    NSMutableString *s = [trimmed.lowercaseString mutableCopy];
    for (NSString *k in fold) {
        [s replaceOccurrencesOfString:k withString:fold[k] options:0 range:NSMakeRange(0, s.length)];
    }
    return s;
}

// شباهت دو توکن: یک منهای فاصله‌ی ویرایش، نرمال‌شده روی طول بلندتر.
// چرا نویسه‌ای و نه برابری: تطبیقِ دودویی روی کلمه‌ای که بد شنیده شده صفر می‌دهد و
// همان یک صفر کل پنجره را زیر آستانه می‌برد. اندازه‌گیریِ واقعی روی این دستگاه:
// «مرغابی» در برابر «خوابی» سه ویرایش روی شش نویسه است، یعنی ۰٫۵۰ — با شمارشِ دودویی
// صفر بود، پنجره ۵۰٪ می‌شد، درز جوش نمی‌خورد و «قرمز» دو بار نوشته شد.
static double ZSeamTokenSim(NSString *x, NSString *y) {
    if ([x isEqualToString:y]) return 1.0;
    NSUInteger n = x.length, m = y.length;
    if (!n || !m) return 0.0;
    // توکنِ غول (چند کلمه‌ی چسبیده، یا آشغال) ارزش هزینه‌ی درجه‌دو را ندارد
    if (n > 48 || m > 48) return 0.0;
    unichar bx[48], by[48];
    [x getCharacters:bx range:NSMakeRange(0, n)];
    [y getCharacters:by range:NSMakeRange(0, m)];
    NSUInteger prev[49], cur[49];
    for (NSUInteger j = 0; j <= m; j++) prev[j] = j;
    for (NSUInteger i = 1; i <= n; i++) {
        cur[0] = i;
        for (NSUInteger j = 1; j <= m; j++) {
            NSUInteger sub = prev[j - 1] + (bx[i - 1] == by[j - 1] ? 0 : 1);
            NSUInteger del = prev[j] + 1, ins = cur[j - 1] + 1;
            cur[j] = MIN(sub, MIN(del, ins));
        }
        memcpy(prev, cur, (m + 1) * sizeof(NSUInteger));
    }
    return 1.0 - (double)prev[m] / (double)MAX(n, m);
}

// آستانه‌ی میانگینِ پنجره. زیر این یعنی «این دو تکه یک چیز نیستند».
static const double kZSeamMeanSim = 0.70;
// و دست‌کم یک لنگرِ محکم در پنجره لازم است. بی این، پنجره‌ای از چند کلمه‌ی نیم‌شبیه
// (که در فارسی فراوان است: می‌کند، می‌کنم، می‌کنی) الکی جوش می‌خورد.
static const double kZSeamStrongSim = 0.85;

// درز دو پاره‌ی هم‌پوشان. تطبیق دقیقِ دم‌به‌سر با یک توکن اختلاف در ناحیه‌ی هم‌پوشانی
// کور می‌شود (اندازه‌گیری روی فایل ۱۷ دقیقه‌ای: «year» در یک پاره «ear» شنیده شده بود)
// و همان چند کلمه دو بار می‌نشست، ۵ درز از ۷۲.
//
// معیار: میانگینِ شباهتِ نویسه‌ایِ توکن‌های پنجره، نه شمارشِ تطبیقِ دقیق. مدارای قبلی
// (۷۰٪ توکنِ مو‌به‌مو یکسان) روی یک کلمه‌ی کاملا بدشنیده می‌شکست: «مرغابی قرمز» در
// برابر «خوابی قرمز» ۵۰٪ می‌داد و رد می‌شد. با میانگین همان پنجره ۰٫۷۵ می‌شود
// (۰٫۵۰ و ۱٫۰۰) و جوش می‌خورد.
//
// و انتخاب k عوض شده: به جای «اولین k از بالا که رد شود»، بهترین امتیاز برنده است و
// سر تساوی k کوچک‌تر. جهتِ حلقه‌ی قبلی روی گفتار تکراری یک k بزرگِ الکی را زودتر از k
// درستِ کوچک قبول می‌کرد و هرچه لایش بود دور می‌ریخت (۶ جمله از ۳۰ در ۱۲۳ ثانیه).
// حالا سر تردید کمترین چیز برداشته می‌شود، چون تکرار برگشت‌پذیر است و گم شدن نه.
//
// maxWords: بیشترین چند کلمه‌ای که هم‌پوشانیِ صوتی *می‌تواند* داشته باشد، از روی
// ثانیه‌های واقعیِ هم‌پوشانی (ZStitchWords). پنجره‌ی گشادتر از هم‌پوشانی یعنی جا باز
// کردن برای بلعیدنِ متنِ واقعی.
ZSeamMatch ZSeamFind(NSString *a, NSString *b, NSUInteger maxWords) {
    ZSeamMatch none = {0, 0};
    if (!a.length || !b.length) return none;
    NSArray *A = [a componentsSeparatedByString:@" "];
    NSArray *B = [b componentsSeparatedByString:@" "];
    NSUInteger W = MAX((NSUInteger)2, maxWords);
    NSUInteger p = MIN(A.count, W), q = MIN(B.count, W);

    NSMutableArray *na = [NSMutableArray arrayWithCapacity:p];
    NSMutableArray *nb = [NSMutableArray arrayWithCapacity:q];
    for (NSUInteger i = A.count - p; i < A.count; i++) [na addObject:ZSeamNorm(A[i])];
    for (NSUInteger j = 0; j < q; j++) [nb addObject:ZSeamNorm(B[j])];

    // هم‌ترازیِ سطحِ کلمه، نه مقایسه‌ی خانه‌به‌خانه. چرا لازم شد: دو تشخیصِ جدا از یک
    // صدا فقط کلمه‌ها را عوضی نمی‌شنوند، گاهی یک کلمه‌ی اضافه هم می‌سازند. اندازه‌گیری
    // روی سشن سه‌دقیقه‌ایِ 2026-07-26: سشن قدیمی «چهار انگشت جستجرهای مختلفی که»
    // شنید و سشن تازه «چهار انگشت مختلفی که»، یعنی یک کلمه اضافه وسطِ ناحیه‌ی
    // هم‌پوشانی. مقایسه‌ی خانه‌به‌خانه از آنجا به بعد همه‌چیز را یک خانه جابه‌جا
    // می‌دید و امتیاز می‌افتاد زیر آستانه، پس درز تکرار می‌نوشت.
    //
    // C[i][j]: کمترین هزینه‌ی هم‌ترازیِ na[0..i) با nb[0..j)، با شروعِ مجانی در na.
    // شروعِ مجانی یعنی «هر دُمی از A»؛ رسیدن به i == p یعنی هم‌پوشانی تا ته A می‌رود،
    // که همان تعریفِ درز است. هزینه‌ی جانشینی ۱ منهای شباهتِ نویسه‌ای است، پس کلمه‌ی
    // نیم‌شنیده تمام امتیاز را نمی‌خورد.
    double C[64][64];
    for (NSUInteger i = 0; i <= p; i++) C[i][0] = 0;          // شروعِ مجانی در A
    for (NSUInteger j = 1; j <= q; j++) C[0][j] = (double)j;  // ولی همه‌ی B باید پوشش داده شود
    double anchor = 0;
    for (NSUInteger i = 1; i <= p; i++) {
        for (NSUInteger j = 1; j <= q; j++) {
            double sim = ZSeamTokenSim(na[i - 1], nb[j - 1]);
            if (sim > anchor) anchor = sim;
            double sub = C[i - 1][j - 1] + (1.0 - sim);
            double del = C[i - 1][j] + 1.0;    // کلمه‌ی اضافه در A
            double ins = C[i][j - 1] + 1.0;    // کلمه‌ی اضافه در B
            C[i][j] = MIN(sub, MIN(del, ins));
        }
    }
    // یک لنگرِ محکم لازم است. بی این، پنجره‌ای از چند کلمه‌ی نیم‌شبیه (که در فارسی
    // فراوان است: می‌کند، می‌کنم، می‌کنی) الکی جوش می‌خورد.
    if (anchor < kZSeamStrongSim) return none;

    NSUInteger bestJ = 0;
    double bestScore = 0;
    for (NSUInteger j = 1; j <= q; j++) {
        double score = 1.0 - C[p][j] / (double)j;
        // یک کلمه لنگر کافی نیست: شباهتِ نسبی روی آن هر دو تکه‌ی بی‌ربط را به هم
        // می‌چسباند. پس پنجره‌ی یک‌کلمه‌ای فقط با تطبیقِ دقیق قبول است.
        if (j == 1 && score < 1.0) continue;
        if (score < kZSeamMeanSim) continue;
        if (score > bestScore) {    // اکید، پس سر تساوی j کوچک‌تر می‌ماند
            bestScore = score;
            bestJ = j;
        }
    }
    return bestJ ? (ZSeamMatch){bestJ, bestScore} : none;
}

// ---------- دُمِ نمایشی: هیچ‌وقت جلوی چشم آب نمی‌رود ----------
// interim گوگل دو جور عقب می‌نشیند و هر دو در ضبط‌های واقعی همین دستگاه هست:
// عقب‌گرد (دُمِ ناپایدار را دور می‌ریزد و پیشوندِ کوتاه‌تر را دوباره می‌فرستد) و
// پنجره‌ی لغزان (پیشوندِ تثبیت‌شده را می‌اندازد و فقط دمِ تازه را می‌دهد). روی صفحه
// هر دو یک شکل بودند: متنِ خاکستری یک‌دفعه پاک می‌شد و کاربر نمی‌دانست برمی‌گردد.
NSString *ZInterimRatchet(NSString *best, NSString *cur) {
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    best = [(best ?: @"") stringByTrimmingCharactersInSet:ws];
    cur = [(cur ?: @"") stringByTrimmingCharactersInSet:ws];
    if (!best.length) return cur;
    if (!cur.length) return best;
    if ([best containsString:cur]) return best;   // عقب‌گرد به پیشوند: نگهش دار
    if ([cur containsString:best]) return cur;    // رشد عادی

    NSArray *A = [best componentsSeparatedByString:@" "];
    NSArray *B = [cur componentsSeparatedByString:@" "];
    // هر دو از یک لحظه شروع شده‌اند؟ (سرشان فازی یکی است) پس بازنویسیِ همان بازه
    // است و بلندتر نمای کامل‌تر است. کوتاه‌تر را نگیر: همان عقب‌گرد است.
    NSUInteger probe = MIN((NSUInteger)3, MIN(A.count, B.count));
    double sum = 0, strongest = 0;
    for (NSUInteger i = 0; i < probe; i++) {
        double s = ZSeamTokenSim(ZSeamNorm(A[i]), ZSeamNorm(B[i]));
        sum += s;
        if (s > strongest) strongest = s;
    }
    if (probe && sum / probe >= kZSeamMeanSim && strongest >= kZSeamStrongSim) {
        return B.count >= A.count ? cur : best;
    }
    // پنجره‌ی لغزان: سرِ cur به دمِ best می‌چسبد؟ همان هم‌ترازیِ فازیِ جوش.
    ZSeamMatch m = ZSeamFind(best, cur, 16);
    if (m.dropWords >= B.count) return best;
    if (m.dropWords) {
        NSArray *rest = [B subarrayWithRange:NSMakeRange(m.dropWords, B.count - m.dropWords)];
        return [best stringByAppendingFormat:@" %@", [rest componentsJoinedByString:@" "]];
    }
    // هیچ نسبتی پیدا نشد. در تردید هر دو می‌مانند: تکرارِ گذرا در متنِ خاکستری بهتر
    // از حرفی است که جلوی چشم آب می‌شود؛ متنِ قطعیِ بعدی به هر حال جایش را می‌گیرد.
    return [NSString stringWithFormat:@"%@ %@", best, cur];
}

// covered را به‌عنوان پیشوندِ فازیِ whole هم‌تراز می‌کند (هر دو از یک لحظه‌ی صوتی
// شروع شده‌اند) و باقی‌مانده‌ی whole را می‌دهد. هم‌ترازی نامطمئن یعنی خالی: آنجا
// حکمِ متنِ قطعی بی‌رقیب است و ما چیزی برای ادعا نداریم.
NSString *ZUncoveredTail(NSString *whole, NSString *covered) {
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    whole = [(whole ?: @"") stringByTrimmingCharactersInSet:ws];
    covered = [(covered ?: @"") stringByTrimmingCharactersInSet:ws];
    if (!whole.length) return @"";
    if (!covered.length) return whole;
    NSArray *A = [whole componentsSeparatedByString:@" "];
    NSArray *B = [covered componentsSeparatedByString:@" "];
    if (B.count + 8 > A.count && [covered containsString:whole]) return @"";
    if (A.count > 60 || B.count > 60) {
        // بزرگ‌تر از این یعنی پوشش تقریبا قطعی است؛ هزینه‌ی DP را نمی‌دهیم
        return B.count >= A.count ? @"" : whole;
    }
    NSUInteger n = A.count, m = B.count;
    NSMutableArray *nA = [NSMutableArray arrayWithCapacity:n];
    NSMutableArray *nB = [NSMutableArray arrayWithCapacity:m];
    for (NSString *t in A) [nA addObject:ZSeamNorm(t)];
    for (NSString *t in B) [nB addObject:ZSeamNorm(t)];
    double C[61][61];
    C[0][0] = 0;
    for (NSUInteger i = 1; i <= n; i++) C[i][0] = (double)i;
    for (NSUInteger j = 1; j <= m; j++) C[0][j] = (double)j;
    for (NSUInteger i = 1; i <= n; i++) {
        for (NSUInteger j = 1; j <= m; j++) {
            double sub = C[i - 1][j - 1] + (1.0 - ZSeamTokenSim(nA[i - 1], nB[j - 1]));
            double del = C[i - 1][j] + 1.0;
            double ins = C[i][j - 1] + 1.0;
            C[i][j] = MIN(sub, MIN(del, ins));
        }
    }
    // پایانِ آزاد در whole: پوشش تا هر جای آن می‌تواند تمام شود. سر تساوی، iِ بزرگ‌تر
    // یعنی دمِ کوتاه‌تر، یعنی کمترین ادعا.
    NSUInteger bestI = 0;
    double bestCost = 1e9;
    for (NSUInteger i = 0; i <= n; i++) {
        if (C[i][m] <= bestCost) {
            bestCost = C[i][m];
            bestI = i;
        }
    }
    double score = 1.0 - bestCost / (double)MAX(m, MAX(bestI, (NSUInteger)1));
    if (score < 0.60 || bestI >= n) return @"";
    NSArray *rest = [A subarrayWithRange:NSMakeRange(bestI, n - bestI)];
    return [rest componentsJoinedByString:@" "];
}

NSString *ZStitchOverlapMax(NSString *a, NSString *b, NSUInteger maxWords) {
    if (!a.length) return b;
    if (!b.length) return a;
    ZSeamMatch m = ZSeamFind(a, b, maxWords);
    if (!m.dropWords) return [NSString stringWithFormat:@"%@ %@", a, b];
    NSArray *B = [b componentsSeparatedByString:@" "];
    if (m.dropWords >= B.count) return a;
    NSArray *rest = [B subarrayWithRange:NSMakeRange(m.dropWords, B.count - m.dropWords)];
    return [a stringByAppendingFormat:@" %@", [rest componentsJoinedByString:@" "]];
}
