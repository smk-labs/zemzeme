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
static NSString *ZModeLabel(ZMode m) { return m == ZModeCursor ? @"کنار کرسر" : @"جمع در پنل"; }

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
    NSString *_text;                 // همه‌ی متنِ این سشن، شاملِ دورهای قبلی
    // **دو شمارنده، نه یکی.** «نشان داده شد» و «سر کرسر درج شد» دو چیزند و یکی
    // گرفتنشان باگی ساخت که کاربر مستقیم دید: در حالت جمع، تک‌تپ متن را در پنل
    // نشان می‌داد و همان را «تحویل‌شده» علامت می‌زد، پس Esc بعدی چیزی برای درج
    // پیدا نمی‌کرد و متن فقط در کلیپ‌بورد می‌ماند.
    NSUInteger _inserted;            // چقدر از متن واقعا سر کرسر رفته
    NSString *_polished;             // آخرین متنی که مدل نوشته؛ پایه‌ی جوشِ دور بعد
    NSTimeInterval _secondsBefore;   // ثانیه‌ی دورهای قبلی؛ ساعت روی هم جمع می‌شود
    NSInteger _round;                // چندمین دورِ شنیدن در همین سشن
    BOOL _listening;
    BOOL _errorState;
    BOOL _working;                   // پاس هوش مصنوعی در جریان
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
        _text = @"";
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
    _recorder = [[ZRecorder alloc] initWithURL:[_sessionDir URLByAppendingPathComponent:@"audio.flac"]];
    _engine.recorder = _recorder;
    _engine.delegate = self;

    if (!ZInjector.accessibilityOK) {
        _warning = @"دسترسی اکسسبیلیتی نیست؛ متن درج نمی‌شود";
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
        case ZEnginePaused: _statusText = @"مکث؛ تک‌تپ Command راست برای ادامه"; break;
        case ZEngineGaveUp:
            _errorState = YES;
            _statusText = msg.length ? msg : @"خطای موتور";
            break;
    }
    [self render];
}

- (void)engineLevel:(float)rms {
    if (_mode == ZModeCursor) [_dot pulseLevel:rms];
    else [_panel pulseLevel:rms];
}

