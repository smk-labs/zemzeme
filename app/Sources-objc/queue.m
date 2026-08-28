// صف تکه‌ها: هر تکه یک جای مستقل، و متن از روی جاها ساخته می‌شود.
//
// تا امروز واحدِ حقیقت، رشته‌ی سرهم‌شده بود: تکه‌ای که متنش نمی‌رسید یک نشانه در همان
// رشته می‌گذاشت و بعدا باید «nامین نشانه» را پیدا و عوض می‌کردیم. آن جراحیِ رشته سه
// عیب داشت که هر سه به کاربر می‌رسید: ترتیب یک قرارداد بود نه یک ساختار، متنِ
// نشانه‌دار تحویل نمی‌شد (یعنی یک تکه کلِ دیکته را گروگان می‌گرفت)، و پر شدنِ نشانه
// فقط با Esc دستی اتفاق می‌افتاد.
//
// حالا هر تکه یک `ZSlot` است با حالتِ خودش، و متن هر لحظه از روی همان‌ها رندر
// می‌شود. ترتیب دیگر ساختاری است: جای دهم همیشه دهم است، چه متنش رسیده باشد چه نه.
//
// و یک تصحیحِ ریشه‌ای که کلِ این تغییر روی آن سوار است: **متنِ خالی همیشه شکست
// نیست.** `ZSegHasVoice` انرژی می‌سنجد نه حرف، و آستانه‌اش عمدا کوچک است تا پچ‌پچ
// از آن رد شود (kZVoiceRMS)؛ پس یک نفس یا صدای دستی روی میز هم از آن رد می‌شود.
// گوگل آن تکه را می‌گیرد، درست جواب می‌دهد «حرفی نبود»، و خط را **تمیز** می‌بندد.
// با قاعده‌ی قدیمی همان می‌شد یک سوراخِ پرنشدنی: ۲۰۲۶-۰۸-۱۹ یک تکه‌ی ۱٫۴ ثانیه‌ای
// از همین جنس ۱۷۴۱ نویسه را گروگان گرفت، کاربر چهار بار Esc زد و آخرش چهار دقیقه
// دیکته را دور ریخت. جداکننده از قبل در دست بود و فقط لاگ می‌شد: دلیلِ بسته شدن.
#import "zemzeme.h"
#import "rewrite.h"

// یک ساعتِ عقب‌نشینی برای **کلِ صف**، نه یکی برای هر تکه. خرابی مالِ شبکه است نه
// مالِ آن تکه‌ی بخصوص، پس ده تکه‌ی در انتظار یعنی ده برابر تلاشِ بی‌فایده روی همان
// خطِ قطع، نه ده شانسِ مستقل. و سقف سی ثانیه: بیشتر از این یعنی قطعیِ کوتاه هم سی
// ثانیه دیده شود، که همان «دیده نشدن» را از بین می‌برد.
NSTimeInterval ZBackoffDelay(NSInteger step) {
    static const NSTimeInterval steps[] = {1, 2, 4, 8, 15, 30};
    const NSInteger n = (NSInteger)(sizeof(steps) / sizeof(steps[0]));
    if (step < 0) step = 0;
    return steps[step < n ? step : n - 1];
}

// ---------- دفترچه ----------
// یک فایل کوچک کنار سشن، تا تکه‌ی در انتظار از بسته شدنِ اپ هم جان سالم ببرد. صدا
// در آن نیست و نباید باشد: audio.flac همان‌جا کنارش است و تکه فقط یک افست است.
//
// و دفترچه **پاک می‌شود** وقتی چیزی در انتظار نمانده. دلیلش سرعتِ لانچ نیست،
// درستی است: فایلِ مانده یعنی لانچِ بعدی سشنی را که تمام شده دوباره برمی‌دارد.
static NSString *const kZQueueManifest = @"queue.json";

NSURL *ZQueueManifestIn(NSURL *sessionDir) {
    return [sessionDir URLByAppendingPathComponent:kZQueueManifest];
}

@implementation ZSlot
@end

@implementation ZQueue {
    NSMutableArray<ZSlot *> *_slots;
    NSLock *_lock;
    dispatch_queue_t _q;         // سریال: تنها کارگر، و تنها راهِ رسیدن به شبکه
    NSCondition *_pass;          // «یک بار امتحان شد» را به finish خبر می‌دهد
    NSInteger _nextSeq;
    NSInteger _firstPassThrough; // بالاترین جایی که دستِ‌کم یک بار رفته
    NSInteger _step;             // پله‌ی عقب‌نشینیِ مشترک
    NSDate *_nextTryAt;
    NSInteger _epoch;            // دور ریختن یکی جلو می‌بردش
    BOOL _pumping;
    BOOL _stopped;
    unsigned long long _bytesUp;
    dispatch_queue_t _io;        // نوشتنِ دفترچه، دور از نخ صدا
}

