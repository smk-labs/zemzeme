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

// سبز یعنی دارد می‌شنود، قرمز یعنی اتصال مشکل دارد (قطعی موقت یا تسلیم)، نارنجی
// در حال وصل شدن، خاکستری مکث. قبلا شنیدن قرمز بود، یعنی حالت سلامت و حالت خرابی
// یک رنگ داشتند. اینجا بیرون از ZPanel نشسته چون حالت کرسر پنلی ندارد و نشانگر
// کنار کرسر باید دقیقا همین معنی‌ها را بگوید، نه کپیِ کمی متفاوتشان.
NSColor *ZStatusColor(ZPanelModel *m) {
    if (m.paused)             return NSColor.systemGrayColor;
    if (m.error || m.trouble) return [NSColor colorWithRed:0.88 green:0.19 blue:0.19 alpha:1];
    if (m.listening)          return [NSColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1];
    return NSColor.systemOrangeColor;
}

// ویوی ادیتور برای مقصد. داخل همین فایل می‌ماند: بیرون کسی نباید به استوریج پنل
// دست بزند، و مقصد خودش عضوِ همین‌جاست.
@interface ZPanel (ZEditorAccess)
- (NSTextView *)liveEditor;
@end

// مقصدِ ادیتورِ حالت جمع. اینجا استوریج مالِ خودمان است، پس تاییدْ خواندنِ مستقیم
// همان رشته است: دقیق، مجانی، و بی هیچ رفت‌وبرگشتی با اپ دیگری.
// ولی متنِ ادیتور با کیبوردِ خودِ کاربر هم عوض می‌شود، پس تایید واقعا لازم است:
// اگر کاربر ته متن را دست بزند، دُمِ ما دیگر آنجا نیست و نباید پاکش کنیم.
@interface ZEditorSink : NSObject <ZTextSink>
- (instancetype)initWithPanel:(ZPanel *)panel;
@end

// ---------- ZPanel ----------
// نوار باریک بدون گرفتن فوکس، روی همه Space ها و فول‌اسکرین. سه دکمه بیشتر ندارد:
// بستن، مکث/ادامه، کپی. متن خاکستری تا سه خط می‌پیچد و پنل قدش را خودش تنظیم می‌کند.
// در حالت «جمع در پنل» یک ادیتور واقعی باز می‌شود: متن قطعی همان‌جا می‌نشیند،
// قابل ویرایش با کیبورد خود کاربر، و تهش با یک دکمه در اپ مقصد درج می‌شود.

static const CGFloat kPW = 500;
static const CGFloat kBarH = 46;      // ارتفاع ردیف پایه (دکمه‌ها + نقطه)
static const CGFloat kBarPad = 10;    // فاصله اولین دکمه از لبه چپ
static const CGFloat kBarStep = 28;   // گام هر دکمه (۲۴ عرض + ۴ فاصله)
static const CGFloat kEditorH = 150;  // ارتفاع ادیتور حالت جمع

// پس‌زمینهٔ پنل (تعریفش در zemzeme.h است، چون کارت میان‌برها هم همین را می‌خواهد):
// دکمه‌ها/برچسب/ادیتور چون خودشان mouseDown را می‌گیرند دست‌نخورده می‌مانند.
@implementation ZDragEffectView
- (BOOL)mouseDownCanMoveWindow { return YES; }
- (void)mouseDown:(NSEvent *)event { [self.window performWindowDragWithEvent:event]; }
@end

