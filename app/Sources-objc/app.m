// دلیگیت اپ (منوبار، URL scheme، چرخه سشن)، سلف‌تست و main.
#import "zemzeme.h"
#import <ServiceManagement/ServiceManagement.h>

// ---------- اجرا در ورود به مک ----------
// چرا این فیچر مهم‌تر از یک راحتیِ کوچک است: هیچ اپی نمی‌تواند وقتی اجرا نمی‌شود
// کلیدی را بشنود. تا زمزمه بسته باشد، تنها راهِ بالا آوردنش با کیبورد یک برنامه‌ی
// همیشه‌بیدارِ دیگر است (Karabiner، یا میان‌بر اپ Shortcuts). با اجرای خودکار در
// ورود، آن «بسته بودن» اصلا پیش نمی‌آید و هاتکی داخلیِ خودِ اپ بی هیچ ابزار جانبی
// کافی است.
//
// حالت از خود سیستم خوانده می‌شود نه از دیفالتز: کاربر می‌تواند همین را در تنظیمات
// سیستم خاموش کند، و اگر نسخه‌ی خودمان را باور کنیم منو دروغ می‌گوید.
static BOOL ZLoginItemOn(void) {
    if (@available(macOS 13.0, *)) {
        return SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
    }
    return NO;
}

static BOOL ZSetLoginItem(BOOL on, NSError **err) {
    if (@available(macOS 13.0, *)) {
        SMAppService *s = SMAppService.mainAppService;
        return on ? [s registerAndReturnError:err] : [s unregisterAndReturnError:err];
    }
    return NO;
}

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
    BOOL _launched;                  // applicationDidFinishLaunching تمام شد و پنل هست
    NSString *_pendingURL;           // آدرسی که پیش از آن رسید و منتظر مانده
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
    [self buildEditMenu];
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
    [NSFileManager.defaultManager createDirectoryAtURL:ZSessionsDir()
                           withIntermediateDirectories:YES attributes:nil error:nil];
    ZRegisterFonts();
    [self buildEditMenu];
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
        // پنل رونویسی فایل که جلو باشد، Esc مالِ خودِ اوست نه سشن دیکته. این پنل
        // یک کارِ پس‌زمینه‌ی طولانی دارد و نباید با کلیدهای سشن دست‌کاری شود.
        if ([ZBatchPanel.shared isFront]) return NO;
        __strong typeof(ws) me = ws;
        if (!me || !me->_session) return NO;
        dispatch_async(dispatch_get_main_queue(), ^{ [me sessionDo:@selector(finish)]; });
        return YES;
    };
    _hotkeys.onHelp = ^{ [ZCheatSheet toggle]; };
    // تک‌تپ Command راست حالا یعنی **پایان**، نه مکث. در نسخه یک متن حین حرف زدن
    // می‌آمد و کاربر هیچ‌وقت لازم نبود چیزی را علامت بدهد؛ حالا لازم است، و آن علامت
    // باید همان کلیدی باشد که دستش رویش است. مکث سر جایش می‌ماند، روی Space.
    _hotkeys.onPauseToggle = ^{ [ws sessionDo:@selector(pauseToggle)]; };
    _hotkeys.onPause = ^{ [ws sessionDo:@selector(togglePause)]; };
    _hotkeys.onCopyNow = ^{ [ws sessionDo:@selector(copyNow)]; };
    _hotkeys.onInsertHere = ^{ [ws sessionDo:@selector(insertHere)]; };
    _hotkeys.onSensToggle = ^{ [ws sessionDo:@selector(toggleSensitivity)]; };
    _hotkeys.onTrash = ^{ [ws sessionDo:@selector(dropPending)]; };
    _hotkeys.onLangSwitch = ^{ [ws sessionDo:@selector(switchLang)]; };
    _hotkeys.onModeToggle = ^{ [ws sessionDo:@selector(toggleMode)]; };
    // بی‌سشن هم کار می‌کند، پس مثل بقیه از sessionDo رد نمی‌شود. تاگل است نه فقط باز
    // کردن: پنل رونویسی با همان F می‌رود پس‌زمینه و با همان F برمی‌گردد، و کار در
    // جریان با پنهان شدنش نمی‌ایستد.
    _hotkeys.onFilePanel = ^{ [ZBatchPanel.shared toggle]; };
    // دکمه‌ی «رونویسی فایل» روی نوار پنل شناور: سومین راه دسترسی. اینجا ست می‌شود نه
    // در ZSession، چون به سشن ربطی ندارد و باید حتی بین دو سشن هم زنده باشد.
    _panel.onFilePanel = ^{ [ws openBatchPanel]; };
    // راهنما از خود نوار هم باز می‌شود. در نسخه یک اختیاری بود چون کاربر لازم نبود
    // چیزی بداند؛ حالا باید بداند تک‌تپ یعنی پایان، پس کارت باید از خودِ پنل پیدا شود.
    _panel.onHelp = ^{ [ZCheatSheet toggle]; };
    // تاگل پاس هوش مصنوعی. مثل F و H بی‌سشن هم کار می‌کند، چون یک **تنظیم** است نه
    // کارِ سشن، و کاربر باید بتواند قبل از شروع حرف زدن تصمیمش را بگیرد.
    _panel.onAIToggle = ^{ [ws toggleAIPass]; };
    _hotkeys.onAIPass = ^{ [ws toggleAIPass]; };
    // B: همین صدا را انگلیسی هم بشنو. مثل A یک تنظیم است، پس بی‌سشن هم کار می‌کند و
    // مثل A از دو در می‌آید: دکمه‌ی نوار و میان‌بر.
    _hotkeys.onSecondPass = ^{ [ws toggleSecondPass]; };
    _panel.onSecondPass = ^{ [ws toggleSecondPass]; };
    // بقیه‌ی دکمه‌های نوار مالِ سشن‌اند و ZSession خودش در wirePanel می‌بنددشان.


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
    // و کلید پاس نهایی هم همین حالا، در پس‌زمینه: منو و کارت راهنما باید از اولین بار
    // درست بگویند کلید هست یا نه، و پرسشِ Keychain حق ندارد نخ اصلی را نگه دارد.
    // و اگر جواب «کلید نیست» بود، تاگل همان‌جا خاموش می‌شود: حالتِ روشنِ بی‌کلید حق
    // ندارد از یک اجرا به اجرای بعد سفر کند. اینجا بی‌پرسش و بی‌پنجره، چون کاربر تازه
    // مک را روشن کرده و مودالِ لانچ مزاحم است؛ پرسش مالِ لحظه‌ای است که خودش روشنش کند.
    if (ZSettings.shared.finalPassEnabled) {
        [ZFinalPass.shared prefetchKey];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!ZSettings.shared.finalPassEnabled || !ZFinalPass.keyKnownMissing) return;
            ZSettings.shared.finalPassEnabled = NO;
            ZLog(@"app: تمیز کردن متن روشن بود ولی کلید نبود؛ خاموش شد");
        });
    }
    // سشن‌های قدیمی‌تر از هفت روز همین‌جا و بی‌صدا جارو می‌شوند
    ZSweepOldSessions();
    ZLog(@"app: launched res=%@ data=%@ ax=%d", ZRes().path, ZSupport().path,
         [ZInjector accessibilityOK]);

    // حالا پنل هست و آدرسِ در صف می‌تواند اجرا شود. اگر کارابینر اپ را با
    // `zemzeme://start` بالا آورده باشد، سشن دقیقا از همین‌جا شروع می‌شود.
    _launched = YES;
    NSString *queued = _pendingURL;
    _pendingURL = nil;
    if (queued.length) [self runURL:queued];
}

