// دروازه‌ی بهبود پرامپت: چه چیزی از متن دیکته در پرامپت نیست، و آیا پرحرف شده.
//
// چرا فایل جدا و نه لای `enhance.m`: همان قرارداد `gate.m` و `seam.m`. تنها چیزی که
// جلوی «مدل بی‌صدا یک عدد یا یک مسیر را خورد» را می‌گیرد همین چند تابع است، پس باید
// در کمتر از یک ثانیه و **بی‌کلید و بی‌شبکه** قابل سنجش باشند. تست طلایی‌اش
// (`bash tools/enhance_gate_test.sh`) این فایل را با `gate.m` تنها کامپایل می‌کند.
//
// و چرا دروازه‌ی دومی لازم بود: `gate.m` بین «متن مو‌به‌مو» و «همان متن، تمیزتر»
// می‌نشیند و درصد پوششِ واژه معیارش است. اینجا کار *تبدیل* است، نه تمیزکاری: فیلر و
// من‌من و جمله‌ی رهاشده باید بروند و شکل عوض شود، پس پوششِ ۷۰٪ می‌تواند کاملا درست
// باشد. آنچه تحمل صفر دارد چیزهایی است که معنایشان در خودشان است.
#import "zemzeme.h"

// سقف طول: بالاتر از این ضریب، مدل دارد حرف اضافه می‌زند نه ساختار می‌دهد.
#define kZEnhLengthFactor 2.5
// ...ولی یک کفِ مطلق هم لازم است، و از یک شکستِ واقعی آمد: ورودیِ «یه تست برای تابع
// ZSeamFind بنویس» شانزده واژه است و ۲٫۵ برابرش چهل. هیچ پرامپتِ ساختاردارِ درستی در
// چهل واژه جا نمی‌شود، پس ضریبِ تنها هر ورودیِ کوتاه را رد می‌کرد. ساختار هزینه‌ی
// ثابت دارد و ضریب فقط برای دیکته‌ی واقعی معنا دارد.
#define kZEnhLengthFloor 80

// مسیر فایل: چیزی که دستِ کم یک اسلش دارد و دو طرفش نویسه‌ی مسیر است. عمدا فقط
// ASCII، پس تاریخ فارسی («۱۴۰۴/۰۵/۰۱») و «و/یا» اینجا مسیر شمرده نمی‌شوند.
// چرا جدا از توکن لاتین: `ZCoverage` مسیر را به تکه‌هایش می‌شکند و «app» و «m» را جدا
// می‌سنجد، یعنی مسیری که تکه‌هایش پراکنده در متن باشند از دستش رد می‌شود. مسیر باید
// **یک‌جا** و مو‌به‌مو در خروجی باشد، وگرنه ایجنت جای اشتباهی را باز می‌کند.
static NSArray<NSString *> *ZEnhPaths(NSString *s) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
              @"[~.]?[A-Za-z0-9_.\\-]*/[A-Za-z0-9_.\\-/]+" options:0 error:nil];
    });
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSCharacterSet *edge = [NSCharacterSet characterSetWithCharactersInString:@"./-"];
    for (NSTextCheckingResult *m in [re matchesInString:s options:0 range:NSMakeRange(0, s.length)]) {
        NSString *p = [[s substringWithRange:m.range] stringByTrimmingCharactersInSet:edge];
        // «//» تنهای وسط یک آدرس، و تکه‌های یک‌حرفی، مسیر نیستند
        if (p.length < 3 || [p rangeOfString:@"/"].location == NSNotFound) continue;
        if ([seen containsObject:p]) continue;
        [seen addObject:p];
        [out addObject:p];
    }
    return out;
}

// ---------- عددِ مقیاس‌دار ----------
// باگ اندازه‌گیری‌شده روی یک دیکته‌ی واقعی (۷۸۰ واژه): گوینده گفت «کد پشت ۱۰ هزار تا
// سفارش» و پرامپت درست نوشت «تا 10000 سفارش». توکنِ `10` ناپدید شد، ولی عدد **نشد**:
// همان عدد با واحدِ خودش ضرب شده بود. دروازه بست، و دو تماس و ۴۱ ثانیه سوخت تا همان
// جوابِ درست دوباره رد شود.
//
// چرا این تحمل *فقط اینجا* درست است و در `gate.m` نه: آن دروازه بین «متن مو‌به‌مو» و
// «همان متن، تمیزتر» می‌نشیند و آنجا عوض شدنِ رقم یعنی خطا. اینجا خروجی متنی است که
// به یک ماشین داده می‌شود، و نوشتنِ «۱۰ هزار» به شکل `10000` دقیقا کارِ درست است.
//
// و چرا شرطش تنگ است: تحمل فقط وقتی اعمال می‌شود که **خودِ گفتار** بلافاصله یک واژه‌ی
// مقیاس آورده باشد. بی این شرط، گم شدنِ `12` با حضور `123` هم بخشیده می‌شد، که یعنی
// دروازه دیگر هیچ عددی را نمی‌پاید.
static NSString *ZEnhFoldDigits(NSString *s) {
    NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= 0x06F0 && c <= 0x06F9) c = (unichar)('0' + c - 0x06F0);
        else if (c >= 0x0660 && c <= 0x0669) c = (unichar)('0' + c - 0x0660);
        [out appendFormat:@"%C", c];
    }
    return out;
}

