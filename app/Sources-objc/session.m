// سشن: از دابل‌تپ تا متن.
//
// قصه‌ی نسخه دو در یک خط: **در حین حرف زدن هیچ متنی نشان داده نمی‌شود.** فقط یک
// نشان که می‌گوید دارم می‌شنوم. سر پایان، یک بار، کل متن.
//
// همین یک تصمیم بیشترِ نسخه یک را حذف کرد. متنِ لحظه‌ای یعنی متنی که هنوز قطعی
// نیست روی صفحه بنشیند، و آن یعنی باید بشود پسش گرفت: دفتر متن، خواندنِ دوباره‌ی
// اکسسبیلیتی، پاک کردن و تایپ دوباره، راچت interim، ناحیه‌ی خاکستری، و مسابقه‌ی
// همه‌ی این‌ها با تایپِ خودِ کاربر. هیچ‌کدام حالا موضوعیت ندارند.
//
// و «پیش‌نمایش» (پیش‌فرض خاموش) این را نقض نمی‌کند، چون آنچه نشان می‌دهد **متنِ
// لحظه‌ای نیست**: تکه‌ی تمام‌شده‌ی رونویسی است، عینا همان چیزی که سر پایان هم تحویل
// می‌شود. چیزی که هیچ‌وقت پس گرفته نمی‌شود، هیچ‌کدام از آن ماشین‌آلات را لازم ندارد.
// تنها کاری که می‌کند، زودتر نشان دادنِ همان متن است، و رنگش می‌گوید هنوز تمام نشده.
//
// در عوض یک بدهیِ تازه داریم و باید صریح صافش کنیم: کاربر باید **بداند** که پایان
// را خودش اعلام می‌کند. در نسخه یک متن حین حرف زدن می‌آمد، پس هیچ‌وقت لازم نبود
// چیزی را علامت بدهد. حالا لازم است، و اپی که ساکت منتظر بماند در حالی که کاربر هم
// منتظر است، خراب است. پس این جمله سه جا نوشته می‌شود: روی پنل، کنار کرسر، و در
// کارت راهنما.
#import "zemzeme.h"

// «حرفت که تمام شد، یک بار Command راست را بزن». یک رشته، سه مصرف‌کننده: اگر هر
// کدام متن خودش را داشت، یکی‌شان دیر یا زود عقب می‌ماند.
NSString *const ZStopHint = @"حرفت که تمام شد، یک بار Command راست را بزن";

// نام حالت برای لاگ و برای فیدبک روی صفحه؛ دو جا، یک منبع
static NSString *ZModeSlug(ZMode m) { return m == ZModeCursor ? @"cursor" : @"collect"; }
NSString *ZModeLabel(ZMode m) { return m == ZModeCursor ? @"کنار کرسر" : @"جمع در پنل"; }

@implementation ZSession {
    ZPanel *_panel;
    ZCaretDot *_dot;
    ZMode _mode;
    ZRecorder *_recorder;
    NSURL *_sessionDir;
    NSRunningApplication *_target;   // اپی که سر شروع جلو بود؛ متن به همان می‌رود
    NSString *_statusText;
    NSString *_warning;
    NSString *_workingMsg;
    // متن دیگر یک رشته‌ی انباشته نیست: از روی جاهای صف رندر می‌شود (`liveText`).
    // انباشتن، ترتیب را به یک قرارداد تبدیل می‌کرد و تکه‌ی دیررس جا نداشت بنشیند.
    ZQueue *_queue;
    // **دو شمارنده، نه یکی.** «نشان داده شد» و «سر کرسر درج شد» دو چیزند و یکی
    // گرفتنشان باگی ساخت که کاربر مستقیم دید: در حالت جمع، تک‌تپ متن را در پنل
    // نشان می‌داد و همان را «تحویل‌شده» علامت می‌زد، پس Esc بعدی چیزی برای درج
    // پیدا نمی‌کرد و متن فقط در کلیپ‌بورد می‌ماند.
    NSUInteger _inserted;            // چقدر از متن واقعا سر کرسر رفته
    NSString *_polished;             // آخرین متنی که مدل نوشته؛ پایه‌ی جوشِ دور بعد
    NSInteger _polishedThrough;      // مدل تا این جا را دیده؛ بعدش خام است
    // تحویل شده ولی هنوز تکه‌ای در راه است. سشن باز می‌ماند و خودش پر می‌شود؛ Escِ
    // بعدی یعنی «همین بس است» و می‌بندد، و صف در پس‌زمینه کارش را تمام می‌کند.
    BOOL _settling;
    NSInteger _dropEpoch;            // چند بار دور ریخته شده؛ جوابِ پاسِ کهنه را می‌اندازد
    NSTimeInterval _secondsBefore;   // ثانیه‌ی دورهای قبلی؛ ساعت روی هم جمع می‌شود
    NSInteger _round;                // چندمین دورِ شنیدن در همین سشن
    BOOL _listening;
    BOOL _errorState;
    ZBusy _busy;                     // کاری در جریان: صدا←متن، یا پاس هوش مصنوعی
    BOOL _paused;                    // شنیدن ایستاده ولی سشن زنده است
    BOOL _closing;                   // این دور آخری است: تحویل بده و ببند
    BOOL _finished;
    BOOL _stopping;
    NSTimer *_clock;
}

- (instancetype)initWithEngine:(ZEngine *)engine panel:(ZPanel *)panel {
    if ((self = [super init])) {
        _engine = engine;
        _panel = panel;
        _dot = [ZCaretDot new];
        _mode = ZSettings.shared.mode;
        // صف مالِ سشن است نه موتور: موتور سر هر دورِ تازه‌ی شنیدن از نو ساخته
        // می‌شود و تکه‌ی جامانده‌ی دور قبل باید از آن جان سالم ببرد.
        _queue = [ZQueue new];
        __weak typeof(self) ws = self;
        _queue.onChange = ^{ [ws queueChanged]; };
    }
    return self;
}

// ---------- شروع ----------

