// نوار شناور (پنل) و سشن تسمه‌نقاله.
#import "zemzeme.h"

// ---------- ZPanelModel ----------

@implementation ZPanelModel
- (instancetype)init {
    if ((self = [super init])) {
        _interim = @"";
        _status = @"";
        _lang = @"fa-IR";
        _targetName = @"";
    }
    return self;
}
@end

// ---------- ZPanel ----------
// نوار باریک بدون گرفتن فوکس، روی همه Space ها و فول‌اسکرین.
// فقط بافر خاکستری و وضعیت را نشان می‌دهد؛ متن قطعی در خود اپ مقصد می‌نشیند.

static const CGFloat kPW = 500, kPH = 46;

@implementation ZPanel {
    NSPanel *_panel;
    NSVisualEffectView *_effect;
    NSView *_dot;
    NSTextField *_text;
    NSView *_chipBg;
    NSTextField *_chipLabel;
    NSButton *_btnClose, *_btnLang, *_btnTarget, *_btnLock;
    BOOL _pulsing;
}

- (instancetype)init {
    if ((self = [super init])) {
        _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, kPW, kPH)
                                            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                              backing:NSBackingStoreBuffered defer:NO];
        _panel.level = NSStatusWindowLevel;
        _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                                  | NSWindowCollectionBehaviorFullScreenAuxiliary
                                  | NSWindowCollectionBehaviorIgnoresCycle;
        _panel.floatingPanel = YES;
        _panel.hidesOnDeactivate = NO;
        _panel.opaque = NO;
        _panel.backgroundColor = NSColor.clearColor;
        _panel.hasShadow = YES;
        _panel.movableByWindowBackground = YES;
        _panel.becomesKeyOnlyIfNeeded = YES;
        _panel.releasedWhenClosed = NO;

        _effect = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, kPW, kPH)];
        _effect.material = NSVisualEffectMaterialHUDWindow;
        _effect.state = NSVisualEffectStateActive;
        _effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        _effect.wantsLayer = YES;
        _effect.layer.cornerRadius = 15;
        _effect.layer.masksToBounds = YES;
        _effect.layer.borderWidth = 0.5;
        _panel.contentView = _effect;

        _dot = [[NSView alloc] initWithFrame:NSMakeRect(kPW - 25, (kPH - 9) / 2, 9, 9)];
        _dot.wantsLayer = YES;
        _dot.layer.cornerRadius = 4.5;
        [_effect addSubview:_dot];

        _text = [NSTextField labelWithString:@""];
        _text.font = ZFont(15, NO);
        _text.textColor = NSColor.secondaryLabelColor;
        _text.alignment = NSTextAlignmentRight;
        _text.lineBreakMode = NSLineBreakByTruncatingHead;
        _text.usesSingleLineMode = YES;
        [_effect addSubview:_text];

        _chipBg = [NSView new];
        _chipBg.wantsLayer = YES;
        _chipBg.layer.cornerRadius = 9;
        _chipBg.hidden = YES;
        [_effect addSubview:_chipBg];
        _chipLabel = [NSTextField labelWithString:@""];
        _chipLabel.font = ZFont(11, NO);
        _chipLabel.textColor = NSColor.secondaryLabelColor;
        _chipLabel.alignment = NSTextAlignmentCenter;
        [_chipBg addSubview:_chipLabel];

        _btnClose = [self makeButton:@"xmark" tip:@"بستن و درج همه (Esc)" action:@selector(closeTap)];
        _btnLang = [NSButton buttonWithTitle:@"فا" target:self action:@selector(langTap)];
        _btnLang.bordered = NO;
        _btnLang.font = ZFont(11, YES);
        _btnLang.contentTintColor = NSColor.secondaryLabelColor;
        _btnLang.toolTip = @"تغییر زبان";
        [_effect addSubview:_btnLang];
        _btnTarget = [self makeButton:@"scope" tip:@"مقصد همینجا: درج در همین اپ جلویی" action:@selector(targetTap)];
        _btnLock = [self makeButton:@"lock.open" tip:@"قفل: درج نکن، فقط جمع کن" action:@selector(lockTap)];

        [self layoutViews];
        [self applyColors];
    }
    return self;
}

