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
    ZEscTap *_escTap;
    ZRCmdTap *_rcmdTap;
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
    _escTap = [ZEscTap new];
    _rcmdTap = [ZRCmdTap new];
    [self setupStatusItem];
    __weak typeof(self) ws = self;
    _rcmdTap.onDoubleTap = ^{ [ws toggleSession]; };
    if (ZSettings.shared.internalHotkey) [_rcmdTap enable];

    // حالت اسکرین‌شات طراحی: zemzeme --uishot <dir>
    NSArray *args = NSProcessInfo.processInfo.arguments;
    NSUInteger i = [args indexOfObject:@"--uishot"];
    if (i != NSNotFound && i + 1 < args.count) {
        [_panel makeShots:args[i + 1]];
        [NSApp terminate:nil];
        return;
    }

    if (![ZInjector accessibilityOK]) [ZInjector promptAccessibility];
    ZLog(@"app: launched root=%@ ax=%d", ZRoot().path, [ZInjector accessibilityOK]);
}

- (void)applicationWillTerminate:(NSNotification *)n {
    [_session finish];
    [_escTap disable];
    [_rcmdTap disable];
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
        [me->_escTap disable];
    };
    _escTap.onEsc = ^{
        __strong typeof(ws) me = ws;
        [me->_session finish];
    };
    [_escTap enable];
    [s start];
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

    [self item:menu title:active ? @"پایان دیکته" : @"شروع دیکته" action:@selector(menuToggle) key:@""];
    [menu addItem:NSMenuItem.separatorItem];

    [self header:menu title:@"زبان"];
    [self item:menu title:@"فارسی" action:@selector(menuLangFa) key:@""].state =
        [ZSettings.shared.lang isEqualToString:@"fa-IR"] ? NSControlStateValueOn : NSControlStateValueOff;
    [self item:menu title:@"English" action:@selector(menuLangEn) key:@""].state =
        [ZSettings.shared.lang isEqualToString:@"en-US"] ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:NSMenuItem.separatorItem];

    [self header:menu title:@"موتور"];
    NSMenuItem *g = [self item:menu title:@"گوگل مستقیم" action:@selector(menuEngineGoogle) key:@""];
    g.state = [ZSettings.shared.engineName isEqualToString:@"google"]
        ? NSControlStateValueOn : NSControlStateValueOff;
    g.enabled = !active;
    NSMenuItem *c = [self item:menu title:@"صفحه کروم (فال‌بک)" action:@selector(menuEngineChrome) key:@""];
    c.state = [ZSettings.shared.engineName isEqualToString:@"chrome"]
        ? NSControlStateValueOn : NSControlStateValueOff;
    c.enabled = !active;
    [self item:menu title:@"باز کردن صفحه موتور کروم" action:@selector(menuOpenChromePage) key:@""];
    [menu addItem:NSMenuItem.separatorItem];

    [self header:menu title:@"درج متن"];
    NSArray *modes = @[@[@"تایپ مستقیم", @(ZInsertType)],
                       @[@"پیست تکه‌ای", @(ZInsertPaste)],
                       @[@"فقط جمع کن", @(ZInsertCollect)]];
    for (NSArray *m in modes) {
        NSMenuItem *mi = [self item:menu title:m[0] action:@selector(menuInsertMode:) key:@""];
        mi.representedObject = m[1];
        mi.state = ZSettings.shared.insertMode == [m[1] integerValue]
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *hk = [self item:menu title:@"هاتکی داخلی بدون Karabiner (آزمایشی)"
                         action:@selector(menuToggleHotkey) key:@""];
    hk.state = ZSettings.shared.internalHotkey ? NSControlStateValueOn : NSControlStateValueOff;
    hk.toolTip = @"اول رول Karabiner را خاموش کن، وگرنه دابل‌تپ به اپ نمی‌رسد";
    [self item:menu title:@"پوشه سشن‌ها" action:@selector(menuOpenSessions) key:@""];
    [self item:menu title:@"دسترسی‌ها در تنظیمات سیستم" action:@selector(menuOpenAccessibility) key:@""];
    [menu addItem:NSMenuItem.separatorItem];
    [self item:menu title:@"خروج از زمزمه" action:@selector(menuQuit) key:@"q"];
}

- (NSMenuItem *)item:(NSMenu *)m title:(NSString *)t action:(SEL)a key:(NSString *)k {
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:t action:a keyEquivalent:k];
    i.target = self;
    [m addItem:i];
    return i;
}

- (void)header:(NSMenu *)m title:(NSString *)t {
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:t action:nil keyEquivalent:@""];
    i.enabled = NO;
    [m addItem:i];
}

- (void)menuToggle { [self toggleSession]; }
- (void)menuLangFa { [self setLang:@"fa-IR"]; }
- (void)menuLangEn { [self setLang:@"en-US"]; }
- (void)setLang:(NSString *)l {
    ZSettings.shared.lang = l;
    [_session.engine setLang:l];
}
- (void)menuEngineGoogle { ZSettings.shared.engineName = @"google"; }
- (void)menuEngineChrome { ZSettings.shared.engineName = @"chrome"; }
- (void)menuOpenChromePage { [ZChromeRelayEngine openPage]; }
- (void)menuInsertMode:(NSMenuItem *)sender {
    ZSettings.shared.insertMode = [sender.representedObject integerValue];
}
- (void)menuToggleHotkey {
    ZSettings.shared.internalHotkey = !ZSettings.shared.internalHotkey;
    if (ZSettings.shared.internalHotkey) [_rcmdTap enable];
    else [_rcmdTap disable];
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
