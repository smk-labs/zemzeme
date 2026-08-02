// دلیگیت اپ (منوبار، URL scheme، چرخه سشن)، سلف‌تست و main.
#import "zemzeme.h"

// ---------- سلف‌تست ----------
// فایل خام s16le/16k را با سرعت واقعی به یک ZGoogleStream می‌دهد؛ همان مسیر
// کد اصلی (اتصال، آپلود استریمی، پارس فریم‌ها) بدون میکروفن و UI محک می‌خورد.
// اجرا: zemzeme --selftest audio.raw [en-US|fa-IR]
int ZSelfTest(NSString *file, NSString *lang) {
    NSData *audio = [NSData dataWithContentsOfFile:file];
    if (!audio) {
        printf("selftest: cannot read %s\n", file.UTF8String);
        return 2;
    }
    printf("selftest: %lu bytes (~%lus), lang=%s\n",
           (unsigned long)audio.length, (unsigned long)(audio.length / 32000), lang.UTF8String);
    __block int finals = 0;
    __block int interims = 0;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    ZGoogleStream *s = [[ZGoogleStream alloc] initWithLang:lang];
    s.onEvent = ^(ZSpeechEvent *ev) {
        for (NSString *f in ev.finals) {
            finals++;
            printf("FINAL: %s\n", f.UTF8String);
        }
        if (ev.interim.length) {
            interims++;
            if (interims % 8 == 1) printf("interim: %s\n", ev.interim.UTF8String);
        }
    };
    s.onClose = ^(NSString *reason) {
        printf("closed: %s\n", reason.UTF8String);
        dispatch_semaphore_signal(sem);
    };
    [s connect];
    printf("selftest: codec=%s\n", s.codecName.UTF8String);

    dispatch_queue_t q = dispatch_queue_create("selftest.pace", DISPATCH_QUEUE_SERIAL);
    __block NSUInteger off = 0;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        NSUInteger n = MIN((NSUInteger)3200, audio.length - off);
        if (n == 0) {
            [s finishUpload];
            dispatch_source_cancel(timer);
            return;
        }
        [s feed:[audio subdataWithRange:NSMakeRange(off, n)]];
        off += n;
    });
    dispatch_resume(timer);

    dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)((audio.length / 32000 + 60) * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(sem, deadline)) {
        printf("selftest: TIMEOUT\n");
        [s cancel];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    }
    printf("selftest: finals=%d interim_events=%d\n", finals, interims);
    return finals > 0 ? 0 : 1;
}

// ---------- خبر دادن به Karabiner ----------
// یک متغیر با یک معنی: «زمزمه بالاست». رول کارابینر فقط وقتی صفر است به Command
// راست دست می‌زند، یعنی تا اپ زنده است کلید فقط مالِ خودِ اپ است.
//
// چرا لازم شد: هر دو طرف همان دابل‌تپ را می‌پاییدند و مسابقه‌شان دیدنی نبود، خوردنی
// بود. کارابینر تپِ تنها را می‌بلعد، ولی اگر کلید کمی بیشتر از ۴۰۰ms پایین بماند
// «تنها» حساب نمی‌شود و همان راست-Command به جریان رویدادها برمی‌گردد؛ تپِ اپ آن را
// تپِ تنها می‌خواند و تک‌تپ یعنی مکث. نتیجه: وسط حرف زدن، موتور بی‌صدا مکث می‌کرد و
// صدای مکث دور ریخته می‌شود، پس آخر کار متن صفر بود. با این متغیر آن مسابقه اصلا
// شکل نمی‌گیرد: هر لحظه دقیقا یک نفر صاحب کلید است.
//
// کارابینر نصب نباشد، همه‌ی این‌ها بی‌صدا رد می‌شوند و اپ مثل قبل کار می‌کند.
static NSString *const kZKarabinerCLI =
    @"/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli";

static void ZTellKarabiner(BOOL up, BOOL waitForIt) {
    if (![NSFileManager.defaultManager isExecutableFileAtPath:kZKarabinerCLI]) return;
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:kZKarabinerCLI];
    t.arguments = @[@"--set-variables",
                    up ? @"{\"zemzeme_running\":1}" : @"{\"zemzeme_running\":0}"];
    t.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    t.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSError *e = nil;
    if (![t launchAndReturnError:&e]) {
        ZLog(@"karabiner: خبر نرفت: %@", e.localizedDescription ?: @"?");
        return;
    }
    // سر خروج باید صبر کرد: پروسه زودتر از رسیدن خبر می‌میرد و رول برای همیشه
    // خاموش می‌ماند. سر لانچ لازم نیست، آنجا کسی عجله ندارد.
    if (waitForIt) [t waitUntilExit];
}

// ---------- AppDelegate ----------

@interface ZAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@end

@implementation ZAppDelegate {
    NSStatusItem *_statusItem;
    ZPanel *_panel;
    ZSession *_session;
    ZHotkeyTap *_hotkeys;
    CFAbsoluteTime _lastToggleAt;    // دیبانس toggle داخلی در برابر toggle بیرونی (Karabiner)
    NSColor *_menubarTint;           // رنگ فعلی آیتم منوبار؛ رندر پرتکرار تصویر نو نسازد
    BOOL _axPrompted;                // پنجره درخواست اکسسبیلیتی فقط یک بار در هر اجرا
    BOOL _toldKarabiner;             // فقط کسی که «بالا» گفته حق دارد «پایین» بگوید
}