- (instancetype)init {
    if ((self = [super init])) {
        _slots = [NSMutableArray array];
        _lock = [NSLock new];
        _pass = [NSCondition new];
        _nextTryAt = NSDate.distantPast;
        _firstPassThrough = -1;
        // یک کارگر، و در نتیجه **یک درخواست در پرواز، همیشه**. نقطه‌ی رایگان گوگل
        // جایی نیست که چند تایی رویش باز کنیم: موازی کردن نه سریع‌ترش می‌کند (تکه‌ی
        // هفت ثانیه‌ای در حدود دو ثانیه رونویسی می‌شود، پس صف هیچ‌وقت از گوینده عقب
        // نمی‌ماند) و ریسکِ «لال شدن» را چند برابر می‌کند.
        _q = dispatch_queue_create("io.seyed.zemzeme.queue", DISPATCH_QUEUE_SERIAL);
        // دفترچه روی نخِ صدا نوشته نمی‌شود. سریال است، پس ترتیبِ نوشتن‌ها همان ترتیبِ
        // تغییرهاست و نسخه‌ی قدیمی‌تر هیچ‌وقت روی تازه‌تر نمی‌نشیند.
        _io = dispatch_queue_create("io.seyed.zemzeme.queue.io", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

// ---------- افزودن و خواندن ----------

- (NSInteger)add:(NSData *)pcm lang:(NSString *)lang extra:(BOOL)extra
           frame:(unsigned long long)frame frames:(unsigned long long)frames {
    ZSlot *s = [ZSlot new];
    s.pcm = pcm;
    s.lang = [lang copy];
    s.extra = extra;
    s.frame = frame;
    s.frames = frames;
    s.state = ZSlotWaiting;
    [_lock lock];
    s.seq = _nextSeq++;
    [_slots addObject:s];
    [_lock unlock];
    [self persist];
    [self kick];
    return s.seq;
}

// متن، از روی جاها. جای نرسیده هیچ نمی‌گذارد (نه نشانه، نه فاصله‌ی اضافه) و جایی
// که سرور گفت حرفی نبود هم همین‌طور: آن تکه **تمام** است و سهمش واقعا هیچ است.
- (NSString *)textFrom:(NSInteger)seq extra:(BOOL)extra {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [_lock lock];
    for (ZSlot *s in _slots) {
        if (s.seq < seq || s.extra != extra) continue;
        if (s.state == ZSlotDone && s.text.length) [parts addObject:s.text];
    }
    [_lock unlock];
    return [parts componentsJoinedByString:@" "];
}

- (NSString *)text { return [self textFrom:0 extra:NO]; }

- (NSArray<ZSlot *> *)snapshot {
    [_lock lock];
    NSArray<ZSlot *> *copy = [_slots copy];
    [_lock unlock];
    return copy;
}

- (NSInteger)waiting {
    [_lock lock];
    NSInteger n = 0;
    for (ZSlot *s in _slots) if (s.state == ZSlotWaiting && !s.extra) n++;
    [_lock unlock];
    return n;
}

- (BOOL)drained { return self.waiting == 0; }

- (unsigned long long)bytesUp {
    [_lock lock];
    unsigned long long n = _bytesUp;
    [_lock unlock];
    return n;
}

// دور ریختن: جاها می‌روند و نوبت یکی جلو می‌رود، پس تکه‌ای که همین حالا روی شبکه
// است جوابش را که آورد بی‌اثر می‌افتد. بی این، حرفِ دورریخته دو ثانیه بعد خودش
// برمی‌گشت؛ همان باگی که در نسخه‌ی رشته‌ای هم بود.
- (void)discard {
    [_lock lock];
    NSUInteger had = _slots.count;
    [_slots removeAllObjects];
    _epoch++;
    _step = 0;
    _nextTryAt = NSDate.distantPast;
    _nextSeq = 0;
    _firstPassThrough = -1;
    [_lock unlock];
    [_pass lock];
    [_pass broadcast];
    [_pass unlock];
    [self persist];
    if (had) ZLog(@"queue: %lu جا دور ریخته شد", (unsigned long)had);
}

- (void)stop {
    [_lock lock];
    _stopped = YES;
    [_lock unlock];
    [_pass lock];
    [_pass broadcast];
    [_pass unlock];
}

// ---------- انتظارِ دورِ اول ----------
// سر پایانِ شنیدن فقط تا اینجا صبر می‌کنیم: هر جایی که تا این لحظه ساخته شده،
// دستِ‌کم **یک بار** امتحان شده باشد. نه بیشتر.
//
// و همین یک جمله کلِ «گروگان‌گیری» را برمی‌دارد. صبر کردن تا خالی شدنِ صف یعنی اگر
// اینترنت رفته باشد، Esc تا برگشتنِ اینترنت هیچ متنی تحویل نمی‌دهد. آنچه رسیده حقِ
// کاربر است و همین حالا می‌رود؛ بقیه خودشان می‌رسند و پنل خودش پر می‌شود.
//
// و سقف دارد، مثل هر انتظار دیگری در این اپ: انتظارِ بی‌سقف یعنی یک روز پنل برای
// همیشه روی «یک لحظه…» می‌ماند و هیچ‌کس نمی‌فهمد چرا.
- (void)waitForFirstPass {
    [_lock lock];
    NSInteger target = _nextSeq - 1;
    [_lock unlock];
    if (target < 0) return;
    NSDate *ceiling = [NSDate dateWithTimeIntervalSinceNow:kZQueueFirstPassCeilingSec];
    [_pass lock];
    for (;;) {
        [_lock lock];
        BOOL done = _stopped || _firstPassThrough >= target || _nextSeq <= target;
        [_lock unlock];
        if (done) break;
        if (![_pass waitUntilDate:ceiling]) {
            ZLog(@"queue: سقفِ انتظارِ دورِ اول (%.0f ثانیه) رد شد، بی‌معطلی تحویل می‌شود",
                 kZQueueFirstPassCeilingSec);
            break;
        }
    }
    [_pass unlock];
}

// ---------- کارگر ----------

- (void)kick {
    [_lock lock];
    BOOL go = !_pumping && !_stopped && [self hasWorkLocked];
    if (go) _pumping = YES;
    [_lock unlock];
    if (go) dispatch_async(_q, ^{ [self pump]; });
}

- (BOOL)hasWorkLocked {
    for (ZSlot *s in _slots) if (s.state == ZSlotWaiting) return YES;
    return NO;
}

// جای بعدی: **اول آنچه هنوز یک بار هم نرفته**، بعد آنچه منتظرِ تلاشِ دوباره است.
// ترتیبش عمدی است: کسی که همین حالا دارد حرف می‌زند نباید پشتِ تلاشِ دوباره‌ی یک
// تکه‌ی ده ثانیه پیش بماند. صدا تازه است و صاحبش منتظر.
- (ZSlot *)nextDueLocked:(NSTimeInterval *)waitOut {
    for (ZSlot *s in _slots) if (s.state == ZSlotWaiting && s.tries == 0) return s;
    NSTimeInterval left = [_nextTryAt timeIntervalSinceNow];
    for (ZSlot *s in _slots) {
        if (s.state != ZSlotWaiting) continue;
        if (left <= 0) return s;
        if (waitOut) *waitOut = left;
        return nil;
    }
    return nil;
}

- (void)pump {
    NSTimeInterval wait = 0;
    [_lock lock];
    if (_stopped) { _pumping = NO; [_lock unlock]; return; }
    ZSlot *s = [self nextDueLocked:&wait];
    if (!s) {
        if (wait > 0) {
            // ساعتِ عقب‌نشینی هنوز نرسیده. نخ را نگه نمی‌داریم؛ همین‌جا برای بعد وقت
            // می‌گیریم. کار تازه که برسد `kick` هم بی‌اثر است چون `_pumping` بالاست،
            // و آن درست است: تکه‌ی تازه سر همین بیدار شدن اول از همه برداشته می‌شود.
            [_lock unlock];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)),
                           _q, ^{ [self pump]; });
            return;
        }
        _pumping = NO;
        [_lock unlock];
        return;
    }
    NSInteger epoch = _epoch;
    NSData *pcm = s.pcm;
    unsigned long long frame = s.frame, frames = s.frames;
    NSString *lang = s.lang;
    NSInteger seq = s.seq;
    BOOL first = s.tries == 0;
    BOOL mayAskAgain = !s.secondOpinionUsed;
    s.tries++;
    [_lock unlock];

    // صدا: از حافظه، وگرنه از خودِ audio.flac. جای برداشته‌شده از دفترچه هیچ صدایی
    // در حافظه ندارد و اصلا برای همین است که دفترچه کار می‌کند.
    //
    // و **بیرون از قفل**، چون خواندن از فایل تا کسری از ثانیه طول می‌کشد و قفلِ
    // این صف را نخِ صدا هم می‌گیرد (هر برشِ تازه یک `add` است). قفل نگه داشتن سرِ
    // دیسک یعنی لکنتِ ضبط.
    if (!pcm.length && self.audio) {
        NSError *de = nil;
        pcm = ZDecodePCMRange(self.audio, frame, frames, &de);
        if (!pcm.length) ZLog(@"queue %ld: صدایش از فایل خوانده نشد: %@", (long)seq,
                              de.localizedDescription ?: @"?");
    }
    NSString *why = nil;
    unsigned long long up = 0;
    NSString *t = pcm.length ? ZTranscribeSegment(pcm, lang, NO, &up, &why) : @"";
    // صدایی در کار نیست، پس تلاشِ دوباره هم بی‌معناست: این تکه دیگر برنمی‌گردد و
    // ماندنش در انتظار فقط یعنی یک حلقه‌ی بی‌پایان روی یک فایلِ نبوده.
    BOOL noAudio = !pcm.length;
    // نظرِ دوم، یک بار در عمرِ هر تکه و بی‌مکث: پیش از باور کردنِ **هر کدام** از دو
    // حکم. نقطه‌ی رایگان گاهی «لال» جواب می‌دهد و آن‌وقت یک بلوکِ هفت ثانیه‌ای کامل
    // گم می‌شود؛ اندازه‌گیری می‌گوید همین یک تلاشِ اضافه حدود ۱۳٪ خالی‌ها را نجات
    // می‌دهد. و در جهت دیگر هم لازم است: «حرفی نبود» حکمِ نهایی است و یک بار دیگر
    // پرسیدن ارزانش است.
    BOOL askedAgain = NO;
    if (!t.length && mayAskAgain && !noAudio) {
        ZLog(@"queue %ld: خالی برگشت (%@)، یک بار دیگر", (long)seq, why ?: @"?");
        askedAgain = YES;
        t = pcm.length ? ZTranscribeSegment(pcm, lang, NO, &up, &why) : @"";
    }

    [_lock lock];
    _bytesUp += up;
    BOOL stale = epoch != _epoch;
    ZSlot *live = nil;
    if (!stale) for (ZSlot *x in _slots) if (x.seq == seq) { live = x; break; }
    if (live) {
        if (askedAgain) live.secondOpinionUsed = YES;
        if (t.length) {
            live.text = t;
            live.state = ZSlotDone;
        } else if (noAudio || ZCloseWasClean(why) || live.extra) {
            // رفت‌وبرگشت کامل شد و سرور خودش خط را بست: یعنی گوش کرد و حرفی نشنید.
            // این تکه **تمام** است، نه خراب. نفس و صدای دست و ته‌مانده‌ی سکوت از
            // همین در بیرون می‌روند و دیگر چیزی را گرو نمی‌گیرند.
            //
            // و جای پاس دوم هم از همین در بیرون می‌رود، حتی وقتی واقعا نرسیده باشد:
            // متنش تحویل کاربر نمی‌شود، پس تلاشِ دوباره‌اش فقط خرج کردنِ همان خطِ
            // نازکی است که تکه‌های اصلی به آن احتیاج دارند.
            live.state = ZSlotSilent;
        }
        // متن رسید یا سرور جواب داد: در هر دو حالت راهِ شبکه باز است، پس ساعتِ
        // عقب‌نشینیِ مشترک همین‌جا صفر می‌شود.
        if (live.state != ZSlotWaiting) { _step = 0; _nextTryAt = NSDate.distantPast; }
        else {
            _nextTryAt = [NSDate dateWithTimeIntervalSinceNow:ZBackoffDelay(_step)];
            if (_step < 5) _step++;
        }
        if (first && seq > _firstPassThrough) _firstPassThrough = seq;
    }
    ZSlotState st = live.state;
    NSInteger tries = live.tries;
    NSTimeInterval nextIn = [_nextTryAt timeIntervalSinceNow];
    [_lock unlock];

    // بازه‌ی این تکه در audio.flac، همان بازه‌ای که خطِ برشِ خط لوله هم دارد. بی آن،
    // خطِ صف و خطِ برش دو شماره‌ی مستقل داشتند (seq و شماره‌ی خط لوله) و وصل کردنشان
    // حدس بود، پس «کدام تکه گم شد» جوابِ خواندنی نداشت.
    NSString *span = [NSString stringWithFormat:@"%.1fs تا %.1fs",
                      frame * 2 / kZPcmBytesPerSec, (frame + frames) * 2 / kZPcmBytesPerSec];
    // و **متنِ** تکه، نه فقط شمارِ نویسه‌اش: مقایسه‌ی متنِ پیش‌نمایش با متنِ نهایی تنها
    // راهِ آزمودنِ «کلمه‌های آخر را دیدم و در متن نبود» است و تا امروز شدنی نبود.
    // سقف ۲۰۰ نویسه، چون تکه‌ی هفت ثانیه‌ای عملا به آن نمی‌رسد و سقف فقط جلوی یک
    // جوابِ در رفته را می‌گیرد.
    NSString *shown = t.length > 200 ? [[t substringToIndex:200] stringByAppendingString:@"…"] : t;
    if (stale || !live) {
        ZLog(@"queue %ld [%@]: جواب رسید ولی جایش دور ریخته شده بود", (long)seq, span);
    } else if (st == ZSlotDone) {
        ZLog(@"queue %ld [%@] ← %lu نویسه%@: %@", (long)seq, span, (unsigned long)t.length,
             tries > 1 ? [NSString stringWithFormat:@" (تلاش %ld)", (long)tries] : @"", shown);
    } else if (st == ZSlotSilent && noAudio) {
        ZLog(@"queue %ld [%@]: صدایش پیدا نشد، از صف افتاد", (long)seq, span);
    } else if (st == ZSlotSilent) {
        ZLog(@"queue %ld [%@]: سرور شنید و حرفی نبود، این تکه تمام است", (long)seq, span);
    } else {
        ZLog(@"queue %ld [%@]: نرسید (%@)، تلاش %ld، %.0f ثانیه دیگر",
             (long)seq, span, why ?: @"?", (long)tries, MAX(0.0, nextIn));
    }

    [self persist];
    [_pass lock];
    [_pass broadcast];
    [_pass unlock];
    if (self.onChange) {
        void (^cb)(void) = self.onChange;
        dispatch_async(dispatch_get_main_queue(), ^{ cb(); });
    }
    dispatch_async(_q, ^{ [self pump]; });
}

