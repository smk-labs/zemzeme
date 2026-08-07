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
    NSString *_drainCommitted;                 // متنِ قطعی‌ای که همین تخلیه تا حالا داده
    NSString *_carryShown;                     // carry منهای آنچه تخلیه پوشانده؛ برای نمایش
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
        _drainCommitted = @"";
        _carryShown = @"";
        _weldWords = ZStitchWords(kZRotateOverlapSec);
    }
    return self;
}

- (NSString *)committed { return _committed; }
- (BOOL)draining { return _draining; }

- (NSString *)pending {
    NSMutableString *p = [NSMutableString stringWithString:_carryShown ?: @""];
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
    NSString *cur = [(interim ?: @"") copy];
    ZEventLogWrite(@{@"k": @"interim", @"text": cur});
    // نمای دُم یک‌طرفه است: عقب‌گردِ interim نگه داشته می‌شود، نه اجرا. اندازه‌گیری
    // روی سشن واقعی 03-09-19 همین دستگاه: interim هفت بار عقب نشست (۲۰۴ به ۱۳۲،
    // ۱۸۵ به ۱۲۸، …) و هر بار متنِ خاکستری جلوی چشم کاربر پاک می‌شد و او نمی‌دانست
    // برمی‌گردد یا نه. فقط متنِ قطعی حق دارد جای دُم را بگیرد.
    _interim = ZInterimRatchet(_interim, cur);
}

