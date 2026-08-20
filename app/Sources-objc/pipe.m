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
// و یک استثنا که خودش قاعده است: تکه‌ای که بی‌متن برگشت **جای خودش را نگه می‌دارد**
// (ZHoleMark). چسباندنِ ساده اگر تکه‌ی گم‌شده را رد کند، سوراخ را می‌دوزد و حرفِ
// گم‌شده هیچ ردی نمی‌گذارد؛ همان چیزی که پایین‌تر سر «جای خالی» شرحش هست.
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

// ---------- جای خالی ----------
// شرحِ کامل سر zemzeme.h. کوتاهش: تکه‌ی بی‌صدا پیش از شبکه رد می‌شود، پس متنِ خالی
// **همیشه** شکست است. جای شکست در متن با یک نشانه می‌ماند تا ترتیب نشکند، و صدایش
// نگه داشته می‌شود تا سر Esc یک بار دیگر برود.
NSString *const ZHoleMark = @"⟨جامانده⟩";

@implementation ZHole
- (instancetype)initWithPCM:(NSData *)pcm lang:(NSString *)lang {
    if ((self = [super init])) {
        _pcm = pcm;
        _lang = [lang copy];
    }
    return self;
}
@end

// nامین نشانه را با متن عوض کن (شمارش از صفر). نشانه‌ای که نبود، هیچ کاری نمی‌کند.
static void ZFillHoleAt(NSMutableString *s, NSUInteger nth, NSString *fill) {
    NSRange scan = NSMakeRange(0, s.length);
    for (NSUInteger k = 0; ; k++) {
        NSRange r = [s rangeOfString:ZHoleMark options:0 range:scan];
        if (r.location == NSNotFound) return;
        if (k == nth) {
            [s replaceCharactersInRange:r withString:fill];
            return;
        }
        scan = NSMakeRange(NSMaxRange(r), s.length - NSMaxRange(r));
    }
}

NSInteger ZRetryHoles(NSMutableArray<ZHole *> *holes, NSArray<NSMutableString *> *texts) {
    NSUInteger i = 0;
    while (i < holes.count) {
        ZHole *h = holes[i];
        NSString *t = ZTranscribeSegment(h.pcm, h.lang, NO, NULL, NULL);
        if (!t.length) {
            // هنوز نه. نشانه‌اش سر جایش می‌ماند و صدایش هم، پس Esc بعدی فقط یک
            // تلاشِ دیگر است. اینجا نه صبر می‌شود نه probe: **آدم** تصمیم می‌گیرد
            // اینترنت کِی برگشته، نه یک حلقه‌ی حدس‌زن.
            i++;
            continue;
        }
        // iامین نشانه، نه اولین: اگر جای خالیِ قبلی هنوز پر نشده باشد، متنِ این یکی
        // حق ندارد جای آن بنشیند و ترتیب را جابه‌جا کند.
        for (NSMutableString *s in texts) ZFillHoleAt(s, i, t);
        [holes removeObjectAtIndex:i];
    }
    return (NSInteger)holes.count;
}

// ---------- خط لوله ----------

@implementation ZPipe {
    NSString *_lang;
    NSMutableData *_buf;
    NSMutableArray<NSString *> *_parts;
    NSLock *_lock;
    dispatch_queue_t _q;        // سریال: ترتیب تکه‌ها همین‌جا تضمین می‌شود
    dispatch_group_t _group;
    NSInteger _next;            // شماره‌ی تکه‌ی بعدی، فقط برای لاگ
    // نوبتِ متن. `discard` یکی جلو می‌بردش و تکه‌هایی که با نوبتِ قبلی رفته‌اند
    // متنشان را دور می‌ریزند. بی این، دور ریختن فقط چیزی را پاک می‌کرد که **رسیده**
    // بود و تکه‌ی در راه دو ثانیه بعد بی‌صدا برمی‌گشت.
    NSInteger _epoch;
    NSInteger _degraded;
    NSInteger _holes;
    // چند تکه‌ی **پشت سر هم** بی‌متن برگشته‌اند. یکی می‌تواند بدشانسی باشد؛ دوتای پشت
    // سر هم یعنی راهِ شبکه بسته است، چون تکه‌ی بی‌صدا اصلا به شبکه نمی‌رسد.
    NSInteger _streak;
    BOOL _done;
    unsigned long long _bytesUp;
}

