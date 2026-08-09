// نوار شناور (پنل) و سشن تسمه‌نقاله.
#import "zemzeme.h"

// ---------- ZPanelModel ----------

@implementation ZPanelModel
- (instancetype)init {
    if ((self = [super init])) {
        _status = @"";
        _lang = @"fa-IR";
    }
    return self;
}
@end

// سبز یعنی دارد می‌شنود، قرمز یعنی اتصال مشکل دارد (قطعی موقت یا تسلیم)، نارنجی
// در حال وصل شدن، خاکستری مکث. قبلا شنیدن قرمز بود، یعنی حالت سلامت و حالت خرابی
// یک رنگ داشتند. اینجا بیرون از ZPanel نشسته چون حالت کرسر پنلی ندارد و نشانگر
// کنار کرسر باید دقیقا همین معنی‌ها را بگوید، نه کپیِ کمی متفاوتشان.
NSColor *ZStatusColor(ZPanelModel *m) {
    if (m.paused)   return NSColor.systemGrayColor;
    if (m.error)    return [NSColor colorWithRed:0.88 green:0.19 blue:0.19 alpha:1];
    if (m.listening) return [NSColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1];
    return NSColor.systemOrangeColor;
}

// ویوی ادیتور برای مقصد. داخل همین فایل می‌ماند: بیرون کسی نباید به استوریج پنل
// دست بزند، و مقصد خودش عضوِ همین‌جاست.
@interface ZPanel (ZEditorAccess)
- (NSTextView *)liveEditor;
@end

// ---------- ZPanel ----------
// نوار باریک بدون گرفتن فوکس، روی همه Space ها و فول‌اسکرین. سه دکمه بیشتر ندارد:
// بستن، مکث/ادامه، کپی. متن خاکستری تا سه خط می‌پیچد و پنل قدش را خودش تنظیم می‌کند.
// در حالت «جمع در پنل» یک ادیتور واقعی باز می‌شود: متن قطعی همان‌جا می‌نشیند،
// قابل ویرایش با کیبورد خود کاربر، و تهش با یک دکمه در اپ مقصد درج می‌شود.

static const CGFloat kPW = 500;
// دو ردیف، نه یکی. تا نسخه‌ی قبل خط وضعیت و یازده دکمه یک ردیف را شریک بودند و
// نتیجه‌اش این شد که جمله‌ی «حرفت که تمام شد…» وسطش بریده می‌شد، یعنی دقیقا همان
// جمله‌ای که تمام نسخه دو به آن بند است. حالا متن کل پهنا را دارد.
static const CGFloat kTextH = 34;     // ردیف بالا: خط وضعیت (تا دو خط) و ساعت و نشان
static const CGFloat kBtnH = 38;      // ردیف پایین: دکمه‌ها با حرف میان‌بر زیرشان
static const CGFloat kBarH = kTextH + kBtnH;
static const CGFloat kBarPad = 12;    // فاصله اولین دکمه از لبه چپ
static const CGFloat kBarStep = 28;   // گام هر دکمه (۲۴ عرض + ۴ فاصله)
static const CGFloat kGroupGap = 14;  // فاصله‌ی بین دو دسته، جای جداکننده
static const CGFloat kEditorH = 150;  // ارتفاع ادیتور حالت جمع
static const CGFloat kGripW = 30;     // دستگیرهٔ دیداری: خطِ وسطِ لبهٔ بالا
static const CGFloat kGripH = 4;
static const CGFloat kGripTop = 5;    // فاصله‌اش از لبهٔ بالا

// پس‌زمینهٔ پنل (تعریفش در zemzeme.h است، چون کارت میان‌برها هم همین را می‌خواهد):
// کشیدن از همه‌جا، جز چیزی که واقعا کلیک لازم دارد (دکمه و ادیتور). تصمیمش در
// hitTest پایین است، نه در این‌که هر ویو خودش mouseDown را بگیرد یا نه.
@implementation ZDragEffectView
- (BOOL)mouseDownCanMoveWindow { return YES; }
- (void)mouseDown:(NSEvent *)event { [self.window performWindowDragWithEvent:event]; }

