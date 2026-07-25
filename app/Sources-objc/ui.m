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
// نوار باریک بدون گرفتن فوکس، روی همه Space ها و فول‌اسکرین. سه دکمه بیشتر ندارد:
// بستن، مکث/ادامه، کپی. متن خاکستری تا سه خط می‌پیچد و پنل قدش را خودش تنظیم می‌کند.
// در حالت «جمع در پنل» یک ادیتور واقعی باز می‌شود: متن قطعی همان‌جا می‌نشیند،
// قابل ویرایش با کیبورد خود کاربر، و تهش با یک دکمه در اپ مقصد درج می‌شود.

static const CGFloat kPW = 500;
static const CGFloat kBarH = 46;      // ارتفاع ردیف پایه (دکمه‌ها + نقطه)
static const CGFloat kEditorH = 150;  // ارتفاع ادیتور حالت جمع

// پس‌زمینهٔ پنل: NSVisualEffectView به‌خودی‌خود opaque حساب می‌شود و
// mouseDownCanMoveWindow پیش‌فرض NO برمی‌گرداند، پس movableByWindowBackground پنل
// روی هیچ پیکسلی اثر نداشت. اینجا صریحا اجازهٔ کشیدن از پس‌زمینه داده می‌شود؛
// دکمه‌ها/برچسب/ادیتور چون خودشان mouseDown را می‌گیرند دست‌نخورده می‌مانند.
@interface ZDragEffectView : NSVisualEffectView
@end

@implementation ZDragEffectView
- (BOOL)mouseDownCanMoveWindow { return YES; }
- (void)mouseDown:(NSEvent *)event { [self.window performWindowDragWithEvent:event]; }
@end

@implementation ZPanel {
    NSPanel *_panel;
    ZDragEffectView *_effect;
    NSView *_dot;
    NSImageView *_grip;
    NSTextField *_text;
    NSView *_chipBg;
    NSTextField *_chipLabel;
    NSButton *_btnClose, *_btnPause, *_btnCopy, *_btnTrash, *_btnInsert;
    NSScrollView *_editorScroll;
    NSTextView *_editor;
    NSTimer *_saveOriginTimer;
    BOOL _pulsing;
    BOOL _collectVisible;
    NSPoint _wantOrigin;         // جای انتخابی کاربر؛ قد کشیدن پنل جابه‌جایش نمی‌کند
    BOOL _haveWantOrigin;
    BOOL _resizing;
}

- (instancetype)init {
    if ((self = [super init])) {
        _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, kPW, kBarH)
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
        _panel.alphaValue = 0.92;   // کمی شیشه‌ای؛ فقط ۸٪ کم‌رنگ‌تر، خوانایی متن عملا دست‌نخورده
        _panel.becomesKeyOnlyIfNeeded = YES;
        _panel.releasedWhenClosed = NO;

        _effect = [[ZDragEffectView alloc] initWithFrame:NSMakeRect(0, 0, kPW, kBarH)];
        _effect.material = NSVisualEffectMaterialHUDWindow;
        _effect.state = NSVisualEffectStateActive;
        _effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        _effect.wantsLayer = YES;
        _effect.layer.cornerRadius = 15;
        _effect.layer.masksToBounds = YES;
        _effect.layer.borderWidth = 0.5;
        _panel.contentView = _effect;

        _dot = [[NSView alloc] initWithFrame:NSMakeRect(kPW - 25, (kBarH - 9) / 2, 9, 9)];
        _dot.wantsLayer = YES;
        _dot.layer.cornerRadius = 4.5;
        [_effect addSubview:_dot];

        // دستگیرهٔ کشیدن: فقط راهنمای دیداری (کل پس‌زمینه از قبل قابل کشیدن است)، کنار نقطه
        NSImage *gripImg = [NSImage imageWithSystemSymbolName:@"line.3.horizontal"
                                      accessibilityDescription:@"دستگیرهٔ جابه‌جایی پنل"];
        gripImg = [gripImg imageWithSymbolConfiguration:
                   [NSImageSymbolConfiguration configurationWithPointSize:9 weight:NSFontWeightRegular]];
        _grip = [NSImageView imageViewWithImage:gripImg ?: [NSImage new]];
        _grip.contentTintColor = NSColor.secondaryLabelColor;
        _grip.toolTip = @"بکش تا جابه‌جا شود";
        _grip.frame = NSMakeRect(kPW - 25 - 8 - 16, (kBarH - 9) / 2, 16, 9);
        [_effect addSubview:_grip];

        _text = [NSTextField labelWithString:@""];
        _text.font = ZFont(15, NO);
        _text.textColor = NSColor.secondaryLabelColor;
        _text.alignment = NSTextAlignmentRight;
        _text.lineBreakMode = NSLineBreakByTruncatingHead;
        _text.usesSingleLineMode = NO;
        _text.cell.wraps = YES;
        _text.maximumNumberOfLines = 3;    // خط وضعیت؛ سر متن خاکستری با سقف پنل تازه می‌شود
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
        _btnPause = [self makeButton:@"pause.fill" tip:@"مکث و ادامه شنیدن (⌥Space)" action:@selector(pauseTap)];
        _btnCopy = [self makeButton:@"doc.on.doc" tip:@"کپی متن تا اینجا (⌥C)" action:@selector(copyTap)];
        _btnTrash = [self makeButton:@"trash"
                                 tip:@"دور ریختن هرچه گفته‌ای و هنوز درج نشده؛ شنیدن ادامه دارد"
                              action:@selector(trashTap)];

        _btnInsert = [NSButton buttonWithTitle:@"درج در همین اپ" target:self action:@selector(insertTap)];
        _btnInsert.bezelStyle = NSBezelStyleRounded;
        _btnInsert.controlSize = NSControlSizeSmall;
        _btnInsert.font = ZFont(12, YES);
        _btnInsert.toolTip = @"کل متن پنل سر کرسر همین اپ تایپ می‌شود (⌥V)";
        _btnInsert.hidden = YES;
        [_effect addSubview:_btnInsert];

        [self layoutViews];
        [self applyColors];
        // موقعیت پنل با کمی تاخیر (debounce) هر بار جابه‌جا شد ذخیره می‌شود، نه فقط موقع hide
        __weak typeof(self) ws = self;
        [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidMoveNotification object:_panel
                                                          queue:nil usingBlock:^(NSNotification *n) {
            [ws panelMoved];
        }];
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

- (void)setButton:(NSButton *)b symbol:(NSString *)symbol {
    NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:b.toolTip];
    b.image = [img imageWithSymbolConfiguration:
               [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightMedium]];
}

