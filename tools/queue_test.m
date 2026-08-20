// تستِ طلاییِ صف. یک باگِ واقعی را قفل می‌کند، و باگ از آن جنسی بود که کاربر
// مستقیم می‌دید: تکه‌ای که متنش خالی برمی‌گشت **همیشه** شکست حساب می‌شد، جایش یک
// ⟨جامانده⟩ی همیشگی در متن می‌ماند، و تا پر نشدنش هیچ متنی تحویل نمی‌شد. ولی متنِ
// خالی همیشه شکست نیست: `ZSegHasVoice` انرژی می‌سنجد نه حرف و آستانه‌اش عمدا کوچک
// است (پچ‌پچ باید رد شود)، پس یک نفس هم از آن رد می‌شود و به شبکه می‌رسد. گوگل درست
// جواب می‌دهد «حرفی نبود» و خط را **تمیز** می‌بندد. ۲۰۲۶-۰۸-۱۹ یک تکه‌ی ۱٫۴ ثانیه‌ای
// از همین جنس ۱۷۴۱ نویسه را گروگان گرفت و آخرش چهار دقیقه دیکته دور ریخته شد.
//
// جداکننده، دلیلِ بسته شدنِ اتصال است: `ok` با متنِ خالی یعنی «شنید و حرفی نبود»
// (تکه تمام است)، هر چیز دیگری یعنی «جواب نگرفتیم» (باید دوباره رفت).
//
// چرا این تست نه شبکه می‌خواهد نه میکروفن: خودِ `pipe.m` و `queue.m` کامپایل می‌شوند
// (همان کدی که در محصول می‌دود) و فقط `ZGoogleStream` یک بدلِ چند خطی است که جوابش
// از یک فیلم‌نامه می‌آید. پس مسیرِ واقعیِ تصمیم زیر تست است، نه ادای آن.
#import "zemzeme.h"

static int failures = 0;

static void ok(BOOL cond, const char *what) {
    printf("%s %s\n", cond ? "ok  " : "FAIL", what);
    if (!cond) failures++;
}

static void okEq(NSString *got, NSString *want, const char *what) {
    BOOL same = [got isEqualToString:want];
    printf("%s %s\n", same ? "ok  " : "FAIL", what);
    if (!same) {
        printf("     خواستیم: %s\n     گرفتیم:  %s\n", want.UTF8String, got.UTF8String);
        failures++;
    }
}

// core.m این را از audio.m می‌خواهد و تست میکروفن ندارد
void ZMicSetHighSensitivity(BOOL on) { (void)on; }

// ---------- بدلِ شبکه ----------
// فیلم‌نامه: هر تماس یک جفتِ (متن، دلیلِ بسته شدن). همین جفت است که تست را ممکن
// می‌کند، چون تمامِ تصمیمِ تازه روی همین دو تا سوار است.
//
// و دو شمارنده که خودشان ادعا هستند: تعدادِ کلِ تماس‌ها (نظرِ دوم باید دقیقا یکی
// باشد، نه صفر و نه نردبان) و بیشترین تماسِ **همزمان** (باید همیشه یک بماند، حتی
// وقتی دو خط لوله به یک صف می‌ریزند: نقطه‌ی رایگان جای فن‌اوت نیست).
static NSMutableArray<NSArray<NSString *> *> *gScript;
static NSInteger gCalls, gLive, gMaxLive;
static NSLock *gLock;

static void ZTestScript(NSArray<NSArray<NSString *> *> *lines) {
    if (!gLock) gLock = [NSLock new];
    gScript = [lines mutableCopy];
    gCalls = gLive = gMaxLive = 0;
}

static NSArray<NSString *> *ZTestReply(void) {
    [gLock lock];
    gCalls++;
    NSArray<NSString *> *r = gScript.count ? gScript.firstObject : @[@"", @"ok"];
    if (gScript.count) [gScript removeObjectAtIndex:0];
    [gLock unlock];
    return r;
}