- (void)start {
    _target = NSWorkspace.sharedWorkspace.frontmostApplication;
    _sessionDir = [ZSessionsDir() URLByAppendingPathComponent:ZTimestampId()];
    [NSFileManager.defaultManager createDirectoryAtURL:_sessionDir
                          withIntermediateDirectories:YES attributes:nil error:nil];
    // صدا همیشه و پیوسته روی دیسک، نه فقط وقتی تاگلی روشن باشد: فایل مرجع همه‌چیز
    // است. اگر شبکه بمیرد یا اپ کرش کند، حرفِ گفته‌شده سر جایش می‌ماند. تاگلِ
    // «ضبط صدای سشن» حالا معنیِ دیگری دارد و پایین‌تر سر پایان اعمال می‌شود.
    NSURL *audio = [_sessionDir URLByAppendingPathComponent:@"audio.flac"];
    _recorder = [[ZRecorder alloc] initWithURL:audio];
    _engine.recorder = _recorder;
    // و از همین‌جا صف می‌داند صدا کجاست و دفترچه‌اش کجا نوشته شود. با این دو، تکه‌ی
    // در انتظار از بسته شدنِ اپ هم جان سالم می‌برد: لانچِ بعدی برش می‌دارد و تمامش
    // می‌کند. `_recorder.url` اینجا هنوز نال است (فایل سر اولین بایت ساخته می‌شود)،
    // پس همان مسیرِ خواسته‌شده داده می‌شود نه جوابِ ضبط‌کننده.
    _queue.audio = audio;
    _queue.manifest = ZQueueManifestIn(_sessionDir);
    _queue.lang = ZSettings.shared.lang;
    _engine.queue = _queue;
    _engine.delegate = self;

    [self wirePanel];

    if (!ZInjector.accessibilityOK) {
        _warning = @"مک هنوز اجازه نداده؛ متن جای کرسر نوشته نمی‌شود";
        [ZInjector promptAccessibility];
    }

    NSError *err = nil;
    if (![_engine startWithError:&err]) {
        _errorState = YES;
        _statusText = err.localizedDescription ?: @"میکروفن باز نشد";
        [self render];
        return;
    }
    ZLog(@"session: شروع، حالت %@، مقصد %@", ZModeSlug(_mode), _target.localizedName ?: @"?");
    if (_mode == ZModeCursor) [_dot show];
    else [_panel show];
    ZPlay(ZSoundStart);
    [self startClock];
    [self render];
}

// بی این، شمارنده فقط سرِ رویدادها تازه می‌شد و عملا میخ می‌ماند. یک تیکِ ثانیه‌ای
// تا وقتی می‌شنویم، و نه یک لحظه بیشتر.
- (void)startClock {
    if (_clock) return;
    __weak typeof(self) ws = self;
    _clock = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
        typeof(self) me = ws;
        if (!me || !me->_listening) return;
        [me render];
    }];
}

- (void)stopClock {
    [_clock invalidate];
    _clock = nil;
}

// دکمه‌های نوار به همین سشن وصل می‌شوند، نه به دلیگیتِ اپ: کارشان مالِ سشن است و
// بی‌سشن معنی ندارند. سه تای دیگر (فایل، راهنما، تمیز کردن متن) در دلیگیت وصل‌اند
// چون بی‌سشن هم کار می‌کنند.
//
// این یک بار جا افتاد و گران بود: موقع جدا کردن پنل از سشن، همین چند خط نیامد و
// **هشت دکمه‌ی نوار بی‌صدا مرده بودند**. میان‌برهای کیبورد کار می‌کردند، پس خرابی
// خوب قایم شده بود: کاربر فقط می‌دید که کلیک روی دکمه هیچ کاری نمی‌کند.
//
// ضعیف، چون پنل از سشن عمر بیشتری دارد و بلاکِ قوی یعنی سشن هیچ‌وقت آزاد نشود.
- (void)wirePanel {
    __weak typeof(self) ws = self;
    _panel.onClose      = ^{ [ws finish]; };
    // `pauseToggle` و نه `togglePause`: دکمه سه چهره دارد (مکث، ادامه، تلاش دوباره) و
    // فقط این یکی هر سه را می‌بندد. با `togglePause` دقیقا در دو حالتی که دکمه
    // «ادامه بده» و «دوباره تلاش کن» نشان می‌داد هیچ کاری نمی‌کرد: آن متد سرِ
    // `_paused` همان اول برمی‌گردد.
    _panel.onPauseToggle = ^{ [ws pauseToggle]; };
    _panel.onCopyNow    = ^{ [ws copyNow]; };
    _panel.onInsertAll  = ^{ [ws insertHere]; };
    _panel.onTrash      = ^{ [ws dropPending]; };
    _panel.onLangSwitch = ^{ [ws switchLang]; };
    _panel.onModeToggle = ^{ [ws toggleMode]; };
    _panel.onSensToggle = ^{ [ws toggleSensitivity]; };
}

// و سرِ پایان باز می‌شوند: پنل زنده می‌ماند و نباید دکمه‌هایش به سشنِ مرده اشاره کنند.
- (void)unwirePanel {
    _panel.onClose = nil;
    _panel.onPauseToggle = nil;
    _panel.onCopyNow = nil;
    _panel.onInsertAll = nil;
    _panel.onTrash = nil;
    _panel.onLangSwitch = nil;
    _panel.onModeToggle = nil;
    _panel.onSensToggle = nil;
}

// ---------- موتور ----------

- (void)engineState:(ZEngineState)state message:(NSString *)msg {
    _errorState = NO;
    _listening = NO;
    switch (state) {
        case ZEngineIdle: _statusText = @""; break;
        case ZEngineConnecting: _statusText = @"در حال اتصال…"; break;
        case ZEngineListening:
            _listening = YES;
            // و همین‌جا، هر بار: تا وقتی می‌شنویم، جمله‌ی پایان جلوی چشم است.
            _statusText = [@"در حال گوش کردن ﹒ " stringByAppendingString:ZStopHint];
            break;
        case ZEnginePaused: _statusText = @"مکث. برای ادامه یک بار Command راست را بزن"; break;
        case ZEngineGaveUp:
            _errorState = YES;
            _statusText = msg.length ? msg : @"تشخیص گفتار قطع شد";
            break;
    }
    [self render];
}

- (void)engineLevel:(float)rms {
    if (_mode == ZModeCursor) [_dot pulseLevel:rms];
    else [_panel pulseLevel:rms];
}