@implementation ZPanel {
    NSPanel *_panel;
    ZDragEffectView *_effect;
    ZMarkView *_dot;
    NSImageView *_grip;
    NSTextField *_text;
    NSView *_chipBg;
    NSTextField *_chipLabel;
    NSButton *_btnClose, *_btnPause, *_btnCopy, *_btnTrash, *_btnInsert;
    NSButton *_btnLang, *_btnMode, *_btnPolish, *_btnFile;
    NSArray<NSButton *> *_bar;    // ترتیب دکمه‌ها؛ یک منبع حقیقت برای چیدمان و پهنای متن
    NSMutableArray<NSTextField *> *_barCaps;   // حرف میان‌بر زیر هر دکمه، به همان ترتیب
    id<ZTextSink> _editorSink;
    ZPanelModel *_lastModel;      // برای رندر دوباره بدون سشن (فیدبک لحظه‌ای)
    NSString *_flash;             // پیام کوتاه تایید کار، چند لحظه روی خط وضعیت
    NSInteger _flashGen;
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

        // نشان پهن‌تر از بلند است، پس قاب با ZMarkAspect حساب می‌شود نه مربع ۹
        _dot = [[ZMarkView alloc] initWithFrame:
            NSMakeRect(kPW - 16 - 9 * ZMarkAspect, (kBarH - 9) / 2, 9 * ZMarkAspect, 9)];
        [_effect addSubview:_dot];

        // دستگیرهٔ کشیدن: فقط راهنمای دیداری (کل پس‌زمینه از قبل قابل کشیدن است)، کنار نقطه
        NSImage *gripImg = [NSImage imageWithSystemSymbolName:@"line.3.horizontal"
                                      accessibilityDescription:@"دستگیرهٔ جابه‌جایی پنل"];
        gripImg = [gripImg imageWithSymbolConfiguration:
                   [NSImageSymbolConfiguration configurationWithPointSize:9 weight:NSFontWeightRegular]];
        _grip = [NSImageView imageViewWithImage:gripImg ?: [NSImage new]];
        _grip.contentTintColor = NSColor.secondaryLabelColor;
        _grip.toolTip = @"بکش تا جابه‌جا شود";
        _grip.frame = NSMakeRect(kPW - 16 - 9 * ZMarkAspect - 8 - 16, (kBarH - 9) / 2, 16, 9);
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

        // همه‌ی دکمه‌ها آیکون‌اند و یک اندازه، و هر تولتیپ حرف میان‌بر خودش را می‌گوید.
        // میان‌بر هر کدام «Command راست + همان حرف» است، و تنها همان.
        _btnClose = [self makeButton:@"xmark" key:@"esc" tip:@"پایان و درج همه (Esc)"
                              action:@selector(closeTap)];
        _btnPause = [self makeButton:@"pause.fill" key:@"⌘"
                                 tip:@"مکث و ادامه (تک‌تپ Command راست، یا Command راست + Space)"
                              action:@selector(pauseTap)];
        _btnCopy = [self makeButton:@"doc.on.doc" key:@"C" tip:@"کپی متن تا اینجا"
                             action:@selector(copyTap)];
        _btnTrash = [self makeButton:@"trash" key:@"D" tip:@"دور ریختن هرچه هنوز درج نشده"
                              action:@selector(trashTap)];
        _btnLang = [self makeButton:@"globe" key:@"L" tip:@"" action:@selector(langTap)];
        _btnMode = [self makeButton:@"square.and.pencil" key:@"E" tip:@"" action:@selector(modeTap)];
        _btnPolish = [self makeButton:@"wand.and.stars" key:@"P"
                                  tip:@"پاس ویرایش فارسی روی متن جمع‌شده"
                               action:@selector(polishTap)];
        _btnInsert = [self makeButton:@"text.insert" key:@"I" tip:@"درج سر کرسر همین اپ"
                               action:@selector(insertTap)];
        // رونویسی فایل: در هر دو حالتِ پنل‌دار پیداست، چون به سشن ربطی ندارد. راه سوم
        // دسترسی است، کنار آیتم منوبار و میان‌بر، و همان یک صف را باز می‌کند.
        _btnFile = [self makeButton:@"arrow.up.doc" key:@"F"
                                tip:@"رونویسی فایل صوتی: صف، پیشرفت و متن یکجا (Command راست + F)"
                             action:@selector(fileTap)];
        _btnPolish.hidden = YES;
        _btnInsert.hidden = YES;
        // ترتیب چیدمان؛ layoutViews و textWidth هر دو از همین یک لیست می‌خوانند، پس
        // پیدا و ناپیدا شدن دکمه‌ها هیچ‌وقت با عدد هاردکد ناهمخوان نمی‌شود.
        _bar = @[_btnClose, _btnPause, _btnCopy, _btnTrash, _btnLang, _btnMode, _btnPolish,
                 _btnInsert, _btnFile];

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

// آیکون + حرف میان‌بر ریز زیرش. تولتیپ روی این پنل هیچ‌وقت ظاهر نمی‌شود (پنل
// nonactivating است و اپ اکسسوری، پس مک تولتیپ را نمی‌کشد)، پس میان‌بر باید
// خودش روی نوار نوشته باشد.
- (NSButton *)makeButton:(NSString *)symbol key:(NSString *)key
                     tip:(NSString *)tip action:(SEL)action {
    NSButton *b = [self makeButton:symbol tip:tip action:action];
    NSTextField *cap = [NSTextField labelWithString:key];
    cap.font = [NSFont monospacedDigitSystemFontOfSize:8 weight:NSFontWeightMedium];
    cap.textColor = NSColor.tertiaryLabelColor;
    cap.alignment = NSTextAlignmentCenter;
    [_effect addSubview:cap];
    if (!_barCaps) _barCaps = [NSMutableArray array];
    [_barCaps addObject:cap];
    return b;
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
    CGFloat cy = (kBarH - 24) / 2;   // مرکز ردیف؛ آیکون‌ها ۴ پیکسل بالاتر می‌روند
    // آیکون کمی بالاتر می‌نشیند تا حرف میان‌بر زیرش جا شود
    CGFloat left = kBarPad;
    for (NSUInteger i = 0; i < _bar.count; i++) {
        NSButton *b = _bar[i];
        NSTextField *cap = i < _barCaps.count ? _barCaps[i] : nil;
        cap.hidden = b.hidden;
        if (b.hidden) continue;
        b.frame = NSMakeRect(left, cy + 4, 24, 24);
        cap.frame = NSMakeRect(left - 3, 3, 30, 10);
        left += kBarStep;
    }
    if (!_chipBg.hidden) {
        NSRect f = _chipBg.frame;
        f.origin = NSMakePoint(left, (kBarH - 18) / 2);
        _chipBg.frame = f;
        left += _chipBg.frame.size.width + 8;
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
    // richText باید روشن باشد: دُم خاکستری یعنی دو رنگ در یک متن، و ویوی متن‌ساده
    // (richText=NO) هر رنگ‌آمیزی رنج‌به‌رنج را پس می‌زند و سر همان addAttributes روی
    // نخ اصلی گیر می‌کند. خروجی همیشه با .string خوانده می‌شود، پس متن ساده می‌ماند.
    _editor.richText = YES;
    _editor.importsGraphics = NO;
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
    // پیدا و ناپیدا شدن دکمه‌ها را render می‌گذارد، یک جا، که دو منبع حقیقت نشود
    [self resizeTo:on ? kBarH + kEditorH : [self conveyorHeight]];
}

// ویوی ادیتور، ساخته‌شده. مقصدِ متن از همین می‌خواند.
- (NSTextView *)liveEditor {
    [self ensureEditor];
    return _editor;
}

- (id<ZTextSink>)editorSink {
    if (!_editorSink) _editorSink = [[ZEditorSink alloc] initWithPanel:self];
    return _editorSink;
}

- (NSString *)editorText {
    return _editor.string ?: @"";
}

// فیدبک کار: یک پیام کوتاه، ۱٫۴ ثانیه، روی خط وضعیت. هر دکمه و هر میان‌بر از این
// رد می‌شود، وگرنه زدنشان هیچ اثری روی صفحه ندارد و آدم شک می‌کند اصلا کار کرد یا نه.
- (void)flash:(NSString *)msg {
    _flash = msg;
    _flashGen++;
    NSInteger gen = _flashGen;
    if (_lastModel) [self render:_lastModel];
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(ws) s = ws;
        if (!s || s->_flashGen != gen) return;    // فیدبک تازه‌تری آمده
        s->_flash = nil;
        if (s->_lastModel) [s render:s->_lastModel];
    });
}