@implementation ZGoogleStream {
    NSString *_lang;
    NSUInteger _fed;
    BOOL _closed;
}
- (instancetype)initWithLang:(NSString *)lang {
    if ((self = [super init])) _lang = [lang copy];
    return self;
}
- (void)connect {
    [gLock lock];
    gLive++;
    if (gLive > gMaxLive) gMaxLive = gLive;
    [gLock unlock];
}
- (void)feed:(NSData *)pcm { _fed += pcm.length; }
- (void)finishUpload {
    _bytesFed = _fed;
    NSArray<NSString *> *reply = ZTestReply();
    // آسنکرون، چون مسیر واقعی هم همین است: `ZTranscribeSegment` روی سمافور می‌نشیند
    // و فقط با `onClose` بلند می‌شود. اگر اینجا همه‌چیز همان‌جا صدا زده شود، آن
    // انتظار اصلا امتحان نمی‌شود.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        if (reply[0].length && self.onEvent) {
            ZSpeechEvent *ev = [ZSpeechEvent new];
            ev.hasResults = YES;
            ev.finals = [NSMutableArray arrayWithObject:reply[0]];
            self.onEvent(ev);
        }
        [self close:reply[1]];
    });
}
- (void)cancel { [self close:@"cancelled"]; }
- (void)close:(NSString *)reason {
    if (_closed) return;
    _closed = YES;
    [gLock lock];
    gLive--;
    [gLock unlock];
    if (self.onClose) self.onClose(reason);
}
@end

// ---------- صدای ساختگی ----------
// موجِ مربعیِ ±۶۰۰۰ یعنی rms ≈ ۰٫۱۸، خیلی بالای هر دو آستانه؛ و سکوت واقعا صفر است.
static void ZTestTone(NSMutableData *d, double sec) {
    NSUInteger n = (NSUInteger)(sec * 16000);
    int16_t *p = malloc(n * 2);
    for (NSUInteger i = 0; i < n; i++) p[i] = (i % 2) ? 6000 : -6000;
    [d appendBytes:p length:n * 2];
    free(p);
}

static void ZTestHush(NSMutableData *d, double sec) {
    [d increaseLengthBy:(NSUInteger)(sec * 16000) * 2];
}

// سه تکه‌ی حرف‌دار: ۶٫۶ ثانیه حرف و ۰٫۴ ثانیه مکث، سه بار. خط لوله دو بار وسط راه
// می‌بُرد و سومی سر `finish` ته‌مانده می‌رود، پس دقیقا سه تکه به «شبکه» می‌رسد.
static NSData *ZTestThreePieces(void) {
    NSMutableData *d = [NSMutableData data];
    for (int i = 0; i < 3; i++) {
        ZTestTone(d, 6.6);
        ZTestHush(d, 0.4);
    }
    return d;
}

// یک دورِ کامل: صدا از همان دانه‌بندیِ ۱۰۰ میلی‌ثانیه‌ایِ موتور رد می‌شود، بعد
// ته‌مانده بریده می‌شود، بعد دقیقا همان‌قدر صبر می‌کنیم که موتور صبر می‌کند: تا
// دورِ اول، نه تا خالی شدنِ صف.
static ZQueue *ZTestRun(NSArray<NSArray<NSString *> *> *script, BOOL secondPass) {
    ZTestScript(script);
    ZQueue *q = [ZQueue new];
    ZPipe *fa = [[ZPipe alloc] initWithLang:@"fa-IR"];
    fa.queue = q;
    ZPipe *en = nil;
    if (secondPass) {
        en = [[ZPipe alloc] initWithLang:@"en-US"];
        en.queue = q;
        en.extra = YES;
    }
    NSData *audio = ZTestThreePieces();
    const NSUInteger step = 3200;
    for (NSUInteger off = 0; off < audio.length; off += step) {
        NSData *c = [audio subdataWithRange:NSMakeRange(off, MIN(step, audio.length - off))];
        [fa feed:c at:off];
        [en feed:c at:off];
    }
    [fa finish];
    [en finish];
    [q waitForFirstPass];
    return q;
}