// اپِ اکسسوری منوی اصلی ندارد، و مک میان‌برهای ویرایش را از **منو** می‌گیرد نه از
// جای دیگر. نتیجه‌اش این بود که در شیتِ «کلید Gemini…» هیچ‌کدام از Command+V و
// Command+A و Command+C کار نمی‌کردند و کاربر کلیدِ چهل‌نویسه‌ای را باید دستی تایپ
// می‌کرد. یک منوی ویرایشِ نامرئی همین را درست می‌کند: دیده نمی‌شود، ولی میان‌برها
// زنده می‌شوند.
- (void)buildEditMenu {
    NSMenu *main = [NSMenu new];
    NSMenuItem *editItem = [NSMenuItem new];
    [main addItem:editItem];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"ویرایش"];
    struct { NSString *t; SEL a; NSString *k; } rows[] = {
        {@"واگرد",        @selector(undo:),       @"z"},
        {@"از نو",        @selector(redo:),       @"Z"},
        {@"برش",          @selector(cut:),        @"x"},
        {@"کپی",          @selector(copy:),       @"c"},
        {@"چسباندن",      @selector(paste:),      @"v"},
        {@"انتخاب همه",   @selector(selectAll:),  @"a"},
    };
    for (unsigned i = 0; i < sizeof(rows) / sizeof(rows[0]); i++) {
        [edit addItemWithTitle:rows[i].t action:rows[i].a keyEquivalent:rows[i].k];
    }
    editItem.submenu = edit;
    NSApp.mainMenu = main;
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
        @"دیکته: Command راست را دو بار پشت هم بزن و حرف بزن. **تا وقتی حرف می‌زنی هیچ "
         "متنی نشان داده نمی‌شود**؛ حرفت که تمام شد یک بار Command راست را بزن و متن "
         "یک‌جا می‌آید.\n\n"
         "الان مک یک پنجره‌ی اجازه باز می‌کند (اسمش Accessibility است)؛ اجازه بده تا "
         "زمزمه بتواند متن را جای کرسر بنویسد. میکروفن هم سرِ اولین دیکته پرسیده می‌شود.\n\n"
         "«تمیز کردن متن» اختیاری است و یک کلید رایگان از Google AI Studio می‌خواهد؛ "
         "هر وقت خواستی، از منوی زمزمه «کلید Gemini…» را بزن.\n\n"
         "راهنمای کامل میان‌برها: Command راست + H.";
    // تیک‌خورده می‌آید و عمدا: زمزمه‌ی بسته هیچ کلیدی را نمی‌شنود، پس اپی که بعد از
    // ری‌استارت بالا نیاید عملا هاتکی ندارد. ولی پنهان هم نیست، چون افزودنِ بی‌خبرِ
    // یک آیتم به لیست ورود همان کاری است که کاربر از اپ‌های دیگر بدش می‌آید.
    NSButton *atLogin = [NSButton checkboxWithTitle:@"بعد از روشن شدن مک، زمزمه خودش بالا بیاید"
                                             target:nil action:NULL];
    atLogin.state = NSControlStateValueOn;
    [atLogin sizeToFit];
    a.accessoryView = atLogin;
    [a addButtonWithTitle:@"باشه"];
    [a addButtonWithTitle:@"راهنمای میان‌برها"];
    NSModalResponse r = [a runModal];
    if (atLogin.state == NSControlStateValueOn) {
        NSError *e = nil;
        if (!ZSetLoginItem(YES, &e)) {
            ZLog(@"login item: روشن نشد: %@", e.localizedDescription ?: @"?");
        }
    }
    if (r == NSAlertSecondButtonReturn) [ZCheatSheet toggle];
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
}

// ---------- URL: zemzeme://toggle | start | stop ----------

- (void)handleURLEvent:(NSAppleEventDescriptor *)event withReply:(NSAppleEventDescriptor *)reply {
    NSString *url = [event paramDescriptorForKeyword:keyDirectObject].stringValue ?: @"";
    ZLog(@"app: url %@", url);
    // **آدرسی که اپ را بالا می‌آورد زودتر از خودِ بالا آمدن می‌رسد.** هندلر در
    // `applicationWillFinishLaunching` نصب می‌شود، پس لانچ‌سرویس آدرس را پیش از
    // `applicationDidFinishLaunching` تحویل می‌دهد. یعنی وقتی کارابینر اپِ بسته را با
    // `zemzeme://start` بالا می‌آورد، سشن پیش از ساخته شدنِ `_panel` شروع می‌شد و با
    // پنلِ nil کار می‌کرد: دیکته می‌رفت، ولی هیچ پنلی روی صفحه نبود. در لاگ هم پیدا
    // بود، `session: start` بالای `app: launched` می‌نشست.
    // پس آدرس در صف می‌ماند تا اپ واقعا سرِ پا باشد.
    if (!_launched) {
        _pendingURL = url;
        ZLog(@"app: url در صف تا پایان لانچ");
        return;
    }
    [self runURL:url];
}