// یک تکه‌ی قطعی از سشنِ زنده. وسط تخلیه نوبتش بعد از تخلیه است (وگرنه حرفِ بعدی
// جلوتر از حرفِ قبلی در متن می‌افتاد)، ولی همان لحظه داخل pending دیده می‌شود، پس
// معطلی روی صفحه پیدا نیست.
- (void)addFinal:(NSString *)text weld:(BOOL)weld {
    ZEventLogWrite(@{@"k": @"final", @"text": text ?: @"", @"weld": @(weld)});
    NSString *t = [(text ?: @"") stringByTrimmingCharactersInSet:
                   NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // متنِ قطعی دُم را مصرف می‌کند، ولی فقط تا جایی که واقعا پوشانده. اگر دُمِ
    // نگه‌داشته از متنِ قطعی درازتر است (interim عقب‌گرد کرده بود و ما نگهش
    // داشتیم)، باقی‌مانده خاکستری می‌ماند: یا تشخیصِ بعدی پوششش می‌دهد و همین‌جا
    // مصرف می‌شود، یا سرِ بستنِ سشن قطعی می‌شود. بی‌صدا دور نمی‌رود.
    // ...ولی «باقی‌مانده» فقط پسوند نیست. ZUncoveredTail ذاتا می‌پرسد «بعد از
    // پوشیده‌شده چه مانده؟»، پس وقتی متنِ قطعی دُمِ interim را می‌پوشاند و **سرِ**
    // آن را نه، آن سر در نقطه‌ی کور می‌افتاد و بی‌صدا می‌رفت.
    //
    // سشن 04-57-19 همین دستگاه، عینا: گوگل در interim «…میگه ساینین» گفت، بعد خودش
    // «ساینین» را پس گرفت و final اش «…میگه» بود. تا اینجا درست کار کرد و «ساینین»
    // به‌عنوان باقی‌ماندهٔ خاکستری ماند. بعد جملهٔ بعدی آمد و interim شد
    // «ساینین مجدد کن»، و final اش «مجدد کن». حالا پوشیده‌شده دقیقا **دُم** است، پس
    // پسوند خالی درآمد و «ساینین» همان‌جا پاک شد. کاربر گفته بودش و روی صفحه هم
    // دیده بودش.
    //
    // سر، از نظر زمانی **پیش از** این متنِ قطعی گفته شده، پس جلوتر از آن می‌نشیند.
    if (t.length) {
        NSString *head = ZUncoveredHead(_interim, t);
        if (head.length) {
            ZLog(@"transcript: سرِ خاکستری «%@» را final نپوشاند؛ پیش از آن قطعی شد", head);
            t = ZJoinText(head, t);
        }
        _interim = ZUncoveredTail(_interim, t);
    }
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
    // carry موتور (نجات‌گرفته از بلندترین interim) با دُمِ نگه‌داشته‌ی خودمان یکی
    // می‌شود؛ هرکدام کامل‌تر بود همان می‌ماند. بی این، لحظه‌ی چرخش خودش یک عقب‌گرد
    // می‌شد: نمایش از دفترِ ما پرتر بود و carry جایش می‌نشست.
    _carry = [ZInterimRatchet(_interim, carry) copy];
    _carryShown = _carry;
    _drainCommitted = @"";
    _interim = @"";
}

// سشن قدیمی متن قطعی‌اش را داد: جای متن معلقش را می‌گیرد. جوش لازم ندارد، چون این
// ادامه‌ی همان تشخیص است نه یک تشخیصِ دومِ همان صدا.
// متنِ قطعیِ سشنِ در حال تخلیه: جای متن معلقش را می‌گیرد، پس پرچمِ جوش را هم از آن
// به ارث می‌برد. هرکدام زودتر برسد پرچم را مصرف می‌کند؛ فقط اولین متنِ یک استریم
// تکرار دارد، نه بقیه‌اش.
- (void)drainFinal:(NSString *)text {
    ZEventLogWrite(@{@"k": @"drainfinal", @"text": text ?: @""});
    BOOL weld = _carryWeld;
    _carryWeld = NO;
    // **سرِ گم‌شده را پس بگیر.** گوگل سرِ چرخش final اش را گاهی با یکی دو کلمه کمتر
    // از سرِ interim می‌فرستد. آن کلمه‌ها در نقطه‌ی کور می‌افتادند: نه در این متنِ
    // قطعی بودند، و نه `_carryShown` پایین می‌توانست بگیردشان چون آن فقط **پسوند**
    // برمی‌گرداند. سشن 03-27-03: خاکستری «که بعضی از حرف‌های اول…» و final
    // «بعضی از حرف‌های اول…»، پس «که» می‌رفت. همان «حرفِ اولِ تیکه را می‌پرونه».
    // فقط در اولین متنِ قطعیِ تخلیه، چون بعدش آن سر از قبل قطعی شده و دوباره
    // چسباندنش یعنی تکرار.
    if (!_drainCommitted.length) {
        NSString *head = ZUncoveredHead(_carry, text);
        if (head.length) {
            ZLog(@"transcript: final سرش را جا انداخته بود، «%@» برگشت", head);
            text = ZJoinText(head, text);
        }
    }
    [self commit:text weld:weld];
    // carry یک‌جا دور ریخته نمی‌شود؛ فقط آن بخشی می‌رود که این متنِ قطعی واقعا
    // پوشانده. باگِ واقعیِ سشن 03-09-19: interim تا «شونه کار پزشکی خیلی مهم» رفته
    // بود و carry آن را داشت، ولی متنِ قطعیِ تخلیه کوتاه‌تر بود و carry با آمدنش
    // یک‌جا نال می‌شد؛ کلمه‌های پزشکی، که در دستِ خودمان بودند، بی‌صدا گم شدند.
    // اگر همان استریم بی‌هیچ متنی می‌مرد، کل carry را قطعی می‌کردیم؛ حالا که متنی
    // داده که *کمتر* را می‌پوشاند، منطقی نیست بیشتر دور بریزیم.
    _drainCommitted = ZJoinText(_drainCommitted, text);
    _carryShown = ZUncoveredTail(_carry, _drainCommitted);
}

// تخلیه بسته شد. متن معلقی که جوابی برایش نیامد خودش قطعی می‌شود (بی این، همان چند
// کلمه بی‌صدا دور می‌رفت)، بعد هرچه منتظر نوبت بود به ترتیب می‌نشیند. چون همه‌ی این
// متن از قبل داخل pending دیده می‌شد، دیفِ روی صفحه صفر است و کاربر تکانی نمی‌بیند.
- (void)endDrain {
    ZEventLogWrite(@{@"k": @"drainend"});
    if (_carryShown.length) {
        ZLog(@"transcript: drain left %lu chars uncovered, keeping them",
             (unsigned long)_carryShown.length);
        [self commit:_carryShown weld:_carryWeld];
    }
    _carry = @"";
    _carryShown = @"";
    _drainCommitted = @"";
    _carryWeld = NO;
    _draining = NO;
    NSArray *held = [_after copy];
    [_after removeAllObjects];
    for (NSDictionary *d in held) [self commit:d[@"text"] weld:[d[@"weld"] boolValue]];
}

// پایان سشن: هرچه هنوز خاکستری است قطعی می‌شود. دُمی که هیچ متنِ قطعی‌ای پوشش
// نداد (عقب‌گردی که هرگز جبران نشد) اینجا می‌نشیند، نه در سطل آشغال.
- (void)sealPending {
    [self endDrain];
    if (_interim.length) {
        ZLog(@"transcript: sealing %lu grey chars at session end", (unsigned long)_interim.length);
        [self commit:_interim weld:NO];
        _interim = @"";
    }
}

// انصراف: فقط دُم. رونوشتِ قطعی دست نمی‌خورد و کوتاه کردنش کارِ مصرف‌کننده است، آن هم
// فقط تا جایی که واقعا درج شده. موتور حق ندارد متنی را که تحویل داده پس بگیرد.
- (void)dropPending {
    ZEventLogWrite(@{@"k": @"drop"});
    _interim = @"";
    _carry = @"";
    _carryShown = @"";
    _drainCommitted = @"";
    _carryWeld = NO;
    [_after removeAllObjects];
    _draining = NO;
}

@end