- (void)applicationWillFinishLaunching:(NSNotification *)n {
    [NSAppleEventManager.sharedAppleEventManager
        setEventHandler:self andSelector:@selector(handleURLEvent:withReply:)
          forEventClass:kInternetEventClass andEventID:kAEGetURL];
}

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    // حالت اسکرین‌شات طراحی: zemzeme --uishot <dir> [file]. قبل از گارد تک‌نمونه، چون
    // اپ دوم نیست که با منوبار رقابت کند: نه آیتم وضعیت می‌سازد نه تپ کیبورد، کارش را
    // می‌کند و می‌رود. قبلا پایین‌تر بود و تا اپ اصلی باز بود هیچ تستی اجرا نمی‌شد.
    NSArray *shotArgs = NSProcessInfo.processInfo.arguments;
    NSUInteger shotAt = [shotArgs indexOfObject:@"--uishot"];
    if (shotAt != NSNotFound && shotAt + 1 < shotArgs.count) {
        ZRegisterFonts();
        _panel = [ZPanel new];
        NSString *dir = shotArgs[shotAt + 1];
        // با یک مسیر فایل در ادامه، جای حالت‌های نمونه یک اجرای واقعی عکس گرفته می‌شود:
        // پنجره را بی‌اجازه‌ی ضبط صفحه فقط از داخل خود پروسه می‌توان دید.
        NSMutableArray<NSURL *> *shotFiles = [NSMutableArray array];
        for (NSUInteger k = shotAt + 2; k < shotArgs.count; k++) {
            NSString *path = shotArgs[k];
            if ([path hasPrefix:@"-"]) break;
            [shotFiles addObject:[NSURL fileURLWithPath:path.stringByExpandingTildeInPath]];
        }
        if (shotFiles.count) {
            [ZBatchPanel.shared runShots:dir files:shotFiles];
            return;
        }
        [_panel makeShots:dir];
        [ZCheatSheet shot:dir];
        ZMarkShot(dir);
        // پنل رونویسی آخر می‌آید و خودش خروج را صدا می‌زند: عکس‌هایش پله‌پله و با
        // فرصت رندر گرفته می‌شوند (جدول ویو-محور بی‌چرخیدن ران‌لوپ خالی درمی‌آید)
        [ZBatchPanel.shared makeShots:dir then:^{ [NSApp terminate:nil]; }];
        return;
    }

    // فقط یک نمونه
    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    if (bid) {
        NSArray *others = [NSRunningApplication runningApplicationsWithBundleIdentifier:bid];
        for (NSRunningApplication *a in others) {
            if (a.processIdentifier != NSProcessInfo.processInfo.processIdentifier) {
                ZLog(@"app: another instance is running, exiting");
                [NSApp terminate:nil];
                return;
            }
        }
    }
    // از اینجا به بعد نمونه‌ی واقعی‌ایم: نه اجرای عکس‌گیری، نه نمونه‌ی دومی که همین
    // حالا برمی‌گردد. پس فقط از اینجا به کارابینر گفته می‌شود «بالا آمدم».
    _toldKarabiner = YES;
    ZTellKarabiner(YES, NO);
    [NSFileManager.defaultManager createDirectoryAtURL:ZSessionsDir()
                           withIntermediateDirectories:YES attributes:nil error:nil];
    ZRegisterFonts();
    _panel = [ZPanel new];
    _hotkeys = [ZHotkeyTap new];
    [self setupStatusItem];
    __weak typeof(self) ws = self;
    _hotkeys.onToggle = ^{ [ws toggleSession]; };
    // Esc با اولویت: کارت راهنمای باز، اول از همه بسته می‌شود (مثل هر پنجره‌ی کوچک مک)،
    // بعد نوبت پایان سشن است. هیچ‌کدام نبود، Esc دست‌نخورده به اپ زیرین می‌رسد.
    _hotkeys.onEscape = ^BOOL{
        if ([ZCheatSheet visible]) {
            [ZCheatSheet close];
            return YES;
        }
        __strong typeof(ws) me = ws;
        if (!me || !me->_session) return NO;
        dispatch_async(dispatch_get_main_queue(), ^{ [me sessionDo:@selector(finish)]; });
        return YES;
    };
    _hotkeys.onHelp = ^{ [ZCheatSheet toggle]; };
    _hotkeys.onPauseToggle = ^{ [ws sessionDo:@selector(pauseToggle)]; };
    _hotkeys.onCopyNow = ^{ [ws sessionDo:@selector(copyNow)]; };
    _hotkeys.onInsertHere = ^{ [ws sessionDo:@selector(insertHere)]; };
    _hotkeys.onTrash = ^{ [ws sessionDo:@selector(dropPending)]; };
    _hotkeys.onLangSwitch = ^{ [ws sessionDo:@selector(switchLang)]; };
    _hotkeys.onModeToggle = ^{ [ws sessionDo:@selector(toggleMode)]; };
    _hotkeys.onPolishNow = ^{ [ws sessionDo:@selector(polishCollected)]; };
    _hotkeys.onFinalPass = ^{ [ws sessionDo:@selector(finalPassNow)]; };
    _hotkeys.onRotateText = ^{ [ws sessionDo:@selector(rotateText)]; };
    _hotkeys.onEnhance = ^{ [ws sessionDo:@selector(enhancePrompt)]; };
    // بی‌سشن هم کار می‌کند، پس مثل بقیه از sessionDo رد نمی‌شود. تاگل است نه فقط باز
    // کردن: پنل رونویسی با همان F می‌رود پس‌زمینه و با همان F برمی‌گردد، و کار در
    // جریان با پنهان شدنش نمی‌ایستد.
    _hotkeys.onFilePanel = ^{ [ZBatchPanel.shared toggle]; };
    // دکمه‌ی «رونویسی فایل» روی نوار پنل شناور: سومین راه دسترسی. اینجا ست می‌شود نه
    // در ZSession، چون به سشن ربطی ندارد و باید حتی بین دو سشن هم زنده باشد.
    _panel.onFilePanel = ^{ [ws openBatchPanel]; };


    // رنگ آیتم منوبار در طول کار دسته‌ای: آبی، فقط تا وقتی کار در جریان است، و فقط
    // اگر سشن زنده‌ای رنگ را در دست نداشته باشد (رنگ سشن یعنی وضعیت میکروفن و مقدم است).
    [NSNotificationCenter.defaultCenter addObserverForName:ZBatchActivity object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        __strong typeof(ws) me = ws;
        if (!me || me->_session) return;
        BOOL running = [note.userInfo[@"running"] boolValue];
        me->_menubarTint = running ? NSColor.systemBlueColor : nil;
        me->_statusItem.button.image = ZMarkImage(18, me->_menubarTint);
    }];

    [self showFirstRunWelcomeIfNeeded];
    [self watchAccessibility];
    // دیمن پاس از همین حالا گرم شود که تکه اول اولین سشن سرد نخورد
    if (ZSettings.shared.polishEnabled) [ZPolish.shared prepare];
    // و کلید پاس نهایی هم همین حالا، در پس‌زمینه: منو و کارت راهنما باید از اولین بار
    // درست بگویند کلید هست یا نه، و پرسشِ Keychain حق ندارد نخ اصلی را نگه دارد.
    if (ZSettings.shared.finalPassEnabled) [ZFinalPass.shared prefetchKey];
    ZLog(@"app: launched res=%@ data=%@ ax=%d polish=%d",
         ZRes().path, ZSupport().path,
         [ZInjector accessibilityOK], ZSettings.shared.polishEnabled);
}

