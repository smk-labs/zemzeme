// موتور: میکروفن، ضبط روی دیسک، و خط لوله. و بس.
//
// آنچه اینجا **نیست** مهم‌تر از آنچه هست: نه چرخش سشن، نه بافر بازپخش، نه واچ‌داگ
// گیر کردن، نه سوپروایزر و backoff، نه هم‌پوشانی، نه نجات و تخلیه. همه‌ی آن‌ها در
// نسخه یک برای تعمیرِ یک چیز بودند: سشنی که ۲۰ تا ۲۴ ثانیه صدا می‌خورد و از سقفِ
// ~۳۰ ثانیه‌ای سرور می‌ترسید. حالا هر سشن یک تکه‌ی ~۷ ثانیه‌ای می‌خورد و می‌میرد، پس
// نه به سقف نزدیک می‌شود، نه چرخشی لازم است، نه درزی هست که دوخته شود.
//
// و چون هیچ متنی در حین حرف زدن نشان داده نمی‌شود، موتور هیچ کانالِ متنِ لحظه‌ای
// ندارد. فقط بلندی صدا بیرون می‌رود (برای نشان)، و سر پایان یک متن.
#import "zemzeme.h"

@implementation ZEngine {
    NSString *_lang;
    ZMic *_mic;
    ZPipe *_fa;
    ZPipe *_en;              // پاس دوم انگلیسی؛ نال یعنی خاموش
    NSDate *_startedAt;
    NSTimeInterval _seconds; // ثانیه‌ی صدای بلعیده‌شده، از بایت‌ها نه از ساعت دیوار
    BOOL _stopping;
    BOOL _fileMode;
    dispatch_source_t _cap;
}

- (instancetype)initWithLang:(NSString *)lang {
    if ((self = [super init])) _lang = [lang copy];
    return self;
}

- (NSTimeInterval)seconds { return _seconds; }

// سطل آشغال ساعت را هم صفر می‌کند. کاربری که «از نو» می‌زند انتظار دارد شمارنده هم
// از نو شروع کند، وگرنه عددی می‌بیند که به هیچ صدایی که هنوز روی دیسک هست مربوط نیست.
- (void)resetClock { _seconds = 0; }

// ---------- شروع ----------

- (BOOL)startWithError:(NSError **)err {
    [self buildPipes];
    _mic = [ZMic new];
    __weak typeof(self) weak = self;
    _mic.onChunk = ^(NSData *pcm) { [weak ingest:pcm]; };
    _mic.onLevel = ^(float rms) {
        typeof(self) me = weak;
        if (me && !me->_stopping) [me->_delegate engineLevel:rms];
    };
    if (![_mic startWithError:err]) return NO;
    _startedAt = NSDate.date;
    [_delegate engineState:ZEngineListening message:nil];
    [self armSessionCap];
    ZLog(@"engine: شروع، زبان %@، میکروفن %@، پاس دوم %@",
         _lang, ZDefaultInputName(), _en ? @"روشن" : @"خاموش");
    return YES;
}

// همان موتور، ولی صدا از یک فایل می‌آید نه از میکروفن. هیچ میان‌بری هم نمی‌زند:
// همان تکه‌های ۱۰۰ میلی‌ثانیه‌ای، همان ingest، همان خط لوله، همان ضبط. تنها فرقش
// این است که آدمی پشتش نیست.
//
// دلیل وجودش صریح است: هر ادعای سرتاسری باید بی‌میکروفن و بی‌آدم تکرارپذیر باشد.
// نسخه یک این را نداشت و «درست شد» یعنی «این بار ندیدمش»، و پنج دور وصله از همان‌جا
// شکست خورد. speed=۱ یعنی زمان واقعی؛ بزرگ‌تر یعنی تندتر از واقعیت.
- (BOOL)startFromPCM:(NSData *)pcm speed:(double)speed error:(NSError **)err {
    _fileMode = YES;
    [self buildPipes];
    _startedAt = NSDate.date;
    [_delegate engineState:ZEngineListening message:nil];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        const NSUInteger step = 3200;      // ۱۰۰ میلی‌ثانیه، همان دانه‌بندی میکروفن
        NSDate *t0 = NSDate.date;
        for (NSUInteger off = 0; off < pcm.length && !self->_stopping; off += step) {
            NSUInteger n = MIN(step, pcm.length - off);
            [self ingest:[pcm subdataWithRange:NSMakeRange(off, n)]];
            if (speed <= 0) continue;
            double due = (off + n) / (kZPcmBytesPerSec * speed);
            double behind = due - [NSDate.date timeIntervalSinceDate:t0];
            if (behind > 0) usleep((useconds_t)(behind * 1e6));
        }
        [self stop];
    });
    return YES;
}

