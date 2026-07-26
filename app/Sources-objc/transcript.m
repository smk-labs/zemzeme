// رونوشت: قلبِ لایه‌ی یک، جدا از شبکه و صدا.
//
// موتور اینجا فقط «چه شنیدم» را می‌گوید و این کلاس تصمیم می‌گیرد رونوشت چه شکلی
// درمی‌آید. عمدا هیچ وابستگی‌ای به استریم و میکروفن ندارد، پس بازپخش می‌تواند بی‌شبکه
// و بی‌میکروفن دقیقا همین منطق را بدواند. تا وقتی این منطق لای موتور بود، تست‌ها
// مسیر زنده را پوشش نمی‌دادند و پنج دور وصله از همان‌جا شکست خورد.
//
// قرارداد بیرونی دو تکه است و بس:
//   committed  فقط رشد می‌کند، پیشوندش قفل است.
//   pending    دُمِ ناپایدار: متنِ معلقِ سشنِ در حال تخلیه + متنِ قطعیِ منتظرِ نوبت +
//              interim جاری. هر سه دیده می‌شوند، پس هیچ‌کدام از صفحه غیب نمی‌شوند.
#import "zemzeme.h"

@implementation ZTranscript {
    NSMutableString *_committed;
    NSString *_carry;                          // متن معلقِ سشنِ در حال تخلیه
    NSMutableArray<NSDictionary *> *_after;    // قطعی‌های سشن تازه، منتظر پایان تخلیه
    NSString *_interim;
    BOOL _draining;
    // آیا اولین متنِ سشنِ در حال تخلیه هنوز نیامده؟ آن یکی صدای هم‌پوشان را دوباره
    // شنیده و باید جوش بخورد. پرچم مالِ **استریم** است نه مالِ مسیر: در گفتار
    // بی‌وقفه، سشن پیش از آنکه متن قطعی بدهد می‌چرخد، پس اولین متنش از مسیر تخلیه
    // می‌رسد. همین را از قلم انداخته بودم و هر درز یک تکرار می‌نوشت.
    BOOL _carryWeld;
}

- (instancetype)init {
    if ((self = [super init])) {
        _committed = [NSMutableString string];
        _after = [NSMutableArray array];
        _interim = @"";
        _carry = @"";
        _weldWords = ZStitchWords(kZRotateOverlapSec);
    }
    return self;
}

- (NSString *)committed { return _committed; }
- (BOOL)draining { return _draining; }

- (NSString *)pending {
    NSMutableString *p = [NSMutableString stringWithString:_carry ?: @""];
    for (NSDictionary *d in _after) [p setString:ZJoinText(p, d[@"text"])];
    return ZJoinText(p, _interim);
}

// تنها راهِ رشد رونوشت. جوش اینجا و فقط اینجا زده می‌شود، در برابر خودِ متنی که همین
// حالا قبلش نشسته، نه در برابر یک «آخرین تکه»ی به‌خاطر‌سپرده که ممکن است دیگر آخرین
// نباشد. باگ واقعی: استریمی که با هم‌پوشانی باز شده بود، تا متن قطعی‌اش برسد خودش
// چرخیده بود و مسیر تخلیه جوش نمی‌زد، پس چند کلمه سر هر درز دو بار می‌نشست.
- (void)commit:(NSString *)raw weld:(BOOL)weld {
    NSString *t = [(raw ?: @"") stringByTrimmingCharactersInSet:
                   NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!t.length) return;
    if (weld && _committed.length) {
        ZSeamMatch m = ZSeamFind(_committed, t, _weldWords);
        NSArray *words = [t componentsSeparatedByString:@" "];
        if (m.dropWords >= words.count) {
            // کل تکه هم‌پوشانی است. دو حالت دارد و تا امروز هر دو یک‌کاسه بودند:
            // اگر تطبیق تقریبا دقیق باشد، تکه واقعا همان صدای دوباره‌شنیده است و
            // باید دور برود. پنجره از ثانیه‌های واقعیِ هم‌پوشانی می‌آید، پس تکه‌ای که
            // کاملا داخلش جا شود از دو ثانیه بلندتر نیست: خطرِ بلعیدنِ یک جمله نیست.
            // اندازه‌گیری روی سشن سه‌دقیقه‌ایِ 2026-07-26: «مدل دیگه» سر درز دو بار
            // نوشته شد، چون قاعده‌ی قبلی بی‌قید و شرط خام را نگه می‌داشت.
            if (m.score >= kZSeamCertain) {
                ZLog(@"transcript: seam dropped a fully re-heard chunk (%lu chars, score %.2f)",
                     (unsigned long)t.length, m.score);
                return;
            }
            // لب‌مرزی. در تردید، تکرار: قرارِ این محصول این است که یک کلمه هم جا
            // نیفتد، و تکرار را کاربر پاک می‌کند، گم‌شده را نه.
            ZLog(@"transcript: seam looked redundant but only %.2f sure, keeping raw", m.score);
        } else if (m.dropWords) {
            NSArray *rest = [words subarrayWithRange:
                             NSMakeRange(m.dropWords, words.count - m.dropWords)];
            NSString *kept = [rest componentsJoinedByString:@" "];
            ZLog(@"transcript: seam stitched, %ld dup chars dropped (score %.2f)",
                 (long)t.length - (long)kept.length, m.score);
            t = kept;
        }
    }
    [_committed setString:ZJoinText(_committed, t)];
}