// یک‌بار در عمر نصب، نه در عمر پروسه: کلید همان کلید معمولی دیفالتز است، پس ری‌استارت
// بی‌شمار همان یک بار می‌ماند. قبل از پنجره‌ی اجازه‌ی اکسسبیلیتی، تا کاربر بداند
// آن پنجره‌ی بعدی چیست و چرا لازم است، نه اینکه یک پنجره‌ی ناشناس مک را ببیند.
- (void)showFirstRunWelcomeIfNeeded {
    static NSString *const kWelcomeKey = @"welcomeShown_v1";
    if ([NSUserDefaults.standardUserDefaults boolForKey:kWelcomeKey]) return;
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:kWelcomeKey];
    NSAlert *a = [NSAlert new];
    a.messageText = @"به زمزمه خوش آمدی";
    a.informativeText =
        @"دیکته: دابل‌تپ Command راست، حرف بزن، Esc یعنی تمام؛ متن سرِ کرسر می‌نشیند.\n\n"
         "الان یک پنجره‌ی اجازه‌ی Accessibility از مک می‌بینی؛ اجازه بده تا زمزمه بتواند "
         "متن را جای کرسر بنویسد. میکروفن هم سرِ اولین دیکته پرسیده می‌شود.\n\n"
         "«پاس نهایی» و «بهبود پرامپت» اختیاری‌اند و یک کلید رایگان از Google AI Studio "
         "می‌خواهند؛ هر وقت خواستی، از منوی زمزمه «کلید Gemini…» را بزن.\n\n"
         "راهنمای کامل میان‌برها: Command راست + H.";
    [a addButtonWithTitle:@"باشه"];
    [a addButtonWithTitle:@"راهنمای میان‌برها"];
    if ([a runModal] == NSAlertSecondButtonReturn) [ZCheatSheet toggle];
}

// اجازه اکسسبیلیتی معمولا بعد از لانچ می‌رسد: کاربر می‌رود در تنظیمات تیک می‌زند.
// قبلا فقط یک بار سر لانچ پرسیده می‌شد، پس تا ری‌استارت بعدی تپ خاموش می‌ماند و
// اپ هر بار پنجره درخواست را باز می‌کرد. حالا آرام نگاه می‌کنیم: لحظه‌ای که اجازه
// رسید تپ بالا می‌آید، بدون ری‌استارت. پنجره درخواست هم فقط یک بار در هر اجرا.
- (void)watchAccessibility {
    if ([ZInjector accessibilityOK]) {
        if (!_hotkeys.enabled) {
            [_hotkeys enable];
            ZLog(@"app: accessibility granted, hotkey tap up");
        }
        return;
    }
    if (!_axPrompted) {
        _axPrompted = YES;
        [ZInjector promptAccessibility];
    }
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [ws watchAccessibility]; });
}

- (void)applicationWillTerminate:(NSNotification *)n {
    // finishNow نه finish: مسیر معمولی ممکن است منتظر پاس ویرایشِ پایانی بماند و
    // اپ تا برگشتنش زنده نمی‌ماند، یعنی متن گم می‌شد. پاس را می‌بازیم، متن را نه.
    [_session finishNow];
    [_hotkeys disable];
    // آخرین کار: کلید را به کارابینر پس بده، وگرنه دابل‌تپ دیگر اپ را بالا نمی‌آورد.
    if (_toldKarabiner) ZTellKarabiner(NO, YES);
}

// ---------- URL: zemzeme://toggle | start | stop ----------

- (void)handleURLEvent:(NSAppleEventDescriptor *)event withReply:(NSAppleEventDescriptor *)reply {
    NSString *url = [event paramDescriptorForKeyword:keyDirectObject].stringValue ?: @"";
    ZLog(@"app: url %@", url);
    if ([url isEqualToString:@"zemzeme://start"]) {
        if (!_session) [self startSession];
    } else if ([url isEqualToString:@"zemzeme://stop"]) {
        [_session finish];
    } else if ([url isEqualToString:@"zemzeme://trash"]) {
        // همان کار سطل آشغال (D). از بیرون هم لازم بود: تنها راهِ سنجیدنِ «صدا هم دور
        // ریخته شود» بی‌دست‌زدن به کیبورد، و برای Karabiner و Shortcuts هم به کار می‌آید.
        [self sessionDo:@selector(dropPending)];
    } else if ([url isEqualToString:@"zemzeme://final"]) {
        [self sessionDo:@selector(finalPassNow)];
    } else if ([url isEqualToString:@"zemzeme://enhance"]) {
        [self sessionDo:@selector(enhancePrompt)];
    } else if ([url isEqualToString:@"zemzeme://files"]) {
        [self openBatchPanel];
    } else if ([url isEqualToString:@"zemzeme://keys"]) {
        [ZCheatSheet toggle];
    } else if ([url isEqualToString:@"zemzeme://quit"]) {
        // خروج نرم برای بیلد تازه: مسیر terminate سشن باز را تمام می‌کند و متنش را
        // نگه می‌دارد. با سیگنال (pkill) این مسیر اجرا نمی‌شود و متن دور می‌ریزد.
        [NSApp terminate:nil];
    } else if ([url isEqualToString:@"zemzeme://toggle"] || !url.length) {
        [self toggleSession];
    } else {
        // قبلا هر آدرس ناشناسی سشن را روشن می‌کرد؛ یک غلط تایپی یعنی ضبط ناخواسته
        ZLog(@"app: unknown url, ignored");
    }
}