// کلِ سطحِ پنل دستگیره است، هرجا که دکمه یا ادیتور نیست.
// چرا لازم شد: لیبلِ خط وضعیت (NSTextField، یعنی NSControl) کلیک را می‌بلعد و
// بیشترِ پهنای نوار را گرفته بود، پس عملا فقط از چند شکافِ باریکِ بین دکمه‌ها می‌شد
// پنل را کشید. برگرداندنِ self یعنی mouseDown همین‌جا می‌رسد و پنجره کشیده می‌شود.
// چیزی که واقعا کلیک لازم دارد دست‌نخورده می‌ماند: دکمه‌ها، و ادیتورِ حالت جمع با
// اسکرولرش (پس انتخاب متن و اسکرول سر جایشان هستند).
- (NSView *)hitTest:(NSPoint)point {
    NSView *v = [super hitTest:point];
    if (!v || v == self) return v;
    for (NSView *p = v; p && p != self; p = p.superview) {
        if ([p isKindOfClass:NSButton.class] || [p isKindOfClass:NSScrollView.class]
            || [p isKindOfClass:NSTextView.class]) return v;
    }
    return self;
}
@end

// دکمه‌ی نوار، با حرفِ میان‌برش. حرف *داخلِ* خودِ دکمه می‌نشیند، نه در آرایه‌ای موازی.
// چرا اینقدر تاکید: قبلا caps آرایه‌ی جدایی بود و چیدمان این دو را با اندیس جفت
// می‌کرد، یعنی «ترتیبِ ساختن باید همان ترتیبِ نوار باشد» یک قاعده‌ی نانوشته بود که
// کامپایلر نمی‌دیدش. دکمه‌ی حساسیت آخر ساخته شد و سومِ نوار نشست، و از آن نقطه به بعد
// همه‌ی حرف‌ها یکی جابه‌جا شدند: زیر «کپی» نوشته بود D. حالا جفت شدن ساختاری است و
// جابه‌جا کردنِ نوار هیچ‌چیزی را به هم نمی‌ریزد.
@interface ZBarButton : NSButton
@property (nonatomic, strong) NSTextField *cap;
@end

@implementation ZBarButton
@end