// چیدمان راست‌به‌چپ با فریم دستی: نقطه پایین راست، دکمه‌ها پایین چپ، متن وسط.
// ادیتور (اگر باز باشد) بالای ردیف پایه می‌نشیند.
- (void)layoutViews {
    CGFloat H = _panel.frame.size.height;
    CGFloat cy = (kBarH - 24) / 2;
    _btnClose.frame = NSMakeRect(10, cy, 24, 24);
    _btnPause.frame = NSMakeRect(38, cy, 24, 24);
    _btnCopy.frame = NSMakeRect(66, cy, 24, 24);
    _btnTrash.frame = NSMakeRect(94, cy, 24, 24);
    CGFloat left = 126;
    if (!_btnInsert.hidden) {
        [_btnInsert sizeToFit];
        _btnInsert.frame = NSMakeRect(left, (kBarH - _btnInsert.frame.size.height) / 2,
                                      _btnInsert.frame.size.width, _btnInsert.frame.size.height);
        left += _btnInsert.frame.size.width + 8;
    }
    CGFloat chipW = _chipBg.hidden ? 0 : _chipBg.frame.size.width;
    if (!_chipBg.hidden) {
        NSRect f = _chipBg.frame;
        f.origin = NSMakePoint(left, (kBarH - 18) / 2);
        _chipBg.frame = f;
        left += chipW + 8;
    }
    CGFloat right = _grip.frame.origin.x - 8;   // قبل از دستگیره تمام شود، نه زیر نقطه
    // در تسمه‌نقاله، فریم متن با قد پنل بالا می‌رود که تا سه خط جا شود
    CGFloat textH = (_collectVisible ? kBarH : H) - 22;
    _text.frame = NSMakeRect(left, 11, MAX(40, right - left), textH);
    if (_collectVisible) {
        _editorScroll.frame = NSMakeRect(12, kBarH, kPW - 24, H - kBarH - 10);
    }
}

- (void)applyColors {
    _effect.layer.borderColor = [NSColor.labelColor colorWithAlphaComponent:0.12].CGColor;
    _chipBg.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.08].CGColor;
}

// ---------- ادیتور حالت جمع ----------

- (void)ensureEditor {
    if (_editorScroll) return;
    _editorScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, kBarH, kPW - 24, kEditorH - 10)];
    _editorScroll.hasVerticalScroller = YES;
    _editorScroll.drawsBackground = NO;
    _editorScroll.borderType = NSNoBorder;
    _editor = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, kPW - 24, kEditorH - 10)];
    _editor.font = ZFont(15, NO);
    _editor.textColor = NSColor.labelColor;
    _editor.drawsBackground = NO;
    _editor.richText = NO;
    _editor.baseWritingDirection = NSWritingDirectionRightToLeft;
    _editor.alignment = NSTextAlignmentRight;
    _editor.textContainerInset = NSMakeSize(4, 8);
    _editor.autoresizingMask = NSViewWidthSizable;
    _editor.verticallyResizable = YES;
    _editor.textContainer.widthTracksTextView = YES;
    _editorScroll.documentView = _editor;
    [_effect addSubview:_editorScroll];
}

- (void)setCollectVisible:(BOOL)on {
    if (on) [self ensureEditor];
    if (_collectVisible == on) return;
    _collectVisible = on;
    _editorScroll.hidden = !on;
    _btnInsert.hidden = !on;
    [self resizeTo:on ? kBarH + kEditorH : [self conveyorHeight]];
}

- (void)appendFinalToEditor:(NSString *)chunk {
    [self ensureEditor];
    NSString *cur = _editor.string;
    NSString *add = cur.length && ![cur hasSuffix:@" "] && ![cur hasSuffix:@"\n"]
        ? [@" " stringByAppendingString:chunk] : chunk;
    [_editor.textStorage replaceCharactersInRange:NSMakeRange(cur.length, 0) withString:add];
    _editor.font = ZFont(15, NO);
    _editor.textColor = NSColor.labelColor;
    [_editor scrollRangeToVisible:NSMakeRange(_editor.string.length, 0)];
}