- (void)toggleSession {
    // با Karabiner که همین toggle را از بیرون با URL صدا می‌زند هم‌زمان نشویم:
    // دو فراخوانی نزدیک به هم (دابل‌تپ داخلی + دابل‌تپ کارابینر) یعنی دومی نادیده گرفته شود
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - _lastToggleAt < 0.2) return;
    _lastToggleAt = now;
    if (_session) [_session finish];
    else [self startSession];
}

- (void)startSession {
    // موتور از حالت می‌آید، نه فقط از تنظیم: حالت یادداشت موتور ضبط را می‌خواهد و
    // همان یک تابع هر دو راه (شروع سشن، و چرخش حالت وسط سشن) را یکی نگه می‌دارد.
    ZSession *s = [[ZSession alloc] initWithEngine:ZMakeEngine(ZSettings.shared.mode) panel:_panel];
    _session = s;
    __weak typeof(self) ws = self;
    s.onFinish = ^{
        __strong typeof(ws) me = ws;
        if (!me) return;
        me->_session = nil;
        me->_hotkeys.sessionActive = NO;
        // آیتم منوبار به template برمی‌گردد که باز با نوار روشن و تیره و هایلایت وفق
        // بیاید؛ مگر کار دسته‌ای هنوز بدود، که رنگ خودش را پس می‌گیرد.
        me->_menubarTint = ZBatchPanel.shared.running ? NSColor.systemBlueColor : nil;
        me->_statusItem.button.image = ZMarkImage(18, me->_menubarTint);
    };
    // در طول سشن آیتم منوبار همان رنگ وضعیت پنل را دارد. تصویر template رنگ را
    // نادیده می‌گیرد، پس نسخه‌ی رنگی template نیست و با خود رنگ کشیده می‌شود؛ و چون
    // render با هر متن خاکستری صدا می‌خورد، فقط سر عوض شدن واقعی رنگ تصویر نو می‌سازیم.
    s.onModel = ^(ZPanelModel *m) {
        __strong typeof(ws) me = ws;
        if (!me) return;
        NSColor *c = ZStatusColor(m);
        if ([c isEqual:me->_menubarTint]) return;
        me->_menubarTint = c;
        me->_statusItem.button.image = ZMarkImage(18, c);
    };
    // شاید موقع لانچ دسترسی نبود؛ همین‌جا یک‌بار دیگر امتحان کن (بی‌ضرر اگر از قبل فعال است)
    [_hotkeys enable];
    _hotkeys.sessionActive = YES;
    [s start];
}

- (void)sessionDo:(SEL)action {
    ZSession *s = _session;
    if (!s) return;
    IMP imp = [s methodForSelector:action];
    ((void (*)(id, SEL))imp)(s, action);
}

// ---------- منوبار ----------

