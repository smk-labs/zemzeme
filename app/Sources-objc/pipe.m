// خط لوله: صدا می‌آید، تکه می‌شود، متن به ترتیب بیرون می‌رود.
//
// یک مسیر تشخیص برای هر دو کاربرد. نسخه یک دو مسیر جدا داشت (زنده با چرخش و
// هم‌پوشانی و دوخت، و دسته‌ای با برش و هم‌پوشانی و دوخت) و هر باگ باید دو بار درست
// می‌شد. تفاوتِ واقعیِ آن دو فقط یک چیز است: صدا از میکروفن می‌آید یا از فایل. پس
// اینجا یک کلاس است و منبع صدا بیرون از آن می‌ماند.
//
// سرهم کردن متن، کلِ الگوریتم: تکه‌ها با یک فاصله به هم می‌چسبند. همین.
// نه هم‌پوشانی، نه جوش، نه جست‌وجوی درز، نه راچت، نه نجاتِ سر و دم.
// اندازه‌گیری روی ضبط ۰۱: هم‌پوشانی ۲٫۵ ثانیه‌ای به‌اضافه‌ی ZStitchOverlapMax پنج
// کلمه را بی‌صدا خورد، تکرارپذیر، در حالی که همان صدا در یک پنجره‌ی جدا سالم
// رونویسی می‌شد. برش سر سکوت هیچ‌وقت مشکل نبود؛ هم‌پوشانی و دوخت بودند.
//
// و یک استثنا که خودش قاعده است: تکه‌ای که متنش نرسیده **جای خودش را نگه می‌دارد**.
// چسباندنِ ساده اگر تکه‌ی گم‌شده را رد کند، سوراخ را می‌دوزد و حرفِ گم‌شده هیچ ردی
// نمی‌گذارد. ولی جا دیگر یک نشانه در رشته نیست: یک `ZSlot` در صف است (queue.m) و
// این فایل فقط می‌برد و تحویلش می‌دهد. رشته‌ای هم که بیرون می‌رود از روی همان جاها
// ساخته می‌شود، پس ترتیب ساختاری است نه یک قرارداد روی متن.
#import "zemzeme.h"

// آیا این تکه اصلا حرف دارد؟ تکه‌ی سکوت حق دارد بی‌متن بماند و نباید یک رفت‌وبرگشت
// شبکه خرج کند. سکوتِ محض هم سر هر سشن یک ثانیه معطلی دارد، پس ارزان نیست.
//
// دو اشتباه اینجا افتاد و هر دو یک ریشه داشتند: «سکوت» را با «بی‌صدا» یکی گرفتن.
//
// **قاب‌به‌قاب، نه میانگینِ کل.** اولین نسخه میانگین توانِ کل تکه را می‌سنجید و روی
// ته‌مانده‌ی سشن خراب شد: تکه‌ی ۸٫۷ ثانیه‌ای که دو ثانیه حرف داشت و بقیه‌اش سکوت بود،
// میانگینش پایین می‌افتاد و کل تکه دور ریخته می‌شد. روی ضبط ۰۷ همین یک خط جمله‌ی
// آخر متن را خورد و تطبیق را از ۷۵٪ به ۶۳٪ آورد.
//
// **و با آستانه‌ی خودش، نه آستانه‌ی مکث.** نسخه‌ی دوم قاب‌به‌قاب بود ولی هنوز با
// kZSegRMS می‌سنجید، و ضبط ۰۴ (پچ‌پچ) را کامل خورد: پچ‌پچ زیر آستانه‌ی مکث است.
BOOL ZSegHasVoice(NSData *pcm) {
    const NSUInteger frame = 320;      // ۲۰ میلی‌ثانیه، بر حسب نمونه
    if (pcm.length < 2) return NO;
    const int16_t *p = pcm.bytes;
    NSUInteger n = pcm.length / 2;
    for (NSUInteger off = 0; off + frame <= n; off += frame) {
        float acc = 0;
        NSUInteger cnt = 0;
        for (NSUInteger i = off; i < off + frame; i += 4) {
            float v = p[i] / 32768.0f;
            acc += v * v;
            cnt++;
        }
        if (sqrtf(acc / MAX(1u, (unsigned)cnt)) > kZVoiceRMS) return YES;
    }
    return NO;
}

// ---------- یک تکه، یک سشن، یک متن ----------
// بلوکه است، پس فقط از نخ پس‌زمینه. همان کاری که مسیر دسته‌ای نسخه یک می‌کرد، ولی
// حالا تنها پیاده‌سازیِ موجود است و مسیر زنده هم از همین می‌خواند.
BOOL ZCloseWasClean(NSString *why) {
    return !why.length || [why isEqualToString:@"ok"];
}