- (NSString *)editorText {
    return _editor.string ?: @"";
}

- (void)clearEditor {
    [self ensureEditor];
    [_editor.textStorage replaceCharactersInRange:NSMakeRange(0, _editor.string.length) withString:@""];
}

// ---------- اندازه ----------

// آخرین تکه‌ای از متن که واقعا در سه خطِ موجود جا می‌شود.
// قبلا با یک عدد ثابت (۱۶۵ کاراکتر) بریده می‌شد، ولی پهنای همین لیبل ثابت نیست:
// دکمه «درج همینجا» و چیپ صف که بیایند، از ۳۴۵ پیکسل به ~۲۰۰ می‌رسد. آن‌وقت متن از
// سه خط می‌زد بیرون و AppKit ته متن را می‌انداخت، یعنی درست همان کلمه‌های تازه‌ای که
// کاربر می‌خواست ببیند. حالا اندازه می‌گیریم و از سرِ متن کم می‌کنیم تا جا شود.
- (NSString *)visibleTail:(NSString *)full {
    CGFloat w = [self textWidth];
    CGFloat cap = [self conveyorMaxTextHeight];
    if ([self heightOf:full width:w] <= cap) return full;
    // جستجوی دودویی روی مرز کلمه: بلندترین دمی که جا می‌شود
    NSArray<NSString *> *words = [full componentsSeparatedByString:@" "];
    NSUInteger lo = 0, hi = words.count;      // lo تعداد کلمه‌ای که از اول انداخته می‌شود
    while (lo < hi) {
        NSUInteger mid = (lo + hi) / 2;
        NSString *cand = [@"… " stringByAppendingString:
            [[words subarrayWithRange:NSMakeRange(mid, words.count - mid)] componentsJoinedByString:@" "]];
        if ([self heightOf:cand width:w] <= cap) hi = mid; else lo = mid + 1;
    }
    if (lo >= words.count) return words.lastObject ?: @"";
    return [@"… " stringByAppendingString:
        [[words subarrayWithRange:NSMakeRange(lo, words.count - lo)] componentsJoinedByString:@" "]];
}

// اندازه‌گیری با خودِ سلولِ همین لیبل، نه با boundingRect روی رشته‌ی خام.
// چرا: boundingRect کمتر از واقعیت می‌شمرد (استایل پاراگراف و شکستن خط سلول را ندارد)،
// پس متن «جا می‌شود» تشخیص داده می‌شد و بعد AppKit خط آخر را می‌انداخت. حالا معیارِ
// بریدن و معیارِ چیدن یکی است. maximumNumberOfLines موقع اندازه‌گیری برداشته می‌شود،
// وگرنه سلول قد را همان سقف خط گزارش می‌کرد و متنِ سرریز «جا شده» به نظر می‌رسید.
- (CGFloat)heightOf:(NSString *)s width:(CGFloat)w {
    NSTextFieldCell *cell = (NSTextFieldCell *)_text.cell;
    NSString *keep = cell.stringValue;
    NSInteger keepMax = _text.maximumNumberOfLines;
    _text.maximumNumberOfLines = 0;
    cell.stringValue = s;
    CGFloat h = [cell cellSizeForBounds:NSMakeRect(0, 0, w, 100000)].height;
    cell.stringValue = keep;
    _text.maximumNumberOfLines = keepMax;
    return h;
}

- (CGFloat)lineHeight { return [self heightOf:@"م" width:10000]; }

// سقف واقعی، همان قدی که فریم لیبل سر سه خط می‌گیرد. با هر عددی بزرگ‌تر از این،
// AppKit خط سوم را می‌انداخت و درست دم متن گم می‌شد؛ با کوچک‌تر، متن به دو خط قناعت
// می‌کرد. رشد هر خط پنل هم از همین قد خط می‌آید، نه از عدد ثابت ۲۱ که کمی کم بود.
- (CGFloat)conveyorLineStep { return ceil([self lineHeight]); }

// تا کجا قد بکشد. سه خط برای دیکته‌ی طولانی دیوار بود: متن از باکس می‌زد بیرون و
// دم حرف (تازه‌ترین کلمه‌ها) دیده نمی‌شد. حالا تا نصف بلندی صفحه بالا می‌رود، حداکثر
// ۱۲ خط. بیشتر از این خواندنی نیست: کسی متن خاکستریِ در حال تغییر را در بیست خط
// دنبال نمی‌کند. از آن به بعد هم شکستی در کار نیست، فقط از سرِ متن کم می‌شود و
// حرف زدن می‌تواند تا هر جا ادامه پیدا کند.
- (NSInteger)conveyorMaxLines {
    NSScreen *sc = _panel.screen ?: NSScreen.mainScreen;
    CGFloat room = (sc ? sc.visibleFrame.size.height : 900) * 0.5 - kBarH;
    NSInteger n = (NSInteger)floor(room / MAX(1.0, [self conveyorLineStep]));
    return MIN(12, MAX(3, n));
}

- (CGFloat)conveyorMaxTextHeight {
    return kBarH + ([self conveyorMaxLines] - 1) * [self conveyorLineStep] - 22;
}