// تا خالی شدنِ صف صبر کن، ولی نه بی‌سقف: انتظارِ بی‌سقف در این ریپو ممنوع است.
static BOOL ZTestSettle(ZQueue *q, double ceiling) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:ceiling];
    while (q.waiting && [NSDate.date compare:end] == NSOrderedAscending) usleep(20000);
    return q.waiting == 0;
}

static NSString *ZTestSrc(NSString *name) {
    NSString *s = [NSString stringWithContentsOfFile:
                   [@"app/Sources-objc/" stringByAppendingString:name]
                                            encoding:NSUTF8StringEncoding error:nil];
    return s ?: @"";
}

int main(void) { @autoreleasepool {
    // ---------- ۱: پله‌های عقب‌نشینی ----------
    // تابعِ خالص، پس مستقیم. یک ساعت برای کلِ صف، نه یکی برای هر تکه: خرابی مالِ
    // شبکه است و ده تکه‌ی در انتظار یعنی ده برابر تلاشِ بی‌فایده روی همان خطِ قطع.
    ok(ZBackoffDelay(0) == 1 && ZBackoffDelay(1) == 2 && ZBackoffDelay(2) == 4 &&
       ZBackoffDelay(3) == 8 && ZBackoffDelay(4) == 15 && ZBackoffDelay(5) == 30,
       "پله‌ها ۱، ۲، ۴، ۸، ۱۵، ۳۰");
    ok(ZBackoffDelay(6) == 30 && ZBackoffDelay(99) == 30, "سقف سی ثانیه");

    // ---------- ۲: تکه‌ی بی‌حرف چیزی را گرو نمی‌گیرد ----------
    // همان تکه‌ی ۱٫۴ ثانیه‌ایِ نفس: از آستانه‌ی انرژی رد می‌شود، به شبکه می‌رسد، و
    // سرور تمیز جواب می‌دهد که حرفی نبود. باید **تمام** شمرده شود، نه سوراخ.
    {
        ZQueue *q = ZTestRun(@[@[@"یک", @"ok"], @[@"", @"ok"], @[@"", @"ok"], @[@"سه", @"ok"]], NO);
        okEq(q.text, @"یک سه", "تکه‌ی بی‌حرف هیچ نمی‌گذارد و متن سرِ خودش می‌آید");
        ok(q.waiting == 0, "هیچ چیز در انتظار نمی‌ماند");
        ok(q.drained, "صف خالی است، پس تحویل و پاسِ تمیزکاری آزادند");
        okEq([q settledTextFrom:0], @"یک سه", "همه‌ی متن حق دارد سر کرسر برود");
        ok(gCalls == 4, "نظرِ دوم دقیقا یک تلاشِ اضافه بود، نه بیشتر");
    }

    // ---------- ۳: نرسیدن، شکست است و دوباره می‌رود ----------
    // همان متنِ خالی، ولی این بار خط اصلا بسته نشد. یعنی جوابی نگرفتیم، نه اینکه
    // جواب «هیچ» بود. و تفاوتِ این دو تنها چیزی است که این تست نگهبانش است.
    //
    // دو بلوک، چون دو ادعای جدا هستند و اگر یکی شوند تست به ساعت گره می‌خورد: حالِ
    // «وسط قطعی» فقط تا رسیدنِ تلاشِ بعدی دوام دارد.
    {
        NSMutableArray *script = [@[@[@"یک", @"ok"],
                                    @[@"", @"err -1009 offline"], @[@"", @"err -1009 offline"],
                                    @[@"سه", @"ok"]] mutableCopy];
        for (int i = 0; i < 12; i++) [script addObject:@[@"", @"err -1009 offline"]];
        ZQueue *q = ZTestRun(script, NO);
        ok(q.waiting == 1, "تکه‌ی نرسیده در انتظار می‌ماند");
        okEq(q.text, @"یک سه", "بقیه‌ی متن گروگان نمی‌ماند و همان لحظه حاضر است");
        okEq([q settledTextFrom:0], @"یک",
             "سر کرسر فقط تا اولین جای نرسیده می‌رود، وگرنه ترتیب به هم می‌خورد");
        [q stop];
    }
    {
        ZQueue *q = ZTestRun(@[@[@"یک", @"ok"],
                               @[@"", @"err -1009 offline"], @[@"", @"err -1009 offline"],
                               @[@"سه", @"ok"],
                               @[@"دو", @"ok"]], NO);
        ok(ZTestSettle(q, 5), "خودش، بی هیچ کلیدی، دوباره رفت و رسید");
        okEq(q.text, @"یک دو سه", "تکه‌ی دیررس سر جای ساختاریِ خودش نشست");
        okEq([q settledTextFrom:0], @"یک دو سه", "و حالا همه‌ی متن قطعی است");
        ok(gCalls == 5, "تلاشِ دوباره یکی بود؛ نظرِ دوم یک بار در عمرِ هر تکه خرج می‌شود");
    }

    // ---------- ۴: هیچ‌وقت بیشتر از یک درخواست در پرواز ----------
    // دو خط لوله (فارسی و پاس دومِ انگلیسی) روی یک صف. تا دیروز هر خط لوله صفِ
    // سریالِ خودش را داشت، یعنی «یکی یکی» فقط داخل هر کدام درست بود و روی هم دو
    // سشنِ همزمان روی نقطه‌ی رایگان باز می‌شد.
    {
        ZQueue *q = ZTestRun(@[], YES);
        ok(gMaxLive == 1, "همیشه یک درخواست در پرواز، حتی با پاس دوم");
        ok(gCalls >= 6, "هر شش تکه (سه اصلی و سه پاس دوم) رفتند");
        ok(q.waiting == 0, "جای پاس دوم هیچ‌وقت در انتظار نمی‌ماند");
    }

    // ---------- ۵: پاس دوم سرِ قطعی دوباره نمی‌رود ----------
    // متنش تحویل کاربر نمی‌شود (فقط کانتکستِ پاس هوش مصنوعی است)، پس تلاشِ دوباره‌اش
    // فقط خرج کردنِ همان خطِ نازکی است که تکه‌های اصلی به آن احتیاج دارند.
    {
        ZTestScript(@[]);
        ZQueue *q = [ZQueue new];
        ZPipe *en = [[ZPipe alloc] initWithLang:@"en-US"];
        en.queue = q;
        en.extra = YES;
        NSData *audio = ZTestThreePieces();
        ZTestScript(@[@[@"", @"err -1009 offline"], @[@"", @"err -1009 offline"]]);
        [en feed:audio at:0];
        [en finish];
        [q waitForFirstPass];
        ok(q.waiting == 0, "قطعیِ پاس دوم هیچ‌کس را منتظر نمی‌گذارد");
        okEq(q.text, @"", "و در متنِ تحویل هم هیچ سهمی ندارد");
    }

    // ---------- ۶: هر جا می‌داند صدایش کجای فایل است ----------
    // تکه نسخه‌ی جداگانه‌ای از صدای خودش ندارد: audio.flac همه‌ی نمونه‌ها را از قبل
    // دارد و جا فقط یک افست و یک طول است. عددها باید **پشت سر هم** باشند و رویِ هم
    // کلِ صدا را بپوشانند، وگرنه تکه‌ای که بعدا از فایل خوانده شود صدای همسایه‌اش را
    // می‌گیرد و آدم متنی می‌بیند که هیچ‌وقت نگفته.
    {
        ZQueue *q = ZTestRun(@[@[@"یک", @"ok"], @[@"دو", @"ok"], @[@"سه", @"ok"]], NO);
        NSArray<ZSlot *> *sl = q.snapshot;
        ok(sl.count == 3, "سه جا ساخته شد");
        BOOL chained = sl.count == 3;
        unsigned long long want = 0;
        for (ZSlot *x in sl) {
            if (x.frame != want || x.frames == 0) chained = NO;
            want = x.frame + x.frames;
        }
        ok(chained, "افست‌ها پشت سر هم‌اند و هیچ فریمی جا نمی‌افتد");
        ok(want == ZTestThreePieces().length / 2, "و رویِ هم دقیقا همان صدای ورودی‌اند");
    }

    // ---------- ۷: دور ریختن، حرفِ دورریخته را برنمی‌گرداند ----------
    {
        ZQueue *q = ZTestRun(@[@[@"یک", @"ok"], @[@"دو", @"ok"], @[@"سه", @"ok"]], NO);
        okEq(q.text, @"یک دو سه", "متن پیش از دور ریختن");
        [q discard];
        okEq(q.text, @"", "و بعدش هیچ");
        ok(q.nextSeq == 0, "شمارشِ جاها هم از صفر");
    }

    // ---------- ۸: همان بازه، از خودِ audio.flac ----------
    // مسیرِ واقعی و کامل: پی‌سی‌امِ شناخته‌شده با همان ضبط‌کننده‌ی محصول روی دیسک
    // می‌رود و بعد یک بازه‌ی وسطش پس گرفته می‌شود. موجِ ورودی عمدا **نردبانی** است نه
    // مربعی: با موج مربعی هر افستی شبیه هر افست دیگری است و یک اشتباهِ یک فریمی
    // هیچ‌وقت دیده نمی‌شود.
    {
        const NSUInteger n = 16000 * 3;
        NSMutableData *pcm = [NSMutableData dataWithLength:n * 2];
        int16_t *p = pcm.mutableBytes;
        for (NSUInteger i = 0; i < n; i++) p[i] = (int16_t)((i * 37) % 20000 - 10000);

        NSURL *dir = [NSURL fileURLWithPath:NSTemporaryDirectory()];
        NSURL *flac = [dir URLByAppendingPathComponent:@"zemzeme-range-test.flac"];
        [NSFileManager.defaultManager removeItemAtURL:flac error:nil];
        ZRecorder *rec = [[ZRecorder alloc] initWithURL:flac];
        [rec feed:pcm];
        [rec finish];
        ok(rec.url != nil, "صدا روی دیسک نشست");

        // و یک دورِ دوم روی همان فایل. تا امروز `finish` ضبط را برای همیشه می‌بست و
        // صدای دورِ دوم هیچ‌جا نمی‌رفت؛ حالا که تکه با افستِ همین فایل شناخته می‌شود،
        // آن سکوت یعنی تکه‌ی دورِ دوم صدای دورِ اول را پس می‌گیرد.
        unsigned long long round2 = rec.pcmBytes / 2;
        NSMutableData *more = [NSMutableData dataWithLength:16000 * 2 * 2];
        int16_t *q2 = more.mutableBytes;
        for (NSUInteger i = 0; i < 16000 * 2; i++) q2[i] = (int16_t)(9000 - (i * 11) % 18000);
        [rec feed:more];
        [rec finish];

        NSError *e = nil;
        NSData *back = ZDecodePCMRange(rec.url, 16000, 8000, &e);
        ok(back.length == 8000 * 2, "بازه به همان طولِ خواسته‌شده برگشت");
        ok(back && memcmp(back.bytes, (const uint8_t *)pcm.bytes + 32000, back.length) == 0,
           "و بایت به بایت همان صدایی است که آن‌جای فایل گفته شده");
        ok(ZDecodePCMRange(rec.url, 16000 * 99, 8000, NULL) == nil,
           "افستِ بیرون از فایل خطا می‌دهد، نه صدای کسِ دیگر");
        NSData *two = ZDecodePCMRange(rec.url, round2 + 8000, 8000, NULL);
        ok(two.length == 8000 * 2 &&
           memcmp(two.bytes, (const uint8_t *)more.bytes + 16000, two.length) == 0,
           "دورِ دومِ همان سشن هم روی همان فایل نشست و سر جای خودش پیدا می‌شود");
        [NSFileManager.defaultManager removeItemAtURL:flac error:nil];
    }

    // ---------- ۹: دفترچه، تا تکه از بسته شدنِ اپ جان سالم ببرد ----------
    // صف **خوابانده** می‌شود و بعد دفترچه خوانده: وگرنه تلاشِ دوباره‌ی یک ثانیه بعد
    // می‌تواند وسط خواندن برسد و فایل را پاک کند، و تست به ساعت گره بخورد.
    {
        NSURL *dir = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                      URLByAppendingPathComponent:@"zemzeme-manifest-test"];
        NSFileManager *fm = NSFileManager.defaultManager;
        [fm removeItemAtURL:dir error:nil];
        [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *man = ZQueueManifestIn(dir);

        // قطعیِ **ادامه‌دار**: هر تلاشی که برسد هم نمی‌رسد. وگرنه تست به ساعت گره
        // می‌خورد؛ روی ماشینِ شلوغ تلاشِ یک ثانیه بعد از خواندنِ دفترچه جلو می‌زد،
        // تکه می‌رسید و فایل درست پیش از خوانده شدن پاک می‌شد.
        NSMutableArray *script = [@[@[@"یک", @"ok"],
                                    @[@"", @"err -1009 offline"], @[@"", @"err -1009 offline"],
                                    @[@"سه", @"ok"]] mutableCopy];
        for (int i = 0; i < 12; i++) [script addObject:@[@"", @"err -1009 offline"]];
        ZTestScript(script);
        ZQueue *q = [ZQueue new];
        q.manifest = man;
        q.audio = [dir URLByAppendingPathComponent:@"audio.flac"];
        q.lang = @"fa-IR";
        ZPipe *fa = [[ZPipe alloc] initWithLang:@"fa-IR"];
        fa.queue = q;
        NSData *audio = ZTestThreePieces();
        const NSUInteger step = 3200;
        for (NSUInteger off = 0; off < audio.length; off += step) {
            [fa feed:[audio subdataWithRange:NSMakeRange(off, MIN(step, audio.length - off))]
                   at:off];
        }
        [fa finish];
        [q waitForFirstPass];
        // نوشتن آسنکرون است (نخ صدا حق ندارد منتظر دیسک بماند)، پس یک مهلت کوتاه
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:3];
        NSDictionary *doc = nil;
        while ([NSDate.date compare:until] == NSOrderedAscending) {
            NSData *raw = [NSData dataWithContentsOfURL:man];
            doc = raw ? [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil] : nil;
            if ([doc[@"slots"] count] == 3) break;
            usleep(20000);
        }
        ok([doc[@"slots"] count] == 3, "هر سه جا در دفترچه‌اند، نه فقط آنکه نرسیده");
        ok([doc[@"slots"][1][@"state"] integerValue] == ZSlotWaiting &&
           [doc[@"slots"][1][@"frames"] unsignedLongLongValue] > 0,
           "جای نرسیده با افست و طولِ خودش نوشته شده، بی هیچ صدایی");
        okEq(doc[@"slots"][0][@"text"], @"یک", "و متنی که رسیده هم، تا لانچِ بعدی از نو نفرستدش");
        okEq(doc[@"audio"], q.audio.path, "و مسیر صدا، چون تکه صدای خودش را ندارد");
        [q stop];    // وگرنه تلاش‌های بعدی فیلم‌نامه‌ی بلوکِ بعدی را می‌خورند
        [fm removeItemAtURL:dir error:nil];
    }

    // ---------- ۱۰: دفترچه‌ی مانده، بدتر از دفترچه‌ی نبوده ----------
    // چیزی در انتظار نماند یعنی این سشن تمام است. فایلی که بماند، لانچِ بعدی سشنِ
    // تمام‌شده را دوباره برمی‌دارد.
    {
        NSURL *dir = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                      URLByAppendingPathComponent:@"zemzeme-manifest-done"];
        NSFileManager *fm = NSFileManager.defaultManager;
        [fm removeItemAtURL:dir error:nil];
        [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *man = ZQueueManifestIn(dir);

        ZTestScript(@[@[@"یک", @"ok"],
                      @[@"", @"err -1009 offline"], @[@"", @"err -1009 offline"],
                      @[@"سه", @"ok"], @[@"دو", @"ok"]]);
        ZQueue *q = [ZQueue new];
        q.manifest = man;
        q.audio = [dir URLByAppendingPathComponent:@"audio.flac"];
        ZPipe *fa = [[ZPipe alloc] initWithLang:@"fa-IR"];
        fa.queue = q;
        [fa feed:ZTestThreePieces() at:0];
        [fa finish];
        [q waitForFirstPass];
        ok(ZTestSettle(q, 5), "تکه‌ی جامانده خودش رسید");
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:3];
        while ([fm fileExistsAtPath:man.path] && [NSDate.date compare:until] == NSOrderedAscending)
            usleep(20000);
        ok(![fm fileExistsAtPath:man.path], "چیزی در انتظار نماند، پس دفترچه هم رفت");
        [fm removeItemAtURL:dir error:nil];
    }

    // ---------- قاعده‌های ریشه‌ای، روی خودِ سورس ----------
    NSString *pip = ZTestSrc(@"pipe.m"), *que = ZTestSrc(@"queue.m");
    NSString *eng = ZTestSrc(@"engine.m"), *ses = ZTestSrc(@"session.m");
    ok(pip.length && que.length && eng.length && ses.length, "سورس‌ها خوانده شدند");

    // دلیلِ بسته شدن باید **برگردد**، نه فقط لاگ شود. اگر این برگردد به لاگِ تنها،
    // «حرفی نبود» و «نرسیدیم» دوباره یک شکل می‌شوند و باگِ اصلی برمی‌گردد.
    ok([pip containsString:@"if (why) *why = closedBecause.length ? closedBecause : @\"cancelled\";"],
       "دلیلِ بسته شدنِ اتصال از ZTranscribeSegment برمی‌گردد");
    ok([que containsString:@"ZCloseWasClean(why)"],
       "صف روی همان دلیل تصمیم می‌گیرد، نه روی خالی بودنِ متن");

    // نشانه‌ی ⟨جامانده⟩ و جراحیِ رشته باید رفته باشند: ترتیب حالا ساختاری است.
    for (NSString *gone in @[@"ZHoleMark", @"ZFillHoleAt", @"ZRetryHoles", @"retryHoles"]) {
        ok(![pip containsString:gone] && ![eng containsString:gone] && ![ses containsString:gone],
           [[NSString stringWithFormat:@"جراحیِ رشته (%@) برداشته شد", gone] UTF8String]);
    }

    // شنیدن هیچ‌وقت نمی‌ایستد و صدا بی‌قیدوشرط ضبط می‌شود.
    ok(![eng containsString:@"_netLost"] && ![eng containsString:@"- (void)netLost"],
       "حالتِ «شنیدن ایستاد» برداشته شد؛ بریدن و صف کردن ادامه دارد");
    ok([eng containsString:@"[self.queue waitForFirstPass];"],
       "سر پایان فقط تا دورِ اول صبر می‌شود، نه تا خالی شدنِ صف");
    ok([ses containsString:@"if (_queue.waiting) {"] && [ses containsString:@"[self showWaiting];"],
       "تکه‌ی در راه یک شمارِ آرام است، نه حالتِ خطا");

    // آنچه **نباید** باشد. هر کدام یک بار وسوسه شد و جواب همیشه یکی است: پشت
    // پروکسی و مسیر tun این دستگاه، سیستم‌عامل «آنلاین» می‌گوید در حالی که گوگل در
    // دسترس نیست. تنها سنجشِ راست، خودِ تلاشِ دوباره است.
    for (NSString *ban in @[@"SCNetworkReachability", @"nw_path_monitor", @"NWPathMonitor"]) {
        ok(![pip containsString:ban] && ![que containsString:ban] &&
           ![eng containsString:ban] && ![ses containsString:ban],
           [[NSString stringWithFormat:@"ناظرِ دسترسیِ شبکه (%@) اضافه نشده", ban] UTF8String]);
    }

    printf(failures ? "\nqueue: %d ادعا افتاد\n" : "\nqueue: همه‌ی ادعاها درست\n", failures);
    return failures ? 1 : 0;
} }