// جای متن را یک‌جا عوض می‌کند: مسیر پاس دستی و مسیر عوض کردن حالت هر دو لازمش دارند
- (void)setEditorText:(NSString *)text {
    [self ensureEditor];
    [_editor.textStorage replaceCharactersInRange:NSMakeRange(0, _editor.string.length)
                                      withString:text ?: @""];
    _editor.font = ZFont(15, NO);
    _editor.textColor = NSColor.labelColor;
    [_editor scrollRangeToVisible:NSMakeRange(_editor.string.length, 0)];
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
    CGFloat left = kBarPad;
    for (NSButton *b in _bar) if (!b.hidden) left += kBarStep;
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
    _lastModel = m;
    // حالت کرسر پنل را اصلا نشان نمی‌دهد، پس اینجا فقط دو حالتِ پنل‌دار می‌مانند و
    // «جمع یا نه» همان یک پرسش قبلی است.
    BOOL collect = m.mode == ZModeCollect;
    [self setCollectVisible:collect];

    // زبان روی همان دکمه دیده می‌شود: آیکون یکی است و تولتیپ می‌گوید الان کدام زبان
    // است و زدنش چه می‌کند. متن روی دکمه نمی‌گذاریم که ردیف یک‌دست بماند.
    BOOL en = [m.lang hasPrefix:@"en"];
    _btnLang.toolTip = en ? @"زبان: انگلیسی. برای رفتن به فارسی بزن (Command راست + L)"
                          : @"زبان: فارسی. برای رفتن به انگلیسی بزن (Command راست + L)";
    // آیکون حالت، همان چیزی که با زدنش می‌گیری. چرخه سه‌تایی است، پس آیکون از
    // حالتِ بعدی خوانده می‌شود نه از حالت فعلی.
    ZMode next = (ZMode)((m.mode + 1) % (ZModeCursor + 1));
    [self setButton:_btnMode symbol:next == ZModeCollect ? @"square.and.pencil"
                                : next == ZModeCursor ? @"text.cursor" : @"bolt.fill"];
    _btnMode.toolTip = next == ZModeCollect
        ? @"رفتن به جمع در پنل، جایی که می‌شود ویرایش کرد (Command راست + E)"
        : next == ZModeCursor
        ? @"رفتن به حالت کنار کرسر: پنل می‌رود و فقط یک نقطه می‌ماند (Command راست + E)"
        : @"رفتن به درج زنده؛ متن جمع‌شده هم با خودش می‌آید (Command راست + E)";
    // پاس دستی و درج فقط در حالت جمع معنا دارند
    _btnPolish.hidden = !collect;
    _btnInsert.hidden = !collect && !m.waitingForTarget;

    // چیپ صف (فقط تسمه‌نقاله، وقتی مقصد جلو نیست)
    NSString *chip = @"";
    if (!collect && m.queued > 0) {
        chip = [ZFaDigits([NSString stringWithFormat:@"%ld", (long)m.queued]) stringByAppendingString:@" در صف"];
    }
    _chipBg.toolTip = (m.waitingForTarget && m.targetName.length)
        ? [NSString stringWithFormat:@"برگرد به %@ تا درج ادامه پیدا کند، یا Command راست و I بزن که همینجا درج شود", m.targetName]
        : nil;
    if (!chip.length) {
        _chipBg.hidden = YES;
    } else {
        _chipBg.hidden = NO;
        _chipLabel.stringValue = chip;
        [_chipLabel sizeToFit];
        CGFloat w = _chipLabel.frame.size.width + 16;
        _chipBg.frame = NSMakeRect(kBarPad, (kBarH - 18) / 2, w, 18);   // x را layoutViews می‌گذارد
        _chipLabel.frame = NSMakeRect(8, 0, w - 16, 17);
    }

    // متن: خاکستری لحظه‌ای؛ وقتی نیست، خط وضعیت. بعد از چیپ می‌آید، نه قبلش: پهنای
    // جای متن به دیده‌شدن چیپ و دکمه بستگی دارد و بریدن متن باید با پهنای همین فریم
    // حساب شود، نه با پهنای فریم قبلی.
    // فیدبک کار (کپی شد، زبان عوض شد…) بر همه‌چیز مقدم است: چند لحظه دیده می‌شود و
    // بعد خودش می‌رود. بدون این، زدن دکمه هیچ نشانه‌ای روی صفحه نداشت.
    // متن خاکستری در حالت جمع اینجا نمی‌آید: آنجا دنبال متن سفیدِ ادیتور استریم می‌شود،
    // چون در این نوار نصفه می‌ماند و آدم نمی‌فهمد ادامه‌اش چه بود.
    NSString *interimHere = collect ? @"" : m.interim;
    if (_flash.length) {
        _text.stringValue = _flash;
        _text.font = ZFont(12.5, YES);
        _text.textColor = NSColor.secondaryLabelColor;
    } else if (interimHere.length) {
        _text.font = ZFont(15, NO);
        _text.maximumNumberOfLines = (NSInteger)[self conveyorMaxLines];
        _text.stringValue = [self visibleTail:interimHere];
        _text.textColor = NSColor.secondaryLabelColor;
    } else {
        // زبان همیشه از مدل خوانده می‌شود، نه از متنی که موقع تغییر وضعیت ساخته شده.
        // قبلا در _statusText پخته می‌شد و بعد از عوض کردن زبان تازه نمی‌شد، پس روی
        // انگلیسی هم می‌نوشت «فارسی».
        NSString *s = m.status;
        if (m.listening) {
            NSString *ln = [m.lang hasPrefix:@"en"] ? @"انگلیسی" : @"فارسی";
            s = s.length ? [s stringByAppendingFormat:@" · %@", ln] : ln;
        }
        _text.stringValue = s;
        _text.font = ZFont(12.5, NO);
        _text.textColor = m.error ? NSColor.systemRedColor : NSColor.tertiaryLabelColor;
    }
    _text.alignment = ([m.lang isEqualToString:@"en-US"] && m.interim.length)
        ? NSTextAlignmentLeft : NSTextAlignmentRight;

    // دکمه مکث سه چهره دارد: مکث، ادامه، تلاش دوباره بعد از خطا
    if (m.error) {
        [self setButton:_btnPause symbol:@"arrow.clockwise"];
        _btnPause.toolTip = @"تلاش دوباره (تک‌تپ Command راست)";
    } else if (m.paused) {
        [self setButton:_btnPause symbol:@"play.fill"];
        _btnPause.toolTip = @"ادامه شنیدن (تک‌تپ Command راست)";
    } else {
        [self setButton:_btnPause symbol:@"pause.fill"];
        _btnPause.toolTip = @"مکث شنیدن (تک‌تپ Command راست)";
    }

    _dot.color = ZStatusColor(m);
    if (m.listening && !m.paused && !_pulsing) [self startPulse];
    if ((!m.listening || m.paused) && _pulsing) [self stopPulse];

    [self resizeTo:collect ? kBarH + kEditorH : [self conveyorHeight]];
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
- (void)langTap { if (self.onLangSwitch) self.onLangSwitch(); }
- (void)modeTap { if (self.onModeToggle) self.onModeToggle(); }
- (void)polishTap { if (self.onPolishNow) self.onPolishNow(); }
- (void)insertTap { if (self.onInsertAll) self.onInsertAll(); }
- (void)fileTap { if (self.onFilePanel) self.onFilePanel(); }

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
    paused.status = @"مکث؛ تک‌تپ Command راست برای ادامه";
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
    error.status = @"شبکه ناپایداره؛ دکمه تلاش دوباره یا تک‌تپ Command راست";
    error.error = YES;

    ZPanelModel *collect = [ZPanelModel new];
    collect.mode = ZModeCollect;
    collect.listening = YES;
    collect.interim = @"و این هم متن خاکستری در جریان";

    NSArray *states = @[@[@"listening", listening], @[@"multiline", multiline], @[@"paused", paused],
                        @[@"queued", queued], @[@"long-narrow", longNarrow],
                        @[@"very-long", veryLong],
                        @[@"error", error], @[@"collect", collect]];
    [_panel orderFrontRegardless];
    for (NSArray *pair in states) {
        ZPanelModel *m = pair[1];
        if (m.mode == ZModeCollect) {
            [self clearEditor];
            // از همان دفتر و همان مقصدی که مسیر واقعی استفاده می‌کند، نه یک راه دوم
            ZTextLedger *shot = [[ZTextLedger alloc] initWithSink:[self editorSink]];
            shot.pendingThrottle = 0;
            [shot applyCommitted:@"متن قطعی‌شده اینجا جمع می‌شود و با کیبورد خودت قابل ویرایش است. "
                                 @"تهش با دکمه درج، یکجا سر کرسر می‌نشیند."
                         pending:m.interim];
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

// ---------- ZEditorSink ----------

@implementation ZEditorSink {
    __weak ZPanel *_panel;
    // فقط برای رنگ: از خودِ دفتر می‌آید و شمارنده‌ی دومی نیست. اگر از دست برود
    // بدترین اتفاق این است که چند نویسه رنگشان دیر عوض شود، نه اینکه متنی پاک شود.
    NSUInteger _lastPendingLen;
}

- (instancetype)initWithPanel:(ZPanel *)panel {
    if ((self = [super init])) _panel = panel;
    return self;
}

- (BOOL)rendersPending { return YES; }
- (BOOL)canRewrite { return YES; }

- (void)appendText:(NSString *)text done:(void (^)(ZSinkResult))done {
    NSTextView *tv = [_panel liveEditor];
    if (!tv) {
        done(ZSinkUnavailable);
        return;
    }
    // هشدار: tv.string یک پروکسیِ زنده است، نه عکس لحظه‌ای. نقطه‌ی درج باید قبل از
    // دست‌کاری در یک عدد ذخیره شود، وگرنه رنجِ رنگ‌آمیزی از ته متن بیرون می‌زند و
    // addAttributes بی‌هیچ خطایی نخ اصلی را قفل می‌کند.
    NSUInteger at = tv.string.length;
    [tv.textStorage replaceCharactersInRange:NSMakeRange(at, 0) withString:text];
    [tv.textStorage addAttributes:@{NSFontAttributeName: ZFont(15, NO),
                                    NSForegroundColorAttributeName: NSColor.labelColor}
                            range:NSMakeRange(at, text.length)];
    [tv scrollRangeToVisible:NSMakeRange(tv.string.length, 0)];
    done(ZSinkOK);
}

- (void)replaceLast:(NSUInteger)n expecting:(NSString *)expected with:(NSString *)text
               done:(void (^)(ZSinkResult))done {
    NSTextView *tv = [_panel liveEditor];
    if (!tv) {
        done(ZSinkUnavailable);
        return;
    }
    NSUInteger len = tv.string.length;
    if (len < n || ![[tv.string substringFromIndex:len - n] isEqualToString:expected]) {
        // کاربر ته متن را دست زده. متنِ او مالِ اوست.
        done(ZSinkDisowned);
        return;
    }
    [tv.textStorage replaceCharactersInRange:NSMakeRange(len - n, n) withString:text];
    if (text.length) {
        [tv.textStorage addAttributes:@{NSFontAttributeName: ZFont(15, NO),
                                        NSForegroundColorAttributeName: NSColor.labelColor}
                                range:NSMakeRange(len - n, text.length)];
    }
    [tv scrollRangeToVisible:NSMakeRange(tv.string.length, 0)];
    done(ZSinkOK);
}

// دُمِ ناپایدار خاکستری دیده می‌شود. فقط ناحیه‌ی تغییر رنگ می‌شود، نه کل متن: روی
// یک سند بلند، رنگ‌آمیزیِ کامل چند بار در ثانیه نخ اصلی را می‌خورد.
- (void)markPendingLength:(NSUInteger)n {
    NSTextView *tv = [_panel liveEditor];
    if (!tv) return;
    NSUInteger len = tv.string.length;
    NSUInteger span = MAX(n, _lastPendingLen);
    NSUInteger start = len >= span ? len - span : 0;
    if (len > start) {
        [tv.textStorage addAttributes:@{NSForegroundColorAttributeName: NSColor.labelColor}
                                range:NSMakeRange(start, len - start)];
    }
    if (n && len >= n) {
        [tv.textStorage addAttributes:@{NSForegroundColorAttributeName: NSColor.secondaryLabelColor}
                                range:NSMakeRange(len - n, n)];
    }
    _lastPendingLen = n;
}

@end

// ---------- ZSession ----------
// مدل تسمه‌نقاله: پنل فقط بافر خاکستری است؛ هر تکه قطعی، بعد از پاس ویرایش،
// همان لحظه سر کرسرِ اپ مقصد درج می‌شود. اگر اپ جلویی عوض شود درج می‌ایستد و
// صف جمع می‌شود (Command راست و I یعنی همینجا درج کن). در حالت «جمع در پنل» به جای درج زنده،
// متن در ادیتور خود پنل می‌نشیند و تهش یکجا درج یا کپی می‌شود. حالت «کرسر» دقیقا
// همان تسمه‌نقاله‌ی زنده است، فقط بی‌پنل: به جای نوار، یک نقطه کنار کرسر. پس در
// همه‌ی این کد تنها پرسشِ حالت این است که «جمع هست یا نه»، و کرسر هیچ شاخه‌ی درجِ
// جداگانه‌ای نمی‌سازد.

// نام حالت برای لاگ و برای فیدبک روی صفحه؛ دو جا، یک منبع
static NSString *ZModeSlug(ZMode m) {
    return m == ZModeCollect ? @"collect" : (m == ZModeCursor ? @"cursor" : @"live");
}

static NSString *ZModeLabel(ZMode m) {
    return m == ZModeCollect ? @"جمع در پنل" : (m == ZModeCursor ? @"کنار کرسر" : @"درج زنده");
}

@implementation ZSession {
    ZPanel *_panel;
    ZCaretDot *_dot;          // فقط در حالت کرسر ساخته می‌شود؛ بیشتر سشن‌ها لازمش ندارند
    ZInjector *_injector;
    NSRunningApplication *_target;

    // ---------- خط لوله ----------
    // یک دفتر، و مقصدی که با حالت عوض می‌شود. صفِ «تکه‌های درج‌نشده» به‌عنوان یک
    // مفهوم جدا وجود ندارد: مقصد جلو نیست یعنی مقصد ننوشت، پس دفتر جلو نمی‌رود و
    // دفعه‌ی بعد همه را یکجا می‌نویسد.
    ZTextLedger *_ledger;
    ZCaretSink *_caretSink;

    // چقدر از رونوشتِ خامِ موتور را دیده‌ایم (برای دفترِ sessions/ و تغذیه‌ی پاس)
    NSUInteger _rawSeen;
    // رونوشتِ ما: خام یا پاس‌خورده. این است که «قطعی» به حساب می‌آید و به دفتر می‌رود.
    NSMutableString *_transcript;
    // تکه‌های خامی که هنوز پاس نخورده‌اند؛ اولی در پرواز است. اینها جزء *pending* اند.
    // نتیجه‌اش دقیقا رفتار قبلی است، ولی حالا از شکل خط لوله درمی‌آید نه از سه شرط
    // پراکنده: در حالت کرسر که دُم رندر می‌شود، متن خام همان لحظه سر کرسر می‌نشیند و
    // با آمدن پاس چند نویسه‌اش عوض می‌شود؛ در حالت زنده که دُم رندر نمی‌شود، تکه
    // خودبه‌خود منتظر پاس می‌ماند.
    NSMutableArray<NSString *> *_awaiting;
    BOOL _polishBusy;
    NSInteger _polishGen;      // سطل آشغال این را می‌چرخاند، پس جوابِ دیررس دور می‌رود
    NSString *_enginePending;

    NSString *_statusText;
    BOOL _errorState;
    BOOL _troubleState;       // قطعی موقت: نقطه قرمز، ولی سشن زنده است
    BOOL _listening;
    ZMode _mode;
    // دفتر کجا بود وقتی وارد حالت جمع شدیم. بیرون آمدن از جمع باید متنِ ادیتور را
    // (با ویرایش‌های خودِ کاربر) سر کرسر بنشاند، پس باید بدانیم از کجا شروع شده بود.
    NSUInteger _editorStintStart;
    NSURL *_sessionFile;
    BOOL _finished;
    BOOL _finishing;          // منتظر پاس ویرایشِ پایانی حالت جمع
    id _frontObserver;
}

- (instancetype)initWithEngine:(id<ZEngine>)engine panel:(ZPanel *)panel {
    if ((self = [super init])) {
        _engine = engine;
        _panel = panel;
        _injector = [ZInjector new];
        _caretSink = [[ZCaretSink alloc] initWithInjector:_injector];
        _transcript = [NSMutableString string];
        _awaiting = [NSMutableArray array];
        _enginePending = @"";
        _statusText = @"";
        NSString *stamp = ZTimestampId();
        _sessionFile = [ZSessionsDir() URLByAppendingPathComponent:
                        [NSString stringWithFormat:@"app-%@.txt", stamp]];
        // ورودیِ خامِ رونوشت، کنار متنِ خام. سشنِ بعدی که چیزی از دستش برود، با
        // `zemzeme --replay` دقیقا همان‌جا دوباره پخش می‌شود، بی‌میکروفن و بی‌شبکه.
        ZEventLogStart([ZSessionsDir() URLByAppendingPathComponent:
                        [NSString stringWithFormat:@"app-%@.events.jsonl", stamp]]);
    }
    return self;
}

- (void)start {
    _mode = ZSettings.shared.mode;
    _target = NSWorkspace.sharedWorkspace.frontmostApplication;
    _caretSink.target = _target;
    _ledger = [[ZTextLedger alloc] initWithSink:[self sinkForMode:_mode]];
    ZLog(@"session: start target=%@ engine=%@ lang=%@ mode=%@",
         _target.bundleIdentifier ?: @"?", ZSettings.shared.engineName, ZSettings.shared.lang,
         ZModeSlug(_mode));
    ZPlay(ZSoundStart);
    __weak typeof(self) ws = self;
    _frontObserver = [NSWorkspace.sharedWorkspace.notificationCenter
        addObserverForName:NSWorkspaceDidActivateApplicationNotification object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *n) {
        // مقصد برگشت؟ هرچه در دفتر مانده همین حالا برود. همین جای صفِ قدیمی را گرفت.
        __strong typeof(ws) s = ws;
        if (!s) return;
        [s->_ledger flushNow];
        [s render];
    }];
    _panel.onClose = ^{ [ws finish]; };
    _panel.onPauseToggle = ^{ [ws pauseToggle]; };
    _panel.onCopyNow = ^{ [ws copyNow]; };
    _panel.onTrash = ^{ [ws dropPending]; };
    _panel.onInsertAll = ^{ [ws insertHere]; };
    _panel.onLangSwitch = ^{ [ws switchLang]; };
    _panel.onModeToggle = ^{ [ws toggleMode]; };
    _panel.onPolishNow = ^{ [ws polishCollected]; };
    if (_mode == ZModeCollect) [_panel clearEditor];
    [self applyModeChrome];
    if (![ZInjector accessibilityOK]) {
        _statusText = @"دسترسی Accessibility نیست؛ درج کار نمی‌کند، متن آخر کار کپی می‌شود";
    }
    if (ZSettings.shared.polishEnabled) [ZPolish.shared prepare];
    self.engine.delegate = self;
    [self.engine startWithLang:ZSettings.shared.lang];
    [self render];
}

// حالت فقط مقصد را عوض می‌کند و یک بولین را، نه منطق را
- (id<ZTextSink>)sinkForMode:(ZMode)m {
    if (m == ZModeCollect) return [_panel editorSink];
    _caretSink.renderPending = (m == ZModeCursor);
    _caretSink.target = _target;
    return _caretSink;
}

// ---------- ZEngineDelegate (روی نخ اصلی) ----------

- (void)engineDidUpdateCommitted:(NSString *)committed pending:(NSString *)pending {
    _enginePending = [pending copy];
    // متنِ تازه‌قطعی‌شده‌ی موتور: اول خام روی دیسک (sessions طلای تست است و خام
    // می‌ماند)، بعد وارد صفِ پاس ویرایش.
    if (committed.length > _rawSeen) {
        NSString *fresh = [[committed substringFromIndex:_rawSeen]
                           stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        _rawSeen = committed.length;
        if (fresh.length) {
            [self appendToSessionFile:fresh];
            [_awaiting addObject:fresh];
            [self drainPolish];
        }
    }
    [self sync];
}

// تنها جایی که دفتر تغذیه می‌شود. یک خط، و همان یک خط برای هر سه حالت.
- (void)sync {
    NSString *pending = ZJoinText([_awaiting componentsJoinedByString:@" "], _enginePending);
    [_ledger applyCommitted:_transcript pending:pending];
    [self render];
}

- (void)drainPolish {
    if (_polishBusy || !_awaiting.count) return;
    NSString *raw = _awaiting.firstObject;
    // حالت جمع: خام می‌نشیند در ادیتور. پاس ویرایش وسط کار روی متنی که داری ویرایشش
    // می‌کنی می‌افتد و ویرایش‌هایت را می‌شوید، پس تا خودت نخواهی (دکمه پاس) یا تا
    // لحظه‌ی درج و پایان، اجرا نمی‌شود. موقع بستن هم معطلی نداریم: خام و همین حالا.
    if (_mode == ZModeCollect || _finished || !ZSettings.shared.polishEnabled) {
        [_awaiting removeObjectAtIndex:0];
        [_transcript setString:ZJoinText(_transcript, raw)];
        [self sync];
        [self drainPolish];
        return;
    }
    _polishBusy = YES;
    NSInteger gen = _polishGen;
    __weak typeof(self) ws = self;
    [ZPolish.shared polish:raw completion:^(NSString *polished) {
        __strong typeof(ws) s = ws;
        if (!s) return;
        s->_polishBusy = NO;
        // سطل آشغال نسل را چرخانده: این جواب دیگر مالِ متنی است که کاربر دور ریخت
        if (gen != s->_polishGen) {
            [s drainPolish];
            return;
        }
        if (s->_awaiting.count) {
            [s->_awaiting removeObjectAtIndex:0];
            [s->_transcript setString:ZJoinText(s->_transcript, polished.length ? polished : raw)];
        }
        [s sync];
        [s drainPolish];
    }];
}

- (void)engineState:(ZEngineState)state message:(NSString *)msg {
    _errorState = NO;
    _listening = NO;
    _troubleState = NO;
    switch (state) {
        case ZEngineIdle: _statusText = @""; break;
        case ZEngineConnecting: _statusText = @"در حال اتصال…"; break;
        case ZEngineListening:
            _listening = YES;
            _statusText = @"دارم گوش می‌دم";   // نام زبان را پنل از مدل می‌چسباند
            break;
        case ZEngineReconnecting:
            _troubleState = YES;
            _statusText = @"اتصال ناپایدار، دوباره وصل می‌شم…";
            break;
        case ZEnginePaused: _statusText = @"مکث؛ تک‌تپ Command راست برای ادامه"; break;
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
    if (_mode == ZModeCursor) [_dot pulseLevel:rms];
    else [_panel pulseLevel:rms];
}

// ---------- اکشن‌ها ----------

// تک‌تپ Command راست: مکث/ادامه؛ بعد از خطا، تلاش دوباره
- (void)pauseToggle {
    if (_errorState) {
        _errorState = NO;
        [self.engine startWithLang:ZSettings.shared.lang];
        ZPlay(ZSoundStart);
        [self render];
        return;
    }
    if (self.engine.paused) {
        [self.engine resume];
        ZPlay(ZSoundResume);
        [_panel flash:@"ادامه"];
    } else {
        [self.engine pause];
        ZPlay(ZSoundPause);
        [_panel flash:@"مکث"];
    }
}

// کل متن سشن. در حالت جمع، متنِ ادیتور مرجع است چون کاربر آنجا ویرایشش کرده.
- (NSString *)fullText {
    if (_mode == ZModeCollect) return [_panel editorText] ?: @"";
    return [ZJoinText(_transcript, [_awaiting componentsJoinedByString:@" "])
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (void)copyNow {
    NSString *t = [self fullText];
    if (t.length) [ZInjector copyFinal:t];
    ZPlay(ZSoundCopy);
    [_panel flash:t.length
        ? [NSString stringWithFormat:@"کپی شد · %@ نویسه", ZFaDigits(@(t.length).stringValue)]
        : @"چیزی برای کپی نیست"];
}

// سطل آشغال: هرچه گفته شده و هنوز درج نشده دور می‌رود، شنیدن ادامه دارد.
// این تنها جایی است که رونوشت حق دارد کوتاه شود، و دقیقا تا جایی که واقعا درج شده.
// متنِ درج‌شده برنمی‌گردد، چون از دست ما خارج شده. `sessions/` هم خام و کامل می‌ماند:
// آن دفتر است، خروجی نیست.
- (void)dropPending {
    [self.engine dropPending];
    _enginePending = @"";
    [_awaiting removeAllObjects];
    _polishGen++;              // جوابِ دیررسِ پاسِ در پرواز نباید بعدا بنشیند
    [_ledger dropOwned];       // دُم را از روی صفحه هم بردار، اگر بشود ثابت کرد
    NSUInteger keep = _mode == ZModeCollect ? _editorStintStart : _ledger.deliveredLength;
    if (_mode == ZModeCollect) {
        // در حالت جمع هیچ‌چیز درج نشده، پس همه‌اش «درج‌نشده» است و ادیتور خالی می‌شود
        [_panel clearEditor];
    }
    if (keep < _transcript.length) {
        [_transcript deleteCharactersInRange:NSMakeRange(keep, _transcript.length - keep)];
    }
    [_ledger adoptSink:[self sinkForMode:_mode] delivered:keep];
    ZPlay(ZSoundTrash);
    [_panel flash:@"متن درج‌نشده دور ریخته شد"];
    [self sync];
}

// چرخش حالت وسط کار، بدون گم شدن متن: زنده ← جمع ← کرسر ← زنده.
// قرارداد قدیمی سر جایش است: بیرون آمدن از جمع متن را درج می‌کند یا با خودش می‌برد،
// هیچ‌وقت دور نمی‌ریزد. دور ریختن کار سطل آشغال است.
- (void)toggleMode {
    ZMode next = (ZMode)((_mode + 1) % (ZModeCursor + 1));
    NSUInteger delivered = _ledger.deliveredLength;
    if (_mode == ZModeCollect) {
        // متنِ جمع‌شده، با ویرایش‌های خودِ کاربر، می‌رود همان‌جا که داشتی می‌نوشتی و
        // یک نسخه هم در کلیپ‌بورد می‌ماند. رونوشت از همان نقطه‌ای که ادیتور شروع شده
        // بود با متنِ ویرایش‌شده جایگزین می‌شود، پس دفتر دقیقا همان را تحویل می‌دهد.
        NSString *t = [[_panel editorText] stringByTrimmingCharactersInSet:
                       NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [_panel clearEditor];
        NSUInteger cut = MIN(_editorStintStart, _transcript.length);
        [_transcript setString:ZJoinText([_transcript substringToIndex:cut], t)];
        delivered = cut;
        if (t.length) [ZInjector copyFinal:t];
    }
    _mode = next;
    ZSettings.shared.mode = next;
    if (next == ZModeCollect) _editorStintStart = delivered;
    [self applyModeChrome];
    [_ledger adoptSink:[self sinkForMode:next] delivered:delivered];
    ZPlay(ZSoundMode);
    ZLog(@"session: mode -> %@", ZModeSlug(next));
    [_panel flash:[@"حالت: " stringByAppendingString:ZModeLabel(next)]];
    [self sync];
}

// پنل و نشانگر دقیقا یکی‌شان دیده می‌شود، هیچ‌وقت هر دو: قرار حالت کرسر این است که
// هیچ‌چیز جلوی صفحه را نگیرد. نشانگر تنبل ساخته می‌شود، چون بیشتر سشن‌ها هرگز به
// این حالت نمی‌روند و ساختن یک پنجره‌ی بی‌مصرف سر هر سشن بیهوده است.
- (void)applyModeChrome {
    if (_mode == ZModeCursor) {
        [_panel hide];
        if (!_dot) _dot = [ZCaretDot new];
        [_dot show];
    } else {
        [_dot hide];
        [_panel show];
    }
}

// چرخش زبان. موتور خودش استریم را با زبان تازه ری‌استارت می‌کند و متن معلق را قبلش
// قطعی می‌کند، پس چیزی از دست نمی‌رود. پاس فارسی روی انگلیسی خودبه‌خود کنار می‌ایستد
// (هم روی زبان سشن، هم روی نبودن حرف فارسی در تکه).
- (void)switchLang {
    NSString *next = [ZSettings.shared.lang hasPrefix:@"en"] ? @"fa-IR" : @"en-US";
    ZSettings.shared.lang = next;
    [self.engine setLang:next];
    ZLog(@"session: lang -> %@", next);
    ZPlay(ZSoundLang);
    [_panel flash:[next hasPrefix:@"en"] ? @"زبان: انگلیسی" : @"زبان: فارسی"];
    [self render];
}

// متن جمع‌شده را یک بار پاس می‌دهد و بعد ادامه می‌دهد. هم دکمه‌ی پاس از این می‌رود،
// هم درج، هم پایان، پس ترتیبِ «اول پاس، بعد درج» یک جا نوشته شده و واگرا نمی‌شود.
// روی نخ پس‌زمینه، چون نسخه‌ی دسته‌ای تا ۹ ثانیه بودجه دارد و نخ اصلی نباید یخ بزند.
- (void)withPolishedCollected:(void (^)(NSString *text))done {
    NSString *raw = [_panel editorText];
    if (!ZSettings.shared.polishEnabled || !raw.length) {
        done(raw);
        return;
    }
    NSString *lang = ZSettings.shared.lang;
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *out = [ZPolish.shared polishSync:raw lang:lang];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) s = ws;
            if (!s) return;
            NSString *t = out.length ? out : raw;
            if (![t isEqualToString:raw]) {
                [s->_panel setEditorText:t];
                // ادیتور از زیر دستِ دفتر عوض شد؛ رونوشت و دفتر باید با آن هم‌تراز شوند
                NSUInteger cut = MIN(s->_editorStintStart, s->_transcript.length);
                [s->_transcript setString:ZJoinText([s->_transcript substringToIndex:cut], t)];
                [s->_ledger adoptSink:[s sinkForMode:s->_mode] delivered:s->_transcript.length];
            }
            done(t);
        });
    });
}

// دکمه‌ی پاس: فقط اعمال روی ادیتور، بی‌آن‌که چیزی درج یا بسته شود
- (void)polishCollected {
    if (_mode != ZModeCollect) return;
    [_panel flash:@"پاس ویرایش…"];
    __weak typeof(self) ws = self;
    [self withPolishedCollected:^(NSString *text) {
        __strong typeof(ws) s = ws;
        // صدا سر نشستنِ پاس، نه سر شروعش: تنها نشانه‌ی «تمام شد» همین است، چون
        // پاس روی نخ پس‌زمینه می‌رود و ممکن است چند صد میلی‌ثانیه طول بکشد.
        ZPlay(ZSoundPolish);
        [s->_panel flash:@"پاس ویرایش انجام شد"];
    }];
}

// Command راست + I یا دکمه «درج در همین اپ»: هرچه هست، سر کرسر همین اپ جلویی
- (void)insertHere {
    _target = NSWorkspace.sharedWorkspace.frontmostApplication;
    _caretSink.target = _target;
    if (_mode == ZModeCollect) {
        if (![_panel editorText].length) return;
        // I درج می‌کند ولی سشن را نمی‌بندد: ادیتور خالی می‌شود و می‌توانی ادامه بدهی.
        // بستن کار Esc است.
        __weak typeof(self) ws = self;
        [self withPolishedCollected:^(NSString *text) {
            __strong typeof(ws) s = ws;
            if (!s || !text.length) return;
            [s injectText:[text stringByAppendingString:@" "]];
            [ZInjector copyFinal:text];    // بیمه: هرچه درج شد در کلیپ‌بورد هم می‌ماند
            [s->_panel clearEditor];
            // متن رفت بیرون؛ ادیتور از صفر شروع می‌کند و دفتر هم با آن
            s->_editorStintStart = s->_transcript.length;
            [s->_ledger adoptSink:[s sinkForMode:s->_mode] delivered:s->_transcript.length];
            ZPlay(ZSoundInsert);
            [s->_panel flash:@"درج شد؛ می‌توانی ادامه بدهی"];
            [s render];
        }];
        return;
    }
    // زنده و کرسر: هرچه در دفتر مانده همین‌جا می‌رود. صدا فقط وقتی واقعا چیزی رفت،
    // وگرنه زدنش روی دفتر خالی دروغ می‌گفت. در حالت کرسر پنلی نیست که چیپ صف را
    // نشان بدهد، پس همین صدا تنها خبر است.
    BOOL had = _ledger.undelivered > 0;
    [_ledger flushNow];
    if (had && _ledger.undelivered == 0) {
        ZPlay(ZSoundInsert);
        [_panel flash:@"درج شد"];
    }
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

// ---------- پایان (Esc یا دابل‌تپ دوباره) ----------

// حالت جمع پاس ویرایش را به تعویق انداخته بود؛ سر پایان یک بار اجرا می‌شود و بعد
// تازه درج و کپی. روی نخ پس‌زمینه، چون نسخه‌ی دسته‌ای تا ۹ ثانیه بودجه دارد و نخ
// اصلی نباید آن‌قدر یخ بزند. مسیر خروج اپ عمدا از این معطلی رد نمی‌شود (finishNow):
// آنجا اپ دارد بسته می‌شود و از دست دادن پاس مهم نیست، از دست دادن متن مهم است.
- (void)finish {
    if (_finished || _finishing) return;
    if (_mode == ZModeCollect && ZSettings.shared.polishEnabled && [_panel editorText].length) {
        _finishing = YES;
        __weak typeof(self) ws = self;
        [self withPolishedCollected:^(NSString *text) {
            __strong typeof(ws) s = ws;
            if (!s) return;
            s->_finishing = NO;
            [s finishNow];
        }];
        return;
    }
    [self finishNow];
}

- (void)finishNow {
    if (_finished) return;
    _finished = YES;
    _finishing = NO;
    [self.engine stop];    // موتور قبل از بستن هرچه معلق دارد را قطعی می‌کند
    // هرچه در صف پاس مانده، بدون معطلی خام قطعی می‌شود (شرط _finished بالا)
    _polishBusy = NO;
    [self drainPolish];
    // آخرین تحویل، بی‌معطلیِ سقفِ زمانی. مقصد جلو نباشد، متن در دفتر می‌ماند و
    // کپیِ پایانی نجاتش می‌دهد.
    if (_mode != ZModeCollect) {
        [_ledger flushNow];
        if (_ledger.undelivered) {
            ZLog(@"session: %lu chars never reached the target, clipboard holds them",
                 (unsigned long)_ledger.undelivered);
        }
    } else if ([_panel editorText].length && [self targetIsFront]) {
        [self injectText:[[_panel editorText] stringByAppendingString:@" "]];
    }
    // بیمه: کل متن سشن، یک بار، ماندگار در کلیپ‌بورد؛ پشتِ صف درج که با پیست مسابقه نگیرد
    NSString *full = [self fullText];
    if (full.length) [_injector copyFinalAfterPending:full];
    ZPlay(ZSoundFinish);
    if (_frontObserver) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:_frontObserver];
    _frontObserver = nil;
    [_panel hide];
    [_dot hide];    // تایمر دنبال‌کردن کرسر همین‌جا می‌ایستد، نه یک تیک بعد
    ZLog(@"session: finished, %lu chars, ledger %@",
         (unsigned long)full.length, _ledger.stats.summary);
    ZEventLogStop();
    if (self.onFinish) self.onFinish();
}

// ---------- کمکی ----------

- (BOOL)targetIsFront {
    NSRunningApplication *f = NSWorkspace.sharedWorkspace.frontmostApplication;
    return _target && f && _target.processIdentifier == f.processIdentifier;
}

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
    // در حالت جمع، دُم خاکستری داخل ادیتور نشسته، پس نوار پایین آن را دوباره نشان
    // نمی‌دهد. در دو حالت دیگر نوار تنها جای دیدنش است.
    m.interim = _mode == ZModeCollect ? @"" : ZJoinText([_awaiting componentsJoinedByString:@" "],
                                                        _enginePending);
    m.status = _statusText;
    // چیپ صف از خودِ دفتر عدد می‌گیرد: «درج‌نشده» یعنی همان چیزی که دفتر نتوانسته
    // تحویل بدهد، نه یک شمارنده‌ی جدا که می‌تواند واگرا شود.
    m.queued = (NSInteger)_ledger.undelivered;
    m.listening = _listening;
    m.paused = self.engine.paused;
    m.error = _errorState;
    m.trouble = _troubleState;
    m.lang = ZSettings.shared.lang;
    m.mode = _mode;
    m.waitingForTarget = _mode != ZModeCollect && _ledger.undelivered > 0 && ![self targetIsFront];
    m.targetName = _target.localizedName ?: @"";
    // در حالت کرسر پنل پنهان است؛ رندر کردنش یعنی قد کشیدن و چیدن یک پنجره‌ی نادیده
    if (_mode == ZModeCursor) [_dot render:m];
    else [_panel render:m];
    // منوبار هم از همین مدل رنگ می‌گیرد؛ کانال وضعیت دومی ساخته نشده
    if (self.onModel) self.onModel(m);
}

@end