// جای متن، با همان حسابی که layoutViews می‌کند. از فریمِ خودِ لیبل خوانده نمی‌شود،
// چون آن یک رندر عقب است و درست همان لحظه‌ای که چیپ ظاهر می‌شود غلط می‌دهد.
- (CGFloat)textWidth {
    CGFloat left = 126;
    if (!_btnInsert.hidden) left += _btnInsert.frame.size.width + 8;
    if (!_chipBg.hidden) left += _chipBg.frame.size.width + 8;
    return MAX(40, (_grip.frame.origin.x - 8) - left);
}

// قد نوار در حالت تسمه‌نقاله: با متن بلند قد می‌کشد، تا سقف conveyorMaxLines
- (CGFloat)conveyorHeight {
    NSString *s = _text.stringValue;
    if (!s.length) return kBarH;
    CGFloat h = [self heightOf:s width:[self textWidth]];
    CGFloat lh = [self lineHeight];
    NSInteger lines = MIN([self conveyorMaxLines], MAX(1, (NSInteger)round(h / MAX(1.0, lh))));
    return kBarH + (lines - 1) * [self conveyorLineStep];
}

- (void)resizeTo:(CGFloat)h {
    NSRect f = _panel.frame;
    if (fabs(f.size.height - h) < 1) {
        [self layoutViews];
        return;
    }
    _resizing = YES;
    f.size.height = h;
    [_panel setFrame:f display:YES];
    // پنل از پایین ثابت است و به بالا قد می‌کشد، پس اگر کاربر نزدیک سقف صفحه گذاشته
    // باشد سرش می‌زند بیرون. با قد تازه دوباره داخل صفحه می‌آید، و چون جای انتخابی
    // کاربر جدا نگه داشته می‌شود، متن که کوتاه شد پنل همان‌جای خودش برمی‌گردد.
    if (_haveWantOrigin) {
        NSScreen *sc = _panel.screen ?: NSScreen.mainScreen;
        if (sc) [_panel setFrameOrigin:[self clampOrigin:_wantOrigin toScreen:sc]];
    }
    _resizing = NO;
    _effect.frame = NSMakeRect(0, 0, kPW, _panel.frame.size.height);
    [self layoutViews];
}

// ---------- نمایش ----------

// پنجره را داخل visibleFrame همان صفحه نگه می‌دارد؛ هرگز بیرون از صفحه برنمی‌گردد
// (مثلا اگر مانیتور دومی که پنل رویش جابه‌جا شده بود از سیستم قطع شده باشد)
- (NSPoint)clampOrigin:(NSPoint)p toScreen:(NSScreen *)screen {
    NSRect vf = screen.visibleFrame;
    NSSize sz = _panel.frame.size;
    CGFloat maxX = NSMaxX(vf) - sz.width, maxY = NSMaxY(vf) - sz.height;
    CGFloat x = maxX < vf.origin.x ? vf.origin.x : MIN(MAX(p.x, vf.origin.x), maxX);
    CGFloat y = maxY < vf.origin.y ? vf.origin.y : MIN(MAX(p.y, vf.origin.y), maxY);
    return NSMakePoint(x, y);
}

- (void)show {
    [self applyColors];
    NSScreen *screen = nil;
    NSPoint origin = NSZeroPoint;
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:@"panelOrigin"];
    if (saved) {
        NSArray *parts = [saved componentsSeparatedByString:@","];
        if (parts.count == 2) {
            NSPoint p = NSMakePoint([parts[0] doubleValue], [parts[1] doubleValue]);
            for (NSScreen *sc in NSScreen.screens) {
                if (NSPointInRect(p, sc.frame)) { screen = sc; origin = p; break; }
            }
        }
    }
    if (!screen) {
        NSPoint mouse = NSEvent.mouseLocation;
        screen = NSScreen.mainScreen;
        for (NSScreen *sc in NSScreen.screens) {
            if (NSMouseInRect(mouse, sc.frame, NO)) { screen = sc; break; }
        }
        NSRect f = screen ? screen.visibleFrame : NSMakeRect(0, 0, 1440, 900);
        origin = NSMakePoint(NSMidX(f) - kPW / 2, NSMinY(f) + 90);
    }
    if (screen) origin = [self clampOrigin:origin toScreen:screen];
    _wantOrigin = origin;
    _haveWantOrigin = YES;
    [_panel setFrameOrigin:origin];
    [_panel orderFrontRegardless];
}

// جابه‌جایی به دست کاربر. جابه‌جایی‌های خودمان (سرِ قد کشیدن پنل) اینجا نمی‌آیند،
// وگرنه جای انتخابی کاربر با جای اصلاح‌شده عوض می‌شد و پنل کم‌کم سر می‌خورد.
- (void)panelMoved {
    if (_resizing) return;
    _wantOrigin = _panel.frame.origin;
    _haveWantOrigin = YES;
    [self scheduleSaveOrigin];
}

- (void)scheduleSaveOrigin {
    [_saveOriginTimer invalidate];
    __weak typeof(self) ws = self;
    _saveOriginTimer = [NSTimer timerWithTimeInterval:0.3 repeats:NO block:^(NSTimer *t) {
        [ws saveOrigin];
    }];
    // common modes: هنگام درگ (که ران‌لوپ داخلی خودش را دارد) هم شمارش تایمر ادامه پیدا کند
    [NSRunLoop.currentRunLoop addTimer:_saveOriginTimer forMode:NSRunLoopCommonModes];
}