- (void)runURL:(NSString *)url {
    if ([url isEqualToString:@"zemzeme://start"]) {
        if (!_session) [self startSession];
    } else if ([url isEqualToString:@"zemzeme://stop"]) {
        [_session finish];
    } else if ([url isEqualToString:@"zemzeme://trash"]) {
        // همان کار سطل آشغال (D). از بیرون هم لازم بود: تنها راهِ سنجیدنِ «صدا هم دور
        // ریخته شود» بی‌دست‌زدن به کیبورد، و برای Karabiner و Shortcuts هم به کار می‌آید.
        [self sessionDo:@selector(dropPending)];
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
    // یک موتور، برای هر دو حالت. نسخه یک اینجا کارخانه داشت چون حالت یادداشت موتور
    // دیگری می‌خواست؛ آن حالت رفت و کارخانه با آن.
    ZSession *s = [[ZSession alloc] initWithEngine:[[ZEngine alloc] initWithLang:ZSettings.shared.lang]
                                            panel:_panel];
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

// منو و نوارِ پنل حالا **یک چیدمان** دارند: همان سه دسته، به همان ترتیب.
//
// قبلا هرکدام ساز خودشان را می‌زدند. سطل آشغال فقط روی نوار بود؛ رونویسی فایل بالای
// منو ولی وسط نوار؛ تاگل‌ها روی نوار یک دسته‌ی جمع‌وجور بودند و در منو پخش در دو جای
// مختلف. یعنی کاربر برای یک اپ باید دو نقشه‌ی جدا در سر می‌داشت، و هر بار که از یکی
// به آن یکی می‌رفت دنبال چیزی می‌گشت که جایش عوض شده بود.
//
// حالا هر دکمه‌ی نوار، در همان دسته و تقریبا همان ترتیب، یک ردیف در منو دارد:
//   دسته‌ی یک — کارهای همین دیکته:  × ⌘ C I D
//   دسته‌ی دو — زبان و حالت و ابزار: L E F H
//   دسته‌ی سه — تاگل‌ها:              S B A
// منو **کامل‌تر** است، نه متفاوت: چیزی که روی یک آیکون جا نمی‌شود همان‌جا در دسته‌ی
// خودش اضافه می‌شود (انتخاب زبان و حالت به‌جای چرخاندنشان، کلید Gemini زیر تاگلی که
// به آن نیاز دارد)، و آخر از همه چیزهایی که اصلا روی نوار نیستند.
- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    menu.autoenablesItems = NO;
    BOOL active = _session != nil;
    BOOL paused = active && _session.engine.paused;

    // ---------- دسته‌ی یک: کارهای همین دیکته (آینه‌ی × ⌘ C I D) ----------
    //
    // **عنوان کوتاه، توضیح در تولتیپ.** ردیف منو جای جمله نیست: چشم آن را در یک نگاه
    // می‌خواند و هر واژه‌ی اضافه همان نگاه را کند می‌کند. پس عنوان‌ها دو کلمه‌اند و
    // هرچه لازم بود گفته شود، همان‌جا در تولتیپ نشسته، نه در خودِ عنوان.
    NSMenuItem *toggle = [self icon:[self item:menu title:active ? @"پایان دیکته" : @"شروع دیکته"
                                        action:@selector(menuToggle) key:@""]
                              symbol:active ? @"stop.circle" : @"mic.fill"];
    toggle.toolTip = active ? @"سشن تمام می‌شود و متن سر کرسر درج می‌شود (Esc)"
                            : @"دو بار زدن Command راست هم همین کار را می‌کند";
    if (active) {
        NSMenuItem *pause = [self item:menu title:paused ? @"ادامه" : @"مکث"
                                action:@selector(menuPauseToggle) key:@" "];
        [self icon:pause symbol:paused ? @"play.circle" : @"pause.circle"];
        pause.toolTip = paused ? @"دوباره گوش کن" : @"بایست و متن تا اینجا را تحویل بده";
        NSMenuItem *copy = [self item:menu title:@"کپی متن" action:@selector(menuCopyNow) key:@"c"];
        [self icon:copy symbol:@"doc.on.doc"];
        copy.toolTip = @"هرچه تا الان گفته‌ای، در کلیپ‌بورد";
        NSMenuItem *ins = [self item:menu title:@"درج متن" action:@selector(menuInsertHere) key:@"i"];
        [self icon:ins symbol:@"text.insert"];
        ins.toolTip = @"متن را در همان برنامه‌ای بنویس که پشت پنل باز است";
        // سطل آشغال تا امروز فقط روی نوار و روی میان‌بر بود. کاری که برگشت ندارد باید
        // از هر سه در پیدا باشد، نه فقط از دری که پنل جلوی چشم است.
        NSMenuItem *trash = [self item:menu title:@"دور ریختن" action:@selector(menuTrash) key:@"d"];
        [self icon:trash symbol:@"trash"];
        trash.toolTip = @"هرچه هنوز درج نشده، به‌علاوه‌ی صدای ضبط‌شده‌اش، دور ریخته می‌شود";
    }
    [menu addItem:NSMenuItem.separatorItem];

    // ---------- دسته‌ی دو: زبان و حالت و ابزارها (آینه‌ی L E F H) ----------
    // **زیرمنو فقط برای انتخابِ چندگزینه‌ای**، و همین دو تا. یک بار تاگل‌های روزمره را
    // توی زیرمنوی «شنیدن» بردم و کاربر فکر کرد فیچر حذف شده؛ پس هرچه تاگل است یک
    // کلیکه می‌ماند و فقط با خط جداکننده دسته می‌شود.
    //
    // عنوانِ ردیفِ پدر مقدارِ فعلی را هم می‌گوید، پس برای **دانستن** حالت لازم نیست
    // زیرمنو باز شود؛ باز کردنش فقط برای **عوض کردن** است.
    BOOL fa = [ZSettings.shared.lang hasPrefix:@"fa"];
    NSMenuItem *langItem = [self icon:[[NSMenuItem alloc]
                                       initWithTitle:fa ? @"زبان: فارسی" : @"زبان: English"
                                              action:nil keyEquivalent:@""]
                                symbol:@"globe"];
    langItem.toolTip = @"زبان دیکته. عوض کردنش از سشن بعد اثر می‌کند، نه وسط همین یکی "
                        "(Command راست + L)";
    NSMenu *langMenu = [NSMenu new];
    langMenu.autoenablesItems = NO;
    [self item:langMenu title:@"فارسی" action:@selector(menuLangFa) key:@""].state =
        fa ? NSControlStateValueOn : NSControlStateValueOff;
    [self item:langMenu title:@"English" action:@selector(menuLangEn) key:@""].state =
        fa ? NSControlStateValueOff : NSControlStateValueOn;
    langItem.submenu = langMenu;
    [menu addItem:langItem];

    // حالت، به‌جای تاگلِ چرخشی. دکمه‌ی E روی نوار بین دو حالت می‌چرخد، و چرخاندن یعنی
    // کاربر باید **اول بداند الان کجاست** تا بفهمد زدنش او را کجا می‌برد. منو جای آن
    // دانستن است: هر دو حالت با اسم دیده می‌شوند و تیک می‌گوید کدام روشن است.
    // قبلا این ردیف اصلا نبود، با این استدلال که «دو جای تنظیم برای یک چیز گیج‌کننده
    // است». ولی دو جا وقتی گیج‌کننده است که دو **رفتار** باشند؛ اینجا یک تنظیم است با
    // دو نما: نوار می‌چرخاندش، منو انتخابش می‌کند.
    ZMode mode = ZSettings.shared.mode;
    NSMenuItem *modeItem = [self icon:[[NSMenuItem alloc]
                                       initWithTitle:[@"جای متن: " stringByAppendingString:ZModeLabel(mode)]
                                              action:nil keyEquivalent:@""]
                                symbol:mode == ZModeCursor ? @"text.cursor" : @"square.and.pencil"];
    modeItem.toolTip = @"متن کجا بنشیند (Command راست + E)";
    NSMenu *modeMenu = [NSMenu new];
    modeMenu.autoenablesItems = NO;
    NSMenuItem *mCollect = [self item:modeMenu title:ZModeLabel(ZModeCollect)
                               action:@selector(menuModeCollect) key:@""];
    mCollect.state = mode == ZModeCollect ? NSControlStateValueOn : NSControlStateValueOff;
    mCollect.toolTip = @"متن در خود پنل جمع می‌شود و می‌توانی ویرایشش کنی؛ سر پایان یک‌جا درج می‌شود";
    NSMenuItem *mCursor = [self item:modeMenu title:ZModeLabel(ZModeCursor)
                              action:@selector(menuModeCursor) key:@""];
    mCursor.state = mode == ZModeCursor ? NSControlStateValueOn : NSControlStateValueOff;
    mCursor.toolTip = @"پنل می‌رود و فقط یک نقطه کنار کرسر می‌ماند؛ متن سر پایان همان‌جا نوشته می‌شود";
    modeItem.submenu = modeMenu;
    [menu addItem:modeItem];

    // رونویسی فایل و راهنما: دو ابزارِ همیشه‌فعال، دقیقا مثل جایشان روی نوار (F و H).
    // به سشن ربطی ندارند و وسط دیکته هم باز می‌شوند.
    NSMenuItem *batch = [self icon:[self item:menu title:@"رونویسی فایل…"
                                       action:@selector(menuBatch) key:@"f"]
                             symbol:@"arrow.up.doc"];
    batch.toolTip = @"فایل صوتی یا تصویری را به متن تبدیل کن. چند فایل پشت هم، با پیشرفت "
                     "زنده و یک متن قابل ویرایش (Command راست + F)";
    // یک آیتم، یک کارت. زیرمنوی قبلی فهرستی از ردیف‌های غیرفعال بود: خاکستری، بی‌آیکون،
    // و متن فارسی و لاتینِ یک‌خطی جابه‌جا خوانده می‌شد. حالا کارت واقعی باز می‌شود
    // (ZCheatSheet) که کی‌کپ و آیکون دارد و کنار دستت باز می‌ماند تا کلیدها را تمرین کنی.
    NSMenuItem *keysItem = [self icon:[self item:menu title:@"راهنمای میان‌برها"
                                          action:@selector(menuCheatSheet) key:@"h"]
                                symbol:@"questionmark.circle"];
    keysItem.toolTip = @"کارت میان‌برها با Command راست + H؛ شناور می‌ماند و با Esc بسته می‌شود";
    [menu addItem:NSMenuItem.separatorItem];

    // ---------- دسته‌ی سه: تاگل‌ها (آینه‌ی S B A) ----------
    // همان سه تاگلِ نوار، به همان ترتیب: دو تای اول مالِ **شنیدن**اند و کنار هم، سومی
    // مالِ **متن** است و آخر می‌آید تا کلیدش بتواند درست زیرش بنشیند.
    // حساسیت از «پیشرفته» دور می‌ماند و عمدا: یک ترجیحِ یک‌باره نیست، تنظیمی است که
    // کاربر بسته به اتاق و میکروفن عوض می‌کند.
    NSMenuItem *sens = [self icon:[self item:menu title:@"حساسیت بالا"
                                       action:@selector(menuToggleSensitivity) key:@"s"]
                            symbol:ZSettings.shared.highSensitivity ? @"ear.fill" : @"ear.badge.waveform"];
    sens.state = ZSettings.shared.highSensitivity ? NSControlStateValueOn : NSControlStateValueOff;
    sens.toolTip = @"حساسیت میکروفن، برای پچ‌پچ کردن، اتاق ساکت، یا میکروفنی که صدایش "
                    "کم می‌رسد. وسط دیکته هم با Command راست + S عوض می‌شود";
    // پاس دوم انگلیسی روی همان صدا. رایگان و موازی، ولی پیش‌فرض خاموش چون سودش فقط
    // روی متنِ پر از اصطلاح فنی دیده می‌شود و در عوض یک سشن به ازای هر تکه خرج دارد.
    NSMenuItem *sec = [self icon:[self item:menu title:@"شنیدن دوزبانه"
                                     action:@selector(menuToggleSecondPass) key:@"b"]
                           symbol:ZSettings.shared.secondPass ? @"character.book.closed.fill"
                                                              : @"character.book.closed"];
    sec.state = ZSettings.shared.secondPass ? NSControlStateValueOn : NSControlStateValueOff;
    sec.toolTip = @"همان صدا را هم‌زمان یک بار انگلیسی هم می‌شنود، تا اصطلاح‌های فنی از "
                   "دست نروند. رایگان است ولی دو برابر سهم کلید را می‌برد. روی گفتار "
                   "روزمره تقریبا هیچ فرقی نمی‌کند؛ برای متنِ پر از اصطلاح روشنش کن "
                   "(دکمه‌ی B روی نوار، یا Command راست + B)";

    // تمیز کردن متن و کلیدش، پشت سر هم: یکی بی آن یکی کار نمی‌کند. کلید **کار** است نه
    // تنظیم، پس در «پیشرفته» جایی ندارد؛ جایش دقیقا زیر همان تاگلی است که به آن نیاز دارد.
    BOOL hasKey = ZFinalPass.hasKey;
    // حالت سوم: کلید در کی‌چین هست ولی ACL آیتم این اپ را نمی‌شناسد (معمولا چون یک بار
    // با `security` در ترمینال ساخته شده). منو پنجره‌ی رمز را بالا نمی‌آورد، پس اینجا
    // فقط راستش را می‌گوید؛ یک بار «کلید Gemini…» و ذخیره‌ی دوباره، تمامش می‌کند.
    BOOL keyLocked = !hasKey && ZFinalPass.keyNeedsPermission;
    NSMenuItem *fin = [self icon:[self item:menu title:@"تمیز کردن متن"
                                     action:@selector(menuToggleFinalPass) key:@"a"]
                           symbol:@"sparkles"];
    fin.state = ZSettings.shared.finalPassEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    fin.toolTip = hasKey
        ? @"سر پایان، **متنِ** دیکته به Gemini می‌رود و تمیزتر برمی‌گردد: نقطه‌گذاری و "
           "پاراگراف‌بندی، و اصلاح واژه‌ای که صد در صد غلط است. صدا هیچ‌وقت فرستاده "
           "نمی‌شود. جواب نیامد، همان متن خام می‌نشیند. (Command راست + A)"
        : @"روشنش کنی، همان‌جا کلید Gemini را می‌خواهد؛ کلید ندهی، دوباره خاموش می‌شود.";
    // کلید Gemini: یک شیت کوچک به‌جای ترمینال. زیر همان تاگلی می‌نشیند که به آن نیاز
    // دارد، چون کلید فقط برای همین یک کار است.
    NSMenuItem *key = [self icon:[self item:menu
                                       title:hasKey ? @"کلید Gemini (هست)"
                                           : keyLocked ? @"کلید Gemini (قفل)"
                                                       : @"کلید Gemini…"
                                     action:@selector(menuSetKey) key:@""]
                           symbol:@"key.fill"];
    key.toolTip = keyLocked
        ? @"کلیدی در Keychain هست ولی این نسخه‌ی زمزمه اجازه‌ی خواندنش را ندارد. "
           "همین‌جا کلید را دوباره بگذار تا صاحبش خودِ زمزمه شود و دیگر پرسیده نشود."
        : @"کلید رایگان از Google AI Studio؛ فقط در Keychain همین دستگاه ذخیره می‌شود. "
           "فقط برای «تمیز کردن متن» لازم است؛ بدون آن، اصلا لازم نیست.";
    [menu addItem:NSMenuItem.separatorItem];

    // ---------- آخر از همه: چیزهایی که روی نوار نیستند ----------
    //
    // «پیشرفته» فقط **پیش‌فرض‌ها**ست: تنظیم‌هایی که کاربر یک بار سرِ نصب می‌بیند و بعد
    // شاید هیچ‌وقت دست نزند. کارها اینجا جایی ندارند و بیرون آمدند: «پوشه‌ی دیکته‌ها» و
    // «اجازه‌های مک» چیزی را عوض نمی‌کنند، یک پنجره باز می‌کنند، و پشتِ در «پیشرفته»
    // گذاشتنشان یعنی کسی که دنبال فایل دیکته‌اش می‌گردد اول باید بپذیرد کار پیشرفته‌ای
    // می‌کند. حالا ردیف خودشان را دارند، همین‌جا و یک کلیکه.
    NSMenuItem *advItem = [self icon:[[NSMenuItem alloc] initWithTitle:@"پیشرفته" action:nil keyEquivalent:@""]
                               symbol:@"gearshape"];
    advItem.toolTip = @"پیش‌فرض‌هایی که یک بار تنظیم می‌شوند: صدا، روش نوشتن، راه‌اندازی";
    NSMenu *adv = [NSMenu new];
    adv.autoenablesItems = NO;

    // صداهای خود زمزمه: یک ترجیحِ یک‌باره، پس جایش همین‌جاست نه ردیف اولِ منو.
    NSMenuItem *snd = [self icon:[self item:adv title:@"صداها"
                                     action:@selector(menuToggleSounds) key:@""]
                           symbol:@"speaker.wave.2"];
    snd.state = ZSettings.shared.soundsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    snd.toolTip = @"هر کار صدای خودش را دارد: شروع، مکث، ادامه، درج، پایان، دور ریختن";

    // ماندنِ صدا روی دیسک، نه خودِ ضبط: ضبط در طول سشن همیشه انجام می‌شود چون فایل
    // مرجع همه‌چیز است. جایش «پیشرفته» است و میان‌بری هم ندارد: یک ترجیحِ یک‌باره است
    // که آدم شاید سالی یک بار عوضش کند، نه چیزی که وسط دیکته لازم شود.
    NSMenuItem *rec = [self icon:[self item:adv title:@"نگه داشتن صدا"
                                     action:@selector(menuToggleRecord) key:@""]
                           symbol:@"record.circle"];
    rec.state = ZSettings.shared.recordSessions ? NSControlStateValueOn : NSControlStateValueOff;
    rec.toolTip = @"صدای دیکته بعد از آماده شدن متن هم روی دیسک بماند (هفت روز، بعد خودکار "
                   "پاک می‌شود). خاموش یعنی همان لحظه پاک شود. در هر دو حالت، در طول خودِ "
                   "دیکته ضبط انجام می‌شود تا اگر اینترنت قطع شد حرفی گم نشود.";

    NSMenuItem *flac = [self icon:[self item:adv title:@"فشرده‌سازی (FLAC)" action:@selector(menuToggleFLAC) key:@""]
                            symbol:@"waveform.circle"];
    flac.state = ZSettings.shared.upstreamFLAC ? NSControlStateValueOn : NSControlStateValueOff;
    flac.toolTip = @"حجم صدایی که فرستاده می‌شود را تا نصف کم می‌کند؛ اگر جواب نداد، خودش به حالت عادی برمی‌گردد";
    [adv addItem:NSMenuItem.separatorItem];

    // **یک سوال، یک ردیف.** قبلا دو ردیفِ تیک‌دار بود، «تایپ مستقیم» و «چسباندن»، و
    // هیچ‌کدام نمی‌گفت موضوع چیست: نه معلوم بود این دو با هم یک انتخاب‌اند، نه اینکه
    // اصلا دارند درباره‌ی چه چیزی تصمیم می‌گیرند. حالا مثل «زبان» و «جای متن»، یک ردیف
    // که مقدار فعلی را در خودش نوشته و زیرمنویی که همان دو راه را با اسمِ کامل می‌گوید.
    BOOL typing = ZSettings.shared.insertMode == ZInsertType;
    NSMenuItem *insItem = [self icon:[[NSMenuItem alloc]
                                      initWithTitle:typing ? @"روش نوشتن: تایپ" : @"روش نوشتن: چسباندن"
                                             action:nil keyEquivalent:@""]
                               symbol:typing ? @"keyboard" : @"doc.on.clipboard"];
    insItem.toolTip = @"متن آماده چطور در برنامه‌ی مقصد نوشته شود: حرف‌به‌حرف تایپ شود، "
                       "یا یک‌جا چسبانده شود";
    NSMenu *insMenu = [NSMenu new];
    insMenu.autoenablesItems = NO;
    NSMenuItem *iType = [self item:insMenu title:@"تایپ کردن، حرف‌به‌حرف"
                            action:@selector(menuInsertMode:) key:@""];
    iType.representedObject = @(ZInsertType);
    iType.state = typing ? NSControlStateValueOn : NSControlStateValueOff;
    iType.toolTip = @"زمزمه متن را حرف‌به‌حرف تایپ می‌کند، مثل کسی که پشت کیبورد نشسته. "
                     "تقریبا همه‌جا کار می‌کند، ولی متن بلند کند نوشته می‌شود.";
    NSMenuItem *iPaste = [self item:insMenu title:@"چسباندن، یک‌جا با Command+V"
                             action:@selector(menuInsertMode:) key:@""];
    iPaste.representedObject = @(ZInsertPaste);
    iPaste.state = typing ? NSControlStateValueOff : NSControlStateValueOn;
    iPaste.toolTip = @"متن در کلیپ‌بورد می‌نشیند و زمزمه Command+V را می‌زند: آنی، حتی برای "
                      "متن بلند. برنامه‌ی مقصد باید چسباندن را قبول کند.";
    insItem.submenu = insMenu;
    [adv addItem:insItem];

    // استثنای Windows App جدا و دیدنی، نه پنهان در کد: پیست آنجا به کلیپ‌بورد ریموت
    // وابسته است و کلیپ‌بورد ریموت گیر می‌کند، ولی تایپ مستقیم فقط وقتی جواب می‌دهد
    // که خود Windows App روی Keyboard Mode = Unicode باشد. پس تصمیمش مال کاربر است.
    // اینجا هم مقدار در خودِ عنوان است نه پشت یک تیک: تیکِ «تایپ مستقیم» جواب می‌داد
    // که کاربر بداند نبودنش یعنی چسباندن، و همان دانستن چیزی بود که کم داشت.
    BOOL rdpType = [ZSettings.shared insertModeForBundleId:kZRDPBundleId] == ZInsertType;
    NSMenuItem *rdp = [self icon:[self item:adv
                                       title:rdpType ? @"Windows App: تایپ" : @"Windows App: چسباندن"
                                      action:@selector(menuToggleRDPType) key:@""]
                           symbol:@"display"];
    rdp.toolTip = rdpType
        ? @"استثنای Windows App. برای برگشتن به چسباندن بزن. تایپ آنجا فقط وقتی جواب "
           "می‌دهد که در نوار منوی خودِ Windows App هم Keyboard Mode ← Unicode باشد."
        : @"استثنای Windows App: ریموت کلیدهای یونیکد را مطمئن نمی‌فرستد، پس آنجا "
           "چسباندن پیش‌فرض است. برای عوض کردنش بزن.";
    [adv addItem:NSMenuItem.separatorItem];

    NSMenuItem *hk = [self icon:[self item:adv title:@"میان‌بر داخلی" action:@selector(menuToggleHotkey) key:@""]
                          symbol:@"command"];
    hk.state = ZSettings.shared.internalHotkey ? NSControlStateValueOn : NSControlStateValueOff;
    // دیگر «آزمایشی» نیست و دیگر با Karabiner دعوا ندارد: رول Karabiner کلید را پاس
    // می‌دهد و قبل از هر کاری با pgrep می‌پرسد اپ بالاست یا نه. بالا که باشد، هیچ.
    hk.toolTip = @"دو بار زدن Command راست، از داخل خود زمزمه. رول Karabiner فقط وقتی "
                  "زمزمه بسته است کاری می‌کند، پس خاموش کردن دستی‌اش لازم نیست";

    // کنارِ هاتکی می‌نشیند چون در عمل شرطِ کار کردنِ آن است: اپِ بسته کلید نمی‌شنود.
    NSMenuItem *li = [self icon:[self item:adv title:@"اجرای خودکار"
                                     action:@selector(menuToggleLoginItem) key:@""]
                          symbol:@"power"];
    li.state = ZLoginItemOn() ? NSControlStateValueOn : NSControlStateValueOff;
    li.toolTip = @"زمزمه بعد از روشن شدن مک خودش بالا می‌آید. با این، میان‌بر داخلی به "
                  "تنهایی کافی است و به Karabiner یا هیچ ابزار جانبی دیگری نیازی نیست";
    advItem.submenu = adv;
    [menu addItem:advItem];

    NSMenuItem *fold = [self icon:[self item:menu title:@"پوشه‌ی دیکته‌ها"
                                      action:@selector(menuOpenSessions) key:@""]
                            symbol:@"folder"];
    fold.toolTip = @"متن و صدای هر سشن، روی همین دستگاه. صدا فقط اگر «نگه داشتن صدا» روشن باشد می‌ماند";
    NSMenuItem *perm = [self icon:[self item:menu title:@"اجازه‌های مک"
                                      action:@selector(menuOpenAccessibility) key:@""]
                            symbol:@"lock.shield"];
    perm.toolTip = @"تنظیمات سیستم، بخش Accessibility: بی این اجازه، متن سر کرسر نوشته نمی‌شود";

    [menu addItem:NSMenuItem.separatorItem];
    [self icon:[self item:menu title:@"خروج" action:@selector(menuQuit) key:@"q"] symbol:@"power"];
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
- (void)menuTrash { [self sessionDo:@selector(dropPending)]; }
- (void)menuCheatSheet { [ZCheatSheet toggle]; }
- (void)menuModeCollect { [self setMode:ZModeCollect]; }
- (void)menuModeCursor { [self setMode:ZModeCursor]; }

// حالت از دو در عوض می‌شود و باید یک رفتار داشته باشد. سشن باز باشد، از راهِ خودِ
// سشن می‌رویم تا پنل و نقطه همان لحظه جابه‌جا شوند و صدا و فیدبکش هم بیاید؛ نباشد،
// فقط تنظیم عوض می‌شود و سشن بعدی با آن بالا می‌آید. چون حالت‌ها دقیقا دوتا هستند،
// «رفتن به آن یکی» همان toggle است.
- (void)setMode:(ZMode)m {
    if (ZSettings.shared.mode == m) return;
    if (_session) {
        [self sessionDo:@selector(toggleMode)];
        return;
    }
    ZSettings.shared.mode = m;
}
// سه راه دسترسی، یک پنل و یک صف: منوبار، Command راست + F، و دکمه‌ی نوار پنل
- (void)openBatchPanel { [ZBatchPanel.shared show]; }
- (void)menuBatch { [self openBatchPanel]; }
- (void)menuLangFa { [self setLang:@"fa-IR"]; }
- (void)menuLangEn { [self setLang:@"en-US"]; }
// زبان از سشن **بعد** اثر می‌کند. عوض کردنش وسط کار یعنی نصف تکه‌ها با یک زبان و
// نصفشان با زبان دیگر رونویسی شوند، و متن حاصل دو تکه‌ی ناجور می‌شد.
- (void)setLang:(NSString *)l { ZSettings.shared.lang = l; }
- (void)menuToggleFLAC { ZSettings.shared.upstreamFLAC = !ZSettings.shared.upstreamFLAC; }
- (void)menuInsertMode:(NSMenuItem *)sender {
    ZSettings.shared.insertMode = [sender.representedObject integerValue];
}
- (void)menuToggleRDPType {
    ZInsertMode now = [ZSettings.shared insertModeForBundleId:kZRDPBundleId];
    [ZSettings.shared setInsertMode:(now == ZInsertType ? ZInsertPaste : ZInsertType) forBundleId:kZRDPBundleId];
}
// شیتِ کلید: جای دستورِ ترمینال. سه دکمه‌ی همیشگی به‌علاوه‌ی «پاک کردن» وقتی کلیدی
// از قبل هست. جواب دکمه‌ها با شیء خودشان مقایسه می‌شود، نه با عددِ ثابت NSAlert، چون
// ترتیب دکمه‌ها این‌جا شرطی است (کلید بود/نبود) و اندیس‌شان جابه‌جا می‌شود.
- (void)menuSetKey {
    BOOL had = ZFinalPass.hasKey;
    NSAlert *a = [NSAlert new];
    a.messageText = @"کلید Gemini";
    a.informativeText =
        @"«تمیز کردن متن» یک کلید رایگان از Google AI Studio می‌خواهد. "
         "کلید فقط روی همین دستگاه، در Keychain، "
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
        // کلید که رفت، تاگل هم می‌رود. وگرنه دقیقا همان حالت بینابینی ساخته می‌شود که
        // این نسخه دارد از بین می‌بردش: روشن، و بی‌کار.
        if (ZSettings.shared.finalPassEnabled) {
            ZSettings.shared.finalPassEnabled = NO;
            [_panel flash:@"کلید پاک شد؛ تمیز کردن متن هم خاموش شد"];
        }
    }
}

// یک جا برای هر دو در: میان‌بر A و ردیف منو. دو پیاده‌سازی یعنی دو رفتار واگرا، و
// همین را نسخه یک بارها به قیمتش یاد گرفت.
- (void)toggleAIPass {
    BOOL on = !ZSettings.shared.finalPassEnabled;
    ZSettings.shared.finalPassEnabled = on;
    if (on) [ZFinalPass.shared prefetchKey];
    [_panel flash:on ? @"تمیز کردن متن روشن شد؛ سر پایان انجام می‌شود"
                     : @"تمیز کردن متن خاموش شد"];
    ZPlay(ZSoundMode);
    // پرسشِ کلید عمدا با تاخیر: `hasKey` روی نخ اصلی محافظه‌کار است و تا جوابِ
    // Keychain نرسیده «نه» می‌گوید. بی این تاخیر، هر بار که کاربر تاگل را روشن
    // می‌کرد یک پرسشِ دروغ می‌گرفت، در حالی که کلید سر جایش بود.
    if (!on) return;
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) me = ws;
        if (!me || !ZSettings.shared.finalPassEnabled) return;
        if (ZFinalPass.keyKnownMissing) [me offerKey];
    });
}