@implementation ZPanel {
    NSPanel *_panel;
    ZDragEffectView *_effect;
    ZMarkView *_dot;
    NSView *_grip;
    NSTextField *_text;
    NSView *_chipBg;
    NSTextField *_chipLabel;
    ZBarButton *_btnClose, *_btnPause, *_btnCopy, *_btnTrash, *_btnInsert;
    ZBarButton *_btnLang, *_btnMode, *_btnFile, *_btnHelp;
    ZBarButton *_btnSens, *_btnAI;
    NSView *_sep1, *_sep2;   // جداکننده‌ی دسته‌ها
    NSProgressIndicator *_spinner;    // جای نشان، وقتی کاری در جریان است
    NSArray<ZBarButton *> *_bar;
    NSArray<NSNumber *> *_groupEnds;  // ترتیب دکمه‌ها؛ یک منبع حقیقت برای چیدمان و پهنای متن
    ZPanelModel *_lastModel;      // برای رندر دوباره بدون سشن (فیدبک لحظه‌ای)
    NSString *_flash;             // پیام کوتاه تایید کار، چند لحظه روی خط وضعیت
    NSInteger _flashGen;
    NSScrollView *_editorScroll;
    NSTextView *_editor;
    NSTimer *_saveOriginTimer;
    BOOL _pulsing;
    BOOL _editorVisible;
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

        // چرخنده، دقیقا جای نشان. پاس نهایی ~۲۰ ثانیه طول می‌کشد و در آن فاصله هیچ
        // متنی نمی‌آید؛ پنلِ بی‌حرکت در همان لحظه بدترین حالت این فیچر است.
        _spinner = [[NSProgressIndicator alloc] initWithFrame:
            NSMakeRect(kPW - 16 - 14, (kBarH - 14) / 2, 14, 14)];
        _spinner.style = NSProgressIndicatorStyleSpinning;
        _spinner.controlSize = NSControlSizeSmall;
        _spinner.displayedWhenStopped = NO;
        [_effect addSubview:_spinner];

        // دستگیره: یک خطِ کوچکِ وسطِ لبه‌ی بالا، و فقط همین. هیچ کاری نمی‌کند و لازم هم
        // نیست بکند، چون کشیدن از همه‌جای پنل کار می‌کند (hitTest بالای همین فایل).
        // تنها کارش این است که بگوید «می‌شود جابه‌جایم کرد». قبلا کنارِ نقطه و شبیه
        // یک دکمه‌ی کوچک بود، یعنی هم شبیه دستگیره نبود هم جای درستی نبود: چشم برای
        // جابه‌جا کردنِ یک پنجره اول می‌رود بالا، نه لای دکمه‌های پایین.
        _grip = [NSView new];
        _grip.wantsLayer = YES;
        _grip.layer.cornerRadius = kGripH / 2;
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
                                 tip:@"مکث و ادامه (Command راست + Space)"
                              action:@selector(pauseTap)];
        _btnCopy = [self makeButton:@"doc.on.doc" key:@"C" tip:@"کپی متن تا اینجا"
                             action:@selector(copyTap)];
        _btnTrash = [self makeButton:@"trash" key:@"D" tip:@"دور ریختن هرچه هنوز درج نشده"
                              action:@selector(trashTap)];
        _btnLang = [self makeButton:@"globe" key:@"L" tip:@"" action:@selector(langTap)];
        _btnMode = [self makeButton:@"square.and.pencil" key:@"E" tip:@"" action:@selector(modeTap)];
        _btnInsert = [self makeButton:@"text.insert" key:@"I" tip:@"درج سر کرسر همین اپ"
                               action:@selector(insertTap)];
        // رونویسی فایل: در هر دو حالتِ پنل‌دار پیداست، چون به سشن ربطی ندارد. راه سوم
        // دسترسی است، کنار آیتم منوبار و میان‌بر، و همان یک صف را باز می‌کند.
        // حساسیت میکروفن. جایش روی نوار عمدی است: درست کنارِ نقطه‌ی ضربان و دکمه‌ی
        // مکث می‌نشیند، یعنی همان‌جا که چشمِ کاربر وقتی می‌بیند حرفش گرفته نمی‌شود
        // اول از همه می‌رود. توی منو گذاشتنش یعنی وسط دیکته باید پنل را رها کنی،
        // منوبار را باز کنی و برگردی؛ این تنظیم دقیقا آن لحظه لازم می‌شود.
        _btnSens = [self makeButton:@"ear.badge.waveform" key:@"S"
                                tip:@"حساسیت بالای میکروفن: برای پچ‌پچ و اتاق ساکت"
                             action:@selector(sensTap)];
        // پاس هوش مصنوعی: تنها دکمه‌ی نوار که یک **تنظیم** را عوض می‌کند نه یک کار
        // را، پس دسته‌ی خودش را دارد و روشن/خاموشی‌اش باید از روی خودِ دکمه دیده
        // شود، نه از منو. جای آینده‌ی تاگل‌های هم‌خانواده (استریم، پاس نگارشی) هم
        // همین‌جاست.
        _btnAI = [self makeButton:@"sparkles" key:@"A"
                              tip:@"" action:@selector(aiTap)];
        _btnFile = [self makeButton:@"arrow.up.doc" key:@"F"
                                tip:@"رونویسی فایل صوتی: صف، پیشرفت و متن یکجا (Command راست + F)"
                             action:@selector(fileTap)];
        // در نسخه دو یک تک‌تپ Command راست یعنی پایان سشن، نه مکث؛ کاربر باید همین را
        // از جایی بداند وگرنه فکر می‌کند اپ گیر کرده. کارت راهنما تنها جایی است که
        // این را می‌گوید، پس باید از خودِ پنل هم در دسترس باشد، نه فقط از منوبار.
        _btnHelp = [self makeButton:@"questionmark.circle" key:@"H"
                                tip:@"راهنمای میان‌برها (Command راست + H)"
                             action:@selector(helpTap)];
        _btnInsert.hidden = YES;
        // سه دسته، و ترتیبشان معنی دارد: اول کارهایی که وسط دیکته لازم می‌شوند،
        // بعد تنظیم‌های کم‌استفاده، و آخر فیچرهایی که تاگل‌اند. یازده آیکون در یک
        // ردیفِ بی‌فاصله فقط یک دیوار است و کاربر هیچ‌کدام را پیدا نمی‌کند.
        // layoutViews از همین یک لیست می‌خواند، پس پیدا و ناپیدا شدن دکمه‌ها
        // هیچ‌وقت با عدد هاردکد ناهمخوان نمی‌شود.
        _bar = @[_btnClose, _btnPause, _btnCopy, _btnInsert, _btnTrash,
                 _btnLang, _btnMode, _btnSens, _btnFile, _btnHelp,
                 _btnAI];
        _groupEnds = @[@4, @9];      // اندیس آخرین دکمه‌ی هر دسته
        _sep1 = [NSView new]; _sep1.wantsLayer = YES; [_effect addSubview:_sep1];
        _sep2 = [NSView new]; _sep2.wantsLayer = YES; [_effect addSubview:_sep2];

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