- (void)saveOrigin {
    NSPoint o = _haveWantOrigin ? _wantOrigin : _panel.frame.origin;
    [NSUserDefaults.standardUserDefaults setObject:[NSString stringWithFormat:@"%.0f,%.0f", o.x, o.y]
                                            forKey:@"panelOrigin"];
}

- (void)hide {
    [_saveOriginTimer invalidate];
    _saveOriginTimer = nil;
    [self saveOrigin];
    [self stopPulse];
    [_panel orderOut:nil];
}

- (void)render:(ZPanelModel *)m {
    [self setCollectVisible:m.collect];

    // چیپ صف (فقط تسمه‌نقاله، وقتی مقصد جلو نیست)
    NSString *chip = @"";
    if (!m.collect && m.queued > 0) {
        chip = [ZFaDigits([NSString stringWithFormat:@"%ld", (long)m.queued]) stringByAppendingString:@" در صف"];
    }
    _chipBg.toolTip = (m.waitingForTarget && m.targetName.length)
        ? [NSString stringWithFormat:@"برگرد به %@ تا درج ادامه پیدا کند، یا ⌥V بزن که همینجا درج شود", m.targetName]
        : nil;
    if (!chip.length) {
        _chipBg.hidden = YES;
    } else {
        _chipBg.hidden = NO;
        _chipLabel.stringValue = chip;
        [_chipLabel sizeToFit];
        CGFloat w = _chipLabel.frame.size.width + 16;
        _chipBg.frame = NSMakeRect(126, (kBarH - 18) / 2, w, 18);
        _chipLabel.frame = NSMakeRect(8, 0, w - 16, 17);
    }

    // متن: خاکستری لحظه‌ای؛ وقتی نیست، خط وضعیت. بعد از چیپ می‌آید، نه قبلش: پهنای
    // جای متن به دیده‌شدن چیپ و دکمه بستگی دارد و بریدن متن باید با پهنای همین فریم
    // حساب شود، نه با پهنای فریم قبلی.
    if (m.interim.length) {
        _text.font = ZFont(15, NO);
        _text.maximumNumberOfLines = (NSInteger)[self conveyorMaxLines];
        _text.stringValue = [self visibleTail:m.interim];
        _text.textColor = NSColor.secondaryLabelColor;
    } else {
        _text.stringValue = m.status;
        _text.font = ZFont(12.5, NO);
        _text.textColor = m.error ? NSColor.systemRedColor : NSColor.tertiaryLabelColor;
    }
    _text.alignment = ([m.lang isEqualToString:@"en-US"] && m.interim.length)
        ? NSTextAlignmentLeft : NSTextAlignmentRight;

    // دکمه مکث سه چهره دارد: مکث، ادامه، تلاش دوباره بعد از خطا
    if (m.error) {
        [self setButton:_btnPause symbol:@"arrow.clockwise"];
        _btnPause.toolTip = @"تلاش دوباره (⌥Space)";
    } else if (m.paused) {
        [self setButton:_btnPause symbol:@"play.fill"];
        _btnPause.toolTip = @"ادامه شنیدن (⌥Space)";
    } else {
        [self setButton:_btnPause symbol:@"pause.fill"];
        _btnPause.toolTip = @"مکث شنیدن (⌥Space)";
    }

    // نقطه
    NSColor *color = m.error ? NSColor.systemGrayColor
        : (m.paused ? NSColor.systemGrayColor
           : (m.listening ? [NSColor colorWithRed:0.88 green:0.19 blue:0.19 alpha:1] : NSColor.systemOrangeColor));
    _dot.layer.backgroundColor = color.CGColor;
    if (m.listening && !m.paused && !_pulsing) [self startPulse];
    if ((!m.listening || m.paused) && _pulsing) [self stopPulse];

    [self resizeTo:m.collect ? kBarH + kEditorH : [self conveyorHeight]];
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
- (void)pauseTap { if (self.onPauseToggle) self.onPauseToggle(); }
- (void)copyTap { if (self.onCopyNow) self.onCopyNow(); }
- (void)trashTap { if (self.onTrash) self.onTrash(); }
- (void)insertTap { if (self.onInsertAll) self.onInsertAll(); }

// اسکرین‌شات برای بازبینی طراحی (بدون نیاز به اجازه ضبط صفحه)
- (void)makeShots:(NSString *)dir {
    ZPanelModel *listening = [ZPanelModel new];
    listening.interim = @"دارم متن نمونه را برای نوار زمزمه می‌گویم که ببینیم";
    listening.listening = YES;

    ZPanelModel *multiline = [ZPanelModel new];
    multiline.interim = @"وقتی جمله خیلی طولانی می‌شود و از یک خط می‌گذرد، نوار خودش قد می‌کشد "
        @"و متن خاکستری تا سه خط می‌پیچد که همه حرف‌های در جریان دیده شوند و چیزی از چشم نیفتد";
    multiline.listening = YES;

    ZPanelModel *paused = [ZPanelModel new];
    paused.status = @"مکث؛ ⌥Space برای ادامه";
    paused.paused = YES;

    ZPanelModel *queued = [ZPanelModel new];
    queued.interim = @"این تکه هنوز خاکستری است";
    queued.listening = YES;
    queued.queued = 3;
    queued.waitingForTarget = YES;
    queued.targetName = @"Windows App";

    // بدترین حالت بریدن متن: هم خیلی بلند، هم چیپ صف جای متن را تنگ کرده.
    // قبلا با عدد ثابت ۱۶۵ کاراکتری بریده می‌شد و همین حالت از سه خط می‌زد بیرون،
    // یعنی دم متن (تازه‌ترین حرف‌ها) دیده نمی‌شد.
    ZPanelModel *longNarrow = [ZPanelModel new];
    longNarrow.interim = @"حالا یک جمله واقعا طولانی می‌گویم که ببینیم نوار چه می‌کند، چون وقتی "
        @"آدم پیوسته حرف می‌زند و مکث نمی‌کند این متن خاکستری همین‌طور بلند و بلندتر می‌شود "
        @"و باید همیشه آخرش پیدا باشد نه اولش، وگرنه آدم نمی‌فهمد کجای حرفش است و همین "
        @"چیزی بود که آزار می‌داد و باید درست می‌شد";
    longNarrow.listening = YES;
    longNarrow.queued = 12;
    longNarrow.waitingForTarget = YES;
    longNarrow.targetName = @"Windows App";

    // دیکته‌ی واقعا طولانی و بی‌مکث: پنل باید قد بکشد، نه این‌که دم حرف را بیندازد
    ZPanelModel *veryLong = [ZPanelModel new];
    veryLong.interim = @"خب حالا می‌خواهم یک متن واقعا طولانی بگویم و هیچ‌جا مکث نکنم تا ببینم "
        @"این نوار چه می‌کند، چون تا الان وقتی حرفم طول می‌کشید از سه خط که می‌گذشت آخرش "
        @"می‌پرید و دیگر نمی‌دیدمش، و آدم وقتی نمی‌بیند کجای حرفش است حس شکست می‌گیرد و "
        @"رشته‌ی کلام از دستش می‌رود، پس باید همین‌طور که حرف می‌زنم پنل بزرگ شود و "
        @"تازه‌ترین جمله‌ها همیشه پیدا باشند، و اگر هم از سقف صفحه گذشت باز شکستی در کار "
        @"نباشد و فقط از اول متن کم شود، چون کسی که دارد دیکته می‌کند فقط می‌خواهد مطمئن "
        @"باشد که حرفش شنیده می‌شود و چیزی جا نمی‌افتد، همین و بس. حالا باز هم ادامه "
        @"می‌دهم و از سقف دوازده خط هم می‌گذرم، که ببینیم پشتیبان کار می‌کند یا نه: از "
        @"اینجا به بعد دیگر پنل بزرگ‌تر نمی‌شود، چون بزرگ‌تر از این روی صفحه فایده‌ای "
        @"ندارد و کسی نمی‌تواند این‌همه متنِ در حال تغییر را بخواند، پس باید از اولِ متن "
        @"کم شود و آخرش، یعنی همین جمله‌ای که همین الان دارم می‌گویم، پیدا بماند و "
        @"جمله‌ی آخر باید دیده شود";
    veryLong.listening = YES;

    ZPanelModel *error = [ZPanelModel new];
    error.status = @"شبکه ناپایداره؛ دکمه تلاش دوباره یا ⌥Space";
    error.error = YES;

    ZPanelModel *collect = [ZPanelModel new];
    collect.collect = YES;
    collect.listening = YES;
    collect.interim = @"و این هم متن خاکستری در جریان";

    NSArray *states = @[@[@"listening", listening], @[@"multiline", multiline], @[@"paused", paused],
                        @[@"queued", queued], @[@"long-narrow", longNarrow],
                        @[@"very-long", veryLong],
                        @[@"error", error], @[@"collect", collect]];
    [_panel orderFrontRegardless];
    for (NSArray *pair in states) {
        ZPanelModel *m = pair[1];
        if (m.collect) {
            [self clearEditor];
            [self appendFinalToEditor:@"متن قطعی‌شده اینجا جمع می‌شود و با کیبورد خودت قابل ویرایش است."];
            [self appendFinalToEditor:@"تهش با دکمه «درج در همین اپ» یکجا سر کرسر می‌نشیند."];
        }
        [self render:m];
        [_effect layoutSubtreeIfNeeded];
        NSBitmapImageRep *rep = [_effect bitmapImageRepForCachingDisplayInRect:_effect.bounds];
        if (!rep) continue;
        [_effect cacheDisplayInRect:_effect.bounds toBitmapImageRep:rep];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:[dir stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"panel-%@.png", pair[0]]] atomically:YES];
    }
    [self setCollectVisible:NO];
    [_panel orderOut:nil];
}

