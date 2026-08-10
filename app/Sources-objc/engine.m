// موتور: میکروفن، ضبط روی دیسک، و خط لوله. و بس.
//
// آنچه اینجا **نیست** مهم‌تر از آنچه هست: نه چرخش سشن، نه بافر بازپخش، نه واچ‌داگ
// گیر کردن، نه سوپروایزر و backoff، نه هم‌پوشانی، نه نجات و تخلیه. همه‌ی آن‌ها در
// نسخه یک برای تعمیرِ یک چیز بودند: سشنی که ۲۰ تا ۲۴ ثانیه صدا می‌خورد و از سقفِ
// ~۳۰ ثانیه‌ای سرور می‌ترسید. حالا هر سشن یک تکه‌ی ~۷ ثانیه‌ای می‌خورد و می‌میرد، پس
// نه به سقف نزدیک می‌شود، نه چرخشی لازم است، نه درزی هست که دوخته شود.
//
// **خط لوله در حین حرف زدن هیچ متنی نمی‌دهد**، و همان یک جمله کوتاه‌ترین توضیح نسخه
// دو است. دو کانال بیشتر ندارد: بلندی صدا (برای نشان)، و سر پایان یک متن.
//
// و یک کانال سوم هست که باید دقیق فهمیده شود، وگرنه شبیه برگشتِ نسخه یک به
// نظر می‌رسد: پیش‌نمایش. آن متن **از این خط لوله نمی‌آید** و هیچ ربطی به متنِ نهایی
// ندارد؛ یک استریم جدا و نمایشی است (preview.m) که موتور فقط صدایش را هم به آن
// می‌دهد و خروجی‌اش را عینا رد می‌کند. نتیجه نیست و هیچ‌وقت نمی‌شود، پس نه دفتری
// می‌خواهد نه راچتی نه پاک‌کنی. خاموش هم که باشد اصلا ساخته نمی‌شود.
#import "zemzeme.h"

@implementation ZEngine {
    NSString *_lang;
    ZMic *_mic;
    ZPipe *_fa;
    ZPipe *_en;              // پاس دوم انگلیسی؛ نال یعنی خاموش
    // خط لوله‌هایی که زبانشان عوض شده و بازنشسته‌اند. زنده‌اند تا متنشان برسد، و سر
    // پایان به ترتیب جلوی متنِ خط لوله‌ی فعلی چیده می‌شوند. خالی، مگر اینکه کاربر
    // وسط دیکته زبان را عوض کرده باشد.
    NSMutableArray<ZPipe *> *_retired;
    NSMutableArray<ZPipe *> *_retiredSecond;
    ZPreviewStream *_preview;   // نمایشی و دور ریختنی؛ نال یعنی خاموش
    NSDate *_startedAt;
    NSTimeInterval _seconds; // ثانیه‌ی صدای بلعیده‌شده، از بایت‌ها نه از ساعت دیوار
    BOOL _stopping;
    BOOL _fileMode;
    dispatch_source_t _cap;
}

// متنِ یک زنجیره‌ی خط لوله: بازنشسته‌ها به ترتیب، بعد زنده. همان قاعده‌ی سرهم کردنِ
// تکه‌ها، یک پله بالاتر: با یک فاصله به هم می‌چسبند و بس.
static NSString *ZChainText(NSArray<ZPipe *> *retired, ZPipe *live) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (ZPipe *p in retired) {
        NSString *t = p.text;
        if (t.length) [parts addObject:t];
    }
    NSString *t = live.text;
    if (t.length) [parts addObject:t];
    return [parts componentsJoinedByString:@" "];
}

- (instancetype)initWithLang:(NSString *)lang {
    if ((self = [super init])) _lang = [lang copy];
    return self;
}

- (NSTimeInterval)seconds { return _seconds; }

// سطل آشغال ساعت را هم صفر می‌کند. کاربری که «از نو» می‌زند انتظار دارد شمارنده هم
// از نو شروع کند، وگرنه عددی می‌بیند که به هیچ صدایی که هنوز روی دیسک هست مربوط نیست.
- (void)resetClock { _seconds = 0; }

