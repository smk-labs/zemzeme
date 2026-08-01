// دروازه‌ی کامل بودن: چه چیزی از متن مو‌به‌مو در متن نهایی نیست.
//
// این فایل عمدا هیچ وابستگی‌ای جز Foundation ندارد و هیچ حالتی هم ندارد، پس تست
// طلایی‌اش تنهایی کامپایلش می‌کند (همان قرارداد seam.m). دلیلش هم همان است: تنها
// چیزی که جلوی «مدل بی‌صدا یک جمله را خورد» را می‌گیرد همین چند تابع است، پس باید
// در کمتر از یک ثانیه و بی‌شبکه قابل سنجش باشند.
//
// هدف یک عدد نیست، جواب دادن به یک سوال است: چه چیزی جا افتاد. پس فهرست جاافتاده‌ها
// برمی‌گردد نه فقط درصد، و همان فهرست است که به پرامپتِ تلاش دوم داده می‌شود.
#import "zemzeme.h"

// نویسه‌هایی که فقط ظاهرند و در سنجش هیچ‌اند: کشیده و اعراب.
static NSString *const kZDrop = @"ـًٌٍَُِّْ";
// و نویسه‌هایی که مرزِ واژه‌اند نه واژه: نیم‌فاصله، جوینده، و دو نشانه‌ی جهت.
// **به فاصله تبدیل می‌شوند، نه حذف.** حذفشان «می شود» و «می‌شود» را دو چیز می‌کرد.
static NSString *const kZSplit = @"‌‍‎‏";

// فیلر و واژه‌های بی‌بار. پاسِ درست این‌ها را عمدا می‌اندازد، پس نبودنشان در خروجی
// «جا افتاد» نیست. فهرست از خودِ آزمایشگاه آمده و همان‌جا روی متن واقعی تنظیم شده.
static NSSet<NSString *> *ZStopWords(void) {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:[@"و که را به از در این آن با هم برای ولی اما یا اگر تا هر بر می نمی "
                                    "یه یک خب دیگه خیلی چون پس البته مثل مثلا یعنی هست هستش بود شد شده کرد کردن "
                                    "من تو او ما شما آنها اون اینا چه چی کی کجا بله نه آره اوکی "
                                    "ببخشید منظورم اوم اه ام آم"
                                   componentsSeparatedByString:@" "]];
    });
    return set;
}

// نرمال‌سازیِ سنجش: عربی به فارسی، ارقام به لاتین، اعراب بیرون، نیم‌فاصله به فاصله.
// فقط برای مقایسه است و هیچ‌وقت روی متنی که کاربر می‌بیند اجرا نمی‌شود.
// نویسه‌به‌نویسه و نه «دنباله‌ی نویسه‌ی مرکب»: اعراب باید *جدا* دیده شود تا بیفتد.
// باگ اندازه‌گیری‌شده: با شمردنِ مرکب، «اِ» یک نویسه‌ی دوواحدی بود و هیچ‌وقت با فهرست
// انداختنی‌ها تطبیق نمی‌خورد، پس همان فیلرِ یک‌حرفی «واژه‌ی جاافتاده» شمرده می‌شد.
static NSString *ZFold(NSString *s) {
    // با NSCharacterSet و نه rangeOfString: جست‌وجوی رشته‌ای مرزِ نویسه‌ی مرکب را
    // رعایت می‌کند، پس یک اعرابِ تنها را هیچ‌وقت داخل رشته‌ی اعراب‌ها پیدا نمی‌کرد و
    // همه‌ی این فهرست بی‌اثر بود. عضویت در مجموعه چنین مرزی نمی‌شناسد.
    static NSCharacterSet *drop, *split;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        drop = [NSCharacterSet characterSetWithCharactersInString:kZDrop];
        split = [NSCharacterSet characterSetWithCharactersInString:kZSplit];
    });
    NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if ([drop characterIsMember:c]) continue;
        if ([split characterIsMember:c]) {
            [out appendString:@" "];
            continue;
        }
        if (c >= 0x06F0 && c <= 0x06F9) { [out appendFormat:@"%C", (unichar)('0' + c - 0x06F0)]; continue; }
        if (c >= 0x0660 && c <= 0x0669) { [out appendFormat:@"%C", (unichar)('0' + c - 0x0660)]; continue; }
        switch (c) {
            case 0x064A: case 0x0649: [out appendString:@"ی"]; break;    // ي و ى عربی
            case 0x0643: [out appendString:@"ک"]; break;                 // ك عربی
            case 0x0629: case 0x06C0: [out appendString:@"ه"]; break;    // ة و ۀ
            case 0x0623: case 0x0625: [out appendString:@"ا"]; break;    // أ و إ
            default: [out appendFormat:@"%C", c];
        }
    }
    return out;
}