NSString *ZTranscribeSegment(NSData *pcm, NSString *lang, BOOL rawUpload,
                             unsigned long long *bytesUp, NSString **why) {
    if (why) *why = nil;
    ZGoogleStream *s = [[ZGoogleStream alloc] initWithLang:lang];
    s.rawUpload = rawUpload;
    NSMutableArray<NSString *> *finals = [NSMutableArray array];
    __block NSString *bestInterim = @"";
    __block NSDate *lastEvent = NSDate.date;
    NSLock *lock = [NSLock new];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    s.onEvent = ^(ZSpeechEvent *ev) {
        [lock lock];
        lastEvent = NSDate.date;
        for (NSString *f in ev.finals) {
            if (f.length) [finals addObject:f];
        }
        // بلندترین interim فقط برای یک حالت نگه داشته می‌شود: سشنی که هیچ متن قطعی
        // نداد. آن‌وقت این تنها متنی است که داریم، و برداشتنش «ادغام» نیست: یک
        // تشخیص است با دو نما، و ما یکی را برمی‌داریم. جایی که متن قطعی آمده باشد،
        // interim اصلا نگاه نمی‌شود.
        if (ev.hasResults && ev.interim.length > bestInterim.length) bestInterim = ev.interim;
        [lock unlock];
    };
    // دلیلِ بسته شدن هم لاگ می‌شود و هم **برمی‌گردد**. لاگ برای آدم است، و برگشتن
    // برای تصمیم: تنها چیزی که «سرور حرفی نشنید» را از «به سرور نرسیدیم» جدا می‌کند
    // همین رشته است، و هر دو حالت متنِ خالی می‌دهند. تا امروز فقط لاگ می‌شد و
    // نتیجه‌اش این بود که یک نفس یا دستی روی میز، که گوگل درست «حرفی نبود» جوابش را
    // می‌داد، همان‌قدر «خرابی» حساب می‌شد که یک ۴۰۳. پایانِ سالم لاگ نمی‌شود (هر تکه
    // یک خط، یعنی نویز)؛ فقط آنچه خراب بوده.
    __block NSString *closedBecause = nil;
    s.onClose = ^(NSString *reason) {
        [lock lock];
        closedBecause = reason;
        [lock unlock];
        if (reason.length && ![reason isEqualToString:@"ok"]) {
            ZLog(@"seg[%@]: اتصال بسته شد: %@", lang, reason);
        }
        dispatch_semaphore_signal(sem);
    };

    [s connect];
    [s feed:pcm];        // اندازه‌گیری‌شده: یک‌جا دادن همان متن را می‌دهد
    [s finishUpload];

    // زهکشی تا بسته شدن اتصال، یا تا وقتی سرور این‌قدر ثانیه هیچ فریمی نفرستد.
    // معیارِ «سکوت فریم» به‌جای «صبر تا بسته شدن»: گاهی سرور اتصال را باز نگه
    // می‌دارد و آنجا معطلی تا ده‌ها ثانیه می‌رفت.
    double sec = pcm.length / kZPcmBytesPerSec;
    NSDate *uploadEnd = NSDate.date;
    NSDate *hard = [NSDate dateWithTimeIntervalSinceNow:kZSegHardWaitSec + sec];
    [lock lock];
    if ([lastEvent compare:uploadEnd] == NSOrderedAscending) lastEvent = uploadEnd;
    [lock unlock];
    while (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW,
                                                      (int64_t)(0.2 * NSEC_PER_SEC)))) {
        [lock lock];
        NSTimeInterval quiet = [NSDate.date timeIntervalSinceDate:lastEvent];
        [lock unlock];
        if (quiet > kZSegQuietWaitSec || [NSDate.date compare:hard] != NSOrderedAscending) {
            [s cancel];
            dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
            break;
        }
    }

    [lock lock];
    NSString *text = finals.count ? [finals componentsJoinedByString:@" "] : bestInterim;
    // «هیچ‌وقت بسته نشد» هم یک دلیل است، نه نبودِ دلیل: خودمان کنسلش کردیم چون سرور
    // ساکت ماند، و آن **قطعا** پایانِ سالم نیست.
    if (why) *why = closedBecause.length ? closedBecause : @"cancelled";
    [lock unlock];
    if (bytesUp) *bytesUp += s.bytesFed;
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

// ---------- خط لوله ----------

@implementation ZPipe {
    NSString *_lang;
    NSMutableData *_buf;
    unsigned long long _bufBase;   // افستِ مطلقِ اولین بایتِ بافر، در سشن
    NSLock *_lock;
    NSInteger _next;            // شماره‌ی تکه‌ی بعدی، فقط برای لاگ
    NSInteger _degraded;
    BOOL _done;
}

- (instancetype)initWithLang:(NSString *)lang {
    if ((self = [super init])) {
        _lang = [lang copy];
        _buf = [NSMutableData data];
        _lock = [NSLock new];
    }
    return self;
}