@end

// ---------- ZSession ----------
// مدل تسمه‌نقاله: پنل فقط بافر خاکستری است؛ هر تکه قطعی، بعد از پاس ویرایش،
// همان لحظه سر کرسرِ اپ مقصد درج می‌شود. اگر اپ جلویی عوض شود درج می‌ایستد و
// صف جمع می‌شود (⌥V یعنی همینجا درج کن). در حالت «جمع در پنل» به جای درج زنده،
// متن در ادیتور خود پنل می‌نشیند و تهش یکجا درج یا کپی می‌شود.

@implementation ZSession {
    ZPanel *_panel;
    ZInjector *_injector;
    NSRunningApplication *_target;
    NSMutableArray<NSString *> *_queue;       // تکه‌های قطعیِ هنوز درج‌نشده (تسمه‌نقاله)
    NSMutableArray<NSString *> *_transcript;  // همه قطعی‌ها برای کپی پایانی
    NSString *_interim;
    NSString *_statusText;
    BOOL _errorState;
    BOOL _listening;
    BOOL _collect;
    NSMutableArray<NSString *> *_pasteBuf;
    NSTimer *_pasteTimer;
    NSURL *_sessionFile;
    BOOL _finished;
    BOOL _collectInserted;    // حالت جمع: insertHere قبلا درج کرده؛ finish دوباره درج نکند
    id _frontObserver;
    // خط لوله پاس ویرایش: ترتیب تکه‌ها حفظ می‌شود، یکی‌یکی
    NSMutableArray<NSString *> *_polishPending;
    BOOL _polishBusy;
    NSString *_polishInFlight;   // خامِ تکه در پرواز؛ موقع بستن برمی‌گردد سر صف
    BOOL _dropNextPolish;    // موقع بستن، تکه در پرواز خام درج شده؛ جواب دیرش دور ریخته شود
}