// توکن: یا یک رشته‌ی حرف، یا یک رشته‌ی رقم. علائم فارسی (، ؛ ؟) بیرون می‌مانند.
// با NSCharacterSet و نه رجکس: مرزِ واژه‌ی ICU خودش نیم‌فاصله را حرف حساب می‌کند و
// همان یک تفاوت، کلِ سنجش را جابه‌جا می‌کرد.
static NSArray<NSString *> *ZTokens(NSString *raw) {
    NSString *s = ZFold(raw);
    NSCharacterSet *letters = NSCharacterSet.letterCharacterSet;
    NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
    NSMutableArray *out = [NSMutableArray array];
    NSMutableString *cur = [NSMutableString string];
    BOOL curDigit = NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        BOOL isL = [letters characterIsMember:c];
        BOOL isD = [digits characterIsMember:c];
        if ((!isL && !isD) || (cur.length && isD != curDigit)) {
            if (cur.length) [out addObject:[cur copy]];
            cur = [NSMutableString string];
        }
        if (isL || isD) {
            if (!cur.length) curDigit = isD;
            [cur appendFormat:@"%C", c];
        }
    }
    if (cur.length) [out addObject:[cur copy]];
    return out;
}

// ترتیب حفظ‌شده، تکراری‌ها حذف
static NSArray<NSString *> *ZUniq(NSArray<NSString *> *in) {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *w in in) {
        if (![seen containsObject:w]) {
            [seen addObject:w];
            [out addObject:w];
        }
    }
    return out;
}

@implementation ZCoverage

+ (instancetype)ofDraft:(NSString *)draft output:(NSString *)out {
    ZCoverage *c = [ZCoverage new];
    NSArray<NSString *> *dt = ZTokens(draft ?: @""), *ot = ZTokens(out ?: @"");
    c->_draftWords = dt.count;
    c->_outWords = ot.count;
    NSSet *oset = [NSSet setWithArray:ot];
    // مرزِ واژه بین دو متن یکی نیست: متن مو‌به‌مو «میکنه» را سرهم می‌نویسد و پاس
    // «می‌کنه» را با نیم‌فاصله، و نیم‌فاصله اینجا فاصله شمرده می‌شود. پس علاوه بر
    // تطبیقِ توکن، داخل رشته‌ی بی‌فاصله هم می‌گردیم. اندازه‌گیری روی متن واقعی:
    // بیشترِ فهرستِ «جا افتاد» پیش از این تکه، همین بود.
    NSString *joinedOut = [ot componentsJoinedByString:@""];
    BOOL (^have)(NSString *) = ^BOOL(NSString *w) {
        // NSLiteralSearch لازم است، وگرنه جست‌وجوی پیش‌فرض سر خوشه‌ی نویسه می‌ایستد و
        // «نکته» را داخل «نکته‌اش» پیدا نمی‌کند: کلمه‌ی حاضر، گم‌شده گزارش می‌شد.
        return [oset containsObject:w]
            || [joinedOut rangeOfString:w options:NSLiteralSearch].location != NSNotFound;
    };
    NSSet *stop = ZStopWords();
    NSMutableArray *content = [NSMutableArray array], *missing = [NSMutableArray array];
    for (NSString *w in ZUniq(dt)) {
        if (w.length < 2 || [stop containsObject:w]) continue;
        [content addObject:w];
        if (!have(w)) [missing addObject:w];
    }
    c->_missing = missing;
    c->_coverage = round((content.count ? 100.0 * (1.0 - (double)missing.count / content.count) : 100.0) * 10) / 10;

    // عدد و لاتین: تحمل صفر و بی هیچ مدارایی. اینجا فقط تطبیق توکن، نه رشته‌ی
    // بی‌فاصله: «۱۲» داخل «۱۲۳» پیدا می‌شود ولی همان یعنی عدد عوض شده.
    NSMutableArray *nums = [NSMutableArray array], *lat = [NSMutableArray array];
    NSCharacterSet *ascii = [NSCharacterSet characterSetWithRange:NSMakeRange('A', 26)];
    NSCharacterSet *asciiLow = [NSCharacterSet characterSetWithRange:NSMakeRange('a', 26)];
    for (NSString *w in ZUniq(dt)) {
        if ([oset containsObject:w]) continue;
        unichar f = [w characterAtIndex:0];
        if ([NSCharacterSet.decimalDigitCharacterSet characterIsMember:f]) {
            [nums addObject:w];
        } else if ([ascii characterIsMember:f] || [asciiLow characterIsMember:f]) {
            [lat addObject:w];
        }
    }
    c->_lostNumbers = [nums sortedArrayUsingSelector:@selector(compare:)];
    c->_lostLatin = [lat sortedArrayUsingSelector:@selector(compare:)];
    c->_passed = c->_lostNumbers.count == 0 && c->_lostLatin.count == 0
                 && c->_coverage >= kZCoverageFloor;
    return c;
}

- (NSString *)summary {
    NSMutableString *s = [NSMutableString stringWithFormat:@"پوشش %.1f%% (%lu←%lu واژه)",
                          _coverage, (unsigned long)_outWords, (unsigned long)_draftWords];
    if (_lostNumbers.count) [s appendFormat:@"، عدد گم: %@", [_lostNumbers componentsJoinedByString:@" "]];
    if (_lostLatin.count) [s appendFormat:@"، لاتین گم: %@", [_lostLatin componentsJoinedByString:@" "]];
    if (_missing.count) {
        NSArray *head = [_missing subarrayWithRange:NSMakeRange(0, MIN(12u, (unsigned)_missing.count))];
        [s appendFormat:@"، جا افتاد (%lu): %@", (unsigned long)_missing.count,
         [head componentsJoinedByString:@" "]];
    }
    return s;
}

@end