- (void)setInterim:(NSString *)interim {
    _interim = [(interim ?: @"") copy];
    ZEventLogWrite(@{@"k": @"interim", @"text": _interim});
}

// یک تکه‌ی قطعی از سشنِ زنده. وسط تخلیه نوبتش بعد از تخلیه است (وگرنه حرفِ بعدی
// جلوتر از حرفِ قبلی در متن می‌افتاد)، ولی همان لحظه داخل pending دیده می‌شود، پس
// معطلی روی صفحه پیدا نیست.
- (void)addFinal:(NSString *)text weld:(BOOL)weld {
    ZEventLogWrite(@{@"k": @"final", @"text": text ?: @"", @"weld": @(weld)});
    NSString *t = [(text ?: @"") stringByTrimmingCharactersInSet:
                   NSCharacterSet.whitespaceAndNewlineCharacterSet];
    _interim = @"";
    if (!t.length) return;
    if (_draining) [_after addObject:@{@"text": t, @"weld": @(weld)}];
    else [self commit:t weld:weld];
}

// چرخش سشن. متن معلقِ این لحظه می‌رود در carry، و carry جزئی از pending است، پس
// **روی صفحه سر جایش می‌ماند**. قبلا اینجا از نمایش غیب می‌شد و اولین interim کوتاهِ
// سشن تازه جایش می‌نشست: در گفتار بی‌وقفه یعنی دویست نویسه می‌رفت و پنج نویسه می‌آمد،
// همان «یک‌دفعه نصف بیشتر متن پرید».
- (void)beginDrainWithCarry:(NSString *)carry weld:(BOOL)weld {
    ZEventLogWrite(@{@"k": @"rotate", @"carry": carry ?: @"", @"weld": @(weld)});
    if (_draining) [self endDrain];    // تخلیه‌ی قبلی هنوز باز بود؛ اول تسویه‌اش کن
    _draining = YES;
    _carryWeld = weld;
    _carry = [ZJoinText(carry, @"") copy];
    _interim = @"";
}

// سشن قدیمی متن قطعی‌اش را داد: جای متن معلقش را می‌گیرد. جوش لازم ندارد، چون این
// ادامه‌ی همان تشخیص است نه یک تشخیصِ دومِ همان صدا.
// متنِ قطعیِ سشنِ در حال تخلیه: جای متن معلقش را می‌گیرد، پس پرچمِ جوش را هم از آن
// به ارث می‌برد. هرکدام زودتر برسد پرچم را مصرف می‌کند؛ فقط اولین متنِ یک استریم
// تکرار دارد، نه بقیه‌اش.
- (void)drainFinal:(NSString *)text {
    ZEventLogWrite(@{@"k": @"drainfinal", @"text": text ?: @""});
    _carry = @"";
    BOOL weld = _carryWeld;
    _carryWeld = NO;
    [self commit:text weld:weld];
}

// تخلیه بسته شد. متن معلقی که جوابی برایش نیامد خودش قطعی می‌شود (بی این، همان چند
// کلمه بی‌صدا دور می‌رفت)، بعد هرچه منتظر نوبت بود به ترتیب می‌نشیند. چون همه‌ی این
// متن از قبل داخل pending دیده می‌شد، دیفِ روی صفحه صفر است و کاربر تکانی نمی‌بیند.
- (void)endDrain {
    ZEventLogWrite(@{@"k": @"drainend"});
    if (_carry.length) {
        ZLog(@"transcript: drain gave nothing, carrying %lu chars", (unsigned long)_carry.length);
        [self commit:_carry weld:_carryWeld];
    }
    _carry = @"";
    _carryWeld = NO;
    _draining = NO;
    NSArray *held = [_after copy];
    [_after removeAllObjects];
    for (NSDictionary *d in held) [self commit:d[@"text"] weld:[d[@"weld"] boolValue]];
}

// انصراف: فقط دُم. رونوشتِ قطعی دست نمی‌خورد و کوتاه کردنش کارِ مصرف‌کننده است، آن هم
// فقط تا جایی که واقعا درج شده. موتور حق ندارد متنی را که تحویل داده پس بگیرد.
- (void)dropPending {
    ZEventLogWrite(@{@"k": @"drop"});
    _interim = @"";
    _carry = @"";
    [_after removeAllObjects];
    _draining = NO;
}

@end