// متنِ خامِ پیش‌نمایش. **هیچ تصمیمی از اینجا نمی‌گذرد**: متن سشن دست نمی‌خورد، چیزی
// درج نمی‌شود، چیزی کپی نمی‌شود، هیچ حالتی عوض نمی‌شود. فقط دُم خاکستری بازنویسی
// می‌شود. خاموش که باشد، این متد یک return است و بس.
//
// و چرا این برگشتِ نسخه یک نیست: آن متنِ لحظه‌ای **نتیجه** بود، پس باید پس گرفته
// می‌شد و دفتر و راچت و پاک‌کن لازم داشت. این نتیجه نیست و هیچ‌وقت نمی‌شود؛ سر پایان
// دور ریخته می‌شود و جایش را متنِ واقعی می‌گیرد. چیزی که دور ریختنی است، دوخت لازم
// ندارد.
//
// جایگزین، نه اضافه: استریم هر بار کلِ متنش را می‌دهد و اینجا هیچ حسابی نگه داشته
// نمی‌شود. حساب نگه داشتن یعنی دو منبع حقیقت برای یک متنِ دورریختنی.
- (void)enginePreview:(NSString *)text {
    if (!ZSettings.shared.previewStream || _mode != ZModeCollect) return;
    if (!_listening) return;
    [_panel setPreviewText:text];
}

// حالِ یک جا عوض شد: متنی رسید، یا سرور گفت حرفی نبود، یا یک تلاش نرسید.
//
// **هیچ آژیری اینجا نیست**، و همین نکته‌ی اصلی است. تا دیروز هر تکه‌ی نرسیده یک صدای
// ناخوشایند و یک هشدار می‌داد و دو تای پشت سر هم پنل را قرمز می‌کرد؛ یعنی یک قطعیِ
// ده ثانیه‌ای، که خودش خود‌به‌خود درست می‌شد، به یک وضعیتِ اضطراری تبدیل می‌شد که
// کاربر باید حلش می‌کرد. حالا فقط یک شمار آرام روی پنل می‌نشیند و صف خودش می‌رود.
- (void)queueChanged {
    // سشن بسته شده و متن دیررس رسیده: بی‌سروصدا سر جایش می‌نشیند. کلیپ‌بورد دست
    // نمی‌خورد (کاربر ده دقیقه پیش رفته و حالا چیز دیگری کپی کرده)، ولی text.txt و
    // ردیف تاریخچه تازه می‌شوند. تاریخچه سر خواندن با sid جمع می‌کند، پس همان ردیفِ
    // خودِ این سشن کامل می‌شود، نه یک ردیف تازه.
    if (_finished) {
        NSString *all = [self.liveText stringByTrimmingCharactersInSet:
                         NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!all.length) return;
        [self writeRawTranscript:_queue.text];
        [self writeTranscript:all];
        ZHistoryAppend(all, _sessionDir.lastPathComponent, ZHistoryViaAuto, _target.localizedName);
        ZLog(@"session: تکه‌ی دیررس نشست، ردیف تاریخچه تازه شد (%ld در راه)", (long)_queue.waiting);
        return;
    }
    [self writeRawTranscript:_queue.text];
    // هنوز داریم می‌شنویم، یا منتظر بسته شدن صدا، یا وسط پاس: فقط شمار تازه شود.
    // تحویل جای خودش را دارد و دو بار تحویل دادن یعنی دو بار درج.
    if (_listening || _stopping || _busy != ZBusyNone) {
        [self render];
        return;
    }
    if (_queue.drained) [self polishThenDeliver];
    else [self render];
}

// متنِ همین لحظه: آنچه مدل تمیز کرده، به‌اضافه‌ی هر چه بعد از آن رسیده. هیچ رشته‌ای
// انباشته نمی‌شود، پس تکه‌ی دیررس خودش سر جای ساختاری‌اش می‌نشیند و هیچ جراحی لازم
// ندارد. و پاسِ ردشده هم دیگر «چسباندنِ دستی» لازم ندارد: دُمِ خام از قبل اینجاست.
- (NSString *)liveText { return [self textWithTail:[_queue textFrom:_polishedThrough extra:NO]]; }

// و متنی که حق دارد سر کرسر برود: فقط تا اولین جای نرسیده. اگر تکه‌ی هفتم در راه
// باشد و هشتم را حالا درج کنیم، هفتم که برسد جایی برای نشستن ندارد و ترتیبِ حرفِ
// آدم به هم می‌خورد. صف که خالی باشد، این دقیقا همان متنِ کامل است.
- (NSString *)caretText {
    if (_queue.drained) return self.liveText;
    return [self textWithTail:[_queue settledTextFrom:_polishedThrough]];
}

- (NSString *)textWithTail:(NSString *)tail {
    if (!_polished.length) return tail ?: @"";
    if (!tail.length) return _polished;
    return [NSString stringWithFormat:@"%@ %@", _polished, tail];
}

// صدا تمام شد و هر تکه دستِ‌کم یک بار امتحان شده. `text` و `second` را موتور از
// روی همین صف ساخته و اینجا لازم نیستند: سشن خودش صاحبِ صف است و آنچه می‌خواهد
// (دُمِ خام، متنِ تمام، متنِ تا اولین جای نرسیده) را از همان‌جا می‌گیرد.
- (void)engineDidFinish:(NSString *)text second:(NSString *)second took:(NSTimeInterval)took {
    _listening = NO;
    // انتظارِ صدا←متن تمام شد. اگر پاس هوش مصنوعی در کار باشد، انتظارِ دومی با شکل و
    // رنگِ خودش شروع می‌شود.
    _busy = ZBusyNone;
    _workingMsg = nil;
    _stopping = NO;    // دورِ بعد باید بتواند دوباره بایستد
    // خام، همین‌جا و پیش از پاس: هرچه تشخیص گفتار داده روی دیسک می‌ماند.
    [self writeRawTranscript:_queue.text];
    ZLog(@"session: دور %ld، متن آماده در %.1f ثانیه، %ld در راه",
         (long)_round, took, (long)_queue.waiting);
    if (_engine.cappedOut) {
        // سقف پنج دقیقه: صریح بگو چه شد و کجا باید برود. سکوت در این لحظه یعنی
        // کاربر فکر کند اپ خراب شده، در حالی که متنش همین‌جاست.
        _warning = @"پنج دقیقه شد و دیکته تمام شد؛ برای صدای بلندتر از رونویسی فایل استفاده کن (Command راست + F)";
    }
    [self polishThenDeliver];
}