// متن آماده است. از اینجا به بعد دیگر صدایی در کار نیست، فقط متن.
- (void)engineDidFinish:(NSString *)text second:(NSString *)second took:(NSTimeInterval)took {
    _listening = NO;
    _stopping = NO;    // دورِ بعد باید بتواند دوباره بایستد
    // **اضافه، نه جایگزین.** یک سشن می‌تواند چند دور شنیدن داشته باشد: تک‌تپ
    // می‌ایستد و تحویل می‌دهد، تک‌تپ بعدی دوباره راه می‌اندازد. اگر اینجا جایگزین
    // می‌کردیم، دورِ دوم حرف‌های دورِ اول را پاک می‌کرد.
    NSString *fresh = [(text ?: @"") stringByTrimmingCharactersInSet:
                       NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // دورِ دومی که پاس هوش مصنوعی روشن است، تکه‌ی خام را **جدا** نگه می‌داریم و
    // چسباندنش را به خودِ مدل می‌سپاریم. شرحش پایین‌تر، سرِ فراخوانِ ادامه.
    BOOL weld = _polished.length > 0 && fresh.length > 0 &&
                ZSettings.shared.finalPassEnabled && ZFinalPass.hasKey;
    if (fresh.length && !weld) {
        _text = _text.length ? [NSString stringWithFormat:@"%@ %@", _text, fresh] : fresh;
    }
    ZLog(@"session: دور %ld، متن آماده در %.1f ثانیه، %lu نویسه‌ی تازه",
         (long)_round, took, (unsigned long)fresh.length);
    if (_engine.cappedOut) {
        // سقف پنج دقیقه: صریح بگو چه شد و کجا باید برود. سکوت در این لحظه یعنی
        // کاربر فکر کند اپ خراب شده، در حالی که متنش همین‌جاست.
        _warning = @"پنج دقیقه شد و سشن تمام شد؛ صدای بلندتر را با Command راست + F رونویسی کن";
    }
    // پاس هوش مصنوعی، فقط روی متن و فقط اگر خودت خواسته باشی. هیچ‌وقت بلوکه‌کننده
    // نیست: نتیجه‌اش که نیامد، همین متن خام تحویل می‌شود.
    if (ZSettings.shared.finalPassEnabled && ZFinalPass.hasKey) {
        _working = YES;
        _workingMsg = @"در حال تمیز کردن متن…";
        [self render];
        __weak typeof(self) ws = self;
        NSString *before = _polished;
        void (^landed)(NSString *, NSString *) = ^(NSString *out, NSString *err) {
            __strong typeof(ws) s = ws;
            if (!s) return;
            s->_working = NO;
            s->_workingMsg = nil;
            if (out.length) {
                s->_text = out;
                s->_polished = out;
            } else {
                // مدل جواب نداد. تکه‌ی خامی که برای جوش خوردن کنار گذاشته بودیم
                // نباید گم شود: همین‌جا دستی می‌چسبد. متن را می‌بازیم یعنی هیچ‌وقت.
                if (weld && fresh.length) {
                    s->_text = before.length ? [NSString stringWithFormat:@"%@ %@", before, fresh] : fresh;
                }
                if (err.length) {
                    s->_warning = [NSString stringWithFormat:@"تمیز کردن نشد (%@)؛ متن خام", err];
                    ZLog(@"session: پاس رد شد: %@", err);
                }
            }
            [s deliver];
        };
        if (weld) {
            // **ادامه، با کانتکست.** تکه‌ی تازه جدا از متنِ قبلی فرستاده می‌شود و
            // مدل کل متن را از نو می‌نویسد، پس درز جوش می‌خورد و ضمیر و نقطه‌گذاری
            // با بقیه یک‌دست درمی‌آید. تکه‌ای که تنها تمیز شود کانتکست ندارد و
            // درزش از یک فرسنگی پیداست.
            //
            // و دو ورودیِ جدا، نه یک متنِ سرهم: مدل باید بداند متنِ اول را خودش
            // نوشته (پس دست نزند) و دومی خامِ تشخیص گفتار است (پس تمیزش کند).
            [ZFinalPass.shared runOnText:fresh appendingTo:before
                                    lang:ZSettings.shared.lang done:landed];
        } else {
            [ZFinalPass.shared runOnText:_text second:second
                                    lang:ZSettings.shared.lang done:landed];
        }
        return;
    }
    if (ZSettings.shared.finalPassEnabled) {
        _warning = @"کلید هوش مصنوعی نیست؛ متن خام";
    }
    [self deliver];
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
    NSString *all = [_text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self writeTranscript:all];

    if (!all.length) {
        // هیچ حرفی شنیده نشد. این دلیل بستنِ پنل نیست: کاربر شاید تازه دارد فکر
        // می‌کند. قبلا همین‌جا سشن بسته می‌شد و کسی که یک لحظه ساکت مانده بود،
        // پنل را از دست می‌داد.
        _statusText = @"چیزی شنیده نشد؛ تک‌تپ بزن و دوباره حرف بزن";
        ZPlay(ZSoundTrash);
        if (_closing) [self endNow];
        else { _paused = YES; [self render]; }
        return;
    }
    // در حالت جمع، متنِ ادیتور مرجع است نه متنِ خام: کاربر ممکن است ویرایشش کرده باشد
    if (_mode == ZModeCollect) {
        [_panel setEditorText:all];
        NSString *edited = [_panel editorText];
        if (edited.length) all = edited;
    }
    [ZInjector copyFinal:all];

    // درج کِی: در حالت کرسر همیشه (پنلی نیست که متن را نشان بدهد)، و در حالت جمع
    // فقط سرِ Esc و دابل‌تپ. و همیشه فقط آنچه هنوز نرفته.
    BOOL insert = (_mode == ZModeCursor) || _closing;
    if (insert) {
        NSString *fresh = _inserted < all.length ? [all substringFromIndex:_inserted] : @"";
        fresh = [fresh stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (fresh.length) {
            // یک فاصله‌ی آخر، ولی فقط وقتی سشن ادامه دارد. دو کار می‌کند: تکه‌ی
            // بعدی که برسد از قبل جدا افتاده و به کلمه‌ی آخر نمی‌چسبد، و کرسر یک
            // قدم جلو می‌رود که در متنِ راست‌به‌چپ جای درستش را پیدا کند.
            // سرِ Esc نمی‌گذاریم: آنجا حرف تمام شده و فاصله‌ی اضافه فقط زباله است.
            [self injectAtCaret:_closing ? fresh : [fresh stringByAppendingString:@" "]];
            _inserted = all.length;
        }
    }

    ZPlay(_closing ? ZSoundFinish : ZSoundInsert);
    if (_closing) {
        [self endNow];
        return;
    }
    _paused = YES;
    _statusText = _mode == ZModeCursor
        ? @"درج شد. تک‌تپ یعنی ادامه بده، Esc یعنی تمام"
        : @"متن اینجاست و قابل ویرایش. تک‌تپ یعنی ادامه بده، Esc یعنی درج و تمام";
    [self render];
}

// یک درج، سر کرسرِ همان اپی که سر شروع جلو بود. نه تکه‌تکه، نه پاک‌کردنی.
- (void)injectAtCaret:(NSString *)text {
    NSRunningApplication *to = _target ?: NSWorkspace.sharedWorkspace.frontmostApplication;
    ZInjector *inj = [ZInjector new];
    ZInsertMode im = [ZSettings.shared insertModeForBundleId:to.bundleIdentifier];
    [inj insert:text pid:to.processIdentifier
    delayMicros:ZSettings.shared.typeDelayMicros
 pasteIfRefused:im == ZInsertPaste
           done:^(BOOL viaAX) { ZLog(@"session: درج شد (ax=%d، %lu نویسه)", viaAX,
                                     (unsigned long)text.length); }];
}

// رونوشت خام کنار صدا، همیشه. طلای تست همین است و باید پیش از هر ویرایشِ دستی
// روی دیسک باشد.
- (void)writeTranscript:(NSString *)text {
    if (!text.length) return;
    [text writeToURL:[_sessionDir URLByAppendingPathComponent:@"text.txt"]
          atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// تاگل «ضبط صدای سشن» حالا اینجا اعمال می‌شود، نه سر شروع: ضبط همیشه لازم است
// (فایل مرجع همه‌چیز است)، ولی **ماندنش** انتخاب کاربر است. خاموش یعنی صدا همین‌جا
// می‌رود و فقط متن می‌ماند. روشن یعنی هفت روز می‌ماند و بعد جارو می‌شود.
- (void)applyAudioPolicy {
    [_recorder finish];
    if (ZSettings.shared.recordSessions) return;
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
    NSString *t = (_mode == ZModeCollect && [_panel editorText].length) ? [_panel editorText] : _text;
    if (!t.length) {
        [_panel flash:@"هنوز متنی نیست"];
        return;
    }
    [ZInjector copyFinal:t];
    ZPlay(ZSoundCopy);
    [_panel flash:@"کپی شد"];
}

- (void)insertHere {
    NSString *t = (_mode == ZModeCollect && [_panel editorText].length) ? [_panel editorText] : _text;
    if (!t.length) {
        [_panel flash:@"هنوز متنی نیست"];
        return;
    }
    [self injectAtCaret:t];
    [ZInjector copyFinal:t];
    _inserted = t.length;
    ZPlay(ZSoundInsert);
    [_panel flash:@"درج شد"];
}

// سطل آشغال: **از صفر**، و صفر یعنی صفر. متن، صدای روی دیسک، و ساعت، هر سه.
// ساعت هم عمدا: کاربر که «از نو» می‌زند انتظار دارد شمارنده هم از نو شروع کند،
// وگرنه عددی می‌بیند که به هیچ صدایی که هنوز هست مربوط نیست.
- (void)dropPending {
    _text = @"";
    _polished = nil;
    _inserted = 0;
    _secondsBefore = 0;
    [_engine resetClock];
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
    // زبان سر سشن بعدی اثر می‌کند و نه همین یکی: تکه‌های در پرواز زبانشان تعیین شده
    // و عوض کردنش وسط راه یعنی نصف متن با یک موتور و نصفش با موتور دیگر.
    [_panel flash:[next hasPrefix:@"fa"] ? @"زبان سشن بعد: فارسی" : @"زبان سشن بعد: English"];
    [self render];
}

- (void)toggleSensitivity {
    BOOL on = !ZSettings.shared.highSensitivity;
    ZSettings.shared.highSensitivity = on;
    [_panel flash:on ? @"حساسیت بالا روشن (بتا)" : @"حساسیت بالا خاموش"];
    [self render];
}

// ---------- پایان ----------

// Esc و دابل‌تپ: تحویل، و تمام. فرقش با تک‌تپ همین یک پرچم است: آنجا سشن زنده
// می‌ماند، اینجا نه. و در حالت جمع، این تنها راهی است که متن **درج** هم می‌شود؛
// تک‌تپ فقط نشانش می‌دهد.
- (void)finish {
    if (_finished) return;
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
    _statusText = @"یک لحظه، متن دارد می‌آید…";
    _listening = NO;
    [self render];
    [_engine stop];    // متن از engineDidFinish: می‌آید
}

// خروج اپ از این در می‌آید: بی‌معطلی، ولی نه بی‌متن.
- (void)finishNow {
    if (_finished) return;
    [self finish];
}

- (void)endNow {
    if (_finished) return;
    _finished = YES;
    [self stopClock];
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
    m.working = _working;
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