- (instancetype)initWithLang:(NSString *)lang {
    if ((self = [super init])) {
        _lang = [lang copy];
        _buf = [NSMutableData data];
        _parts = [NSMutableArray array];
        _lock = [NSLock new];
        _group = dispatch_group_create();
        // سریال و نه موازی: «تکه‌ها به ترتیب رونویسی و به ترتیب اضافه می‌شوند، یک
        // صف نه یک ادغام». موازی کردن هم وسوسه‌انگیز بود و هم بی‌فایده: تکه‌ی هفت
        // ثانیه‌ای در ~۲ ثانیه رونویسی می‌شود، پس صف هیچ‌وقت از گوینده عقب نمی‌ماند.
        // در عوض یک سشنِ همزمان یعنی نصف کردنِ ریسکِ «لال شدنِ» نقطه‌ی رایگان.
        _q = dispatch_queue_create("io.seyed.zemzeme.pipe", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSString *)text {
    [_lock lock];
    NSString *t = [_parts componentsJoinedByString:@" "];
    [_lock unlock];
    return t;
}

- (NSInteger)degradedCuts {
    [_lock lock];
    NSInteger n = _degraded;
    [_lock unlock];
    return n;
}

- (NSInteger)holes {
    [_lock lock];
    NSInteger n = _holes;
    [_lock unlock];
    return n;
}

- (unsigned long long)bytesUp {
    [_lock lock];
    unsigned long long n = _bytesUp;
    [_lock unlock];
    return n;
}

- (void)feed:(NSData *)pcm {
    if (_done || !pcm.length) return;
    [_lock lock];
    [_buf appendData:pcm];
    [_lock unlock];
    [self drain:NO];
}

// ته‌مانده را ببر و صف را خالی کن. بلوکه است تا آخرین تکه هم متنش برسد: فراخوان
// دقیقا همین را می‌خواهد، چون کاربر دستش روی کلید پایان است و منتظر متن.
- (void)finish {
    if (_done) return;
    _done = YES;
    [self drain:YES];
    dispatch_group_wait(_group, DISPATCH_TIME_FOREVER);
}

- (void)cancel {
    _done = YES;
    [_lock lock];
    [_buf setLength:0];
    [_lock unlock];
}

// سطل آشغال، و «همه‌چیز» یعنی هر سه جایی که متن می‌تواند قایم شود: تکه‌های
// رونویسی‌شده، صدای نبریده‌ی داخل بافر، و تکه‌هایی که همین حالا روی صف‌اند.
//
// آن سومی نکته‌ی اصلی است و باگ از همان‌جا می‌آمد: تکه‌ای که یک ثانیه پیش فرستاده شده
// دو ثانیه بعد متنش می‌رسد و بی‌صدا به `_parts` اضافه می‌شود. پس دور ریختن اگر فقط
// پاک کردنِ اینجا و الان باشد، حرفِ دورریخته چند ثانیه بعد خودش برمی‌گردد.
//
// برخلاف `cancel` این خط لوله را نمی‌کشد: کاربر «از صفر» خواسته، نه «تمامش کن».
- (void)discard {
    [_lock lock];
    NSUInteger had = _parts.count;
    [_parts removeAllObjects];
    [_buf setLength:0];
    // نشانه‌های جای خالی هم رفتند، پس شمارش هم از صفر: متنی که این‌ها به آن اشاره
    // می‌کردند دیگر وجود ندارد.
    _holes = 0;
    _streak = 0;
    _epoch++;
    [_lock unlock];
    ZLog(@"pipe[%@]: دور ریخته شد، %lu تکه‌ی متن و بافر خالی شد", _lang, (unsigned long)had);
}

// هرچه تکه‌ی کامل در بافر هست را بیرون بکش و بفرست. سر نخِ صدا صدا زده می‌شود، پس
// اینجا فقط بریدن انجام می‌شود و رونویسی می‌رود روی صف.
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
        NSInteger idx = _next++;
        NSInteger epoch = _epoch;    // زیر همین قفل، وگرنه تکه با نوبتِ بعدی برچسب می‌خورد
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
        [self run:piece index:idx epoch:epoch];
        if (c.tail) return;
    }
}

- (BOOL)stale:(NSInteger)epoch {
    [_lock lock];
    BOOL old = epoch != _epoch;
    [_lock unlock];
    return old;
}