- (void)persist {
    NSURL *file = self.manifest;
    if (!file) return;
    // رونوشت زیر قفل و همین‌جا، نوشتن آن‌طرف: اگر رونوشت هم آن‌طرف گرفته می‌شد، دو
    // نوشتنِ پشت سر هم می‌توانستند هر دو حالِ **آخر** را ببینند و ترتیب معنا نداشت.
    NSArray<ZSlot *> *slots = self.snapshot;
    NSURL *audio = self.audio;
    NSString *lang = self.lang;
    dispatch_async(_io, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSMutableArray *rows = [NSMutableArray array];
        BOOL anyWaiting = NO;
        for (ZSlot *s in slots) {
            if (s.extra) continue;    // متنش تحویل کاربر نمی‌شود؛ نگه داشتنش بی‌معناست
            if (s.state == ZSlotWaiting) anyWaiting = YES;
            [rows addObject:@{@"seq": @(s.seq), @"state": @(s.state),
                              @"text": s.text ?: @"", @"lang": s.lang ?: (lang ?: @""),
                              @"frame": @(s.frame), @"frames": @(s.frames),
                              @"tries": @(s.tries), @"second": @(s.secondOpinionUsed)}];
        }
        if (!anyWaiting || !audio) {
            [fm removeItemAtURL:file error:nil];
            return;
        }
        NSDictionary *doc = @{@"v": @1, @"audio": audio.path ?: @"",
                              @"lang": lang ?: @"", @"slots": rows};
        NSData *d = [NSJSONSerialization dataWithJSONObject:doc
                                                    options:NSJSONWritingSortedKeys error:nil];
        if (d) [d writeToURL:file options:NSDataWritingAtomic error:nil];
    });
}