- (void)setupStatusItem {
    _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    _statusItem.button.image = ZMarkImage(18, nil);
    _statusItem.button.image.accessibilityDescription = @"زمزمه";
    NSMenu *menu = [NSMenu new];
    menu.delegate = self;
    _statusItem.menu = menu;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    menu.autoenablesItems = NO;
    BOOL active = _session != nil;
    BOOL paused = active && _session.engine.paused;

    // بالا: ۴ اقدام اصلی (فقط وقتی سشن فعال است بیشتر از شروع معنا دارد)
    [self icon:[self item:menu title:active ? @"پایان و درج (Esc)" : @"شروع دیکته"
                    action:@selector(menuToggle) key:@""]
        symbol:active ? @"stop.circle" : @"mic.fill"];
    if (active) {
        NSMenuItem *pause = [self item:menu title:@"مکث/ادامه" action:@selector(menuPauseToggle) key:@" "];
        [self icon:pause symbol:paused ? @"play.circle" : @"pause.circle"];
        pause.toolTip = paused ? @"ادامه شنیدن" : @"مکث شنیدن";
        NSMenuItem *copy = [self item:menu title:@"کپی متن" action:@selector(menuCopyNow) key:@"c"];
        [self icon:copy symbol:@"doc.on.doc"];
        copy.toolTip = @"کپی کل متن دیکته‌شده تا الان";
        NSMenuItem *ins = [self item:menu title:@"درج همینجا" action:@selector(menuInsertHere) key:@"i"];
        [self icon:ins symbol:@"text.insert"];
        ins.toolTip = @"درج در اپی که پشت پنل باز است";
    }
    // رونویسی فایل: کنار «شروع دیکته» می‌نشیند چون هم‌رده‌ی آن است، دو راه رسیدن به متن.
    // همیشه فعال است: به سشن ربطی ندارد و وسط دیکته هم می‌شود بازش کرد.
    NSMenuItem *batch = [self icon:[self item:menu title:@"رونویسی فایل…"
                                       action:@selector(menuBatch) key:@""]
                             symbol:@"arrow.up.doc"];
    batch.toolTip = @"فایل صوتی یا تصویری را به متن تبدیل کن: صف، پیشرفت زنده، "
                     "متن یکجای قابل ویرایش (Command راست + F)";
    [menu addItem:NSMenuItem.separatorItem];

    // رادیوی حالت‌ها از اینجا برداشته شد و با آمدن حالت سوم (کرسر) هم برنمی‌گردد:
    // دکمه‌ی E وسط سشن بین هر سه می‌چرخد و با حفظ متن، و دو جای تنظیم برای یک چیز
    // فقط گیج‌کننده بود. حالت شروع همان حالتی است که آخرین بار با E انتخاب شده.
    NSMenuItem *pol = [self icon:[self item:menu title:@"ویرایش فارسی" action:@selector(menuTogglePolish) key:@""]
                           symbol:@"wand.and.stars"];
    pol.state = ZSettings.shared.polishEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    pol.toolTip = @"نیم‌فاصله، ارقام فارسی، نقطه‌گذاری و املای مطمئن روی هر تکه قطعی فارسی";
    NSMenuItem *lat = [self icon:[self item:menu title:@"واژه‌های فنی لاتین"
                                     action:@selector(menuToggleLatinTerms) key:@""]
                           symbol:@"textformat"];
    lat.state = ZSettings.shared.latinTerms ? NSControlStateValueOn : NSControlStateValueOff;
    lat.toolTip = @"وام‌واژه‌های فنی به لاتین برمی‌گردند (کامیت ← commit). فقط واژه‌های "
                   "فهرست app/py/terms.txt، بدون هیچ حدسی؛ واژه‌های دوپهلو عمدا در فهرست نیستند";
    // پاس نهایی: کنار پاس ویرایش می‌نشیند چون هم‌رده‌ی آن است، ولی کارِ دیگری می‌کند و
    // تولتیپش همین را می‌گوید. تا کلید ست نشده باشد، ردیف خودش خبر می‌دهد: روشن بودنش
    // بی‌کلید فقط یک پیام خطا در پایان هر سشن است.
    BOOL hasKey = ZFinalPass.hasKey;
    // حالت سوم: کلید در کی‌چین هست ولی ACL آیتم این اپ را نمی‌شناسد (معمولا چون یک بار
    // با `security` در ترمینال ساخته شده). منو پنجره‌ی رمز را بالا نمی‌آورد، پس اینجا
    // فقط راستش را می‌گوید؛ یک بار «کلید Gemini…» و ذخیره‌ی دوباره، تمامش می‌کند.
    BOOL keyLocked = !hasKey && ZFinalPass.keyNeedsPermission;
    // کلید Gemini: یک شیت کوچک به‌جای ترمینال. بالای هر دو ردیفی می‌نشیند که به آن
    // نیاز دارند، چون کلید مشترک است (همان `ZFinalPass`، همان `zemzeme-gemini`).
    NSMenuItem *key = [self icon:[self item:menu
                                       title:hasKey ? @"کلید Gemini (تنظیم‌شده)"
                                           : keyLocked ? @"کلید Gemini (کی‌چین اجازه نمی‌دهد)"
                                                       : @"کلید Gemini…"
                                     action:@selector(menuSetKey) key:@""]
                           symbol:@"key.fill"];
    key.toolTip = keyLocked
        ? @"کلیدی در Keychain هست ولی این نسخه‌ی اپ اجازه‌ی خواندنش را ندارد. "
           "همین‌جا کلید را دوباره بگذار تا صاحبش خودِ زمزمه شود و دیگر پرسیده نشود."
        : @"کلید رایگان از Google AI Studio؛ فقط در Keychain همین دستگاه ذخیره می‌شود. "
           "لازمِ «پاس نهایی» و «بهبود پرامپت»؛ بدون آن دو، اصلا لازم نیست.";
    NSMenuItem *fin = [self icon:[self item:menu title:hasKey ? @"پاس نهایی با هوش مصنوعی"
                                                              : @"پاس نهایی با هوش مصنوعی (کلید نیست)"
                                     action:@selector(menuToggleFinalPass) key:@""]
                           symbol:@"sparkles"];
    fin.state = ZSettings.shared.finalPassEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    fin.toolTip = hasKey
        ? @"سر پایان سشن، کل صدا یک‌جا به جمینای می‌رود و یک متن تمیز و کامل برمی‌گردد "
           "(Command راست + N). مسیر زنده دست‌نخورده می‌ماند. در زنده/جمع/کرسر به ردیف "
           "«ضبط صدای سشن» هم نیاز دارد، وگرنه صدایی برای شنیدن نیست."
        : ZFinalPass.missingKeyHint;
    if (ZSettings.shared.finalPassEnabled) {
        NSMenuItem *plain = [self icon:[self item:menu title:@"همیشه ساده (بی‌بولت)"
                                           action:@selector(menuTogglePlainNotes) key:@""]
                                 symbol:@"text.alignright"];
        plain.state = ZSettings.shared.plainNotes ? NSControlStateValueOn : NSControlStateValueOff;
        plain.toolTip = @"شکل خروجی را خودِ گفتار تعیین می‌کند: فهرست شمرده بولت می‌شود و "
                         "روایت پاراگراف می‌ماند. این تاگل بولت را کلا خاموش می‌کند.";
    }
    // بهبود پرامپت: بتا، و برچسبش واقعی است نه تعارف. تاگل جدا، پیش‌فرض خاموش، و
    // ردیفش زیر پاس نهایی چون همان کلید و همان انتقال را استفاده می‌کند. با این حال
    // کارِ دیگری است: آن سه روی «متن چه شکلی دربیاید» کار می‌کنند، این یکی متن را به
    // چیز دیگری تبدیل می‌کند، و به صدا و به پایان سشن هیچ ربطی ندارد.
    NSMenuItem *enh = [self icon:[self item:menu title:hasKey ? @"بهبود پرامپت (بتا)"
                                                              : @"بهبود پرامپت (بتا، کلید نیست)"
                                     action:@selector(menuToggleEnhance) key:@""]
                           symbol:@"curlybraces"];
    enh.state = ZSettings.shared.enhanceEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    enh.toolTip = hasKey
        ? @"متنِ آماده را به یک پرامپت درست تبدیل می‌کند، از همان چیزی که دیکته کرده‌ای "
           "(Command راست + B). هیچ‌وقت خودکار نیست و هیچ‌وقت به اپ مقصد تایپ نمی‌شود؛ "
           "متن دیکته می‌ماند و R بین دو نسخه می‌چرخد."
        : ZFinalPass.missingKeyHint;
    // ضبط صدا در سه حالت دیکته. جدا از تاگل بالا و پیش‌فرض خاموش: ضبطِ ناخواسته بدترین
    // پیش‌فرض ممکن است. حالت یادداشت به این ردیف کاری ندارد و همیشه ضبط می‌کند.
    NSMenuItem *rec = [self icon:[self item:menu title:@"ضبط صدای سشن"
                                     action:@selector(menuToggleRecord) key:@""]
                           symbol:@"record.circle"];
    rec.state = ZSettings.shared.recordSessions ? NSControlStateValueOn : NSControlStateValueOff;
    rec.toolTip = @"صدای دیکته‌های زنده/جمع/کرسر را هم روی دیسک نگه می‌دارد (~۱۲ کیلوبایت "
                   "بر ثانیه)، تا پاس نهایی روی آن‌ها هم شدنی باشد. سطل آشغال صدا را هم "
                   "دور می‌ریزد. حالت یادداشت همیشه ضبط می‌کند.";
    NSMenuItem *snd = [self icon:[self item:menu title:@"صدا" action:@selector(menuToggleSounds) key:@""]
                           symbol:@"speaker.wave.2"];
    snd.state = ZSettings.shared.soundsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    snd.toolTip = @"هر کار صدای خودش را دارد: شروع، مکث، ادامه، درج، پایان، دور ریختن";
    [menu addItem:NSMenuItem.separatorItem];

    // زبان: زیرمنوی کوچک
    NSMenuItem *langItem = [self icon:[[NSMenuItem alloc] initWithTitle:@"زبان" action:nil keyEquivalent:@""]
                                symbol:@"globe"];
    NSMenu *langMenu = [NSMenu new];
    [self item:langMenu title:@"فارسی" action:@selector(menuLangFa) key:@""].state =
        [ZSettings.shared.lang isEqualToString:@"fa-IR"] ? NSControlStateValueOn : NSControlStateValueOff;
    [self item:langMenu title:@"English" action:@selector(menuLangEn) key:@""].state =
        [ZSettings.shared.lang isEqualToString:@"en-US"] ? NSControlStateValueOn : NSControlStateValueOff;
    langItem.submenu = langMenu;
    [menu addItem:langItem];

    // پیشرفته: همه‌چیزهای کم‌استفاده در یک زیرمنو
    NSMenuItem *advItem = [self icon:[[NSMenuItem alloc] initWithTitle:@"پیشرفته" action:nil keyEquivalent:@""]
                               symbol:@"gearshape"];
    NSMenu *adv = [NSMenu new];
    adv.autoenablesItems = NO;

    NSMenuItem *g = [self icon:[self item:adv title:@"گوگل مستقیم" action:@selector(menuEngineGoogle) key:@""]
                         symbol:@"bolt.fill"];
    g.state = [ZSettings.shared.engineName isEqualToString:@"google"]
        ? NSControlStateValueOn : NSControlStateValueOff;
    g.enabled = !active;
    NSMenuItem *c = [self icon:[self item:adv title:@"صفحه کروم (فال‌بک)" action:@selector(menuEngineChrome) key:@""]
                         symbol:@"arrow.triangle.2.circlepath"];
    c.state = [ZSettings.shared.engineName isEqualToString:@"chrome"]
        ? NSControlStateValueOn : NSControlStateValueOff;
    c.enabled = !active;
    [self icon:[self item:adv title:@"باز کردن صفحه موتور" action:@selector(menuOpenChromePage) key:@""]
        symbol:@"arrow.up.right.square"];
    [adv addItem:NSMenuItem.separatorItem];

    NSMenuItem *flac = [self icon:[self item:adv title:@"فشرده‌سازی صدا (FLAC)" action:@selector(menuToggleFLAC) key:@""]
                            symbol:@"waveform.circle"];
    flac.state = ZSettings.shared.upstreamFLAC ? NSControlStateValueOn : NSControlStateValueOff;
    flac.toolTip = @"حجم آپلود صدا را تا نصف کم می‌کند؛ اگر جور نشد خودش موقع اتصال به حالت خام برمی‌گردد";
    [adv addItem:NSMenuItem.separatorItem];

    NSArray *modes = @[@[@"تایپ مستقیم", @(ZInsertType), @"keyboard"],
                       @[@"پیست تکه‌ای", @(ZInsertPaste), @"doc.on.clipboard"]];
    for (NSArray *m in modes) {
        NSMenuItem *mi = [self icon:[self item:adv title:m[0] action:@selector(menuInsertMode:) key:@""]
                              symbol:m[2]];
        mi.representedObject = m[1];
        mi.state = ZSettings.shared.insertMode == [m[1] integerValue]
            ? NSControlStateValueOn : NSControlStateValueOff;
        mi.toolTip = @"روش پیش‌فرض همه‌ی اپ‌ها؛ Windows App استثنای خودش را دارد (ردیف بعد)";
    }
    // استثنای Windows App جدا و دیدنی، نه پنهان در کد: پیست آنجا به کلیپ‌بورد ریموت
    // وابسته است و کلیپ‌بورد ریموت گیر می‌کند، ولی تایپ مستقیم فقط وقتی جواب می‌دهد
    // که خود Windows App روی Keyboard Mode = Unicode باشد. پس تصمیمش مال کاربر است.
    NSMenuItem *rdp = [self icon:[self item:adv title:@"Windows App: تایپ مستقیم" action:@selector(menuToggleRDPType) key:@""]
                           symbol:@"display"];
    rdp.state = [ZSettings.shared insertModeForBundleId:kZRDPBundleId] == ZInsertType
        ? NSControlStateValueOn : NSControlStateValueOff;
    rdp.toolTip = @"اول در نوار منوی Windows App: Keyboard Mode ← Unicode. بی آن، فارسی در ریموت درست تایپ نمی‌شود";
    [adv addItem:NSMenuItem.separatorItem];

    NSMenuItem *hk = [self icon:[self item:adv title:@"هاتکی داخلی" action:@selector(menuToggleHotkey) key:@""]
                          symbol:@"command"];
    hk.state = ZSettings.shared.internalHotkey ? NSControlStateValueOn : NSControlStateValueOff;
    // دیگر «آزمایشی» نیست و دیگر با Karabiner دعوا ندارد: تا اپ بالاست رول Karabiner
    // خودش کنار می‌کشد (متغیر zemzeme_running)، پس هر لحظه یک نفر صاحب کلید است.
    hk.toolTip = @"دابل‌تپ Command راست، از داخل خود اپ. تا زمزمه بالاست رول Karabiner "
                  "خودش کنار می‌کشد، پس خاموش کردن دستی‌اش لازم نیست";
    [adv addItem:NSMenuItem.separatorItem];

    [self icon:[self item:adv title:@"پوشه سشن‌ها" action:@selector(menuOpenSessions) key:@""] symbol:@"folder"];
    [self icon:[self item:adv title:@"دسترسی‌ها" action:@selector(menuOpenAccessibility) key:@""] symbol:@"lock.shield"];
    advItem.submenu = adv;
    [menu addItem:advItem];

    // یک آیتم، یک کارت. زیرمنوی قبلی فهرستی از ردیف‌های غیرفعال بود: خاکستری، بی‌آیکون،
    // و متن فارسی و لاتینِ یک‌خطی جابه‌جا خوانده می‌شد. حالا کارت واقعی باز می‌شود
    // (ZCheatSheet) که کی‌کپ و آیکون دارد و کنار دستت باز می‌ماند تا کلیدها را تمرین کنی.
    NSMenuItem *keysItem = [self icon:[self item:menu title:@"راهنما"
                                          action:@selector(menuCheatSheet) key:@""]
                                symbol:@"questionmark.circle"];
    // نشانه‌ی ⌘H فقط برای دیده شدن است: کار واقعی را تپ سراسری می‌کند، با Command راست
    keysItem.keyEquivalent = @"h";
    keysItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    keysItem.toolTip = @"کارت میان‌برها با Command راست + H؛ شناور می‌ماند و با Esc بسته می‌شود";

    [menu addItem:NSMenuItem.separatorItem];
    [self icon:[self item:menu title:@"خروج از زمزمه" action:@selector(menuQuit) key:@"q"] symbol:@"power"];
}