- (NSButton *)makeButton:(NSString *)symbol tip:(NSString *)tip action:(SEL)action {
    NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip];
    img = [img imageWithSymbolConfiguration:
           [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightMedium]];
    NSButton *b = [NSButton buttonWithImage:img ?: [NSImage new] target:self action:action];
    b.bordered = NO;
    b.buttonType = NSButtonTypeMomentaryChange;
    b.contentTintColor = NSColor.secondaryLabelColor;
    b.toolTip = tip;
    [_effect addSubview:b];
    return b;
}

// چیدمان راست‌به‌چپ با فریم دستی: نقطه سمت راست، دکمه‌ها سمت چپ
- (void)layoutViews {
    CGFloat cy = (kPH - 24) / 2;
    _btnClose.frame = NSMakeRect(10, cy, 24, 24);
    _btnLang.frame = NSMakeRect(38, cy, 26, 24);
    _btnTarget.frame = NSMakeRect(66, cy, 24, 24);
    _btnLock.frame = NSMakeRect(94, cy, 24, 24);

    CGFloat chipW = _chipBg.hidden ? 0 : _chipBg.frame.size.width;
    CGFloat left = 124 + chipW + (_chipBg.hidden ? 0 : 8);
    CGFloat right = kPW - 25 - 12;
    _text.frame = NSMakeRect(left, (kPH - 22) / 2, MAX(40, right - left), 22);
    if (!_chipBg.hidden) {
        NSRect f = _chipBg.frame;
        f.origin = NSMakePoint(124, (kPH - 18) / 2);
        _chipBg.frame = f;
    }
}

- (void)applyColors {
    _effect.layer.borderColor = [NSColor.labelColor colorWithAlphaComponent:0.12].CGColor;
    _chipBg.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.08].CGColor;
}

- (void)show {
    [self applyColors];
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:@"panelOrigin"];
    if (saved) {
        NSArray *parts = [saved componentsSeparatedByString:@","];
        if (parts.count == 2) {
            NSPoint p = NSMakePoint([parts[0] doubleValue], [parts[1] doubleValue]);
            for (NSScreen *sc in NSScreen.screens) {
                if (NSPointInRect(p, sc.frame)) {
                    [_panel setFrameOrigin:p];
                    [_panel orderFrontRegardless];
                    return;
                }
            }
        }
    }
    NSPoint mouse = NSEvent.mouseLocation;
    NSScreen *screen = NSScreen.mainScreen;
    for (NSScreen *sc in NSScreen.screens) {
        if (NSMouseInRect(mouse, sc.frame, NO)) { screen = sc; break; }
    }
    NSRect f = screen ? screen.visibleFrame : NSMakeRect(0, 0, 1440, 900);
    [_panel setFrameOrigin:NSMakePoint(NSMidX(f) - kPW / 2, NSMinY(f) + 90)];
    [_panel orderFrontRegardless];
}

- (void)hide {
    NSPoint o = _panel.frame.origin;
    [NSUserDefaults.standardUserDefaults setObject:[NSString stringWithFormat:@"%.0f,%.0f", o.x, o.y]
                                            forKey:@"panelOrigin"];
    [self stopPulse];
    [_panel orderOut:nil];
}

- (void)render:(ZPanelModel *)m {
    // متن: خاکستری لحظه‌ای؛ وقتی نیست، خط وضعیت
    if (m.interim.length) {
        _text.stringValue = m.interim;
        _text.font = ZFont(15, NO);
        _text.textColor = NSColor.secondaryLabelColor;
    } else {
        _text.stringValue = m.status;
        _text.font = ZFont(12.5, NO);
        _text.textColor = m.error ? NSColor.systemRedColor : NSColor.tertiaryLabelColor;
    }
    _text.alignment = ([m.lang isEqualToString:@"en-US"] && m.interim.length)
        ? NSTextAlignmentLeft : NSTextAlignmentRight;

    // چیپ صف/قفل
    NSString *chip = @"";
    if (m.locked) {
        chip = @"قفل";
    } else if (m.queued > 0) {
        chip = [ZFaDigits([NSString stringWithFormat:@"%ld", (long)m.queued]) stringByAppendingString:@" در صف"];
    }
    _chipBg.toolTip = (m.waitingForTarget && m.targetName.length)
        ? [NSString stringWithFormat:@"برگرد به %@ تا درج ادامه پیدا کند", m.targetName] : nil;
    if (!chip.length) {
        _chipBg.hidden = YES;
    } else {
        _chipBg.hidden = NO;
        _chipLabel.stringValue = chip;
        [_chipLabel sizeToFit];
        CGFloat w = _chipLabel.frame.size.width + 16;
        _chipBg.frame = NSMakeRect(124, (kPH - 18) / 2, w, 18);
        _chipLabel.frame = NSMakeRect(8, 0, w - 16, 17);
    }

    // دکمه‌ها
    _btnLang.title = [m.lang isEqualToString:@"fa-IR"] ? @"فا" : @"EN";
    NSImage *lockImg = [NSImage imageWithSystemSymbolName:m.locked ? @"lock.fill" : @"lock.open"
                                accessibilityDescription:@"قفل"];
    lockImg = [lockImg imageWithSymbolConfiguration:
               [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightMedium]];
    _btnLock.image = lockImg;
    _btnLock.contentTintColor = m.locked ? NSColor.controlAccentColor : NSColor.secondaryLabelColor;

    // نقطه
    NSColor *color = m.error ? NSColor.systemGrayColor
        : (m.listening ? [NSColor colorWithRed:0.88 green:0.19 blue:0.19 alpha:1] : NSColor.systemOrangeColor);
    _dot.layer.backgroundColor = color.CGColor;
    if (m.listening && !_pulsing) [self startPulse];
    if (!m.listening && _pulsing) [self stopPulse];

    [self layoutViews];
}