// ---------- برداشتنِ صف سر لانچ ----------
// «تکه‌ی در انتظار از بسته شدنِ اپ هم جان سالم می‌برد» تا اینجا فقط یک فایل بود.
// این تابع آن را به قول تبدیل می‌کند: هر سشنی که دفترچه دارد برداشته می‌شود و
// تمام می‌شود، بی هیچ رابطی و بی هیچ کلیدی.
//
// **بی رابط، و عمدا.** اپ تازه بالا آمده و کاربر شاید دارد کار دیگری می‌کند؛ پنجره
// یا نشانِ تازه‌ای برای حرفِ ده دقیقه پیش، مزاحمت است نه خدمت. متن سر جای خودش
// می‌نشیند (text.txt) و ردیف تاریخچه‌ی همان سشن تازه می‌شود، چون تاریخچه سر خواندن
// با sid جمع می‌کند. کاربر هر وقت سراغش برود، کامل پیدایش می‌کند.
//
// و پاسِ تمیزکاری اینجا اجرا **نمی‌شود**: کلید در کی‌چین است و خواندنش می‌تواند یک
// پنجره‌ی رمز بالا بیاورد، آن هم بی‌آنکه کسی منتظرِ چیزی باشد. متنِ خام و کامل، از
// متنِ تمیزِ نصفه بهتر است.
// و دو در به این مسیر باز می‌شود، نه یکی: لانچ (پایین)، و پایانِ سشن که صفِ
// بی‌صاحبش را همین‌جا می‌سپارد (`ZAdoptOrphanQueue`). هر دو یک سیم‌کشی دارند، پس
// تکه‌ی دیررس چه در همین اجرا برسد چه در اجرای بعدی، از یک راه می‌نشیند.
//
// جدول با sid کلید می‌خورد و صف را **زنده نگه می‌دارد** تا خالی شدنش. دو نخ لمسش
// می‌کنند (نخ اصلی سرِ پایانِ سشن، نخ کارگرِ لانچ سرِ بالا آمدن)، پس قفل دارد. قفل
// فقط خودِ جدول را می‌پوشاند و روی هیچ کال‌بکی نگه داشته نمی‌شود.
static NSMutableDictionary<NSString *, ZQueue *> *gResumed;
static NSLock *gResumedLock;