// عددهایی که در خودِ گفتار واژه‌ی مقیاس پشتشان آمده. «تا» و «تومان» عمدا نیستند: آن‌ها
// مقیاس نیستند و بودنشان تحمل را به هر عددی باز می‌کرد.
static NSSet<NSString *> *ZEnhScaledNumbers(NSString *draft) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
              @"([0-9]+)\\s*(هزار|میلیون|میلیارد|صدهزار|thousand|million|billion|k|m)\\b"
              options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSString *s = ZEnhFoldDigits(draft ?: @"");
    NSMutableSet *out = [NSMutableSet set];
    for (NSTextCheckingResult *m in [re matchesInString:s options:0 range:NSMakeRange(0, s.length)]) {
        [out addObject:[s substringWithRange:[m rangeAtIndex:1]]];
    }
    return out;
}

// همه‌ی عددهای خروجی، با ارقام لاتین‌شده
static NSArray<NSString *> *ZEnhOutNumbers(NSString *out) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"[0-9]+" options:0 error:nil];
    });
    NSString *s = ZEnhFoldDigits(out ?: @"");
    NSMutableArray *nums = [NSMutableArray array];
    for (NSTextCheckingResult *m in [re matchesInString:s options:0 range:NSMakeRange(0, s.length)]) {
        [nums addObject:[s substringWithRange:m.range]];
    }
    return nums;
}

// ---------- توکن لاتین، با دو تفاوت از `gate.m` ----------
// هر دو تفاوت از یک شکستِ اندازه‌گیری‌شده روی سشن انگلیسی آمدند، و هر دو در آن دروازه
// درست‌اند و اینجا غلط:
//
// ۱. **بی‌توجه به بزرگی و کوچکی حرف.** پرامپت مارک‌داون است، پس واژه‌ی سر تیتر و سر
//    بولت بزرگ می‌شود: `refactor` می‌شود `Refactor`. با تطبیقِ حساس به حرف، هر پرامپت
//    انگلیسیِ **درستی** رد می‌شد. در `gate.m` این خطر نبود، چون آنجا هر دو طرف متنِ
//    پیوسته‌ی یک زبان‌اند و کسی تیتر نمی‌سازد.
// ۲. **فیلر انگلیسی هم فیلر است.** فهرست ایست `gate.m` تمامش فارسی است، پس «okay» و
//    «um» و «so» توکن لاتینِ **تحمل‌صفر** شمرده می‌شدند، در حالی که انداختنشان دقیقا
//    همان کاری است که از این پاس خواسته‌ایم. یعنی دروازه هر سشن انگلیسی را می‌بست.
//
// فهرست عمدا فقط واژه‌ی دستوری و فیلر است: هیچ شناسه، نام ابزار، مسیر یا عددی در آن
// نیست و نمی‌تواند باشد، پس چیزی که واقعا معنا دارد هیچ‌وقت بخشیده نمی‌شود.
static NSSet<NSString *> *ZEnhStopLatin(void) {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:[@"um uh er ah okay ok so like just really actually basically "
                                    "well now then right sorry mean means yeah yes no not maybe "
                                    "i you we it he she they me my your our its their this that "
                                    "these those there here what which who when where why how "
                                    "a an the and or but if because since while of to in on at "
                                    "for with from by as into over under about per than too also "
                                    "is are was were be been being am do does did done doing "
                                    "have has had will would can could should shall may might must "
                                    "get got make made let need want going gonna wanna kinda sorta "
                                    "thing things stuff kind sort lot lots very much many some any "
                                    "every single each one two both all more most less least "
                                    "still even only again another other same such thats its "
                                    "please thanks anyway whatever something anything nothing"
                                   componentsSeparatedByString:@" "]];
    });
    return set;
}

