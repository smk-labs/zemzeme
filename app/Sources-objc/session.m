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
    NSString *_text;                 // متن نهایی، بعد از پایان
    BOOL _listening;
    BOOL _errorState;
    BOOL _working;                   // پاس هوش مصنوعی در جریان
    BOOL _reviewing;                 // سشن تمام شده، پنل با متن باز مانده
    BOOL _finished;
    BOOL _stopping;
}

- (instancetype)initWithEngine:(ZEngine *)engine panel:(ZPanel *)panel {
    if ((self = [super init])) {
        _engine = engine;
        _panel = panel;
        _dot = [ZCaretDot new];
        _mode = ZSettings.shared.mode;
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
    [self render];
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
            _statusText = ZStopHint;
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
    _text = text ?: @"";
    ZLog(@"session: متن آماده در %.1f ثانیه، %lu نویسه", took, (unsigned long)_text.length);
    if (_engine.cappedOut) {
        // سقف پنج دقیقه: صریح بگو چه شد و کجا باید برود. سکوت در این لحظه یعنی
        // کاربر فکر کند اپ خراب شده، در حالی که متنش همین‌جاست.
        _warning = @"پنج دقیقه شد و سشن تمام شد؛ صدای بلندتر را با Command راست + F رونویسی کن";
    }
    // پاس هوش مصنوعی، فقط روی متن و فقط اگر خودت خواسته باشی. هیچ‌وقت بلوکه‌کننده
    // نیست: نتیجه‌اش که نیامد، همین متن خام تحویل می‌شود.
    if (ZSettings.shared.finalPassEnabled && ZFinalPass.hasKey) {
        _working = YES;
        _workingMsg = @"پاس هوش مصنوعی…";
        [self render];
        __weak typeof(self) ws = self;
        [ZFinalPass.shared runOnText:_text second:second lang:ZSettings.shared.lang
                                done:^(NSString *out, NSString *err) {
            __strong typeof(ws) s = ws;
            if (!s) return;
            s->_working = NO;
            s->_workingMsg = nil;
            if (out.length) {
                s->_text = out;
            } else if (err.length) {
                s->_warning = [NSString stringWithFormat:@"پاس هوش مصنوعی نشد (%@)؛ متن خام", err];
                ZLog(@"session: پاس رد شد: %@", err);
            }
            [s deliver];
        }];
        return;
    }
    if (ZSettings.shared.finalPassEnabled) {
        _warning = @"کلید هوش مصنوعی نیست؛ متن خام";
    }
    [self deliver];
}

// ---------- تحویل ----------
// یک بار، و فقط اینجا. دو حالت، دو مقصد، ولی یک متن و یک لحظه.
- (void)deliver {
    NSString *text = [_text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self writeTranscript:text];
    [self applyAudioPolicy];

    if (!text.length) {
        _statusText = @"چیزی شنیده نشد";
        ZPlay(ZSoundTrash);
        [self endNow];
        return;
    }
    [ZInjector copyFinal:text];

    if (_mode == ZModeCursor) {
        // کرسر: یک درج، سر کرسرِ همان اپی که سر شروع جلو بود. نه تکه‌تکه، نه
        // پاک‌کردنی، نه دفتری: متن یک بار و کامل می‌رود.
        ZInjector *inj = [ZInjector new];
        ZInsertMode im = [ZSettings.shared insertModeForBundleId:_target.bundleIdentifier];
        [inj insert:text pid:_target.processIdentifier
        delayMicros:ZSettings.shared.typeDelayMicros
     pasteIfRefused:im == ZInsertPaste
               done:^(BOOL viaAX) { ZLog(@"session: درج شد (ax=%d)", viaAX); }];
        ZPlay(ZSoundFinish);
        [self endNow];
        return;
    }

    // جمع: متن در ادیتور خود پنل می‌نشیند و قابل ویرایش است. پنل باز می‌ماند تا
    // خوانده شود، و دکمه‌های شنیدن جایشان را به دکمه‌های متن می‌دهند.
    [_panel setEditorText:text];
    _reviewing = YES;
    _statusText = @"متن آماده است؛ ویرایشش کن، یا با I درج و با Esc ببند";
    ZPlay(ZSoundFinish);
    [self render];
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

- (void)pauseToggle {
    // تک‌تپ Command راست: **پایان**، نه مکث. این خودِ تصمیم است و نه اشتباه: در
    // نسخه دو کاربر باید یک راه ساده برای گفتن «حرفم تمام شد» داشته باشد، و آن راه
    // باید همان چیزی باشد که دستش رویش است. مکث با همان کلید در دسترس می‌ماند
    // (Command راست + Space) ولی دیگر معنیِ پیش‌فرضِ تک‌تپ نیست.
    if (_reviewing || _finished) return;
    [self finish];
}

- (void)togglePause {
    if (_engine.paused) {
        [_engine resume];
        ZPlay(ZSoundResume);
    } else {
        [_engine pause];
        ZPlay(ZSoundPause);
    }
    [self render];
}

- (void)copyNow {
    NSString *t = _reviewing ? [_panel editorText] : _text;
    if (!t.length) {
        [_panel flash:@"هنوز متنی نیست"];
        return;
    }
    [ZInjector copyFinal:t];
    ZPlay(ZSoundCopy);
    [_panel flash:@"کپی شد"];
}

- (void)insertHere {
    NSString *t = _reviewing ? [_panel editorText] : _text;
    if (!t.length) {
        [_panel flash:@"هنوز متنی نیست"];
        return;
    }
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    ZInjector *inj = [ZInjector new];
    ZInsertMode im = [ZSettings.shared insertModeForBundleId:front.bundleIdentifier];
    [inj insert:t pid:front.processIdentifier
    delayMicros:ZSettings.shared.typeDelayMicros
 pasteIfRefused:im == ZInsertPaste
           done:^(BOOL viaAX) {}];
    [ZInjector copyFinal:t];
    ZPlay(ZSoundInsert);
    [_panel flash:@"درج شد"];
}

- (void)dropPending {
    if (_reviewing) {
        [_panel clearEditor];
        _text = @"";
        [_panel flash:@"متن دور ریخته شد"];
    } else {
        [_recorder discard];
        [_panel flash:@"صدای تا اینجا دور ریخته شد؛ از الان از نو"];
    }
    ZPlay(ZSoundTrash);
    [self render];
}

// دو حالت، پس چرخش یعنی رفت‌وبرگشت. حالت وسط سشن عوض شود، متن جایی نمی‌رود: هنوز
// چیزی تحویل نشده، فقط مقصدش عوض می‌شود.
- (void)toggleMode {
    if (_reviewing || _finished) return;
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

- (void)finish {
    if (_finished) return;
    if (_reviewing) {
        [self endNow];
        return;
    }
    if (_stopping) return;
    _stopping = YES;
    _statusText = @"یک لحظه، متن دارد می‌آید…";
    _listening = NO;
    [self render];
    [_engine stop];    // متن از engineDidFinish: می‌آید
}

// خروج اپ از این در می‌آید: بی‌معطلی، ولی نه بی‌متن.
- (void)finishNow {
    if (_finished) return;
    if (_reviewing) {
        [self endNow];
        return;
    }
    [self finish];
}

- (void)endNow {
    if (_finished) return;
    _finished = TRUE;
    _reviewing = NO;
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
    m.review = _reviewing;
    m.elapsed = _listening ? _engine.seconds : 0;
    if (_mode == ZModeCursor) [_dot render:m];
    else [_panel render:m];
    // منوبار هم از همین مدل رنگ می‌گیرد؛ کانال وضعیت دومی ساخته نشده
    if (self.onModel) self.onModel(m);
}

@end