- (instancetype)initWithEngine:(id<ZEngine>)engine panel:(ZPanel *)panel {
    if ((self = [super init])) {
        _engine = engine;
        _panel = panel;
        _injector = [ZInjector new];
        _queue = [NSMutableArray array];
        _transcript = [NSMutableArray array];
        _pasteBuf = [NSMutableArray array];
        _polishPending = [NSMutableArray array];
        _interim = @"";
        _statusText = @"";
        _sessionFile = [ZSessionsDir() URLByAppendingPathComponent:
                        [NSString stringWithFormat:@"app-%@.txt", ZTimestampId()]];
    }
    return self;
}

- (void)start {
    _collect = ZSettings.shared.collectMode;
    _target = NSWorkspace.sharedWorkspace.frontmostApplication;
    ZLog(@"session: start target=%@ engine=%@ lang=%@ collect=%d",
         _target.bundleIdentifier ?: @"?", ZSettings.shared.engineName, ZSettings.shared.lang, _collect);
    __weak typeof(self) ws = self;
    _frontObserver = [NSWorkspace.sharedWorkspace.notificationCenter
        addObserverForName:NSWorkspaceDidActivateApplicationNotification object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *n) {
        [ws pump];
        [ws render];
    }];
    _panel.onClose = ^{ [ws finish]; };
    _panel.onPauseToggle = ^{ [ws pauseToggle]; };
    _panel.onCopyNow = ^{ [ws copyNow]; };
    _panel.onTrash = ^{ [ws dropPending]; };
    _panel.onInsertAll = ^{ [ws insertHere]; };
    if (_collect) [_panel clearEditor];
    [_panel show];
    if (![ZInjector accessibilityOK]) {
        _statusText = @"دسترسی Accessibility نیست؛ درج کار نمی‌کند، متن آخر کار کپی می‌شود";
    }
    if (ZSettings.shared.polishEnabled) [ZPolish.shared prepare];
    self.engine.delegate = self;
    [self.engine startWithLang:ZSettings.shared.lang];
    [self render];
}

// ---------- ZEngineDelegate (روی نخ اصلی) ----------

- (void)engineInterim:(NSString *)text {
    _interim = [text copy];
    [self render];
}

// تکه قطعی: اول خام روی دیسک (sessions طلای تست است و خام می‌ماند)،
// بعد از خط لوله پاس ویرایش رد می‌شود و بعد درج/جمع.
- (void)engineFinal:(NSString *)text {
    [self appendToSessionFile:text];
    [_polishPending addObject:text];
    [self drainPolish];
}

- (void)drainPolish {
    if (_polishBusy || !_polishPending.count) return;
    NSString *raw = _polishPending.firstObject;
    [_polishPending removeObjectAtIndex:0];
    if (_finished) {
        // موقع بستن معطلی نداریم: خام و همین حالا
        [self acceptFinal:raw];
        [self drainPolish];
        return;
    }
    _polishBusy = YES;
    _polishInFlight = raw;
    __weak typeof(self) ws = self;
    [ZPolish.shared polish:raw completion:^(NSString *polished) {
        __strong typeof(ws) s = ws;
        if (!s) return;
        s->_polishBusy = NO;
        s->_polishInFlight = nil;
        if (s->_dropNextPolish) {
            s->_dropNextPolish = NO;    // بسته شدیم و خامش درج شده؛ این جواب دور ریخته می‌شود
        } else {
            [s acceptFinal:polished];
        }
        [s drainPolish];
    }];
}