- (void)resetPreview { [_preview reset]; }

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
    if (!_retired) {
        _retired = [NSMutableArray array];
        _retiredSecond = [NSMutableArray array];
    }
    _fa = [[ZPipe alloc] initWithLang:_lang];
    // پاس دوم انگلیسی روی همان صدا: رایگان، موازی، و روی متنِ پر از اصطلاح خیلی خوب.
    // اندازه‌گیری روی ضبط ۰۲: پاس فارسی از «دیتابیس پستگرس» به بعد را کامل انداخته
    // بود و پاس انگلیسی همان‌جا شنیده بود. ولی روی ۰۷ (اصطلاح‌های رایج) تقریبا هیچ،
    // پس بیمه است نه ستون، و پیش‌فرض خاموش.
    //
    // و نال کردنِ صریح در حالت دیگر لازم است، نه اضافه: این تابع حالا بار دوم هم صدا
    // زده می‌شود (سر عوض کردن زبان). بی این خط، رفتن از فارسی به انگلیسی خط لوله‌ی
    // بازنشسته‌ی پاس دوم را زنده نگه می‌داشت و صدای تازه را هم به آن می‌داد.
    _en = (ZSettings.shared.secondPass && [_lang hasPrefix:@"fa"])
        ? [[ZPipe alloc] initWithLang:@"en-US"] : nil;
}

// ---------- زبان، وسط سشن ----------
//
// چرا این‌قدر کوچک است: در نسخه دو هر تکه سشنِ مستقل خودش را می‌گیرد و تکه‌ها فقط با
// یک فاصله به هم می‌چسبند. پس «زبان عوض شد» یعنی «این خط لوله را همین‌جا ببند، بعدی
// را با زبان تازه باز کن». درزی نیست که بخواهد دوخته شود، و همین است که کاری را که
// در نسخه یک شدنی نبود اینجا به چند خط تبدیل می‌کند.
//
// صدایی که تا این لحظه در بافر مانده با زبان **قبلی** رونویسی می‌شود. این مصالحه
// نیست، درست است: آن صدا به همان زبان گفته شده. تنها هزینه‌اش یک برش سر همین نقطه
// است، و آدم عملا وقتی زبان را عوض می‌کند که جمله‌اش تمام شده.
//
// قبلا این تابع وجود نداشت و switchLang فقط تنظیم را می‌نوشت. نتیجه بدترین حالت
// ممکن بود: دکمه‌ی نوار همان لحظه زبان تازه را نشان می‌داد و موتور تا آخر سشن به
// زبان قبلی می‌نوشت، یعنی رابط دروغ می‌گفت.
- (void)switchLang:(NSString *)lang {
    if (_stopping || !lang.length || [lang isEqualToString:_lang]) return;

    // بازنشسته، نه کشته: صدایشان گفته شده و متنش حق کاربر است. finish بلوکه است
    // (منتظر شبکه می‌ماند) پس روی نخ پس‌زمینه می‌رود؛ نخ اصلی وسط دیکته حق ندارد
    // حتی یک لحظه بایستد. سر پایان، stop دوباره finish می‌زند و آن یکی بی‌ضرر است:
    // ZPipe با پرچم _done از تکرار محافظت می‌کند.
    NSMutableArray<ZPipe *> *closing = [NSMutableArray array];
    if (_fa) { [_retired addObject:_fa]; [closing addObject:_fa]; }
    if (_en) { [_retiredSecond addObject:_en]; [closing addObject:_en]; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        for (ZPipe *p in closing) [p finish];
    });

    _lang = [lang copy];
    [self buildPipes];

    // پیش‌نمایش هم زبان دارد و همان لحظه باید عوض شود، وگرنه دُم خاکستری به یک زبان
    // حدس می‌زند و متن نهایی به زبان دیگر می‌آید. نال کردنش کافی است: syncPreview سر
    // تکه‌ی صدای بعدی خودش دوباره و با زبان تازه می‌سازدش.
    [_preview stop];
    _preview = nil;

    ZLog(@"engine: زبان وسط سشن شد %@، %lu خط لوله بازنشسته",
         _lang, (unsigned long)(_retired.count + _retiredSecond.count));
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
    // و آخر از همه، چون مهم‌ترین نیست: پیش‌نمایش. **بعد از** ضبط و خط لوله، تا اگر
    // روزی کند یا خراب شد، آن دو تا از قبل صدایشان را گرفته باشند.
    [self syncPreview];
    [_preview feed:pcm];
}