// توکنِ لاتین: با حرف شروع می‌شود و می‌تواند رقم و زیرخط داشته باشد، پس `python3` و
// `auth_ts` یک توکن‌اند نه دو. `gate.m` حرف و رقم را جدا می‌کند و برای سنجشِ فارسی
// درست است؛ اینجا نامِ ابزار باید یک‌جا بماند.
static NSArray<NSString *> *ZEnhLatinTokens(NSString *s) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"[A-Za-z][A-Za-z0-9_]*"
                                                      options:0 error:nil];
    });
    NSString *low = (s ?: @"").lowercaseString;
    NSMutableArray *out = [NSMutableArray array];
    for (NSTextCheckingResult *m in [re matchesInString:low options:0 range:NSMakeRange(0, low.length)]) {
        [out addObject:[low substringWithRange:m.range]];
    }
    return out;
}

static NSArray<NSString *> *ZEnhLostLatin(NSString *draft, NSString *out) {
    NSSet *have = [NSSet setWithArray:ZEnhLatinTokens(out)];
    NSSet *stop = ZEnhStopLatin();
    NSMutableArray *lost = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *w in ZEnhLatinTokens(draft)) {
        // یک‌حرفی‌ها بیرون‌اند: در گفتار حرفِ تنها معمولا آواست نه واژه («a»، «I»)
        if (w.length < 2 || [stop containsObject:w] || [seen containsObject:w]) continue;
        [seen addObject:w];
        if (![have containsObject:w]) [lost addObject:w];
    }
    return [lost sortedArrayUsingSelector:@selector(compare:)];
}

@implementation ZEnhGate

+ (instancetype)ofDraft:(NSString *)draft output:(NSString *)out {
    ZEnhGate *g = [ZEnhGate new];
    // عدد از همان سنجه‌ی اندازه‌گیری‌شده می‌آید، با هر دو باگی که در آن درست شد
    // (نیم‌فاصله به فاصله، و تطبیقِ بی‌فاصله). تکرارِ آن منطق یعنی تکرارِ آن دو باگ.
    // لاتین اما بازنویسی شده، و چرایش همین بالا نوشته است.
    ZCoverage *c = [ZCoverage ofDraft:draft output:out];
    // ...و بعد همان یک تحملِ مخصوصِ این کار: عددی که واحدش را خورده، گم نشده.
    NSSet *scaled = ZEnhScaledNumbers(draft);
    NSArray *outNums = scaled.count ? ZEnhOutNumbers(out) : @[];
    NSMutableArray *lostNums = [NSMutableArray array];
    for (NSString *n in c.lostNumbers) {
        BOOL absorbed = NO;
        if ([scaled containsObject:n]) {
            for (NSString *o in outNums) {
                // درازتر، و با همان سر: `10` داخل `10000`. مساوی بودن اینجا ممکن نیست،
                // چون آن‌وقت `ZCoverage` اصلا گمش نمی‌دید.
                if (o.length > n.length && [o hasPrefix:n]) {
                    absorbed = YES;
                    break;
                }
            }
        }
        if (!absorbed) [lostNums addObject:n];
    }
    g->_lostNumbers = lostNums;
    g->_lostLatin = ZEnhLostLatin(draft, out);
    g->_draftWords = c.draftWords;
    g->_outWords = c.outWords;

    NSMutableArray *lostPaths = [NSMutableArray array];
    for (NSString *p in ZEnhPaths(draft ?: @"")) {
        if ([out rangeOfString:p].location == NSNotFound) [lostPaths addObject:p];
    }
    g->_lostPaths = lostPaths;

    g->_allowedWords = (NSUInteger)MAX((double)kZEnhLengthFloor,
                                       kZEnhLengthFactor * (double)c.draftWords);
    g->_tooLong = c.outWords > g->_allowedWords;
    g->_passed = g->_lostNumbers.count == 0 && g->_lostLatin.count == 0
                 && g->_lostPaths.count == 0 && !g->_tooLong;
    return g;
}

- (NSString *)summary {
    NSMutableString *s = [NSMutableString stringWithFormat:@"%lu←%lu واژه (سقف %lu)",
                          (unsigned long)_outWords, (unsigned long)_draftWords,
                          (unsigned long)_allowedWords];
    if (_tooLong) [s appendString:@"، پرحرف"];
    if (_lostNumbers.count) [s appendFormat:@"، عدد گم: %@", [_lostNumbers componentsJoinedByString:@" "]];
    if (_lostLatin.count) [s appendFormat:@"، لاتین گم: %@", [_lostLatin componentsJoinedByString:@" "]];
    if (_lostPaths.count) [s appendFormat:@"، مسیر گم: %@", [_lostPaths componentsJoinedByString:@" "]];
    return s;
}

@end