// پاس هوش مصنوعی، فقط روی متن و فقط اگر خودت خواسته باشی. هیچ‌وقت بلوکه‌کننده نیست:
// نتیجه‌اش که نیامد، همین متن خام تحویل می‌شود.
//
// و **یک بار، سرِ خالی شدنِ صف**، نه هر دور. مدل کلِ متن را از نو می‌نویسد؛ اگر
// وسطش جای نرسیده‌ای باشد، آن درز را «تمیز» می‌کند و تکه‌ی بعدی که برسد دیگر جایی
// ندارد. پس تا آخرین تکه نرسیده، متن خام می‌ماند و همان تحویل می‌شود.
- (void)polishThenDeliver {
    NSInteger through = _queue.nextSeq;
    NSString *fresh = [_queue textFrom:_polishedThrough extra:NO];
    // شرطِ پاس، و **نه `hasKey`**. این یک خط چند وقت پاس هوش مصنوعی را بی‌صدا خاموش
    // نگه داشته بود: `hasKey` روی نخ اصلی عمدا محافظه‌کار است و فقط جوابِ کش‌شده‌ی
    // پرسشِ **بی‌پنجره**ی کی‌چین را می‌دهد. روی این دستگاه آن پرسش همیشه ۲۵۲۹۳
    // (errSecAuthFailed) می‌گیرد، پس سر هر لانچِ تازه `hasKey` نه می‌گفت و پاس اصلا
    // اجرا نمی‌شد. معیار درست «کلید را همین حالا در دست دارم» نیست، «می‌دانیم که
    // کلیدی نیست» است: مسیر خودِ پاس با اجازه‌ی پنجره می‌خواند و اگر آخرش کلید نبود
    // خودش خطای روشن برمی‌گرداند و متن خام سر جایش می‌ماند.
    BOOL want = ZSettings.shared.finalPassEnabled && _queue.drained && fresh.length > 0;
    if (!want || ZFinalPass.keyKnownMissing) {
        if (want) {
            // یک منبع حقیقت برای این جمله. «نیست» و «پذیرفته نشد» دو کارِ مختلف از
            // کاربر می‌خواهند، و تا امروز هر دو «نیست» می‌گفتند.
            _warning = ZFinalPass.missingKeyHint;
        }
        [self deliver];
        return;
    }
    _busy = ZBusyPolish;
    _workingMsg = @"در حال تمیز کردن متن…";
    [self render];
    __weak typeof(self) ws = self;
    NSString *before = _polished;
    NSInteger epoch = _dropEpoch;
    void (^landed)(NSString *, NSString *) = ^(NSString *out, NSString *err) {
        __strong typeof(ws) s = ws;
        if (!s) return;
        s->_busy = ZBusyNone;
        s->_workingMsg = nil;
        // وسط پاس، کاربر دور ریخت. این جواب مالِ متنی است که دیگر وجود ندارد و
        // نوشتنش یعنی برگشتنِ همان حرف‌هایی که کاربر گفت پاکشان کن.
        if (s->_dropEpoch != epoch) {
            ZLog(@"session: پاس رسید ولی متنش دور ریخته شده بود، انداخته شد");
            [s deliver];
            return;
        }
        if (out.length) {
            s->_polished = out;
            s->_polishedThrough = through;
        } else if (err.length) {
            // مدل جواب نداد. چیزی گم نمی‌شود و چسباندنِ دستی هم لازم نیست: متن از
            // روی جاها رندر می‌شود، پس دُمِ خام از قبل سر جایش است.
            s->_warning = [NSString stringWithFormat:@"تمیز نشد (%@)؛ همان متن خام ماند", err];
            ZLog(@"session: پاس رد شد: %@", err);
        }
        [s deliver];
    };
    if (before.length) {
        // **ادامه، با کانتکست.** تکه‌ی تازه جدا از متنِ قبلی فرستاده می‌شود و مدل کل
        // متن را از نو می‌نویسد، پس درز جوش می‌خورد و ضمیر و نقطه‌گذاری با بقیه
        // یک‌دست درمی‌آید. و دو ورودیِ جدا، نه یک متنِ سرهم: مدل باید بداند متنِ اول
        // را خودش نوشته (پس دست نزند) و دومی خامِ تشخیص گفتار است.
        [ZFinalPass.shared runOnText:fresh appendingTo:before
                                lang:ZSettings.shared.lang done:landed];
    } else {
        [ZFinalPass.shared runOnText:_queue.text second:[_queue textFrom:0 extra:YES]
                                lang:ZSettings.shared.lang done:landed];
    }
}