// تاگل وسط دیکته هم باید همان لحظه اثر کند، در هر دو جهت: روشن که شد پیش‌نمایش راه
// بیفتد، و خاموش که شد **واقعا بایستد**، نه اینکه پنهان شود و پهنای باند بخورد.
// اینجا و نه سر ساختِ موتور، چون تاگل به دورِ شنیدن گره نخورده.
//
// مسیر فایل هیچ‌وقت پیش‌نمایش ندارد: آنجا آدمی پشتش نیست که نگاه کند، و ابزار
// اندازه‌گیری حق ندارد یک تماس شبکه‌ی اضافه در حسابش بیاورد.
- (void)syncPreview {
    BOOL want = (ZSettings.shared.previewStream || _previewInFileMode)
              && (!_fileMode || _previewInFileMode);
    if (want == (_preview != nil)) return;
    if (!want) {
        [_preview stop];
        _preview = nil;
        ZLog(@"preview: خاموش شد");
        return;
    }
    _preview = [[ZPreviewStream alloc] initWithLang:_lang];
    __weak typeof(self) weak = self;
    _preview.onText = ^(NSString *t) {
        typeof(self) me = weak;
        if (!me || me->_stopping) return;
        id<ZEngineDelegate> d = me->_delegate;
        if ([d respondsToSelector:@selector(enginePreview:)]) [d enginePreview:t];
    };
    [_preview start];
    ZLog(@"preview: روشن شد، زبان %@", _lang);
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
    // پیش‌نمایش همین‌جا و بی‌معطلی می‌میرد، نه سر رسیدن متن: از این لحظه پنل دارد
    // «یک لحظه…» می‌گوید و یک حدسِ خامِ تازه فقط نویز است.
    [_preview stop];
    _preview = nil;
    [_recorder finish];

    NSDate *t0 = NSDate.date;
    // خالی کردن صف بلوکه است، پس روی نخ پس‌زمینه. نخ اصلی باید آزاد بماند تا پنل
    // بتواند «یک لحظه…» را نشان بدهد؛ یخ زدنِ رابط سر پایان بدترین لحظه‌ی ممکن است.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // بازنشسته‌ها هم منتظر می‌مانند. تقریبا همیشه از قبل تمام شده‌اند (سر عوض
        // کردن زبان finish خورده‌اند) و این حلقه آنی رد می‌شود؛ ولی اگر کاربر یک
        // ثانیه بعدِ عوض کردن زبان سشن را ببندد، متنِ آن تکه هنوز در راه است و
        // نباید جا بماند.
        for (ZPipe *p in self->_retired) [p finish];
        for (ZPipe *p in self->_retiredSecond) [p finish];
        [self->_fa finish];
        [self->_en finish];
        NSString *fa = ZChainText(self->_retired, self->_fa);
        NSString *en = ZChainText(self->_retiredSecond, self->_en);
        NSTimeInterval took = [NSDate.date timeIntervalSinceDate:t0];
        ZLog(@"engine: پایان، %.0f ثانیه صدا، %.1f ثانیه تا متن، %lu نویسه، %ld برش تحمیلی",
             self->_seconds, took, (unsigned long)fa.length, (long)self.degradedCuts);
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
    [_preview stop];
    _preview = nil;
    [_fa cancel];
    [_en cancel];
    for (ZPipe *p in _retired) [p cancel];
    for (ZPipe *p in _retiredSecond) [p cancel];
    [_recorder discard];
}

// جمعِ کل سشن، نه فقط خط لوله‌ی فعلی: اگر کاربر وسط راه زبان را عوض کرده باشد،
// برش‌های تحمیلیِ قبل از آن هم مالِ همین سشن‌اند و در شمارش می‌آیند.
- (NSInteger)degradedCuts {
    NSInteger n = _fa.degradedCuts;
    for (ZPipe *p in _retired) n += p.degradedCuts;
    return n;
}

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