// **حالت بینابینی وجود ندارد.** «روشن، ولی کلید ندارد» یعنی تاگلی که روشن است و هیچ
// کاری نمی‌کند؛ کاربر هر بار منتظر چیزی می‌ماند که قرار نیست بیاید. پس فقط دو در
// هست: کلید همین‌جا گذاشته می‌شود، یا تاگل خودش خاموش می‌شود. بستن پنجره با Esc هم
// همان درِ دوم است.
//
// دکمه‌ی «بعدا» و پرچمِ keyOfferDismissed هر دو برداشته شدند. «بعدا» یعنی «الان نه»،
// ولی آن پرچم آن را «هیچ‌وقت» می‌فهمید و یک بار زدنش، این پرسش را برای همیشه خفه
// می‌کرد. حالا هر بار که کاربر خودش دوباره روشنش کند، دوباره پرسیده می‌شود.
- (void)offerKey {
    NSAlert *a = [NSAlert new];
    a.messageText = @"«تمیز کردن متن» بی کلید Gemini کار نمی‌کند";
    a.informativeText = @"یا همین حالا کلید را بگذار، یا این تنظیم خاموش می‌شود؛ روشنِ "
                         "بی‌کلید فقط یعنی متن خام تحویل داده می‌شود و تو منتظر بمانی. "
                         "کلید رایگان است و فقط در Keychain همین دستگاه می‌ماند.";
    NSButton *set = [a addButtonWithTitle:@"کلید را بگذار"];
    [a addButtonWithTitle:@"خاموشش کن"];
    if ([a runModal] == [a.buttons indexOfObject:set] + NSAlertFirstButtonReturn) {
        [self menuSetKey];
        // شیتِ کلید بسته شد ولی کلیدی ننشست (لغو، یا کلیدِ خالی): همان درِ دوم.
        if (ZFinalPass.hasKey) {
            [_panel flash:@"کلید ذخیره شد؛ تمیز کردن متن روشن است"];
            return;
        }
    }
    ZSettings.shared.finalPassEnabled = NO;
    [_panel flash:@"کلید نبود، پس تمیز کردن متن خاموش شد"];
}