- (void)pulseLevel:(float)level {
    CGFloat s = 1 + MIN(MAX(level, 0.0f), 1.0f) * 0.5;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _dot.layer.affineTransform = CGAffineTransformMakeScale(s, s);
    [CATransaction commit];
}

- (void)startPulse {
    _pulsing = YES;
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
    a.fromValue = @1.0;
    a.toValue = @0.35;
    a.duration = 0.6;
    a.autoreverses = YES;
    a.repeatCount = HUGE_VALF;
    [_dot.layer addAnimation:a forKey:@"pulse"];
}

- (void)stopPulse {
    _pulsing = NO;
    [_dot.layer removeAnimationForKey:@"pulse"];
    _dot.layer.opacity = 1;
}

- (void)closeTap { if (self.onClose) self.onClose(); }
- (void)lockTap { if (self.onToggleLock) self.onToggleLock(); }
- (void)targetTap { if (self.onRetarget) self.onRetarget(); }
- (void)langTap { if (self.onToggleLang) self.onToggleLang(); }

// اسکرین‌شات برای بازبینی طراحی (بدون نیاز به اجازه ضبط صفحه)
- (void)makeShots:(NSString *)dir {
    ZPanelModel *listening = [ZPanelModel new];
    listening.interim = @"دارم متن نمونه را برای نوار زمزمه می‌گویم که ببینیم";
    listening.listening = YES;

    ZPanelModel *status = [ZPanelModel new];
    status.status = @"دارم گوش می‌دم";
    status.listening = YES;

    ZPanelModel *queued = [ZPanelModel new];
    queued.interim = @"این تکه هنوز خاکستری است";
    queued.listening = YES;
    queued.queued = 3;
    queued.waitingForTarget = YES;
    queued.targetName = @"Windows App";

    ZPanelModel *locked = [ZPanelModel new];
    locked.status = @"دارم گوش می‌دم";
    locked.listening = YES;
    locked.locked = YES;

    ZPanelModel *error = [ZPanelModel new];
    error.status = @"شبکه ناپایداره؛ برای تلاش دوباره دابل‌تپ کن";
    error.error = YES;

    NSDictionary *states = @{@"listening": listening, @"status": status, @"queued": queued,
                             @"locked": locked, @"error": error};
    [_panel orderFrontRegardless];
    for (NSString *name in states) {
        [self render:states[name]];
        [_effect layoutSubtreeIfNeeded];
        NSBitmapImageRep *rep = [_effect bitmapImageRepForCachingDisplayInRect:_effect.bounds];
        if (!rep) continue;
        [_effect cacheDisplayInRect:_effect.bounds toBitmapImageRep:rep];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:[dir stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"panel-%@.png", name]] atomically:YES];
    }
    [_panel orderOut:nil];
}

@end

// ---------- ZSession ----------
// مدل تسمه‌نقاله: پنل فقط بافر خاکستری است؛ هر تکه قطعی همان لحظه سر کرسرِ
// اپ مقصد درج می‌شود. اگر اپ جلویی عوض شود درج می‌ایستد و صف جمع می‌شود.