- (void)run:(NSData *)pcm index:(NSInteger)idx epoch:(NSInteger)epoch {
    dispatch_group_async(_group, _q, ^{
        if (!ZSegHasVoice(pcm)) {
            ZLog(@"pipe[%@] %ld: سکوت، رد شد", self->_lang, (long)idx);
            return;    // یک رفت‌وبرگشت شبکه صرفه ندارد
        }
        // پیش از شبکه، نه بعدش: صدای دورریخته اصلا لازم نیست رونویسی شود. صف سریال
        // است، پس تکه‌های پشتِ سطل آشغال همه همین‌جا و ارزان می‌افتند.
        if ([self stale:epoch]) {
            ZLog(@"pipe[%@] %ld: دور ریخته شده بود، فرستاده نشد", self->_lang, (long)idx);
            return;
        }
        unsigned long long up = 0;
        NSString *t = ZTranscribeSegment(pcm, self->_lang, NO, &up, NULL);
        // یک تلاش دوباره، بی‌مکث و فقط برای همین یک حالت: تکه حرف داشت و سشن هیچ
        // متنی نداد. نقطه‌ی رایگان گاهی «لال» جواب می‌دهد و آن‌وقت یک بلوکِ هفت
        // ثانیه‌ای کامل گم می‌شود، یعنی دقیقا همان خرابی‌ای که نسخه دو برای رفعش
        // نوشته شده. مکث ندارد چون کاربر منتظر است؛ بیشتر از یکی هم نه.
        if (!t.length) {
            ZLog(@"pipe[%@] %ld: سشن لال، یک بار دیگر", self->_lang, (long)idx);
            t = ZTranscribeSegment(pcm, self->_lang, NO, &up, NULL);
        }
        [self->_lock lock];
        // بایت‌ها را هرجور که شد بشمار: واقعا روی سیم رفته‌اند و این شمارنده‌ی شبکه
        // است نه دفترِ متن. ولی متن، فقط اگر نوبتش هنوز همان باشد.
        self->_bytesUp += up;
        BOOL stale = epoch != self->_epoch;
        BOOL hole = NO, lost = NO;
        if (!stale) {
            if (t.length) {
                [self->_parts addObject:t];
                self->_streak = 0;
            } else {
                // **نشانه، نه حذف.** تا امروز این تکه از `_parts` می‌افتاد و بقیه به
                // هم می‌چسبیدند، پس یک جمله‌ی گم‌شده هیچ ردی نمی‌گذاشت: نه در متن، نه
                // برای کاربر، نه در لاگ. حالا جایش سر جای خودش می‌ماند تا هم ترتیب
                // نشکند و هم بشود بعدا دقیقا همان‌جا پرش کرد.
                [self->_parts addObject:ZHoleMark];
                self->_holes++;
                self->_streak++;
                hole = YES;
                lost = self->_streak >= 2;
            }
        }
        [self->_lock unlock];
        if (stale) {
            // وسط رفت‌وبرگشت شبکه، کاربر دور ریخت. این متن مالِ صدایی است که دیگر
            // وجود ندارد، پس نه در متن می‌نشیند نه به پیش‌نمایش خبر می‌دهد.
            ZLog(@"pipe[%@] %ld: متن رسید ولی دور ریخته شده بود، انداخته شد", self->_lang, (long)idx);
            return;
        }
        if (hole) {
            ZLog(@"pipe[%@] %ld: حرف داشت و بی‌متن برگشت، جایش علامت خورد (%ld جای خالی)",
                 self->_lang, (long)idx, (long)self.holes);
            // صدا با خودش می‌رود بیرون: تنها کسی که می‌داند متن کجا نشسته و سر Esc
            // باید کجا وصله شود، مصرف‌کننده است، نه خط لوله.
            if (self.onHole) self.onHole([[ZHole alloc] initWithPCM:pcm lang:self->_lang]);
            if (lost) {
                ZLog(@"pipe[%@]: دو تکه‌ی پشت سر هم بی‌متن برگشت", self->_lang);
                if (self.onLost) self.onLost();
            }
            return;
        }
        ZLog(@"pipe[%@] %ld ← %lu نویسه", self->_lang, (long)idx, (unsigned long)t.length);
        if (self.onPart) self.onPart(t);
    });
}

@end