- (void)menuToggleFinalPass { [self toggleAIPass]; }

// شنیدنِ انگلیسیِ موازی. مثل A یک تنظیم است، پس بی‌سشن هم کار می‌کند. اثرش از دورِ
// **بعدیِ** شنیدن است و نه همین دور، چون خط لوله‌ها سر ساختِ موتور بسته می‌شوند؛
// پیام هم همین را می‌گوید تا کاربر وسط دیکته منتظر معجزه نماند.
- (void)toggleSecondPass {
    BOOL on = !ZSettings.shared.secondPass;
    ZSettings.shared.secondPass = on;
    [_panel flash:on ? @"از دور بعد، همین صدا انگلیسی هم شنیده می‌شود"
                     : @"شنیدن انگلیسیِ هم‌زمان خاموش شد"];
    ZPlay(ZSoundMode);
}
- (void)menuToggleSecondPass { [self toggleSecondPass]; }
- (void)menuToggleRecord { ZSettings.shared.recordSessions = !ZSettings.shared.recordSessions; }
- (void)menuToggleSounds {
    ZSettings.shared.soundsEnabled = !ZSettings.shared.soundsEnabled;
    ZPlay(ZSoundStart);    // روشن که شد، خودش را می‌شنوانَد
}
// تپ همیشه سرپا است؛ این تنظیم فقط تفسیر دابل‌تپ به toggle را روشن/خاموش می‌کند
- (void)menuToggleSensitivity {
    ZSession *s = _session;
    if (s) {    // سشن باز است: از همان راهِ سشن برو تا پیام و رندر هم بیایند
        [self sessionDo:@selector(toggleSensitivity)];
        return;
    }
    BOOL on = !ZSettings.shared.highSensitivity;
    ZSettings.shared.highSensitivity = on;
    ZLog(@"mic: حساسیت بالا %@", on ? @"روشن" : @"خاموش");
}