// آیکون + حرف میان‌بر ریز زیرش، و حرف به خودِ همین دکمه چسبیده. تولتیپ روی این پنل
// هیچ‌وقت ظاهر نمی‌شود (پنل nonactivating است و اپ اکسسوری، پس مک تولتیپ را نمی‌کشد)،
// پس میان‌بر باید خودش روی نوار نوشته باشد.
- (ZBarButton *)makeButton:(NSString *)symbol key:(NSString *)key
                       tip:(NSString *)tip action:(SEL)action {
    ZBarButton *b = [self makeButton:symbol tip:tip action:action];
    NSTextField *cap = [NSTextField labelWithString:key];
    cap.font = [NSFont monospacedDigitSystemFontOfSize:8 weight:NSFontWeightMedium];
    cap.textColor = NSColor.tertiaryLabelColor;
    cap.alignment = NSTextAlignmentCenter;
    [_effect addSubview:cap];
    b.cap = cap;
    return b;
}

- (ZBarButton *)makeButton:(NSString *)symbol tip:(NSString *)tip action:(SEL)action {
    NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip];
    img = [img imageWithSymbolConfiguration:
           [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightMedium]];
    ZBarButton *b = [ZBarButton buttonWithImage:img ?: [NSImage new] target:self action:action];
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
    // نوار پایینِ پنل دو ردیف دارد و ترتیبشان عمدی است: **دکمه‌ها بالا، خط وضعیت
    // زیرشان.** اول برعکس بود و خط وضعیت می‌رفت لای دستگیره‌ی بالای پنل، هم زشت
    // بود هم شبیه بخشی از قاب. پایین بودنش یعنی یک نوارِ مخصوصِ خودش: جای فیدبک و
    // آموزش، جدا از کنترل‌ها.
    CGFloat btnY = kTextH;      // ردیف دکمه‌ها از بالای ردیف متن شروع می‌شود
    CGFloat left = kBarPad;
    NSInteger i = 0, sep = 0;
    NSView *seps[2] = {_sep1, _sep2};
    for (ZBarButton *b in _bar) {
        b.cap.hidden = b.hidden;
        if (!b.hidden) {
            b.frame = NSMakeRect(left, btnY + 12, 24, 24);
            b.cap.frame = NSMakeRect(left - 3, btnY + 1, 30, 10);
            left += kBarStep;
        }
        if (sep < 2 && i == _groupEnds[sep].integerValue) {
            seps[sep].frame = NSMakeRect(left + kGroupGap / 2 - 1, btnY + 13, 1, 20);
            left += kGroupGap;
            sep++;
        }
        i++;
    }
    // ساعت و نشان هم‌ردیفِ دکمه‌ها می‌مانند، سمت راست، تا کلِ پهنای ردیف پایین
    // برای متن آزاد بماند. همین یک تصمیم بود که جمله‌ی «حرفت که تمام شد…» را از
    // بریده شدن نجات داد.
    _dot.frame = NSMakeRect(kPW - 16 - 9 * ZMarkAspect, btnY + 17, 9 * ZMarkAspect, 9);
    _spinner.frame = NSMakeRect(kPW - 16 - 14, btnY + 15, 14, 14);
    if (!_chipBg.hidden) {
        NSRect f = _chipBg.frame;
        f.origin = NSMakePoint(_dot.frame.origin.x - f.size.width - 10, btnY + 13);
        _chipBg.frame = f;
    }
    _text.frame = NSMakeRect(kBarPad, 4, kPW - 2 * kBarPad, kTextH - 7);
    // دستگیره وسطِ لبه‌ی بالا می‌نشیند، پس با قد کشیدنِ پنل با آن بالا می‌رود
    _grip.frame = NSMakeRect((kPW - kGripW) / 2, H - kGripTop - kGripH, kGripW, kGripH);
    if (_editorVisible) {
        _editorScroll.frame = NSMakeRect(12, kBarH, kPW - 24, H - kBarH - 10);
    }
}