// کلیدهای کنار آیتم‌های منو فقط نمایشی‌اند؛ کار واقعی را تپ سراسری می‌کند و آن هم
// فقط با Command راست. پس همین‌جا هم ⌘ نشان می‌دهیم نه ⌥: ⌥ دیگر هیچ کاری نمی‌کند و
// نشان دادنش کاربر را دنبال کلیدی می‌فرستد که جواب نمی‌دهد.
- (NSMenuItem *)item:(NSMenu *)m title:(NSString *)t action:(SEL)a key:(NSString *)k {
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:t action:a keyEquivalent:k];
    i.target = self;
    if (k.length) i.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [m addItem:i];
    return i;
}

// آیکن SF Symbol برای یک ردیف منو؛ اگر اسم نماد اشتباه باشد imageWithSystemSymbolName نال
// برمی‌گرداند و اینجا لاگ می‌شود تا خاموش از قلم نیفتد.
- (NSMenuItem *)icon:(NSMenuItem *)i symbol:(NSString *)name {
    NSImage *img = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    if (!img) ZLog(@"menu: SF Symbol پیدا نشد: %@", name);
    i.image = img;
    return i;
}

- (void)menuToggle { [self toggleSession]; }
- (void)menuPauseToggle { [self sessionDo:@selector(pauseToggle)]; }
- (void)menuCopyNow { [self sessionDo:@selector(copyNow)]; }
- (void)menuInsertHere { [self sessionDo:@selector(insertHere)]; }
- (void)menuCheatSheet { [ZCheatSheet toggle]; }
// سه راه دسترسی، یک پنل و یک صف: منوبار، Command راست + F، و دکمه‌ی نوار پنل
- (void)openBatchPanel { [ZBatchPanel.shared show]; }
- (void)menuBatch { [self openBatchPanel]; }
- (void)menuLangFa { [self setLang:@"fa-IR"]; }
- (void)menuLangEn { [self setLang:@"en-US"]; }
- (void)setLang:(NSString *)l {
    ZSettings.shared.lang = l;
    [_session.engine setLang:l];
}
- (void)menuEngineGoogle { ZSettings.shared.engineName = @"google"; }
- (void)menuEngineChrome { ZSettings.shared.engineName = @"chrome"; }
- (void)menuOpenChromePage { [ZChromeRelayEngine openPage]; }
- (void)menuToggleFLAC { ZSettings.shared.upstreamFLAC = !ZSettings.shared.upstreamFLAC; }
- (void)menuInsertMode:(NSMenuItem *)sender {
    ZSettings.shared.insertMode = [sender.representedObject integerValue];
}
- (void)menuToggleRDPType {
    ZInsertMode now = [ZSettings.shared insertModeForBundleId:kZRDPBundleId];
    [ZSettings.shared setInsertMode:(now == ZInsertType ? ZInsertPaste : ZInsertType) forBundleId:kZRDPBundleId];
}
- (void)menuTogglePolish {
    ZSettings.shared.polishEnabled = !ZSettings.shared.polishEnabled;
    if (ZSettings.shared.polishEnabled) [ZPolish.shared prepare];
}
- (void)menuToggleLatinTerms { ZSettings.shared.latinTerms = !ZSettings.shared.latinTerms; }
// شیتِ کلید: جای دستورِ ترمینال. سه دکمه‌ی همیشگی به‌علاوه‌ی «پاک کردن» وقتی کلیدی
// از قبل هست. جواب دکمه‌ها با شیء خودشان مقایسه می‌شود، نه با عددِ ثابت NSAlert، چون
// ترتیب دکمه‌ها این‌جا شرطی است (کلید بود/نبود) و اندیس‌شان جابه‌جا می‌شود.
- (void)menuSetKey {
    BOOL had = ZFinalPass.hasKey;
    NSAlert *a = [NSAlert new];
    a.messageText = @"کلید Gemini";
    a.informativeText =
        @"«پاس نهایی» و «بهبود پرامپت» یک کلید رایگان از Google AI Studio می‌خواهند "
         "(سهم رایگان: ۲۰ درخواست در روز). کلید فقط روی همین دستگاه، در Keychain، "
         "می‌ماند؛ نه در ریپو، نه روی هیچ سروری از طرف زمزمه.\n\n"
         "پیش از گرفتن کلید، بخش «داده و حریم خصوصی» در README را بخوان: در سهم "
         "رایگان گوگل ممکن است از صدا و متن برای بهبود مدل‌هایش استفاده کند.";
    NSSecureTextField *field = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    field.placeholderString = had ? @"کلید تازه، جای قبلی می‌نشیند" : @"کلید را اینجا بچسبان";
    a.accessoryView = field;
    NSButton *save = [a addButtonWithTitle:@"ذخیره"];
    NSButton *get = [a addButtonWithTitle:@"دریافت کلید رایگان"];
    NSButton *clear = had ? [a addButtonWithTitle:@"پاک کردن کلید"] : nil;
    [a addButtonWithTitle:@"لغو"];
    a.window.initialFirstResponder = field;
    NSModalResponse resp = [a runModal];
    if (resp == [a.buttons indexOfObject:save] + NSAlertFirstButtonReturn) {
        NSError *err = nil;
        if ([ZFinalPass saveKey:field.stringValue error:&err]) {
            NSAlert *ok = [NSAlert new];
            ok.messageText = @"کلید ذخیره شد";
            [ok runModal];
        } else {
            NSAlert *e = [NSAlert new];
            e.alertStyle = NSAlertStyleWarning;
            e.messageText = @"ذخیره نشد";
            e.informativeText = err.localizedDescription ?: @"خطای نامشخص";
            [e runModal];
        }
    } else if (resp == [a.buttons indexOfObject:get] + NSAlertFirstButtonReturn) {
        [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://aistudio.google.com/apikey"]];
        [self menuSetKey];    // برگشت به همین شیت، چون کاربر رفت کلید بگیرد و برمی‌گردد بچسباند
    } else if (clear && resp == [a.buttons indexOfObject:clear] + NSAlertFirstButtonReturn) {
        [ZFinalPass clearKey];
    }
}

- (void)menuToggleFinalPass {
    ZSettings.shared.finalPassEnabled = !ZSettings.shared.finalPassEnabled;
    if (!ZSettings.shared.finalPassEnabled) return;
    // پرسشِ Keychain می‌تواند پنجره‌ی اجازه باز کند، پس همین حالا و در پس‌زمینه پرسیده
    // می‌شود: کاربر همان لحظه‌ای که تاگل را زده جواب می‌دهد، نه وسط پایانِ یک سشن.
    [ZFinalPass.shared prefetchKey];
    if (!ZFinalPass.hasKey) ZLog(@"final: %@", ZFinalPass.missingKeyHint);
}
- (void)menuTogglePlainNotes { ZSettings.shared.plainNotes = !ZSettings.shared.plainNotes; }
- (void)menuToggleEnhance {
    ZSettings.shared.enhanceEnabled = !ZSettings.shared.enhanceEnabled;
    if (!ZSettings.shared.enhanceEnabled) return;
    // همان کلیدِ پاس نهایی، پس همان پرسشِ پس‌زمینه: کاربر همان لحظه‌ای که تاگل را زده
    // جواب پنجره‌ی Keychain را می‌دهد، نه وسط کار.
    [ZFinalPass.shared prefetchKey];
    if (!ZFinalPass.hasKey) ZLog(@"enhance: %@", ZFinalPass.missingKeyHint);
}
- (void)menuToggleRecord { ZSettings.shared.recordSessions = !ZSettings.shared.recordSessions; }
- (void)menuToggleSounds {
    ZSettings.shared.soundsEnabled = !ZSettings.shared.soundsEnabled;
    ZPlay(ZSoundStart);    // روشن که شد، خودش را می‌شنوانَد
}
// تپ همیشه سرپا است؛ این تنظیم فقط تفسیر دابل‌تپ به toggle را روشن/خاموش می‌کند
- (void)menuToggleHotkey {
    ZSettings.shared.internalHotkey = !ZSettings.shared.internalHotkey;
}
- (void)menuOpenSessions { [NSWorkspace.sharedWorkspace openURL:ZSessionsDir()]; }
- (void)menuOpenAccessibility {
    NSURL *u = [NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    [NSWorkspace.sharedWorkspace openURL:u];
}
- (void)menuQuit { [NSApp terminate:nil]; }

@end

// ---------- main ----------

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray *args = NSProcessInfo.processInfo.arguments;
        NSUInteger i = [args indexOfObject:@"--selftest"];
        if (i != NSNotFound && i + 1 < args.count) {
            NSString *lang = i + 2 < args.count ? args[i + 2] : @"en-US";
            return ZSelfTest(args[i + 1], lang);
        }
        // حالت دسته‌ای قبل از ساختن NSApplication برمی‌گردد: نه آیتم منوبار، نه تپ
        // کیبورد، نه اجازه اکسسبیلیتی. اپ منوبارِ در حال اجرا هم دست نمی‌خورد،
        // چون گارد «یک نمونه» در applicationDidFinishLaunching است و اینجا
        // هیچ‌وقت به آن نمی‌رسیم.
        if ([args containsObject:@"--transcribe"]) return ZBatchMain(args);
        // پاس نهایی روی یک فایل صوتی، بی‌رابط. مثل حالت دسته‌ای پیش از NSApplication
        // برمی‌گردد، پس اپ منوبارِ در حال اجرا دست‌نخورده می‌ماند.
        if ([args containsObject:@"--finalpass"]) return ZFinalPassMain(args);
        // بهبود پرامپت روی یک متن، بی‌رابط و بی‌صدا. مثل دو حالت بالا پیش از
        // NSApplication برمی‌گردد؛ دلیل وجودش ست طلایی است.
        if ([args containsObject:@"--enhance"]) return ZEnhanceMain(args);
        // آیکون بسته برای build.sh؛ مثل حالت دسته‌ای قبل از NSApplication برمی‌گردد
        NSUInteger ic = [args indexOfObject:@"--appicon"];
        if (ic != NSNotFound && ic + 1 < args.count) return ZMarkIconMain(args[ic + 1]);
        // اندازه‌گیری نردبان کرسر: مثل دو حالت بالا پیش از NSApplication برمی‌گردد، پس
        // اپ منوبارِ در حال اجرا دست نمی‌خورد و هیچ سشن دیکته‌ای باز نمی‌شود.
        if ([args containsObject:@"--caretprobe"]) return ZCaretProbeMain(args);
        // بازپخشِ یک سشنِ ضبط‌شده از همان خط لوله، با مقصدِ در حافظه. مثل دو حالت
        // بالا پیش از NSApplication برمی‌گردد: نه اپ در حال اجرا دست می‌خورد، نه
        // میکروفنی باز می‌شود، نه بایتی روی شبکه می‌رود.
        if ([args containsObject:@"--replay"]) return ZReplayMain(args);
        NSApplication *app = NSApplication.sharedApplication;
        static ZAppDelegate *delegate;
        delegate = [ZAppDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