- (void)menuToggleHotkey {
    ZSettings.shared.internalHotkey = !ZSettings.shared.internalHotkey;
}

- (void)menuToggleLoginItem {
    BOOL want = !ZLoginItemOn();
    NSError *e = nil;
    if (ZSetLoginItem(want, &e)) {
        ZLog(@"login item: %@", want ? @"روشن" : @"خاموش");
        return;
    }
    // شکستش را بی‌صدا نمی‌گذاریم: کاربر تیک را زده و اگر هیچ نبینَد فکر می‌کند شد.
    // معمولا یعنی مک اجازه‌ی مدیریتِ آیتم‌های ورود را نداده، و درِ آن در تنظیمات است.
    ZLog(@"login item: %@ کردن نشد: %@", want ? @"روشن" : @"خاموش", e.localizedDescription ?: @"?");
    NSAlert *a = [NSAlert new];
    a.messageText = want ? @"اجرای خودکار روشن نشد" : @"اجرای خودکار خاموش نشد";
    a.informativeText = [NSString stringWithFormat:
        @"مک اجازه نداد: %@\n\nمی‌توانی همین را دستی از تنظیمات سیستم، بخش «General ← "
         "Login Items»، تغییر دهی.", e.localizedDescription ?: @"دلیل نامعلوم"];
    [a addButtonWithTitle:@"باشه"];
    [a addButtonWithTitle:@"تنظیمات سیستم"];
    if ([a runModal] == NSAlertSecondButtonReturn) {
        NSURL *u = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.LoginItems-Settings.extension"];
        [NSWorkspace.sharedWorkspace openURL:u];
    }
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
        // یک WAV از **کل** مسیر زنده، بی‌میکروفن و بی‌آدم. شرط سخت نسخه دو: هر ادعای
        // سرتاسری باید تکرارپذیر باشد. مثل حالت دسته‌ای پیش از NSApplication برمی‌گردد.
        if ([args containsObject:@"--livewav"]) return ZLiveWavMain(args);
        if ([args containsObject:@"--aipass"]) return ZAIPassMain(args);
        // آیکون بسته برای build.sh؛ مثل حالت دسته‌ای قبل از NSApplication برمی‌گردد
        NSUInteger ic = [args indexOfObject:@"--appicon"];
        if (ic != NSNotFound && ic + 1 < args.count) return ZMarkIconMain(args[ic + 1]);
        // اندازه‌گیری نردبان کرسر: مثل دو حالت بالا پیش از NSApplication برمی‌گردد، پس
        // اپ منوبارِ در حال اجرا دست نمی‌خورد و هیچ سشن دیکته‌ای باز نمی‌شود.
        if ([args containsObject:@"--caretprobe"]) return ZCaretProbeMain(args);
        // خودآزمای میکروفن: چند ثانیه از **همان** مسیری که دیکته از آن می‌خورد
        // (ZMic، تبدیل به ۱۶ کیلوهرتز مونو s16) در یک WAV می‌ریزد. دلیل وجودش این
        // بود که «صدا بد ضبط می‌شود» تا امروز فقط یک حس بود و هیچ عددی نداشت؛ با یک
        // فایل واقعی می‌شود بلندی، بریدگی، و پهنای باند را اندازه گرفت نه حدس زد.
        // مثل بقیه‌ی حالت‌ها پیش از NSApplication برمی‌گردد، پس اپِ در حال اجرا و
        // سشن بازش دست نمی‌خورند.
        NSUInteger md = [args indexOfObject:@"--micdump"];
        if (md != NSNotFound && md + 1 < args.count) {
            double secs = md + 2 < args.count ? [args[md + 2] doubleValue] : 10.0;
            return ZMicDumpMain(args[md + 1], secs > 0 ? secs : 10.0);
        }
        NSApplication *app = NSApplication.sharedApplication;
        static ZAppDelegate *delegate;
        delegate = [ZAppDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