- (void)buildPipes {
    _fa = [[ZPipe alloc] initWithLang:_lang];
    // پاس دوم انگلیسی روی همان صدا: رایگان، موازی، و روی متنِ پر از اصطلاح خیلی خوب.
    // اندازه‌گیری روی ضبط ۰۲: پاس فارسی از «دیتابیس پستگرس» به بعد را کامل انداخته
    // بود و پاس انگلیسی همان‌جا شنیده بود. ولی روی ۰۷ (اصطلاح‌های رایج) تقریبا هیچ،
    // پس بیمه است نه ستون، و پیش‌فرض خاموش.
    if (ZSettings.shared.secondPass && [_lang hasPrefix:@"fa"]) {
        _en = [[ZPipe alloc] initWithLang:@"en-US"];
    }
}

// ---------- صدا ----------

- (void)ingest:(NSData *)pcm {
    if (_stopping || self.paused) return;
    _seconds += pcm.length / kZPcmBytesPerSec;
    // ضبط اول، خط لوله بعد. فایل روی دیسک مرجع همه‌چیز است: اگر شبکه بمیرد یا اپ
    // کرش کند، صدا سر جایش است. تشخیص را می‌شود دوباره گرفت، حرفِ گفته‌شده را نه.
    [_recorder feed:pcm];
    [_fa feed:pcm];
    [_en feed:pcm];
}

// ---------- سقف پنج دقیقه ----------
// چرا سقف: این ابزار دیکته است نه ضبط جلسه. صدای بلندتر جای دیگری دارد و اپ باید
// همان‌جا را نشان بدهد، نه اینکه بی‌صدا ادامه بدهد و کاربر نداند چه شد.
// هرچه تا اینجا رونویسی شده می‌ماند: سقف یعنی «تمامش کن»، نه «دورش بریز».
- (void)armSessionCap {
    __weak typeof(self) weak = self;
    _cap = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_cap, dispatch_time(DISPATCH_TIME_NOW,
                                                  (int64_t)(kZMaxSessionSec * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER, NSEC_PER_SEC);
    dispatch_source_set_event_handler(_cap, ^{
        typeof(self) me = weak;
        if (!me || me->_stopping) return;
        ZLog(@"engine: سقف پنج دقیقه، سشن خودش تمام می‌شود");
        me->_cappedOut = YES;
        [me stop];
    });
    dispatch_resume(_cap);
}

// ---------- مکث ----------

- (void)pause {
    if (_paused) return;
    _paused = YES;
    [_delegate engineState:ZEnginePaused message:nil];
}

- (void)resume {
    if (!_paused) return;
    _paused = NO;
    [_delegate engineState:ZEngineListening message:nil];
}

// ---------- پایان ----------

- (void)stop {
    if (_stopping) return;
    _stopping = YES;
    if (_cap) {
        dispatch_source_cancel(_cap);
        _cap = nil;
    }
    [_mic stop];
    _mic = nil;
    [_recorder finish];

    NSDate *t0 = NSDate.date;
    // خالی کردن صف بلوکه است، پس روی نخ پس‌زمینه. نخ اصلی باید آزاد بماند تا پنل
    // بتواند «یک لحظه…» را نشان بدهد؛ یخ زدنِ رابط سر پایان بدترین لحظه‌ی ممکن است.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self->_fa finish];
        [self->_en finish];
        NSString *fa = self->_fa.text;
        NSString *en = self->_en.text;
        NSTimeInterval took = [NSDate.date timeIntervalSinceDate:t0];
        ZLog(@"engine: پایان، %.0f ثانیه صدا، %.1f ثانیه تا متن، %lu نویسه، %ld برش تحمیلی",
             self->_seconds, took, (unsigned long)fa.length, (long)self->_fa.degradedCuts);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_delegate engineDidFinish:fa second:en.length ? en : nil took:took];
        });
    });
}

- (void)cancel {
    _stopping = YES;
    if (_cap) {
        dispatch_source_cancel(_cap);
        _cap = nil;
    }
    [_mic stop];
    _mic = nil;
    [_fa cancel];
    [_en cancel];
    [_recorder discard];
}

- (NSInteger)degradedCuts { return _fa.degradedCuts; }

@end

// ---------- جاروی هفت‌روزه ----------
// صدای سشن برای عیب‌یابی می‌ماند، ولی نه برای همیشه. هفت روز کافی است که یک تشخیصِ
// بد پیدا و بازسازی شود، و کوتاه است که ضبطِ حرف‌های آدم روی دیسک تلنبار نشود.
// سر لانچ اجرا می‌شود و بی‌صدا: نه دیالوگی، نه سوالی.
void ZSweepOldSessions(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-kZSessionKeepDays * 86400];
        NSArray *items = [fm contentsOfDirectoryAtURL:ZSessionsDir()
                           includingPropertiesForKeys:@[NSURLContentModificationDateKey]
                                              options:0 error:nil];
        NSUInteger gone = 0;
        for (NSURL *u in items) {
            NSDate *m = nil;
            if (![u getResourceValue:&m forKey:NSURLContentModificationDateKey error:nil]) continue;
            if (!m || [m compare:cutoff] != NSOrderedAscending) continue;
            if ([fm removeItemAtURL:u error:nil]) gone++;
        }
        if (gone) ZLog(@"جارو: %lu سشن قدیمی‌تر از %d روز پاک شد", (unsigned long)gone, kZSessionKeepDays);
    });
}