@implementation ZSession {
    ZPanel *_panel;
    ZInjector *_injector;
    NSRunningApplication *_target;
    NSMutableArray<NSString *> *_queue;       // تکه‌های قطعیِ هنوز درج‌نشده
    NSMutableArray<NSString *> *_transcript;  // همه قطعی‌ها برای کپی پایانی
    NSString *_interim;
    NSString *_statusText;
    BOOL _errorState;
    BOOL _listening;
    BOOL _locked;
    NSMutableArray<NSString *> *_pasteBuf;
    NSTimer *_pasteTimer;
    NSURL *_sessionFile;
    BOOL _finished;
    id _frontObserver;
}

- (instancetype)initWithEngine:(id<ZEngine>)engine panel:(ZPanel *)panel {
    if ((self = [super init])) {
        _engine = engine;
        _panel = panel;
        _injector = [ZInjector new];
        _queue = [NSMutableArray array];
        _transcript = [NSMutableArray array];
        _pasteBuf = [NSMutableArray array];
        _interim = @"";
        _statusText = @"";
        _sessionFile = [ZSessionsDir() URLByAppendingPathComponent:
                        [NSString stringWithFormat:@"app-%@.txt", ZTimestampId()]];
    }
    return self;
}

- (void)start {
    _target = NSWorkspace.sharedWorkspace.frontmostApplication;
    ZLog(@"session: start target=%@ engine=%@ lang=%@",
         _target.bundleIdentifier ?: @"?", ZSettings.shared.engineName, ZSettings.shared.lang);
    __weak typeof(self) ws = self;
    _frontObserver = [NSWorkspace.sharedWorkspace.notificationCenter
        addObserverForName:NSWorkspaceDidActivateApplicationNotification object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *n) {
        [ws pump];
        [ws render];
    }];
    _panel.onClose = ^{ [ws finish]; };
    _panel.onToggleLock = ^{
        __strong typeof(ws) s = ws;
        if (!s) return;
        s->_locked = !s->_locked;
        [s pump];
        [s render];
    };
    _panel.onRetarget = ^{ [ws retarget]; };
    _panel.onToggleLang = ^{ [ws toggleLang]; };
    [_panel show];
    if (![ZInjector accessibilityOK]) {
        _statusText = @"دسترسی Accessibility نیست؛ درج کار نمی‌کند، متن آخر کار کپی می‌شود";
    }
    self.engine.delegate = self;
    [self.engine startWithLang:ZSettings.shared.lang];
    [self render];
}

// ---------- ZEngineDelegate (روی نخ اصلی) ----------

- (void)engineInterim:(NSString *)text {
    _interim = [text copy];
    [self render];
}

- (void)engineFinal:(NSString *)text {
    [_transcript addObject:text];
    [self appendToSessionFile:text];
    [_queue addObject:text];
    [self pump];
    [self render];
}

- (void)engineState:(ZEngineState)state message:(NSString *)msg {
    _errorState = NO;
    _listening = NO;
    switch (state) {
        case ZEngineIdle: _statusText = @""; break;
        case ZEngineConnecting: _statusText = @"در حال اتصال…"; break;
        case ZEngineListening:
            _listening = YES;
            _statusText = @"دارم گوش می‌دم";
            break;
        case ZEngineReconnecting: _statusText = @"اتصال ناپایدار، دوباره وصل می‌شم…"; break;
        case ZEngineGaveUp:
            _errorState = YES;
            _statusText = msg.length ? msg : @"خطای موتور";
            break;
        case ZEnginePageNeeded:
            _errorState = YES;
            _statusText = @"صفحه کروم باز نیست؛ از منوی زمزمه بازش کن";
            break;
    }
    [self render];
}

- (void)engineLevel:(float)rms {
    [_panel pulseLevel:rms];
}

// ---------- تسمه‌نقاله ----------

- (BOOL)targetIsFront {
    NSRunningApplication *f = NSWorkspace.sharedWorkspace.frontmostApplication;
    return _target && f && _target.processIdentifier == f.processIdentifier;
}