// چرا این کلاس دیگر نه صفی دارد، نه گروهی، نه متنی: رونویسی رفت به `ZQueue`.
// اینجا فقط بریدن مانده، و همین درست است. یک صف برای کلِ سشن یعنی یک کارگر و یک
// درخواست در پرواز، حتی وقتی پاس دوم روشن است یا وسط سشن زبان عوض شده و دو خط
// لوله زنده‌اند. قبلا هر خط لوله صفِ سریالِ خودش را داشت، یعنی «یکی یکی» فقط داخل
// هر خط لوله درست بود و روی هم دو تا سشن همزمان روی نقطه‌ی رایگان باز می‌شد.
- (NSInteger)degradedCuts {
    [_lock lock];
    NSInteger n = _degraded;
    [_lock unlock];
    return n;
}

- (void)feed:(NSData *)pcm at:(unsigned long long)absByte {
    if (_done || !pcm.length) return;
    [_lock lock];
    // بافر که خالی است، لنگر از نو گرفته می‌شود. همین یک شرط هر سه حالت را می‌پوشاند:
    // شروعِ سشن، خط لوله‌ای که وسط سشن ساخته شده (عوض کردن زبان)، و بعد از دور ریختن.
    if (!_buf.length) _bufBase = absByte;
    [_buf appendData:pcm];
    [_lock unlock];
    [self drain:NO];
}

// ته‌مانده را ببر. دیگر بلوکه نیست و منتظر شبکه نمی‌ماند: انتظارِ متن کارِ صف است
// (`waitForFirstPass`) و آنجا سقف دارد. این تفاوت همان چیزی است که «Esc تا برگشتنِ
// اینترنت هیچ متنی نمی‌دهد» را برمی‌دارد.
- (void)finish {
    if (_done) return;
    _done = YES;
    [self drain:YES];
}

- (void)cancel {
    _done = YES;
    [_lock lock];
    [_buf setLength:0];
    [_lock unlock];
}

// صدای نبریده دور ریخته می‌شود. جاهای رونویسی‌شده مالِ صف‌اند و صف خودش دور
// می‌ریزدشان، یک بار، برای همه‌ی خط لوله‌ها.
- (void)discard {
    [_lock lock];
    [_buf setLength:0];
    [_lock unlock];
}

// هرچه تکه‌ی کامل در بافر هست را بیرون بکش و به صف بده. سر نخِ صدا صدا زده می‌شود،
// پس اینجا فقط بریدن انجام می‌شود.
- (void)drain:(BOOL)eof {
    for (;;) {
        [_lock lock];
        ZSegCut c = ZSegFind(_buf.bytes, _buf.length, eof);
        if (!c.cut) {
            [_lock unlock];
            return;
        }
        NSData *piece = [_buf subdataWithRange:NSMakeRange(0, c.cut)];
        [_buf replaceBytesInRange:NSMakeRange(0, c.cut) withBytes:NULL length:0];
        unsigned long long base = _bufBase;
        _bufBase += c.cut;
        NSInteger idx = _next++;
        if (c.degraded) _degraded++;
        [_lock unlock];

        double sec = c.cut / kZPcmBytesPerSec;
        if (c.degraded) {
            // هیچ‌وقت بی‌صدا سر تایمر نبُر: عددِ بلندی‌ای که به آن رضایت دادیم در
            // لاگ می‌ماند، وگرنه بعدا کسی نمی‌فهمد چرا این مرز وسط یک کلمه افتاد.
            ZLog(@"pipe[%@] %ld: برش تحمیلی، %.1fs، مکثی نبود و rms=%.4f", _lang, (long)idx, sec, c.rms);
        } else if (c.tail) {
            ZLog(@"pipe[%@] %ld: %.1fs، ته‌مانده", _lang, (long)idx, sec);
        } else {
            ZLog(@"pipe[%@] %ld: %.1fs، مکث %.0fms، امتیاز %.2f", _lang, (long)idx, sec,
                 c.quietSec * 1000, c.score);
        }
        // تکه‌ی ساکت اصلا جا نمی‌گیرد: یک رفت‌وبرگشت شبکه صرفه ندارد و سکوتِ محض هم
        // سر هر سشن یک ثانیه معطلی دارد. **ولی** این دیگر آن ادعای قدیمی را نمی‌سازد
        // که «هر چه به شبکه می‌رسد حرف دارد»: آستانه‌اش عمدا کوچک است و نفس هم از آن
        // رد می‌شود. جوابِ خالیِ سرور را حالا صف قضاوت می‌کند، نه این شرط.
        if (!ZSegHasVoice(piece)) {
            ZLog(@"pipe[%@] %ld: سکوت، رد شد", _lang, (long)idx);
            if (c.tail) return;
            continue;
        }
        [self.queue add:piece lang:_lang extra:self.extra
                  frame:base / 2 frames:c.cut / 2];   // s16le مونو: دو بایت، یک فریم
        if (c.tail) return;
    }
}

@end