- (void)applyColors {
    _effect.layer.borderColor = [NSColor.labelColor colorWithAlphaComponent:0.12].CGColor;
    _chipBg.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.08].CGColor;
    // CGColor مثل بقیه‌ی رنگ‌های لایه‌ای اینجا، نه NSColor: با عوض شدن روشن و تاریک
    // خودش به‌روز نمی‌شود، پس از همین یک نقطه دوباره ساخته می‌شود
    _grip.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.25].CGColor;
    CGColorRef line = [NSColor.labelColor colorWithAlphaComponent:0.14].CGColor;
    _sep1.layer.backgroundColor = line;
    _sep2.layer.backgroundColor = line;
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

- (void)setEditorVisible:(BOOL)on {
    if (on) [self ensureEditor];
    if (_editorVisible == on) return;
    _editorVisible = on;
    _editorScroll.hidden = !on;
    // پیدا و ناپیدا شدن دکمه‌ها را render می‌گذارد، یک جا، که دو منبع حقیقت نشود
    [self resizeTo:on ? kBarH + kEditorH : kBarH];
}

// ویوی ادیتور، ساخته‌شده. مقصدِ متن از همین می‌خواند.
- (NSTextView *)liveEditor {
    [self ensureEditor];
    return _editor;
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

// دقیقه و ثانیه، با ارقام فارسی. حالت یادداشت متنی برای نشان دادن ندارد، پس همین
// عدد تنها مدرکِ «ضبط دارد جلو می‌رود» است.
static NSString *ZClock(NSTimeInterval sec) {
    int s = (int)(sec + 0.5);
    return ZFaDigits([NSString stringWithFormat:@"%02d:%02d", s / 60, s % 60]);
}

- (void)render:(ZPanelModel *)m {
    _lastModel = m;
    // ادیتور فقط در حالت جمع باز است؛ حالت کرسر پنل را اصلا نشان نمی‌دهد و متن
    // مستقیم سر کرسر می‌نشیند، نه اینجا.
    BOOL collect = m.mode == ZModeCollect;
    BOOL editor = collect;
    [self setEditorVisible:editor];

    // زبان روی همان دکمه دیده می‌شود: آیکون یکی است و تولتیپ می‌گوید الان کدام زبان
    // است و زدنش چه می‌کند. متن روی دکمه نمی‌گذاریم که ردیف یک‌دست بماند.
    BOOL en = [m.lang hasPrefix:@"en"];
    _btnLang.toolTip = en ? @"زبان: انگلیسی. برای رفتن به فارسی بزن (Command راست + L)"
                          : @"زبان: فارسی. برای رفتن به انگلیسی بزن (Command راست + L)";
    // آیکون حالت، همان چیزی که با زدنش می‌گیری: چرخش دوتایی و ساده، جمع ↔ کرسر.
    ZMode next = collect ? ZModeCursor : ZModeCollect;
    [self setButton:_btnMode symbol:next == ZModeCursor ? @"text.cursor" : @"square.and.pencil"];
    _btnMode.toolTip = next == ZModeCursor
        ? @"رفتن به حالت کنار کرسر: پنل می‌رود و فقط یک نقطه می‌ماند (Command راست + E)"
        : @"رفتن به جمع در پنل: متن اینجا می‌نشیند و قابل ویرایش است (Command راست + E)";

    // سشن که تمام شد (در بازبینی، یا وسط کارِ پایانی) دکمه‌های شنیدن معنا ندارند؛
    // دکمه‌های متن می‌مانند. نشان دادنِ دکمه‌ای که کار نمی‌کند، دروغ است.
    // حساسیت: آیکون خودش حالت را می‌گوید، مثل بقیه‌ی دکمه‌های این نوار. گوشِ ساده
    // یعنی عادی، گوشِ پر یعنی حساسیت بالا روشن است.
    BOOL sens = ZSettings.shared.highSensitivity;
    [self setButton:_btnSens symbol:sens ? @"ear.fill" : @"ear.badge.waveform"];
    _btnSens.toolTip = sens
        ? @"حساسیت بالا روشن است: صدای آرام تا حد زیادی بزرگ می‌شود. برای برگشتن بزن "
           "(Command راست + S)"
        : @"حساسیت بالای میکروفن: برای پچ‌پچ کردن و اتاق ساکت، یا میکروفنی که صدایش "
           "کم می‌رسد (Command راست + S)";

    // پاس هوش مصنوعی: روشن/خاموشی از روی خودِ دکمه دیده می‌شود، نه از منو. رنگ
    // می‌گیرد یعنی روشن است. بی‌کلید هم روشن نمی‌شود و تولتیپ همان را می‌گوید.
    BOOL ai = ZSettings.shared.finalPassEnabled;
    BOOL key = ZFinalPass.hasKey;
    _btnAI.contentTintColor = ai ? (key ? NSColor.systemBlueColor : NSColor.systemOrangeColor) : nil;
    _btnAI.toolTip = !key
        ? @"پاس هوش مصنوعی: کلید جمینای نیست. از منوی زمزمه «کلید Gemini…» را بزن (A)"
        : ai ? @"پاس هوش مصنوعی روشن است: سر پایان، متن برای فرمتینگ و اصلاح واژه‌های "
                "غلط به جمینای می‌رود. صدا هیچ‌وقت فرستاده نمی‌شود. برای خاموش کردن بزن (A)"
             : @"پاس هوش مصنوعی خاموش است: متن خامِ تشخیص گفتار تحویل می‌شود. برای "
                "روشن کردن بزن (A)";

    BOOL over = m.review || m.working;
    _btnPause.hidden = over;
    _btnMode.hidden = over;
    _btnLang.hidden = over;
    _btnSens.hidden = over;
    _btnClose.toolTip = m.working ? @"لغو؛ صدا سر جایش می‌ماند (Esc)"
                      : m.review ? @"بستن (Esc)" : @"پایان و درج همه (Esc)";
    _btnTrash.toolTip = m.working ? @"لغو و پاک کردن صدا و متن (D)"
                      : @"دور ریختن هرچه هنوز درج نشده، و صدای ضبط‌شده (D)";
    _btnInsert.hidden = !editor || m.working;

    // چیپ: فقط ساعتِ ضبط، و در هر سشنِ زنده‌ای نشان داده می‌شود، نه فقط یک حالت خاص.
    // ساعتِ دورِ فعلی، درشت. و اگر دورِ قبلی‌ای بوده، مجموع کنارش و ریزتر: کاربر
    // باید بداند الان چقدر حرف زده، نه فقط اینکه روی هم چقدر شده.
    NSString *chip = m.elapsed > 0 ? ZClock(m.elapsed) : @"";
    if (chip.length && m.elapsedTotal > m.elapsed + 1) {
        chip = [chip stringByAppendingFormat:@"  ﹒%@", ZClock(m.elapsedTotal)];
    } else if (!chip.length && m.elapsedTotal > 0) {
        chip = ZClock(m.elapsedTotal);
    }
    if (!chip.length) {
        _chipBg.hidden = YES;
    } else {
        _chipBg.hidden = NO;
        _chipLabel.stringValue = chip;
        [_chipLabel sizeToFit];
        CGFloat w = _chipLabel.frame.size.width + 16;
        _chipBg.frame = NSMakeRect(0, 0, w, 18);   // جایش را layoutViews می‌گذارد
        _chipLabel.frame = NSMakeRect(8, 0, w - 16, 17);
    }

    // اولویت خط وضعیت: کاری در جریان (پاس نهایی…) از همه مهم‌تر، بعد فیدبک لحظه‌ای
    // دکمه (کپی شد، زبان عوض شد…)، وگرنه وضعیت ساده. نسخه دو هیچ متن میانی‌ای ندارد
    // که با این‌ها رقابت کند؛ همین یک خط کوتاه همیشه کافی است.
    if (m.working && m.workingMsg.length) {
        // کاری در جریان (پاس نهایی): پیام مرحله بر همه‌چیز مقدم است، چون تنها خبرِ
        // زنده‌ای است که در آن بیست ثانیه وجود دارد.
        _text.stringValue = m.workingMsg;
        _text.font = ZFont(12.5, YES);
        _text.textColor = NSColor.secondaryLabelColor;
    } else if (_flash.length) {
        _text.stringValue = _flash;
        _text.font = ZFont(12.5, YES);
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

    // نشان و چرخنده یک جا می‌نشینند و هیچ‌وقت هر دو دیده نمی‌شوند: تا کاری در جریان
    // است چرخنده حرف می‌زند، بعدش نشان.
    _dot.hidden = m.working;
    if (m.working) [_spinner startAnimation:nil];
    else [_spinner stopAnimation:nil];

    [self resizeTo:editor ? kBarH + kEditorH : kBarH];
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
- (void)insertTap { if (self.onInsertAll) self.onInsertAll(); }
- (void)fileTap { if (self.onFilePanel) self.onFilePanel(); }
- (void)sensTap { if (self.onSensToggle) self.onSensToggle(); }
- (void)helpTap { if (self.onHelp) self.onHelp(); }
- (void)aiTap { if (self.onAIToggle) self.onAIToggle(); }

// اسکرین‌شات برای بازبینی طراحی (بدون نیاز به اجازه ضبط صفحه)
- (void)makeShots:(NSString *)dir {
    ZPanelModel *listening = [ZPanelModel new];
    listening.status = @"دارم گوش می‌کنم";
    listening.listening = YES;

    ZPanelModel *paused = [ZPanelModel new];
    paused.status = @"مکث؛ تک‌تپ Command راست برای ادامه";
    paused.paused = YES;

    ZPanelModel *error = [ZPanelModel new];
    error.status = @"شبکه ناپایداره؛ دکمه تلاش دوباره یا تک‌تپ Command راست";
    error.error = YES;

    // بازبینی: سشن تمام شده و متن نهایی در ادیتور نشسته
    ZPanelModel *review = [ZPanelModel new];
    review.mode = ZModeCollect;
    review.review = YES;
    review.status = @"متن نهایی نشست و در کلیپ‌بورد هم هست";

    NSArray *states = @[@[@"listening", listening], @[@"paused", paused],
                        @[@"error", error], @[@"review", review]];
    [_panel orderFrontRegardless];
    for (NSArray *pair in states) {
        ZPanelModel *m = pair[1];
        [self clearEditor];
        if (m.review) {
            [self setEditorText:@"متن قطعی‌شده اینجا جمع می‌شود و با کیبورد خودت قابل ویرایش است. "
                                @"تهش با دکمه درج، یکجا سر کرسر می‌نشیند."];
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
    [self setEditorVisible:NO];
    [_panel orderOut:nil];
}

@end