// ---------- تحویل ----------
// دو گونه پایان داریم و فرقشان همان چیزی است که کاربر می‌خواست:
//
//   تک‌تپ Command راست  →  مکث. آنچه تا اینجا گفته شده تحویل می‌شود و **سشن زنده
//                          می‌ماند**؛ تک‌تپ بعدی ادامه‌اش می‌دهد.
//   Esc یا دابل‌تپ       →  تحویل، و تمام. پنل می‌رود.
//
// و درج همیشه فقط **متنِ تازه** را می‌برد (`_inserted`)، وگرنه دورِ دوم کلِ متن
// را دوباره سر کرسر می‌ریخت.
- (void)deliver {
    // **هیچ‌وقت گروگان نگیر.** تا دیروز اگر تکه‌ای نرسیده بود، تحویل همین‌جا می‌ایستاد
    // و تا Escِ دستیِ کاربر (که خودش یک تلاشِ دوباره بود) هیچ متنی بیرون نمی‌رفت:
    // ۲۰۲۶-۰۸-۱۹ یک تکه‌ی ۱٫۴ ثانیه‌ای ۱۷۴۱ نویسه را همین‌طور نگه داشت. آنچه رسیده
    // حقِ کاربر است و همین حالا می‌رود؛ بقیه خودشان می‌رسند و همین‌جا می‌نشینند.
    BOOL wouldInsert = (_mode == ZModeCursor) || _closing;
    _busy = ZBusyNone;
    _workingMsg = nil;
    // اینجا و فقط اینجا خاکستری تمام می‌شود. تا این خط، متن هنوز «در حال آمدن» است:
    // اگر پاس هوش مصنوعی روشن باشد، deliver تا نشستنِ آن پاس اصلا صدا زده نمی‌شود، پس
    // دُم خاکستری دقیقا همان‌قدر می‌ماند که کار واقعا تمام نشده. رنگ یک معنی دارد و
    // همین است.
    [_panel setPreviewText:nil];
    NSString *all = [self.liveText stringByTrimmingCharactersInSet:
                     NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self writeTranscript:all];

    if (!all.length && _queue.waiting) {
        // هنوز هیچ تکه‌ای نرسیده ولی همه در راه‌اند. این «چیزی نشنیدم» نیست و نباید
        // این‌طور گفته شود: حرف زده شده، صدایش روی دیسک است، و فقط هنوز متن نشده.
        _paused = YES;
        [self showWaiting];
        return;
    }
    if (!all.length) {
        // هیچ حرفی شنیده نشد. این دلیل بستنِ پنل نیست: کاربر شاید تازه دارد فکر
        // می‌کند. قبلا همین‌جا سشن بسته می‌شد و کسی که یک لحظه ساکت مانده بود،
        // پنل را از دست می‌داد.
        _statusText = @"چیزی نشنیدم. یک بار Command راست را بزن و دوباره حرف بزن";
        ZPlay(ZSoundTrash);
        if (_closing) [self endNow];
        else { _paused = YES; [self render]; }
        return;
    }
    // در حالت جمع، متنِ ادیتور مرجع است نه متنِ خام: کاربر ممکن است ویرایشش کرده باشد.
    //
    // **اول بخوان، بعد بنویس.** تا امروز برعکس بود (`setEditorText:all` و بعد پس
    // خواندنِ همان)، یعنی متنِ خام روی تایپِ کاربر نوشته می‌شد و بعد همان خام پس
    // خوانده می‌شد: `edited` همیشه با `all` یکی درمی‌آمد و ویرایش کاربر بی‌صدا گم
    // می‌شد. این ادعا از روز اول در همین کامنت بود و از روز اول هم غلط بود؛ فقط
    // چون ادیتور فوکوس نمی‌گرفت هیچ‌کس نمی‌توانست ببیندش. حالا که می‌گیرد، اولین
    // تایپ و Esc همان لحظه نشانش می‌دهد.
    if (_mode == ZModeCollect) {
        if ([_panel editorTouched]) {
            // متن مالِ کاربر است و برنده هم همان: پاس هوش مصنوعی هم حق ندارد رویش
            // بنویسد. ادیتور هم دست نمی‌خورد تا چیزی که می‌بیند همان چیزی باشد که رفت.
            NSString *edited = [_panel editorText];
            if (edited.length) all = edited;
        } else {
            [_panel setEditorText:all];
        }
    }
    // خانه‌ی خودِ متن، و **پیش از** هر تحویلی. کلیپ‌بورد ممکن است دست مدیر کلیپ‌بورد
    // نیفتد و درج ممکن است جای عوضی بنشیند؛ این تنها خطی است که برای ماندنِ متن
    // لازم نیست هیچ‌کدامشان درست کار کرده باشند. سرِ هر مکث دوباره نوشته می‌شود و
    // چون sid یکی است، همان یک ردیف تازه می‌شود نه ردیفِ تازه‌ای اضافه.
    ZHistoryAppend(all, _sessionDir.lastPathComponent, ZHistoryViaAuto, _target.localizedName);
    // امضا اینجا و فقط اینجا سوار می‌شود: تاریخچه و text.txt متنِ خودِ کاربر را
    // گرفتند و امضا تویشان نیست. تاگل که فردا خاموش شود، همان ردیف‌های قدیمی هم
    // بی‌امضا تحویل می‌دهند.
    //
    // و تا تکه‌ای در راه است، امضا نمی‌خورد: امضا یعنی «تمام شد» و این متن هنوز
    // تمام نشده. تکه‌ی بعدی که برسد، همین‌جا دوباره رد می‌شود و آن‌وقت امضا می‌گیرد.
    BOOL sign = _queue.drained;
    [ZInjector copyFinal:sign ? ZSigned(all) : all];

    // درج کِی: در حالت کرسر همیشه (پنلی نیست که متن را نشان بدهد)، و در حالت جمع
    // فقط سرِ Esc و دابل‌تپ. و همیشه فقط آنچه هنوز نرفته.
    //
    // و هیچ‌وقت وقتی جای خالی مانده: متنِ سوراخ‌دار سر کرسرِ کسی نمی‌رود. تحویلِ نصفه
    // بدترین حالت است، چون کاربر نمی‌فهمد چه چیزی کم است.
    // و آنچه سر کرسر می‌رود فقط تا اولین جای نرسیده است (`caretText`): درج کردنِ
    // متنِ بعد از یک جای خالی یعنی وقتی آن جا پر شد، حرف‌ها جابه‌جا سر کرسر نشسته
    // باشند. تحویل نمی‌ایستد، فقط از جایی که ترتیبش قطعی است جلوتر نمی‌رود.
    if (wouldInsert) {
        NSString *src = [self.caretText stringByTrimmingCharactersInSet:
                         NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *fresh = _inserted < src.length ? [src substringFromIndex:_inserted] : @"";
        fresh = [fresh stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (fresh.length) {
            // یک فاصله‌ی آخر، ولی فقط وقتی سشن ادامه دارد. دو کار می‌کند: تکه‌ی
            // بعدی که برسد از قبل جدا افتاده و به کلمه‌ی آخر نمی‌چسبد، و کرسر یک
            // قدم جلو می‌رود که در متنِ راست‌به‌چپ جای درستش را پیدا کند.
            // سرِ Esc نمی‌گذاریم: آنجا حرف تمام شده و فاصله‌ی اضافه فقط زباله است.
            // امضا مالِ **درجِ آخر** است، نه هر تکه. در حالت کرسر متن سر هر مکث
            // تکه‌تکه سر کرسر می‌رود؛ اگر امضا به هر تکه می‌چسبید، متنِ کاربر لای
            // چند امضا تکه‌تکه می‌شد. `_closing` همان مرزِ «این آخرین تکه است».
            BOOL last = _closing && _queue.drained;
            [self injectAtCaret:last ? ZSigned(fresh) : [fresh stringByAppendingString:@" "]
                           keep:ZSigned(all)];
            _inserted = src.length;
        }
    }

    // تکه‌ای در راه است: متن رفت، ولی سشن باز می‌ماند و خودش کامل می‌شود. نه پنجره‌ی
    // خطا، نه صدای ناخوشایند، نه کاری که کاربر باید بکند. Escِ بعدی یعنی «همین بس
    // است» و می‌بندد؛ صف در پس‌زمینه کارش را تمام می‌کند و ردیف تاریخچه را تازه.
    if (_queue.waiting) {
        _paused = YES;
        [self showWaiting];
        return;
    }
    _settling = NO;

    ZPlay(_closing ? ZSoundFinish : ZSoundInsert);
    if (_closing) {
        [self endNow];
        return;
    }
    _paused = YES;
    _statusText = _mode == ZModeCursor
        ? @"درج شد. برای ادامه یک بار بزن، برای تمام کردن Esc"
        : @"متن اینجاست و می‌توانی ویرایشش کنی. برای ادامه یک بار بزن، Esc برای درج و پایان";
    [self render];
}

// شمارِ آرام. تنها چیزی که کاربر باید بداند این است که کار خودش دارد پیش می‌رود و
// کاری از او خواسته نشده. عدد هم برای همین است: بی عدد، «هنوز کامل نشده» می‌تواند
// یعنی یک کلمه یا یعنی نصف دیکته.
- (void)showWaiting {
    _settling = YES;
    _errorState = NO;
    _warning = nil;
    NSInteger n = _queue.waiting;
    _statusText = n == 1
        ? @"یک تکه هنوز در راه است؛ خودش می‌رسد و همین‌جا کامل می‌شود"
        : [NSString stringWithFormat:@"%ld تکه هنوز در راه است؛ خودشان می‌رسند و همین‌جا کامل می‌شود", (long)n];
    [self render];
}

// یک درج، سر کرسرِ همان اپی که سر شروع جلو بود. نه تکه‌تکه، نه پاک‌کردنی.
//
// `keep` متنی است که باید **آخرِ کار** روی کلیپ‌بورد بماند، و حتما پشتِ صف درج
// نوشته می‌شود. چرا: مسیر پیست، کلیپ‌بورد را با نشانه‌ی transient پر می‌کند تا
// تاریخچه‌گیرها آن را رد کنند، و آن نوشتن **بعدِ** copyFinal اتفاق می‌افتد، چون درج
// روی صف است و copyFinal همان‌جا روی نخ اصلی. نتیجه‌اش این بود که در ریموت دسکتاپ
// (تنها اپی که همیشه پیست می‌گیرد) آخرین چیزِ روی کلیپ‌بورد همیشه transient بود:
// مکی هیچ‌وقت متن را در تاریخچه ثبت نمی‌کرد و کاربر با هر پیستِ دستی دست خالی
// می‌ماند. یک کپیِ ساده‌ی پایانی پشتِ همان صف، دقیقا همان بیمه‌ای است که وعده‌اش
// داده شده بود.
- (void)injectAtCaret:(NSString *)text keep:(NSString *)keep {
    // **اول کلید را پس بده.** از وقتی ادیتورِ پنل فوکوس می‌گیرد، پنل می‌تواند پنجره‌ی
    // کلید باشد، و پیست با CGEventPost به هر که فوکوس دارد می‌رود نه به یک pid. بی این
    // خط، کاربری که متن را در پنل ویرایش کرده و بعد درج زده، متن را در همان پنل پیست
    // می‌گیرد و اپ مقصد دست خالی می‌ماند.
    [_panel yieldKey];
    NSRunningApplication *to = _target ?: NSWorkspace.sharedWorkspace.frontmostApplication;
    ZInjector *inj = [ZInjector new];
    ZInsertMode im = [ZSettings.shared insertModeForBundleId:to.bundleIdentifier];
    [inj insert:text pid:to.processIdentifier
    delayMicros:ZSettings.shared.typeDelayMicros
 pasteIfRefused:im == ZInsertPaste
           done:^(BOOL viaAX) { ZLog(@"session: درج شد (ax=%d، %lu نویسه)", viaAX,
                                     (unsigned long)text.length); }];
    if (keep.length) [inj copyFinalAfterPending:keep];
}

// متنِ تحویل‌شده کنار صدا. این **بعدِ** پاس هوش مصنوعی نوشته می‌شود، پس همان چیزی
// است که کاربر گرفته، نه رونوشتِ خام.
- (void)writeTranscript:(NSString *)text {
    if (!text.length) return;
    [text writeToURL:[_sessionDir URLByAppendingPathComponent:@"text.txt"]
          atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// و رونوشتِ **خام**، جدا، پیش از هر دست خوردنی. تا امروز کامنتِ بالای همین فایل
// می‌گفت text.txt «طلای تست» است و خام است، و نبود: در `deliver` و بعدِ پاس نوشته
// می‌شد، پس با پاسِ روشن، متنِ خام هیچ‌جا نمی‌ماند.
//
// هزینه‌اش را همان روز دادیم: برای محکِ پرامپت، متنِ خامِ یک سشن لازم شد و مجبور
// شدیم از فایل صدا **دوباره رونویسی** کنیم تا به دستش بیاوریم، یعنی طلای تست از
// اول وجود نداشت. یک فایل چند بایتی جلوی تکرارش را می‌گیرد.
- (void)writeRawTranscript:(NSString *)text {
    if (!text.length) return;
    [text writeToURL:[_sessionDir URLByAppendingPathComponent:@"raw.txt"]
          atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// تاگل «ضبط صدای سشن» حالا اینجا اعمال می‌شود، نه سر شروع: ضبط همیشه لازم است
// (فایل مرجع همه‌چیز است)، ولی **ماندنش** انتخاب کاربر است. خاموش یعنی صدا همین‌جا
// می‌رود و فقط متن می‌ماند. روشن یعنی هفت روز می‌ماند و بعد جارو می‌شود.
- (void)applyAudioPolicy {
    [_recorder finish];
    if (ZSettings.shared.recordSessions) return;
    // و تا تکه‌ای در راه است، صدا نمی‌رود. تکه‌ی در انتظار هیچ نسخه‌ی جداگانه‌ای از
    // صدای خودش ندارد؛ audio.flac تنها جایی است که آن چند ثانیه در آن هست.
    if (_queue.waiting) {
        ZLog(@"session: صدا نگه داشته شد، %ld تکه هنوز در راه است", (long)_queue.waiting);
        return;
    }
    NSURL *audio = _recorder.url;
    if (audio) [NSFileManager.defaultManager removeItemAtURL:audio error:nil];
}

// ---------- اکشن‌ها ----------

// تک‌تپ Command راست: **مکث و تحویل**. سشن زنده می‌ماند و تک‌تپ بعدی ادامه‌اش
// می‌دهد. اولین نسخه‌ی نسخه دو اینجا سشن را می‌بست و اشتباه بود: کسی که یک لحظه
// می‌ایستد تا فکر کند، نباید مجبور شود دوباره دابل‌تپ بزند.
- (void)pauseToggle {
    if (_finished) return;
    if (_paused) {
        [self resumeListening];
        return;
    }
    if (_stopping) return;
    _closing = NO;
    [self stopListening];
}

// دکمه‌ی مکث و Command راست + Space: مکثِ ساده، بی‌تحویل. صدا می‌ایستد و همان
// لحظه ادامه می‌گیرد، بی‌آنکه تکه‌ای بسته شود یا متنی برود.
- (void)togglePause {
    if (_finished || _paused) return;
    if (_engine.paused) {
        [_engine resume];
        ZPlay(ZSoundResume);
    } else {
        [_engine pause];
        ZPlay(ZSoundPause);
    }
    [self render];
}

// دورِ تازه‌ی شنیدن، روی همان سشن. موتور نو می‌شود (موتورِ تمام‌شده برنمی‌گردد) ولی
// متن و ساعت و پوشه‌ی سشن همان می‌مانند.
- (void)resumeListening {
    if (!_paused || _finished) return;
    _paused = NO;
    _stopping = NO;
    _round++;
    _engine = [[ZEngine alloc] initWithLang:ZSettings.shared.lang];
    _engine.delegate = self;
    _engine.recorder = _recorder;
    _engine.queue = _queue;
    NSError *err = nil;
    if (![_engine startWithError:&err]) {
        _errorState = YES;
        _statusText = err.localizedDescription ?: @"میکروفن باز نشد";
        _paused = YES;
        [self render];
        return;
    }
    ZPlay(ZSoundResume);
    [self startClock];
    ZLog(@"session: دور %ld شروع شد", (long)_round);
    [self render];
}

- (void)copyNow {
    NSString *t = (_mode == ZModeCollect && [_panel editorText].length) ? [_panel editorText] : self.liveText;
    if (!t.length) {
        [_panel flash:@"هنوز متنی نیست"];
        return;
    }
    // دکمه‌ی کپی هم یک تحویل است: متنی که کاربر همین حالا برداشت. و در حالت جمع
    // ممکن است ویرایش‌شده باشد، یعنی چیزی که deliver نوشته بود دیگر همان نیست.
    ZHistoryAppend(t, _sessionDir.lastPathComponent, ZHistoryViaCopy, _target.localizedName);
    [ZInjector copyFinal:ZSigned(t)];
    ZPlay(ZSoundCopy);
    [_panel flash:@"کپی شد"];
}

- (void)insertHere {
    NSString *t = (_mode == ZModeCollect && [_panel editorText].length) ? [_panel editorText] : self.liveText;
    if (!t.length) {
        [_panel flash:@"هنوز متنی نیست"];
        return;
    }
    ZHistoryAppend(t, _sessionDir.lastPathComponent, ZHistoryViaInsert, _target.localizedName);
    // دکمه‌ی درج امضا می‌خورد حتی با جای خالیِ پذیرفته‌شده، و این با قاعده‌ی بالا
    // نمی‌جنگد: آنجا اپ متن را نگه داشته بود، اینجا کاربر گفته «همین‌طور که هست
    // ببرش». تحویل تمام شد، پس امضا حق دارد.
    NSString *out = ZSigned(t);
    [ZInjector copyFinal:out];
    [self injectAtCaret:out keep:out];
    _inserted = t.length;    // طولِ متنِ خودِ کاربر، بی امضا: امضا هیچ‌وقت شمرده نمی‌شود
    ZPlay(ZSoundInsert);
    [_panel flash:@"درج شد"];
}

// سطل آشغال: **از صفر**، و صفر یعنی صفر. متن، صدای روی دیسک، و ساعت، هر سه.
// ساعت هم عمدا: کاربر که «از نو» می‌زند انتظار دارد شمارنده هم از نو شروع کند،
// وگرنه عددی می‌بیند که به هیچ صدایی که هنوز هست مربوط نیست.
//
// و «هر سه» تا امروز دو تا بود. متن دو جا زندگی می‌کند و اینجا فقط یکی‌شان پاک
// می‌شد: نسخه‌ی سشن. تکه‌های رونویسی‌شده داخل خط لوله‌ی موتور می‌ماندند و سر پایان
// از همان‌جا برمی‌گشتند، پس پنل می‌گفت «همه‌چیز دور ریخته شد» و Esc بعدی همان
// حرف‌ها را سر کرسر می‌ریخت. پیامی که کاربر می‌خواند و کاری که اپ می‌کرد، دو چیز.
- (void)dropPending {
    // یک خط، و هر سه جایی که متن می‌تواند قایم شود را می‌برد: جاهای رونویسی‌شده،
    // صدای نبریده، و تکه‌ای که همین حالا روی شبکه است (نوبتِ صف یکی جلو می‌رود، پس
    // جوابش که آمد بی‌اثر می‌افتد). تا دیروز این سه تا سه جای مختلف بودند و یکی‌شان
    // همیشه جا می‌ماند: پنل می‌گفت همه‌چیز پاک شد و Esc بعدی همان حرف‌ها را برمی‌گرداند.
    [_engine discardText];
    _polished = nil;
    _polishedThrough = 0;
    _inserted = 0;
    _secondsBefore = 0;
    _settling = NO;
    // و درِ سومِ برگشت: پاسِ هوش مصنوعیِ در جریان. نتیجه‌اش چند ثانیه بعد می‌رسد و
    // متنِ **قبلِ** دور ریختن را می‌نویسد. یک نوبت کافی است که آن جواب بی‌اثر بماند.
    _dropEpoch++;
    [_engine resetClock];
    // پیش‌نمایش هم از صفر، وگرنه حرف‌های دورریخته چند ثانیه بعد دوباره خاکستری
    // برمی‌گشتند: استریم هر بار کلِ متنِ جمع‌شده‌اش را می‌دهد و از دور ریختن خبر ندارد.
    [_engine resetPreview];
    [_recorder discard];
    [_panel clearEditor];
    ZPlay(ZSoundTrash);
    [_panel flash:@"همه‌چیز دور ریخته شد؛ از صفر"];
    [self render];
}

// دو حالت، پس چرخش یعنی رفت‌وبرگشت. حالت وسط سشن عوض شود، متن جایی نمی‌رود: هنوز
// چیزی تحویل نشده، فقط مقصدش عوض می‌شود.
- (void)toggleMode {
    if (_finished) return;
    ZMode next = _mode == ZModeCollect ? ZModeCursor : ZModeCollect;
    _mode = next;
    ZSettings.shared.mode = next;
    // دُم خاکستری مالِ پنل است و پنل دارد می‌رود (یا تازه آمده و لنگرش دیگر معتبر
    // نیست). لنگرِ تازه از اولین متنِ بعدیِ استریم گرفته می‌شود.
    [_panel setPreviewText:nil];
    if (next == ZModeCursor) {
        [_panel hide];
        [_dot show];
    } else {
        [_dot hide];
        [_panel show];
    }
    ZPlay(ZSoundMode);
    [_panel flash:[NSString stringWithFormat:@"حالت: %@", ZModeLabel(next)]];
    ZLog(@"session: حالت شد %@", ZModeSlug(next));
    [self render];
}

- (void)switchLang {
    NSString *next = [ZSettings.shared.lang hasPrefix:@"fa"] ? @"en-US" : @"fa-IR";
    ZSettings.shared.lang = next;
    ZPlay(ZSoundLang);
    // و همین سشن، نه سشن بعدی. قبلا فقط تنظیم نوشته می‌شد و موتور تا آخر به زبان
    // قبلی می‌نوشت، در حالی که دکمه‌ی نوار همان لحظه زبان تازه را نشان می‌داد: رابط
    // یک چیز می‌گفت و متن چیز دیگری درمی‌آمد. حالا موتور خودش تکه‌ی جاری را می‌بندد
    // و تکه‌ی بعدی را با زبان تازه باز می‌کند، پس وسط حرف زدن هم می‌شود عوضش کرد،
    // هر چند بار که لازم شد.
    [_engine switchLang:next];
    [_panel flash:[next hasPrefix:@"fa"] ? @"زبان: فارسی" : @"زبان: English"];
    [self render];
}

- (void)toggleSensitivity {
    BOOL on = !ZSettings.shared.highSensitivity;
    ZSettings.shared.highSensitivity = on;
    [_panel flash:on ? @"حساسیت بالای میکروفن روشن شد" : @"حساسیت بالای میکروفن خاموش شد"];
    [self render];
}

// ---------- پایان ----------

// Esc و دابل‌تپ: تحویل، و تمام. فرقش با تک‌تپ همین یک پرچم است: آنجا سشن زنده
// می‌ماند، اینجا نه. و در حالت جمع، این تنها راهی است که متن **درج** هم می‌شود؛
// تک‌تپ فقط نشانش می‌دهد.
- (void)finish {
    if (_finished) return;
    // متن از قبل رفته و فقط تکه‌ای در راه مانده. Escِ دوم یعنی «همین بس است»: پنل
    // می‌رود و صف در پس‌زمینه کارش را تمام می‌کند؛ آنچه دیر برسد در text.txt و در
    // ردیف تاریخچه‌ی همین سشن می‌نشیند.
    if (_settling) {
        ZLog(@"session: بسته شد و %ld تکه در پس‌زمینه ماند", (long)_queue.waiting);
        [self endNow];
        return;
    }
    _closing = YES;
    if (_paused) {
        // شنیدن از قبل ایستاده و متن آماده است: همین حالا تحویل بده و ببند،
        // بی‌آنکه دور تازه‌ای باز شود.
        [self deliver];
        return;
    }
    if (_stopping) return;
    [self stopListening];
}

// موتور را بخوابان و منتظر متن بمان. هر دو در پایان (تک‌تپ و Esc) از همین‌جا
// رد می‌شوند و تنها تفاوتشان `_closing` است.
- (void)stopListening {
    if (_stopping) return;
    _stopping = YES;
    // ثانیه‌های این دور **همین‌جا** به مجموع اضافه می‌شوند، نه سرِ رسیدن متن. قبلا
    // آنجا بود و در آن دو سه ثانیه‌ی فاصله، مجموع یک لحظه به عددِ دورِ قبل برمی‌گشت
    // و بعد می‌پرید جلو. عددی که جلوی چشم کاربر عقب برود، از نبودنش بدتر است.
    _secondsBefore += _engine.seconds;
    // از این لحظه تا رسیدنِ متن، پنل باید **حرکت** داشته باشد. قبلا فقط یک جمله بود و
    // نشانِ بی‌حرکت، و آن چند ثانیه دقیقا شبیه گیر کردنِ اپ به نظر می‌رسید. حالا
    // میله‌های صدا می‌گویند صدا دارد متن می‌شود، و شکلشان با جرقه‌های پاس هوش مصنوعی
    // فرق دارد تا معلوم باشد منتظر کدام یکی هستیم.
    _busy = ZBusySpeech;
    _workingMsg = @"یک لحظه، صدا دارد متن می‌شود…";
    _statusText = _workingMsg;
    _listening = NO;
    [self render];
    [_engine stop];    // متن از engineDidFinish: می‌آید
}

// خروج اپ از این در می‌آید: بی‌معطلی، ولی نه بی‌متن.
- (void)finishNow {
    if (_finished) return;
    [self finish];
}

// صف اینجا **کشته نمی‌شود**: تکه‌ی در راه بعد از رفتنِ پنل هم می‌رسد و جای خودش
// می‌نشیند. تنها چیزی که می‌رود، رابط است.
- (void)endNow {
    if (_finished) return;
    _finished = YES;
    [self stopClock];
    [self unwirePanel];
    [_dot hide];
    [_panel hide];
    [_panel clearEditor];
    if (self.onFinish) self.onFinish();
}

// ---------- رندر ----------

- (void)render {
    ZPanelModel *m = [ZPanelModel new];
    m.status = _warning.length ? _warning : _statusText;
    m.listening = _listening;
    m.paused = _engine.paused;
    m.error = _errorState;
    m.lang = ZSettings.shared.lang;
    m.mode = _mode;
    m.busy = _busy;
    m.workingMsg = _workingMsg;
    m.review = _paused;
    // دو عدد، چون دو سوال جداست: «الان چند ثانیه است که دارم حرف می‌زنم» و «رویِ
    // هم چقدر شده». اولی زنده جلو می‌رود و درشت است، دومی فقط وقتی دورِ دومی در
    // کار باشد کنارش و ریزتر می‌آید.
    m.elapsed = _listening ? _engine.seconds : 0;
    m.elapsedTotal = _secondsBefore + m.elapsed;
    m.rounds = _round;
    if (_mode == ZModeCursor) [_dot render:m];
    else [_panel render:m];
    // منوبار هم از همین مدل رنگ می‌گیرد؛ کانال وضعیت دومی ساخته نشده
    if (self.onModel) self.onModel(m);
}

@end
