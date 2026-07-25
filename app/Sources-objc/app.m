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

// ---------- AppDelegate ----------

@interface ZAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@end

@implementation ZAppDelegate {
    NSStatusItem *_statusItem;
    ZPanel *_panel;
    ZSession *_session;
    ZHotkeyTap *_hotkeys;
    CFAbsoluteTime _lastToggleAt;    // دیبانس toggle داخلی در برابر toggle بیرونی (Karabiner)
    BOOL _axPrompted;                // پنجره درخواست اکسسبیلیتی فقط یک بار در هر اجرا
}

- (void)applicationWillFinishLaunching:(NSNotification *)n {
    [NSAppleEventManager.sharedAppleEventManager
        setEventHandler:self andSelector:@selector(handleURLEvent:withReply:)
          forEventClass:kInternetEventClass andEventID:kAEGetURL];
}

- (void)applicationDidFinishLaunching:(NSNotification *)n {
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
    _panel = [ZPanel new];
    _hotkeys = [ZHotkeyTap new];
    [self setupStatusItem];
    __weak typeof(self) ws = self;
    _hotkeys.onToggle = ^{ [ws toggleSession]; };
    _hotkeys.onEsc = ^{ [ws sessionDo:@selector(finish)]; };
    _hotkeys.onPauseToggle = ^{ [ws sessionDo:@selector(pauseToggle)]; };
    _hotkeys.onCopyNow = ^{ [ws sessionDo:@selector(copyNow)]; };
    _hotkeys.onInsertHere = ^{ [ws sessionDo:@selector(insertHere)]; };

    // حالت اسکرین‌شات طراحی: zemzeme --uishot <dir>
    NSArray *args = NSProcessInfo.processInfo.arguments;
    NSUInteger i = [args indexOfObject:@"--uishot"];
    if (i != NSNotFound && i + 1 < args.count) {
        [_panel makeShots:args[i + 1]];
        [NSApp terminate:nil];
        return;
    }

    [self watchAccessibility];
    // دیمن پاس از همین حالا گرم شود که تکه اول اولین سشن سرد نخورد
    if (ZSettings.shared.polishEnabled) [ZPolish.shared prepare];
    ZLog(@"app: launched res=%@ data=%@ ax=%d polish=%d",
         ZRes().path, ZSupport().path,
         [ZInjector accessibilityOK], ZSettings.shared.polishEnabled);
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
    [_session finish];
    [_hotkeys disable];
}

// ---------- URL: zemzeme://toggle | start | stop ----------

- (void)handleURLEvent:(NSAppleEventDescriptor *)event withReply:(NSAppleEventDescriptor *)reply {
    NSString *url = [event paramDescriptorForKeyword:keyDirectObject].stringValue ?: @"";
    ZLog(@"app: url %@", url);
    if ([url isEqualToString:@"zemzeme://start"]) {
        if (!_session) [self startSession];
    } else if ([url isEqualToString:@"zemzeme://stop"]) {
        [_session finish];
    } else {
        [self toggleSession];
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
    id<ZEngine> engine = [ZSettings.shared.engineName isEqualToString:@"chrome"]
        ? (id<ZEngine>)[ZChromeRelayEngine new] : (id<ZEngine>)[ZGoogleEngine new];
    ZSession *s = [[ZSession alloc] initWithEngine:engine panel:_panel];
    _session = s;
    __weak typeof(self) ws = self;
    s.onFinish = ^{
        __strong typeof(ws) me = ws;
        if (!me) return;
        me->_session = nil;
        me->_hotkeys.sessionActive = NO;
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
    _statusItem.button.image = [NSImage imageWithSystemSymbolName:@"waveform"
                                         accessibilityDescription:@"زمزمه"];
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
        NSMenuItem *ins = [self item:menu title:@"درج همینجا" action:@selector(menuInsertHere) key:@"v"];
        [self icon:ins symbol:@"text.insert"];
        ins.toolTip = @"درج در اپی که پشت پنل باز است";
    }
    [menu addItem:NSMenuItem.separatorItem];

    // حالت: دو رادیو + یک تاگل، بدون ردیف تیتر
    [self icon:[self item:menu title:@"درج زنده" action:@selector(menuModeLive) key:@""]
        symbol:@"cursorarrow.motionlines"].state =
        !ZSettings.shared.collectMode ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenuItem *cm = [self icon:[self item:menu title:@"جمع در پنل" action:@selector(menuModeCollect) key:@""]
                          symbol:@"rectangle.and.pencil.and.ellipsis"];
    cm.state = ZSettings.shared.collectMode ? NSControlStateValueOn : NSControlStateValueOff;
    cm.toolTip = @"متن در خود پنل جمع می‌شود و قابل ویرایش است؛ تهش با یک دکمه درج یا کپی می‌شود";
    NSMenuItem *pol = [self icon:[self item:menu title:@"ویرایش فارسی" action:@selector(menuTogglePolish) key:@""]
                           symbol:@"wand.and.stars"];
    pol.state = ZSettings.shared.polishEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    pol.toolTip = @"نیم‌فاصله، ارقام فارسی، نقطه‌گذاری و املای مطمئن روی هر تکه قطعی فارسی";
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
        mi.toolTip = @"برای Windows App همیشه پیست انتخاب می‌شود، حتی اگر اینجا تایپ باشد";
    }
    [adv addItem:NSMenuItem.separatorItem];

    NSMenuItem *hk = [self icon:[self item:adv title:@"هاتکی داخلی (آزمایشی)" action:@selector(menuToggleHotkey) key:@""]
                          symbol:@"command"];
    hk.state = ZSettings.shared.internalHotkey ? NSControlStateValueOn : NSControlStateValueOff;
    hk.toolTip = @"اول رول Karabiner را خاموش کن، وگرنه دابل‌تپ به اپ نمی‌رسد";
    [adv addItem:NSMenuItem.separatorItem];

    [self icon:[self item:adv title:@"پوشه سشن‌ها" action:@selector(menuOpenSessions) key:@""] symbol:@"folder"];
    [self icon:[self item:adv title:@"دسترسی‌ها" action:@selector(menuOpenAccessibility) key:@""] symbol:@"lock.shield"];
    advItem.submenu = adv;
    [menu addItem:advItem];

    [menu addItem:NSMenuItem.separatorItem];
    [self icon:[self item:menu title:@"خروج از زمزمه" action:@selector(menuQuit) key:@"q"] symbol:@"power"];
}

// شورتکات‌های نمایشی ⌥ فقط راهنما هستند؛ کار واقعی را تپ سراسری سشن می‌کند
- (NSMenuItem *)item:(NSMenu *)m title:(NSString *)t action:(SEL)a key:(NSString *)k {
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:t action:a keyEquivalent:k];
    i.target = self;
    if (k.length && ![k isEqualToString:@"q"]) i.keyEquivalentModifierMask = NSEventModifierFlagOption;
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
- (void)menuModeLive { ZSettings.shared.collectMode = NO; }
- (void)menuModeCollect { ZSettings.shared.collectMode = YES; }
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
- (void)menuTogglePolish {
    ZSettings.shared.polishEnabled = !ZSettings.shared.polishEnabled;
    if (ZSettings.shared.polishEnabled) [ZPolish.shared prepare];
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
        NSApplication *app = NSApplication.sharedApplication;
        static ZAppDelegate *delegate;
        delegate = [ZAppDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