static NSLock *zResumedLock(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gResumed = [NSMutableDictionary dictionary];
        gResumedLock = [NSLock new];
    });
    return gResumedLock;
}

// نه یعنی این sid از قبل دستِ یکی هست. همین یک جواب است که جلوی دو صف روی یک صدا
// را می‌گیرد، یعنی جلوی دو ردیف تاریخچه و دو بار نوشتنِ text.txt.
static BOOL zHoldResumed(NSString *sid, ZQueue *q) {
    NSLock *lock = zResumedLock();
    [lock lock];
    BOOL fresh = gResumed[sid] == nil;
    if (fresh) gResumed[sid] = q;
    [lock unlock];
    return fresh;
}

// و رها کردن، همان لحظه که صف واقعا تمام شد. بی این، هر سشنی که با تکه‌ی در راه
// بسته شود تا بسته شدنِ اپ یک صف و یک بلاک را زنده نگه می‌دارد.
static void zDropResumed(NSString *sid, ZQueue *q) {
    NSLock *lock = zResumedLock();
    [lock lock];
    if (gResumed[sid] == q) [gResumed removeObjectForKey:sid];
    [lock unlock];
}

+ (ZQueue *)queueFromManifest:(NSURL *)file {
    NSData *raw = [NSData dataWithContentsOfURL:file];
    NSDictionary *doc = raw ? [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil] : nil;
    if (![doc isKindOfClass:NSDictionary.class]) return nil;
    NSString *audio = doc[@"audio"];
    NSArray *rows = doc[@"slots"];
    if (![rows isKindOfClass:NSArray.class] || !audio.length) return nil;
    // صدا نباشد، هیچ‌کدام از این جاها برنمی‌گردند. دفترچه‌ی بی‌صدا فقط یک حلقه‌ی
    // بی‌پایان است، پس همان‌جا برداشته می‌شود.
    if (![NSFileManager.defaultManager fileExistsAtPath:audio]) {
        ZLog(@"queue: دفترچه بود ولی صدایش نه، پاک شد: %@", file.path);
        [NSFileManager.defaultManager removeItemAtURL:file error:nil];
        return nil;
    }
    ZQueue *q = [ZQueue new];
    q.manifest = file;
    q.audio = [NSURL fileURLWithPath:audio];
    q.lang = doc[@"lang"];
    BOOL any = NO;
    NSInteger top = 0;
    for (NSDictionary *r in rows) {
        if (![r isKindOfClass:NSDictionary.class]) continue;
        ZSlot *s = [ZSlot new];
        s.seq = [r[@"seq"] integerValue];
        s.state = (ZSlotState)[r[@"state"] integerValue];
        s.text = r[@"text"];
        s.lang = [r[@"lang"] length] ? r[@"lang"] : q.lang;
        s.frame = [r[@"frame"] unsignedLongLongValue];
        s.frames = [r[@"frames"] unsignedLongLongValue];
        s.tries = [r[@"tries"] integerValue];
        s.secondOpinionUsed = [r[@"second"] boolValue];
        // صدا با خودش نمی‌آید و نباید بیاید: افست و طول تنها چیزی است که لازم است.
        if (s.state == ZSlotWaiting && !s.frames) continue;
        if (s.state == ZSlotWaiting) any = YES;
        [q addRestored:s];
        if (s.seq >= top) top = s.seq + 1;
    }
    [q setNextSeq:top];
    return any ? q : nil;
}