- (void)acceptFinal:(NSString *)text {
    [_transcript addObject:text];
    if (_collect) {
        [_panel appendFinalToEditor:text];
    } else {
        [_queue addObject:text];
        [self pump];
    }
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
        case ZEnginePaused: _statusText = @"مکث؛ ⌥Space برای ادامه"; break;
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

// ---------- اکشن‌ها ----------

// ⌥Space: مکث/ادامه؛ بعد از خطا، تلاش دوباره
- (void)pauseToggle {
    if (_errorState) {
        _errorState = NO;
        [self.engine startWithLang:ZSettings.shared.lang];
        [self render];
        return;
    }
    if (self.engine.paused) [self.engine resume];
    else [self.engine pause];
}

// ⌥C: کپی متن تا اینجا (ماندگار)
- (void)copyNow {
    NSString *t = _collect ? [_panel editorText]
                           : [[_transcript componentsJoinedByString:@" "]
                              stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (t.length) [ZInjector copyFinal:t];
}

// سطل آشغال: هرچه گفته شده و هنوز درج نشده دور می‌رود، شنیدن ادامه دارد.
// موتور متن خاکستری و صدای پشتش را می‌ریزد؛ اینجا بقیه‌ی خط لوله پاک می‌شود.
// حالت جمع فرق دارد: آنجا متن قطعی داخل ادیتور خودِ کاربر است و دست‌کارش نمی‌کنیم،
// چون کاربر همان‌جا می‌تواند ویرایشش کند. متن درج‌شده هم برنمی‌گردد، چون از دست ما
// خارج شده. `sessions/` هم خام و کامل می‌ماند: آن دفتر است، خروجی نیست.
- (void)dropPending {
    [self.engine dropPending];
    _interim = @"";
    // پاسخ دیررسِ پاس ویرایشِ در پرواز نباید بعدا بنشیند
    if (_polishInFlight) _dropNextPolish = YES;
    [_polishPending removeAllObjects];
    if (!_collect) {
        // این تکه‌ها به ترتیب در _transcript هم نشسته‌اند، پس دقیقا همان تعداد از
        // دُمش برداشته می‌شود که کپی پایانی هم متن دورریخته را نداشته باشد.
        NSUInteger drop = _queue.count + _pasteBuf.count;
        [_queue removeAllObjects];
        [_pasteBuf removeAllObjects];
        if (drop > _transcript.count) drop = _transcript.count;
        if (drop) {
            [_transcript removeObjectsInRange:NSMakeRange(_transcript.count - drop, drop)];
        }
    }
    [self render];
}

// ⌥V یا دکمه «درج در همین اپ»: هرچه هست، سر کرسر همین اپ جلویی
- (void)insertHere {
    _target = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (_collect) {
        NSString *t = [_panel editorText];
        if (!t.length) return;
        [self injectText:[t stringByAppendingString:@" "]];
        _collectInserted = YES;
        [self finish];
        return;
    }
    [self pump];
    [self render];
}

- (void)injectText:(NSString *)text {
    if (![ZInjector accessibilityOK] || [ZInjector secureInputActive]) return;
    if ([ZSettings.shared insertModeForBundleId:_target.bundleIdentifier] == ZInsertPaste) {
        [_injector paste:text delayMicros:ZSettings.shared.pasteDelayMicros];
    } else {
        [_injector type:text delayMicros:ZSettings.shared.typeDelayMicros];
    }
}

// ---------- تسمه‌نقاله ----------

- (BOOL)targetIsFront {
    NSRunningApplication *f = NSWorkspace.sharedWorkspace.frontmostApplication;
    return _target && f && _target.processIdentifier == f.processIdentifier;
}

- (void)pump {
    if (_collect || !_queue.count) return;
    if (![ZInjector accessibilityOK] || ![self targetIsFront] || [ZInjector secureInputActive]) return;
    NSString *chunk = [[_queue componentsJoinedByString:@" "] stringByAppendingString:@" "];
    [_queue removeAllObjects];
    if ([ZSettings.shared insertModeForBundleId:_target.bundleIdentifier] == ZInsertType) {
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

// ---------- پایان (Esc یا دابل‌تپ دوباره) ----------

- (void)finish {
    if (_finished) return;
    _finished = YES;
    if (_polishBusy) {
        // تکه در پرواز: خامش برمی‌گردد سر صف که همین حالا درج شود؛ جواب دیرِ پاس دور ریخته می‌شود
        _dropNextPolish = YES;
        if (_polishInFlight) [_polishPending insertObject:_polishInFlight atIndex:0];
        _polishInFlight = nil;
        _polishBusy = NO;
    }
    [self.engine stop];    // موتور قبل از بستن salvage می‌کند و finalها همین‌جا می‌رسند
    // هرچه در خط لوله پاس مانده، بدون معطلی خام پذیرفته می‌شود
    [self drainPolish];
    [self flushPasteBuf];
    // پایان: در حالت زنده باقی صف، در حالت جمع کل متن ادیتور؛ اگر مقصد جلوست درج
    // می‌شود، وگرنه کپیِ زیر همین تابع نجاتش می‌دهد. اگر ⌥V/دکمه درج قبلا درج کرده
    // (insertHere -> _collectInserted) اینجا دوباره درج نمی‌شود.
    if (_collect) {
        NSString *t = [_panel editorText];
        if (!_collectInserted && t.length && [self targetIsFront]) {
            [self injectText:[t stringByAppendingString:@" "]];
        }
    } else if (_queue.count && [self targetIsFront]) {
        [self injectText:[[_queue componentsJoinedByString:@" "] stringByAppendingString:@" "]];
        [_queue removeAllObjects];
    }
    // بیمه: کل متن سشن، یک بار، ماندگار در کلیپ‌بورد؛ پشتِ صف درج که با پیست مسابقه نگیرد
    NSString *full = _collect ? [_panel editorText]
                              : [[_transcript componentsJoinedByString:@" "]
                                 stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (full.length) [_injector copyFinalAfterPending:full];
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
    m.listening = _listening;
    m.paused = self.engine.paused;
    m.error = _errorState;
    m.lang = ZSettings.shared.lang;
    m.collect = _collect;
    m.waitingForTarget = !_collect && _queue.count > 0 && ![self targetIsFront];
    m.targetName = _target.localizedName ?: @"";
    [_panel render:m];
}

@end