- (void)pump {
    if (!_queue.count) return;
    ZInsertMode mode = [ZSettings.shared insertModeForBundleId:_target.bundleIdentifier];
    if (mode == ZInsertCollect || _locked) return;
    if (![ZInjector accessibilityOK] || ![self targetIsFront] || [ZInjector secureInputActive]) return;
    NSString *chunk = [[_queue componentsJoinedByString:@" "] stringByAppendingString:@" "];
    [_queue removeAllObjects];
    if (mode == ZInsertType) {
        [_injector type:chunk delayMicros:ZSettings.shared.typeDelayMicros];
    } else {
        // ادغام تکه‌ها با تایمر کوتاه: پیست‌های کمتر، برای RDP امن‌تر
        [_pasteBuf addObject:chunk];
        [_pasteTimer invalidate];
        __weak typeof(self) ws = self;
        _pasteTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:NO block:^(NSTimer *t) {
            [ws flushPasteBuf];
        }];
    }
}

- (void)flushPasteBuf {
    [_pasteTimer invalidate];
    _pasteTimer = nil;
    if (!_pasteBuf.count) return;
    NSString *text = [_pasteBuf componentsJoinedByString:@""];
    [_pasteBuf removeAllObjects];
    [_injector paste:text delayMicros:ZSettings.shared.pasteDelayMicros];
}

- (void)retarget {
    // مقصد جدید: همین اپ جلویی؛ صف همین‌جا خالی می‌شود
    _target = NSWorkspace.sharedWorkspace.frontmostApplication;
    ZLog(@"session: retarget to %@", _target.bundleIdentifier ?: @"?");
    [self pump];
    [self render];
}

- (void)toggleLang {
    NSString *newLang = [ZSettings.shared.lang isEqualToString:@"fa-IR"] ? @"en-US" : @"fa-IR";
    ZSettings.shared.lang = newLang;
    [self.engine setLang:newLang];
    [self render];
}

// ---------- پایان (Esc یا دابل‌تپ دوباره) ----------

- (void)finish {
    if (_finished) return;
    _finished = YES;
    [self.engine stop];    // موتور قبل از بستن salvage می‌کند و finalها همین‌جا می‌رسند
    [self flushPasteBuf];
    // باقی صف: اگر مقصد جلوست درج کن، وگرنه فقط کپی نجاتش می‌دهد
    if (_queue.count && [ZInjector accessibilityOK] && [self targetIsFront]
        && ![ZInjector secureInputActive] && !_locked) {
        ZInsertMode mode = [ZSettings.shared insertModeForBundleId:_target.bundleIdentifier];
        NSString *chunk = [[_queue componentsJoinedByString:@" "] stringByAppendingString:@" "];
        if (mode == ZInsertType) {
            [_injector type:chunk delayMicros:ZSettings.shared.typeDelayMicros];
            [_queue removeAllObjects];
        } else if (mode == ZInsertPaste) {
            [_injector paste:chunk delayMicros:ZSettings.shared.pasteDelayMicros];
            [_queue removeAllObjects];
        }
    }
    // بیمه: کل متن سشن، یک بار، ماندگار در کلیپ‌بورد.
    // نقطه اتصال «پاس اصلاح متن» آینده همین‌جاست: متن می‌رود تو، اصلاح‌شده می‌آید بیرون.
    NSString *full = [[_transcript componentsJoinedByString:@" "]
                      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (full.length) [ZInjector copyFinal:full];
    if (_frontObserver) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:_frontObserver];
    _frontObserver = nil;
    [_panel hide];
    ZLog(@"session: finished, %lu chunks, %lu chars copied",
         (unsigned long)_transcript.count, (unsigned long)full.length);
    if (self.onFinish) self.onFinish();
}

// ---------- کمکی ----------

- (void)appendToSessionFile:(NSString *)chunk {
    NSData *d = [[chunk stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:_sessionFile.path];
    if (!h) {
        [NSFileManager.defaultManager createFileAtPath:_sessionFile.path contents:d attributes:nil];
        return;
    }
    @try {
        [h seekToEndOfFile];
        [h writeData:d];
    } @catch (NSException *e) {}
    [h closeFile];
}

- (void)render {
    ZPanelModel *m = [ZPanelModel new];
    m.interim = _interim;
    m.status = _statusText;
    m.queued = (NSInteger)(_queue.count + _pasteBuf.count);
    m.locked = _locked;
    m.listening = _listening;
    m.error = _errorState;
    m.lang = ZSettings.shared.lang;
    m.waitingForTarget = _queue.count > 0 && ![self targetIsFront];
    m.targetName = _target.localizedName ?: @"";
    [_panel render:m];
}

@end
