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
    }
    return self;
}

// ---------- افزودن و خواندن ----------

- (NSInteger)add:(NSData *)pcm lang:(NSString *)lang {
    ZSlot *s = [ZSlot new];
    s.pcm = pcm;
    s.lang = [lang copy];
    s.state = ZSlotWaiting;
    [_lock lock];
    s.seq = _nextSeq++;
    [_slots addObject:s];
    [_lock unlock];
    [self kick];
    return s.seq;
}

// متن، از روی جاها. جای نرسیده هیچ نمی‌گذارد (نه نشانه، نه فاصله‌ی اضافه) و جایی
// که سرور گفت حرفی نبود هم همین‌طور: آن تکه **تمام** است و سهمش واقعا هیچ است.
- (NSString *)textFrom:(NSInteger)seq {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [_lock lock];
    for (ZSlot *s in _slots) {
        if (s.seq < seq) continue;
        if (s.state == ZSlotDone && s.text.length) [parts addObject:s.text];
    }
    [_lock unlock];
    return [parts componentsJoinedByString:@" "];
}

- (NSString *)text { return [self textFrom:0]; }

- (NSInteger)nextSeq {
    [_lock lock];
    NSInteger n = _nextSeq;
    [_lock unlock];
    return n;
}

- (NSInteger)waiting {
    [_lock lock];
    NSInteger n = 0;
    for (ZSlot *s in _slots) if (s.state == ZSlotWaiting) n++;
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
    NSData *pcm = [self pcmForLocked:s];
    NSString *lang = s.lang;
    NSInteger seq = s.seq;
    BOOL first = s.tries == 0;
    BOOL mayAskAgain = !s.secondOpinionUsed;
    s.tries++;
    [_lock unlock];

    NSString *why = nil;
    unsigned long long up = 0;
    NSString *t = pcm.length ? ZTranscribeSegment(pcm, lang, NO, &up, &why) : @"";
    if (!pcm.length) why = @"no-audio";
    // نظرِ دوم، یک بار در عمرِ هر تکه و بی‌مکث: پیش از باور کردنِ **هر کدام** از دو
    // حکم. نقطه‌ی رایگان گاهی «لال» جواب می‌دهد و آن‌وقت یک بلوکِ هفت ثانیه‌ای کامل
    // گم می‌شود؛ اندازه‌گیری می‌گوید همین یک تلاشِ اضافه حدود ۱۳٪ خالی‌ها را نجات
    // می‌دهد. و در جهت دیگر هم لازم است: «حرفی نبود» حکمِ نهایی است و یک بار دیگر
    // پرسیدن ارزانش است.
    BOOL askedAgain = NO;
    if (!t.length && mayAskAgain) {
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
        } else if (ZCloseWasClean(why)) {
            // رفت‌وبرگشت کامل شد و سرور خودش خط را بست: یعنی گوش کرد و حرفی نشنید.
            // این تکه **تمام** است، نه خراب. نفس و صدای دست و ته‌مانده‌ی سکوت از
            // همین در بیرون می‌روند و دیگر چیزی را گرو نمی‌گیرند.
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

    if (stale || !live) {
        ZLog(@"queue %ld: جواب رسید ولی جایش دور ریخته شده بود", (long)seq);
    } else if (st == ZSlotDone) {
        ZLog(@"queue %ld ← %lu نویسه%@", (long)seq, (unsigned long)t.length,
             tries > 1 ? [NSString stringWithFormat:@" (تلاش %ld)", (long)tries] : @"");
    } else if (st == ZSlotSilent) {
        ZLog(@"queue %ld: سرور شنید و حرفی نبود، این تکه تمام است", (long)seq);
    } else {
        ZLog(@"queue %ld: نرسید (%@)، تلاش %ld، %.0f ثانیه دیگر",
             (long)seq, why ?: @"?", (long)tries, MAX(0.0, nextIn));
    }

    [_pass lock];
    [_pass broadcast];
    [_pass unlock];
    if (self.onChange) {
        void (^cb)(void) = self.onChange;
        dispatch_async(dispatch_get_main_queue(), ^{ cb(); });
    }
    dispatch_async(_q, ^{ [self pump]; });
}

// صدای یک جا. فاز یک: در حافظه. فاز دو همین‌جا از audio.flac می‌خواند و آن‌وقت
// این تنها جایی است که باید عوض شود.
- (NSData *)pcmForLocked:(ZSlot *)s { return s.pcm; }

@end
