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
NSString *ZStitchOverlapMax(NSString *a, NSString *b, NSUInteger maxWords) {
    if (!a.length) return b;
    if (!b.length) return a;
    NSArray *A = [a componentsSeparatedByString:@" "];
    NSArray *B = [b componentsSeparatedByString:@" "];
    NSMutableArray *nA = [NSMutableArray arrayWithCapacity:A.count];
    NSMutableArray *nB = [NSMutableArray arrayWithCapacity:B.count];
    for (NSString *t in A) [nA addObject:ZSeamNorm(t)];
    for (NSString *t in B) [nB addObject:ZSeamNorm(t)];

    NSUInteger maxK = MIN(MIN(A.count, B.count), MAX((NSUInteger)2, maxWords));
    NSUInteger bestK = 0;
    double bestScore = 0;
    for (NSUInteger k = 2; k <= maxK; k++) {
        double sum = 0, strongest = 0;
        for (NSUInteger i = 0; i < k; i++) {
            double s = ZSeamTokenSim(nA[nA.count - k + i], nB[i]);
            sum += s;
            if (s > strongest) strongest = s;
        }
        double mean = sum / (double)k;
        if (mean < kZSeamMeanSim || strongest < kZSeamStrongSim) continue;
        if (mean > bestScore) {    // اکید، پس سر تساوی k کوچک‌تر می‌ماند
            bestScore = mean;
            bestK = k;
        }
    }
    if (bestK) {
        NSArray *rest = [B subarrayWithRange:NSMakeRange(bestK, B.count - bestK)];
        return rest.count ? [a stringByAppendingFormat:@" %@",
                             [rest componentsJoinedByString:@" "]] : a;
    }
    // پنجره‌ی یک‌کلمه‌ای فقط با تطبیق دقیق: یک کلمه لنگر کافی نیست و شباهتِ نسبی
    // روی آن هر دو تکه‌ی بی‌ربط را به هم می‌چسباند.
    if ([nA.lastObject length] && [nA.lastObject isEqualToString:nB.firstObject]) {
        NSArray *rest = [B subarrayWithRange:NSMakeRange(1, B.count - 1)];
        return rest.count ? [a stringByAppendingFormat:@" %@",
                             [rest componentsJoinedByString:@" "]] : a;
    }
    return [NSString stringWithFormat:@"%@ %@", a, b];
}