- (void)addRestored:(ZSlot *)s {
    [_lock lock];
    [_slots addObject:s];
    [_lock unlock];
}

- (void)setNextSeq:(NSInteger)n {
    [_lock lock];
    _nextSeq = n;
    _firstPassThrough = n - 1;   // دورِ اولِ این‌ها قبلا رفته؛ کسی منتظرشان نیست
    [_lock unlock];
}

- (void)resume { [self kick]; }

// متن را سرِ جایش می‌نشاند و جواب می‌دهد که **واقعا نشست**. جدا از تابع پایین، چون
// تنها همین یک جواب حق دارد صدا را پاک کند و بدون آن، «تور» پیش از چیزی که باید
// نجاتش بدهد می‌رفت.
static BOOL zLandResumedText(ZQueue *q, NSString *sid,
                             NSString *rewrite, NSIndexSet *covers) {
    NSCharacterSet *edges = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    // دو متن، همان دو تای مسیر زنده. تحویل از لایه‌ی بازنویسی می‌آید (ویرایشِ کاربر
    // یا پاس)، خام از خودِ صف. سپردنِ صف بی لایه یعنی تکه‌ی دیررس متنِ ویرایش‌شده را
    // با خام عوض کند، یعنی همان باگ C1 از درِ پشتی برگردد.
    NSString *all = [ZRewriteText(rewrite, covers, q.snapshot, NO) stringByTrimmingCharactersInSet:edges];
    NSString *raw = [q.text stringByTrimmingCharactersInSet:edges];
    // متنی در کار نیست، پس تنها نسخه‌ی این حرف‌ها همان audio.flac است.
    if (!all.length) return NO;
    NSURL *dir = q.manifest.URLByDeletingLastPathComponent;
    // بلندتر یا هیچ. متنِ روی دیسک می‌تواند نسخه‌ی تمیزشده‌ی همان حرف‌ها باشد و آن را
    // با نسخه‌ی خام عوض کردن، یک قدم عقب است. ولی متنی که تکه‌های جامانده‌اش رسیده‌اند
    // تقریبا همیشه بلندتر است، و همان قاعده به زبان ساده: تکه‌ی دیررس فقط اضافه
    // می‌کند، هیچ‌وقت کم نمی‌کند. و همین حالت یعنی متن از قبل امن است، نه اینکه شکست
    // خورده باشد.
    NSURL *txt = [dir URLByAppendingPathComponent:@"text.txt"];
    NSString *had = [NSString stringWithContentsOfURL:txt
                                             encoding:NSUTF8StringEncoding error:nil];
    if (all.length <= had.length) return YES;
    NSError *err = nil;
    if (![all writeToURL:txt atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        ZLog(@"queue: سشن %@ متنش روی دیسک ننشست (%@)، پس صدا هم دست نمی‌خورد",
             sid, err.localizedDescription ?: @"?");
        return NO;
    }
    // raw.txt هم همین‌جا تازه می‌شود، چون مسیر زنده هر بار هر دو را می‌نویسد و
    // تکه‌ی دیررس نباید یکی از آن دو را عقب‌مانده جا بگذارد. سرِ لانچِ بعدی لایه‌ای
    // در کار نیست (با پروسه رفته)، پس آنجا این دو یکی درمی‌آیند و همان درست است.
    [raw writeToURL:[dir URLByAppendingPathComponent:@"raw.txt"]
         atomically:YES encoding:NSUTF8StringEncoding error:nil];
    ZHistoryAppend(all, raw, sid, ZHistoryViaAuto, nil);
    ZLog(@"queue: سشن %@ دیر تمام شد، %lu نویسه در تاریخچه نشست",
         sid, (unsigned long)all.length);
    return YES;
}

// آنچه سرِ تمام شدنِ یک صفِ برداشته‌شده باید بیفتد. بیرون از بلوک، چون بلوکِ داخلِ
// یک حلقه‌ی دو تو در تو جای منطق نیست و چون تست باید بتواند صدایش بزند بی آنکه
// پوشه‌ی واقعیِ سشن‌ها را بخواند. `sid` نامِ پوشه‌ی سشن است: هم برای لاگ، هم برای
// ردیف تاریخچه، که سر خواندن با همین جمع می‌شود.
static void zFinishResumed(ZQueue *q, NSString *sid,
                           NSString *rewrite, NSIndexSet *covers) {
    if (!q || !q.drained) return;
    BOOL safe = zLandResumedText(q, sid, rewrite, covers);
    // و همان تاگل «ضبط صدای سشن»، اینجا هم. سشن سر پایانش صدا را نگه داشته بود چون
    // تکه‌ای در راه بود، بعد اپ بسته شد، و تا امروز دیگر هیچ‌کس سراغ آن صدا نمی‌آمد:
    // تنها راه رفتنش جاروی هفت‌روزه بود. یعنی دقیقا همان سشنی که با شبکه‌ی بد بسته
    // شده، تاگل رویش بی‌اثر می‌ماند. حالا همین‌جا که صف تمام می‌شود، تاگل حرف آخر را
    // می‌زند.
    //
    // و **بعد** از تاییدِ نوشتنِ متن، نه پیش از آن. تا امروز برعکس بود و درست بالای
    // دو راهِ برگشتِ زودهنگام می‌نشست: متن که ننشیند، صدا از قبل رفته بود و آن سشن
    // هیچ نسخه‌ای نداشت. صدا تنها تور واقعی است (متنِ گم‌شده‌ی B1 از همین فایل با
    // `--transcribe` برگشت)، پس تور آخر از همه می‌رود (باگ B2).
    //
    // و تاگلِ **همین حالا** خوانده می‌شود، نه حالش سرِ ضبط. تاگل یک قاعده‌ی ایستاست نه
    // انتخابِ تکیِ هر سشن، و اپ از قبل هر صدایی را سر هفت روز جارو می‌کند. نگه داشتنِ
    // حالِ آن روز در دفترچه، یک کلید تازه و یک مسیرِ مهاجرت می‌خواست، آن هم فقط برای
    // کسی که درست بین دو لانچ تاگل را عوض کرده باشد.
    if (safe && !ZSettings.shared.recordSessions && q.audio) {
        [NSFileManager.defaultManager removeItemAtURL:q.audio error:nil];
        ZLog(@"queue: سشن %@ تمام شد و صدایش رفت (ضبط صدای سشن خاموش است)", sid);
    }
    zDropResumed(sid, q);
}

// و همان، از بیرون: مسیرِ لانچ لایه‌ای ندارد چون لایه با پروسه‌ی قبلی رفته.
void ZFinishResumedSession(ZQueue *q, NSString *sid) {
    zFinishResumed(q, sid, nil, nil);
}

// سشن بسته شد و تکه‌ای هنوز در راه است. تا امروز حرف دقیقا همین‌جا گم می‌شد: تنها
// نگه‌دارنده‌ی سشن `app.m` است و `onFinish` همان لحظه رهایش می‌کند، پس کال‌بکِ صف که
// با `__weak` بسته شده روی نال خالی می‌شود. شاهدش این بود که «تکه‌ی دیررس نشست» در
// کلِ تاریخِ app.log صفر بار نوشته شده (باگ B1).
//
// پس صف از سشن جدا می‌شود و صاحبِ تازه‌اش همین جدول است، با همان سیم‌کشیِ لانچ.
// رابطی هم در کار نیست و نباید باشد: کاربر رفته و پنجره‌ی تازه مزاحمت است نه خدمت.
void ZAdoptOrphanQueue(ZQueue *q, NSString *sid, NSString *rewrite, NSIndexSet *covers) {
    if (!q || !sid.length) return;
    // چیزی در راه نیست، پس مسیر زنده خودش تحویل داده و text.txt همان متنِ تحویل‌شده
    // است. برداشتنِ صف اینجا یعنی متنِ خام روی متنِ پاس‌خورده بنشیند.
    if (q.drained) return;
    if (!zHoldResumed(sid, q)) return;
    __weak ZQueue *wq = q;
    q.onChange = ^{ zFinishResumed(wq, sid, rewrite, covers); };
    ZLog(@"queue: سشن %@ بی‌صاحب ماند و برداشته شد، %ld تکه در راه", sid, (long)q.waiting);
    // و اگر همان تکه درست میانِ دیدن و سیم‌کشی رسیده باشد، کال‌بکِ کهنه‌اش روی سشنِ
    // رفته خالی شده و کسی خبردار نشده. یک بار همین‌جا پرسیده می‌شود.
    if (q.drained) zFinishResumed(q, sid, rewrite, covers);
}

void ZResumePendingQueues(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSArray<NSURL *> *dirs = [fm contentsOfDirectoryAtURL:ZSessionsDir()
                                   includingPropertiesForKeys:nil options:0 error:nil];
        for (NSURL *dir in dirs) {
            NSURL *file = ZQueueManifestIn(dir);
            if (![fm fileExistsAtPath:file.path]) continue;
            ZQueue *q = [ZQueue queueFromManifest:file];
            if (!q) continue;
            NSString *sid = dir.lastPathComponent;
            // همان سشن می‌تواند همین حالا دستِ `ZAdoptOrphanQueue` باشد: دفترچه تا
            // خالی شدنِ صف روی دیسک می‌ماند، پس این تابع هم می‌بیندش. دو صف روی یک
            // صدا یعنی دو ردیف تاریخچه و دو بار نوشتنِ همان فایل.
            if (!zHoldResumed(sid, q)) continue;
            ZLog(@"queue: سشن %@ برداشته شد، %ld تکه در راه", sid, (long)q.waiting);
            __weak ZQueue *wq = q;
            q.onChange = ^{ ZFinishResumedSession(wq, sid); };
            [q resume];
        }
    });
}

@end
