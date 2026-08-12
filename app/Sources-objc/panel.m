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
// در حالت «جمع در پنل» یک ادیتور واقعی باز می‌شود: متن قطعی همان‌جا می‌نشیند، با یک
// کلیک روی متن قابل ویرایش با کیبورد خودِ کاربر می‌شود (پنل با **آمدنش** فوکوس
// نمی‌گیرد، فقط با همان کلیک؛ ZPanelWindow پایین‌تر)، و تهش با یک دکمه در اپ مقصد
// درج می‌شود.

// ۵۲۸ و نه ۵۰۰: دکمه‌ی تاریخچه که آمد، ردیف دکمه‌ها تا نزدیکِ نشان و ساعت می‌رسید.
// یک گامِ دکمه پهن‌تر شد تا آن فاصله همان که بود بماند؛ بقیه‌ی چیدمان از همین عدد
// حساب می‌شود، پس جای هیچ‌چیز دیگری دستی درست نشد.
static const CGFloat kPW = 528;
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
// ---------- پنجره‌ی پنل ----------
// **چرا این کلاس لازم شد:** ادیتورِ حالت «جمع در پنل» فوکوس نمی‌گرفت و کاربر
// نمی‌توانست متن را ویرایش کند، در حالی که خودِ NSTextView از اول editable بود.
// دلیلش یک پیش‌فرضِ AppKit است: `canBecomeKeyWindow` برای پنجره‌ی borderless پیش‌فرض
// NO برمی‌گرداند. پس `becomesKeyOnlyIfNeeded` هیچ‌وقت شانسِ کارکردن نداشت، پنل
// هیچ‌وقت پنجره‌ی کلید نمی‌شد، و فوکوس به ادیتور نمی‌رسید.
//
// `becomesKeyOnlyIfNeeded = YES` سرِ جایش می‌ماند و همان چیزی است که این را بی‌خطر
// می‌کند: پنل با **آمدنش** کلید نمی‌شود، فقط وقتی کاربر روی ویویی کلیک کند که واقعا
// کیبورد لازم دارد، یعنی همین ادیتور. دکمه‌های نوار کیبورد لازم ندارند، پس زدنشان
// فوکوس را از اپ مقصد نمی‌کند.
//
// و nonactivating هم سرِ جایش: پنل کلید می‌شود بی آنکه **اپ** فعال شود، پس
// `frontmostApplication` همان اپ مقصد می‌ماند و ادعایی که flick_test می‌سنجد
// («اپ فعال نمی‌شود») دست‌نخورده است.
@implementation ZPanelWindow
- (BOOL)canBecomeKeyWindow { return YES; }
@end

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

// ---------- نشانِ «دارم کار می‌کنم» ----------
// دو انتظار داریم و شکلشان باید فرق کند، چون کاربر باید بی‌خواندنِ خط وضعیت بفهمد
// منتظر چیست: انتظارِ چندثانیه‌ایِ خودِ دیکته، یا انتظارِ تا ~۲۰ ثانیه‌ایِ یک تنظیمِ
// اختیاری که می‌شود اصلا خاموشش کرد. یک چرخنده‌ی خاکستری برای هر دو، این را نمی‌گفت.
//
// پس هرکدام شکلِ کارِ خودش را دارد:
//   صدا←متن:  سه میله‌ی صدا که بالا و پایین می‌روند، همان سه میله‌ی نشانِ خودِ زمزمه
//   پاس هوش مصنوعی:  سه جرقه که پشت سر هم روشن و خاموش می‌شوند، همان آیکون دکمه‌ی A
// و رنگ هم همین را دوباره می‌گوید: نارنجی (همان رنگِ «در حال کار» در ZStatusColor) و
// آبی (همان رنگی که دکمه‌ی A روشن که باشد می‌گیرد).
@interface ZBusyView : NSView
@property (nonatomic) ZBusy mode;
@end

// یک جرقه‌ی چهارپر. قوس‌ها با کنترل‌پوینتِ نزدیک به مرکز کشیده می‌شوند، پس پرها
// مقعرند و شکل واقعا «جرقه» درمی‌آید نه لوزی.
static NSBezierPath *ZSparkPath(NSPoint c, CGFloat r) {
    CGFloat k = r * 0.22;
    NSBezierPath *p = [NSBezierPath bezierPath];
    NSPoint tip[4] = {{c.x, c.y + r}, {c.x + r, c.y}, {c.x, c.y - r}, {c.x - r, c.y}};
    NSPoint ctl[4] = {{c.x + k, c.y + k}, {c.x + k, c.y - k},
                      {c.x - k, c.y - k}, {c.x - k, c.y + k}};
    [p moveToPoint:tip[0]];
    for (int i = 0; i < 4; i++) {
        [p curveToPoint:tip[(i + 1) % 4] controlPoint1:ctl[i] controlPoint2:ctl[i]];
    }
    [p closePath];
    return p;
}

@implementation ZBusyView {
    NSTimer *_tick;
    double _phase;
}

- (void)setMode:(ZBusy)m {
    if (_mode == m) return;
    _mode = m;
    _phase = 0;
    self.hidden = (m == ZBusyNone);
    if (m == ZBusyNone) {
        [_tick invalidate];
        _tick = nil;
        return;
    }
    if (_tick) return;
    __weak typeof(self) ws = self;
    _tick = [NSTimer timerWithTimeInterval:1.0 / 30 repeats:YES block:^(NSTimer *t) {
        typeof(self) me = ws;
        if (!me) return;
        me->_phase += 0.13;
        me.needsDisplay = YES;
    }];
    // common modes: وسط کشیدنِ پنل هم باید بچرخد، وگرنه نشان دقیقا وقتی می‌ایستد که
    // کاربر دارد پنل را جابه‌جا می‌کند تا بهتر ببیندش.
    [NSRunLoop.currentRunLoop addTimer:_tick forMode:NSRunLoopCommonModes];
}

- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds;
    if (_mode == ZBusySpeech) {
        // سه میله، با فازِ ۱۲۰ درجه‌ای. هیچ‌وقت به صفر نمی‌رسند: میله‌ی ناپدید یعنی
        // نشانِ نصفه، و آدم فکر می‌کند چیزی گیر کرده.
        [[NSColor.systemOrangeColor colorWithAlphaComponent:0.95] set];
        CGFloat w = 3, gap = 2.5;
        CGFloat x = (b.size.width - (3 * w + 2 * gap)) / 2;
        for (int i = 0; i < 3; i++) {
            double f = 0.5 + 0.5 * sin(_phase + i * 2.094);
            CGFloat h = b.size.height * (0.34 + 0.66 * f);
            NSRect r = NSMakeRect(x + i * (w + gap), (b.size.height - h) / 2, w, h);
            [[NSBezierPath bezierPathWithRoundedRect:r xRadius:w / 2 yRadius:w / 2] fill];
        }
        return;
    }
    if (_mode != ZBusyPolish) return;
    // سه جرقه با اندازه و فازِ متفاوت: یکی بزرگ و دو تای ریز، پس چشم یک «درخشش»
    // می‌بیند نه سه چیزِ هم‌وزن که با هم چشمک بزنند.
    CGFloat s = MIN(b.size.width, b.size.height);
    struct { CGFloat x, y, r, ph; } sp[3] = {
        {0.38, 0.42, 0.30, 0.0},
        {0.76, 0.74, 0.17, 2.1},
        {0.78, 0.24, 0.13, 4.2},
    };
    for (int i = 0; i < 3; i++) {
        double f = 0.5 + 0.5 * sin(_phase * 1.6 + sp[i].ph);
        CGFloat r = s * sp[i].r * (0.55 + 0.45 * f);
        [[NSColor.systemBlueColor colorWithAlphaComponent:0.35 + 0.65 * f] set];
        [ZSparkPath(NSMakePoint(b.origin.x + b.size.width * sp[i].x,
                                b.origin.y + b.size.height * sp[i].y), r) fill];
    }
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
    NSTextField *_previewTag;     // سرنویسِ کوچکِ بالای ادیتور، فقط وقتی دُم خاکستری هست
    ZBarButton *_btnClose, *_btnPause, *_btnCopy, *_btnTrash, *_btnInsert;
    ZBarButton *_btnLang, *_btnMode, *_btnFile, *_btnHistory, *_btnHelp;
    ZBarButton *_btnSens, *_btnAI, *_btnSecond, *_btnPreview;
    NSView *_sep1, *_sep2;   // جداکننده‌ی دسته‌ها
    ZBusyView *_busy;                 // جای نشان، وقتی کاری در جریان است
    NSArray<ZBarButton *> *_bar;
    NSArray<NSNumber *> *_groupEnds;  // ترتیب دکمه‌ها؛ یک منبع حقیقت برای چیدمان و پهنای متن
    ZPanelModel *_lastModel;      // برای رندر دوباره بدون سشن (فیدبک لحظه‌ای)
    NSString *_flash;             // پیام کوتاه تایید کار، چند لحظه روی خط وضعیت
    NSInteger _flashGen;
    NSScrollView *_editorScroll;
    NSTextView *_editor;
    NSString *_wroteText;         // آخرین متنی که **ما** در ادیتور نوشتیم؛ مرجعِ editorTouched
    // دُمِ پیش‌نمایش: کجا شروع می‌شود، و **عینا** چه چیزی نوشتیم. دومی مدرکِ «کاربر
    // دست نزده» است و بی آن، هر نوشتنِ تازه می‌توانست تایپِ خودِ کاربر را پاک کند.
    NSUInteger _previewLoc;
    NSString *_previewText;
    BOOL _previewGaveUp;          // کاربر در دُم تایپ کرد: تا نوشتنِ کاملِ بعدی دست نگه دار
    NSTimer *_saveOriginTimer;
    BOOL _pulsing;
    BOOL _editorVisible;
    NSPoint _wantOrigin;         // جای انتخابی کاربر؛ قد کشیدن پنل جابه‌جایش نمی‌کند
    BOOL _haveWantOrigin;
    BOOL _resizing;
}

- (instancetype)init {
    if ((self = [super init])) {
        _panel = [[ZPanelWindow alloc] initWithContentRect:NSMakeRect(0, 0, kPW, kBarH)
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

        // نشانِ کار، دقیقا جای نشانِ زمزمه. هر دو انتظار در همین یک نقطه می‌نشینند، پس
        // چشم برای فهمیدنِ «الان منتظر چی هستم» جای تازه‌ای یاد نمی‌گیرد؛ فقط شکل و
        // رنگش عوض می‌شود. پنلِ بی‌حرکت در آن ~۲۰ ثانیه بدترین حالت ممکن است.
        _busy = [[ZBusyView alloc] initWithFrame:
            NSMakeRect(kPW - 16 - 15, (kBarH - 15) / 2, 15, 15)];
        _busy.hidden = YES;
        [_effect addSubview:_busy];

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

        // سرنویسِ دُم خاکستری. «خام» به‌تنهایی کافی نبود: کاربر غلط را می‌دید و باز
        // نمی‌دانست تکلیفش چیست. پس این خط سه کار می‌کند و هر سه لازم‌اند: می‌گوید
        // بتاست، می‌گوید **نگرانِ غلط‌هایش نباش**، و می‌گوید متنِ درست کِی می‌آید.
        // بی جمله‌ی دوم، هر غلطِ استریم یک لحظه اعتماد کاربر به کلِ رونویسی را می‌خورد.
        _previewTag = [NSTextField labelWithString:
            @"پیش‌نمایش (بتا) ﹒ نگرانِ غلط‌هایش نباش، متن درست سر پایان می‌آید"];
        _previewTag.font = ZFont(10.5, NO);
        _previewTag.textColor = NSColor.tertiaryLabelColor;
        _previewTag.alignment = NSTextAlignmentRight;
        _previewTag.hidden = YES;
        [_effect addSubview:_previewTag];

        // همه‌ی دکمه‌ها آیکون‌اند و یک اندازه، و هر تولتیپ حرف میان‌بر خودش را می‌گوید.
        // میان‌بر هر کدام «Command راست + همان حرف» است، و تنها همان.
        _btnClose = [self makeButton:@"xmark" key:@"esc" tip:@"پایان دیکته و درج متن (Esc)"
                              action:@selector(closeTap)];
        _btnPause = [self makeButton:@"pause.fill" key:@"⌘"
                                 tip:@"بایست و متن تا اینجا را تحویل بده"
                              action:@selector(pauseTap)];
        _btnCopy = [self makeButton:@"doc.on.doc" key:@"C" tip:@"کپی متن تا اینجا"
                             action:@selector(copyTap)];
        _btnTrash = [self makeButton:@"trash" key:@"D" tip:@"دور ریختن هرچه هنوز درج نشده"
                              action:@selector(trashTap)];
        _btnLang = [self makeButton:@"globe" key:@"L" tip:@"" action:@selector(langTap)];
        _btnMode = [self makeButton:@"square.and.pencil" key:@"E" tip:@"" action:@selector(modeTap)];
        _btnInsert = [self makeButton:@"text.insert" key:@"I" tip:@"درج متن سر کرسر، در برنامه‌ای که پشت پنل است"
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
        // دو زبانه: همان صدا، هم‌زمان انگلیسی هم شنیده می‌شود. تاگل است، پس کنار آن
        // دو تای دیگر و با همان قاعده: روشن که باشد رنگ می‌گیرد.
        _btnSecond = [self makeButton:@"character.book.closed" key:@"B"
                                  tip:@"" action:@selector(secondTap)];
        // پیش‌نمایش: چهارمین تاگل. زیرنویس، دقیقا همان چیزی که می‌گیری. جایش کنار دو
        // تاگلِ شنیدن و قبل از تاگلِ متن است، چون کارش نه شنیدن است نه عوض کردنِ متن:
        // فقط زودتر نشان دادنِ همان متن.
        _btnPreview = [self makeButton:@"captions.bubble" key:@"P"
                                   tip:@"" action:@selector(previewTap)];
        _btnFile = [self makeButton:@"arrow.up.doc" key:@"F"
                                tip:@"رونویسی فایل صوتی: چند فایل پشت هم، با متن قابل ویرایش (Command راست + F)"
                             action:@selector(fileTap)];
        // در نسخه دو یک تک‌تپ Command راست یعنی پایان سشن، نه مکث؛ کاربر باید همین را
        // از جایی بداند وگرنه فکر می‌کند اپ گیر کرده. کارت راهنما تنها جایی است که
        // این را می‌گوید، پس باید از خودِ پنل هم در دسترس باشد، نه فقط از منوبار.
        // تاریخچه: کنار «فایل» و «راهنما» می‌نشیند چون مثل آن دو به سشن ربطی ندارد
        // و بی‌سشن هم باز می‌شود. اصلا بیشترِ وقت‌ها همان‌جا لازم می‌شود: کسی که
        // متنش را گم کرده، دیگر سشنی ندارد.
        _btnHistory = [self makeButton:@"clock.arrow.circlepath" key:@"T"
                                   tip:@"تاریخچه: بیست متن آخر، با درج و کپی (Command راست + T)"
                                action:@selector(historyTap)];
        _btnHelp = [self makeButton:@"questionmark.circle" key:@"H"
                                tip:@"راهنمای میان‌برها (Command راست + H)"
                             action:@selector(helpTap)];
        _btnInsert.hidden = YES;
        // سه دسته، و ترتیبشان معنی دارد: اول کارهایی که وسط دیکته لازم می‌شوند،
        // بعد تنظیم‌های کم‌استفاده، و آخر فیچرهایی که تاگل‌اند. یازده آیکون در یک
        // ردیفِ بی‌فاصله فقط یک دیوار است و کاربر هیچ‌کدام را پیدا نمی‌کند.
        // layoutViews از همین یک لیست می‌خواند، پس پیدا و ناپیدا شدن دکمه‌ها
        // هیچ‌وقت با عدد هاردکد ناهمخوان نمی‌شود.
        // دسته‌ی سوم مالِ **تاگل‌ها**ست، نه فقط پاس هوش مصنوعی: حساسیت میکروفن و
        // شنیدنِ دوزبانه هم تاگل‌اند و جایشان کنار همان است، نه لای تنظیم‌های لحظه‌ای.
        // هر سه هم وقتی روشن‌اند رنگ می‌گیرند، پس از روی نوار معلوم است چه چیزی فعال است.
        // ترتیب داخل همین دسته: اول دو تاگلِ **شنیدن** (حساسیت، دوزبانه) و بعد تاگلِ
        // **متن** (هوش مصنوعی). آخر بودنِ A تصادفی نیست: در منو کلید Gemini درست زیر
        // همین ردیف می‌نشیند، و اگر A وسط می‌ماند آن کلید صفِ تاگل‌ها را می‌شکست.
        _bar = @[_btnClose, _btnPause, _btnCopy, _btnInsert, _btnTrash,
                 _btnLang, _btnMode, _btnFile, _btnHistory, _btnHelp,
                 _btnSens, _btnSecond, _btnPreview, _btnAI];
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
    _busy.frame = NSMakeRect(kPW - 16 - 15, btnY + 14, 15, 15);
    if (!_chipBg.hidden) {
        NSRect f = _chipBg.frame;
        f.origin = NSMakePoint(_dot.frame.origin.x - f.size.width - 10, btnY + 13);
        _chipBg.frame = f;
    }
    _text.frame = NSMakeRect(kBarPad, 4, kPW - 2 * kBarPad, kTextH - 7);
    // دستگیره وسطِ لبه‌ی بالا می‌نشیند، پس با قد کشیدنِ پنل با آن بالا می‌رود
    _grip.frame = NSMakeRect((kPW - kGripW) / 2, H - kGripTop - kGripH, kGripW, kGripH);
    if (_editorVisible) {
        // سرنویسِ پیش‌نمایش بالای ادیتور می‌نشیند و جایش را از قدِ ادیتور می‌گیرد، نه
        // از قدِ پنل: نبودنش نباید پنل را یک نوارِ خالی بلندتر کند.
        CGFloat tag = _previewTag.hidden ? 0 : 15;
        _previewTag.frame = NSMakeRect(16, H - 10 - tag, kPW - 32, tag);
        _editorScroll.frame = NSMakeRect(12, kBarH, kPW - 24, H - kBarH - 10 - tag);
    } else {
        _previewTag.hidden = YES;
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

// کلید را پس بده، وگرنه پیست در همین پنل می‌نشیند. توضیح کامل در هدر.
//
// چرا orderOut و بعد orderFrontRegardless و نه یک متد تک‌خطی: AppKit راهِ مستقیمی
// برای «کلید نباش» نمی‌دهد؛ `resignKeyWindow` یک اطلاع است نه یک دستور. بیرون بردن
// پنجره کلید را پس می‌دهد و مک آن را به اپِ جلو (همان مقصد) برمی‌گرداند، و برگشتنِ
// بی‌درنگ هم پنل را کلید نمی‌کند چون becomesKeyOnlyIfNeeded فقط با کلیک روی ادیتور
// کلید می‌دهد. سریع است و در همان فریم تمام می‌شود.
- (void)yieldKey {
    if (!_panel.isKeyWindow) return;
    [_panel makeFirstResponder:nil];
    [_panel orderOut:nil];
    [_panel orderFrontRegardless];
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

// **کپی، نه خودِ رشته.** `NSTextView.string` رشته‌ی زنده‌ی پشتِ NSTextStorage را
// می‌دهد، نه یک عکسِ لحظه‌ای: هر کس این را نگه دارد و بعدا بخواند، محتوای *همان
// لحظه* را می‌بیند نه محتوای وقت گرفتن. و سرِ Esc، `clearEditor` ادیتور را خالی
// می‌کند، پس هر خواننده‌ی معوقی رشته‌ی خالی می‌گرفت.
//
// هزینه‌اش را کاربر داد: کپیِ پایانیِ کلیپ‌بورد پشتِ صفِ درج می‌نشیند، یعنی حدود یک
// ثانیه بعد. تا آن لحظه پنل بسته و ادیتور خالی شده بود، و کلیپ‌بورد به‌جای متن، خالی
// پر می‌شد. در لاگ دقیقا پیداست: `کلیپ‌بورد پایانی، 0 نویسه` زیرِ یک درجِ ۱۴۹ نویسه‌ای.
// در ریموت دسکتاپ همیشه دیده می‌شد و جای دیگر نه، چون فقط آنجا مسیرِ پیست بلافاصله
// کپیِ اولِ سالم را با نسخه‌ی transient می‌پوشاند و مدیر کلیپ‌بورد فرصت دیدنش را
// نداشت؛ بقیه‌ی اپ‌ها آن کپیِ اول را نگه می‌داشتند و خالی شدنِ بعدی به چشم نمی‌آمد.
- (NSString *)editorText {
    return [_editor.string copy] ?: @"";
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

// جای متن را یک‌جا عوض می‌کند: مسیر پاس دستی و مسیر عوض کردن حالت هر دو لازمش دارند.
// و این همان نقطه‌ای است که خاکستری سفید می‌شود: متنِ تمام‌شده کلِ ادیتور را از نو
// می‌نویسد، پس دُم پیش‌نمایش نه «جایگزین» که اصلا بی‌موضوع می‌شود.
- (void)setEditorText:(NSString *)text {
    [self ensureEditor];
    [self forgetPreview];
    [_editor.textStorage replaceCharactersInRange:NSMakeRange(0, _editor.string.length)
                                      withString:text ?: @""];
    _editor.font = ZFont(15, NO);
    _editor.textColor = NSColor.labelColor;
    [_editor scrollRangeToVisible:NSMakeRange(_editor.string.length, 0)];
    _wroteText = [text ?: @"" copy];
}

- (void)clearEditor {
    [self ensureEditor];
    [self forgetPreview];
    [_editor.textStorage replaceCharactersInRange:NSMakeRange(0, _editor.string.length) withString:@""];
    _wroteText = @"";
}

// کاربر خودش در ادیتور تایپ کرده؟ همان قاعده‌ی دُمِ پیش‌نمایش، یک پله بالاتر: هرچه
// نوشته‌ایم را عینا به یاد داریم، و اگر متنِ زنده دیگر همان نیست یعنی متن مالِ اوست.
//
// چرا لازم شد: مسیر تحویل در حالت جمع، **اول** متنِ خام را روی ادیتور می‌نوشت و
// **بعد** همان را پس می‌خواند، پس تایپِ کاربر پاک می‌شد و ادعای «متنِ ادیتور مرجع
// است» هیچ‌وقت درست نبود. تا وقتی ادیتور فوکوس نمی‌گرفت کسی نمی‌دیدش.
- (BOOL)editorTouched {
    if (!_editor) return NO;
    NSString *live = _editor.string;
    // دُمِ خاکستری مالِ ماست نه کاربر، پس از ته کنار گذاشته می‌شود وگرنه هر
    // پیش‌نمایشی «کاربر تایپ کرده» خوانده می‌شد.
    if (_previewText.length && [live hasSuffix:_previewText])
        live = [live substringToIndex:live.length - _previewText.length];
    return ![live isEqualToString:_wroteText ?: @""];
}

// ---------- دُمِ پیش‌نمایش ----------
// خاکستری یک معنی دارد و فقط همان: **هنوز تمام نشده.** پس اگر پاس هوش مصنوعی روشن
// باشد، دُم تا نشستنِ آن پاس خاکستری می‌ماند، نه تا رسیدنِ متن خام. سفید شدن کارِ
// setEditorText: است، و آن یک جا بیشتر نیست.

// خاکستریِ دُم. از labelColor ساخته می‌شود نه از secondaryLabelColor، چون آن یکی خودش
// آلفا دارد و ضرب کردنِ آلفا در آلفا در حالت تاریک متن را عملا ناخوانا می‌کرد.
static NSColor *ZPreviewColor(void) {
    return [NSColor.labelColor colorWithAlphaComponent:0.45];
}

- (void)forgetPreview {
    _previewText = nil;
    _previewLoc = 0;
    _previewGaveUp = NO;
    if (!_previewTag.hidden) {
        _previewTag.hidden = YES;
        [self layoutViews];
    }
}

- (void)setPreviewText:(NSString *)text {
    if (!_editor && !text.length) return;    // ادیتوری نیست و چیزی هم برای پاک کردن نیست
    [self ensureEditor];
    if (_previewGaveUp) return;
    NSTextStorage *ts = _editor.textStorage;

    // شرطِ نوشتن: دُمِ قبلی هنوز عینا همان‌جاست که گذاشتیمش و هنوز ته متن است. نبود،
    // یعنی کاربر خودش تایپ کرده و از این لحظه متن مالِ اوست: دست نگه می‌داریم و تا
    // نوشتنِ کاملِ بعدی هیچ‌چیز را پاک نمی‌کنیم. تایپِ کاربر را باختن یعنی هیچ‌وقت.
    if (_previewText) {
        NSUInteger end = _previewLoc + _previewText.length;
        if (end != ts.length ||
            ![[ts.string substringFromIndex:_previewLoc] isEqualToString:_previewText]) {
            _previewText = nil;
            _previewGaveUp = YES;
            return;
        }
    } else {
        if (!text.length) return;
        _previewLoc = ts.length;    // لنگر: ته متنِ سفیدِ دورهای قبلی
    }

    // یک فاصله سرِ دُم، وقتی چیزی قبلش هست. بی این، اولین کلمه‌ی پیش‌نمایشِ دورِ دوم
    // به آخرین کلمه‌ی دورِ اول می‌چسبد. فاصله جزوِ خودِ دُم است و با آن هم پاک می‌شود،
    // پس در متنِ نهایی اثری از خودش نمی‌گذارد.
    NSString *body = text ?: @"";
    if (body.length && _previewLoc > 0) body = [@" " stringByAppendingString:body];

    // بی فِید، بی انیمیشن. یک نسخه فِیدِ ورودِ تکه داشت و آن وقتی معنی داشت که هر ~۱۰
    // ثانیه یک بار تکه‌ی تازه می‌نشست. حالا متن هم‌گام با حرف زدن جلو می‌رود و interim
    // خودش را بازنویسی می‌کند، پس فِید یعنی کلِ متن چند بار در ثانیه پلک بزند. متنی که
    // مدام حرکت می‌کند، حرکتِ اضافه لازم ندارد.
    [ts beginEditing];
    [ts replaceCharactersInRange:NSMakeRange(_previewLoc, ts.length - _previewLoc) withString:body];
    if (body.length) {
        NSRange r = NSMakeRange(_previewLoc, body.length);
        [ts addAttribute:NSFontAttributeName value:ZFont(15, NO) range:r];
        [ts addAttribute:NSForegroundColorAttributeName value:ZPreviewColor() range:r];
    }
    [ts endEditing];

    if (!body.length) {
        [self forgetPreview];
        return;
    }
    _previewText = [body copy];
    // اسکرول به آخر، وگرنه متن از پایین کادر بیرون می‌رود و کاربر یک بلوکِ بی‌حرکت
    // می‌بیند در حالی که پایینش دارد تند جلو می‌رود.
    [_editor scrollRangeToVisible:NSMakeRange(ts.length, 0)];
    if (_previewTag.hidden) {
        _previewTag.hidden = NO;
        [self layoutViews];
    }
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
        : @"رفتن به جمع در پنل: متن اینجا جمع می‌شود و با کلیک روی آن ویرایش هم می‌شود (Command راست + E)";

    // سشن که تمام شد (در بازبینی، یا وسط کارِ پایانی) دکمه‌های شنیدن معنا ندارند؛
    // دکمه‌های متن می‌مانند. نشان دادنِ دکمه‌ای که کار نمی‌کند، دروغ است.
    // حساسیت: آیکون خودش حالت را می‌گوید، مثل بقیه‌ی دکمه‌های این نوار. گوشِ ساده
    // یعنی عادی، گوشِ پر یعنی حساسیت بالا روشن است.
    BOOL sens = ZSettings.shared.highSensitivity;
    [self setButton:_btnSens symbol:sens ? @"ear.fill" : @"ear.badge.waveform"];
    _btnSens.contentTintColor = sens ? NSColor.systemBlueColor : nil;
    _btnSens.toolTip = sens
        ? @"حساسیت بالا روشن است: صدای آرام تا حد زیادی بزرگ می‌شود. برای برگشتن بزن "
           "(Command راست + S)"
        : @"حساسیت بالای میکروفن: برای پچ‌پچ کردن و اتاق ساکت، یا میکروفنی که صدایش "
           "کم می‌رسد (Command راست + S)";

    // پاس هوش مصنوعی: روشن/خاموشی از روی خودِ دکمه دیده می‌شود، نه از منو. رنگ
    // می‌گیرد یعنی روشن است. بی‌کلید هم روشن نمی‌شود و تولتیپ همان را می‌گوید.
    BOOL ai = ZSettings.shared.finalPassEnabled;
    // نارنجی یعنی «روشن است ولی کاری نمی‌کند»، و حق دارد فقط وقتی بیاید که **بدانیم**
    // کلیدی نیست. با `hasKey` این رنگ دروغ می‌گفت: آن تابع جوابِ پرسشِ بی‌پنجره‌ی
    // کی‌چین را می‌دهد و آن پرسش می‌تواند سر ACL رد شود، پس روی کلیدِ سالمِ ذخیره‌شده هم
    // نارنجی می‌شد. همان معیارِ سشن، همان‌جا: کلید معلوم نیست ≠ کلید نیست.
    BOOL key = !ZFinalPass.keyKnownMissing;
    _btnAI.contentTintColor = ai ? (key ? NSColor.systemBlueColor : NSColor.systemOrangeColor) : nil;
    // جمله‌ی بی‌کلید از یک جا می‌آید (ZFinalPass)، چون سه حالت دارد و اینجا هاردکد
    // شدنش یعنی دو تایش دروغ باشد: کلید نیست، کلید قفل است، یا کلید رد شده.
    _btnAI.toolTip = !key
        ? [@"تمیز کردن متن: " stringByAppendingString:ZFinalPass.missingKeyHint]
        : ai ? @"تمیز کردن متن روشن است: سر پایان، متن برای نقطه‌گذاری و اصلاح واژه‌های "
                "غلط به Gemini می‌رود. صدا هیچ‌وقت فرستاده نمی‌شود. برای خاموش کردن بزن (A)"
             : @"تمیز کردن متن خاموش است: متن همان‌طور که شنیده شده تحویل می‌شود. برای "
                "روشن کردن بزن (A)";

    // دو زبانه، سومین تاگل و با همان قاعده‌ی دو تای قبلی: کتابِ بسته یعنی خاموش،
    // کتابِ باز و رنگی یعنی همین صدا انگلیسی هم شنیده می‌شود. اثرش از دور بعدیِ
    // شنیدن است، چون خط لوله‌ها سر ساختِ موتور بسته می‌شوند.
    BOOL two = ZSettings.shared.secondPass;
    [self setButton:_btnSecond symbol:two ? @"character.book.closed.fill" : @"character.book.closed"];
    _btnSecond.contentTintColor = two ? NSColor.systemBlueColor : nil;
    _btnSecond.toolTip = two
        ? @"دوزبانه روشن است: همین صدا از دور بعد انگلیسی هم شنیده می‌شود، تا اصطلاح‌های "
           "فنی از دست نروند. برای خاموش کردن بزن (Command راست + B)"
        : @"دوزبانه: همین صدا را هم‌زمان انگلیسی هم بشنو. برای متنِ پر از اصطلاح فنی؛ "
           "روی گفتار روزمره فرقی نمی‌کند (Command راست + B)";

    // پیش‌نمایش. تولتیپ عمدا **توصیه به خاموش کردن** دارد و این یک تعارف نیست: متنی
    // که وسط حرف زدن جلوی چشم بیاید، رشته‌ی کلام را پاره می‌کند. کسی که با دیدنش
    // راحت‌تر است روشنش می‌کند؛ بقیه باید بدانند خاموشی حالتِ درست است.
    BOOL prev = ZSettings.shared.previewStream;
    [self setButton:_btnPreview symbol:prev ? @"captions.bubble.fill" : @"captions.bubble"];
    _btnPreview.contentTintColor = prev ? NSColor.systemBlueColor : nil;
    _btnPreview.toolTip = prev
        ? @"پیش‌نمایش روشن است: متنِ خاکستری هم‌گام با حرف زدنت جلو می‌رود، ولی خام است "
           "و غلط دارد. متنِ درست سر پایان می‌آید و سفید می‌شود. برای تمرکز بیشتر "
           "خاموشش کن (Command راست + P)"
        : @"پیش‌نمایش (آزمایشی): متن را هم‌گام با حرف زدنت نشان می‌دهد، خاکستری و خام. "
           "روی متنِ نهایی هیچ اثری ندارد. خاموش بماند بهتر است: خواندنِ حرفِ خودت وسط "
           "حرف زدن حواست را پرت می‌کند (Command راست + P)";
    // حالت کنار کرسر پنلی ندارد که چیزی در آن نشان داده شود، پس دکمه هم آنجا معنا
    // ندارد. مثل بقیه‌ی نوار غیب نمی‌شود، فقط خاموش و بی‌رنگ می‌ماند و می‌گوید چرا.
    if (!collect) {
        _btnPreview.contentTintColor = nil;
        _btnPreview.toolTip = @"پیش‌نمایش فقط در حالت «جمع در پنل» دیده می‌شود؛ کنار کرسر "
                               "پنلی نیست که متن در آن بنشیند (Command راست + E)";
    }

    // **هیچ دکمه‌ای غیب نمی‌شود.** قبلا سرِ مکث نصفشان می‌رفتند، با این استدلال که
    // «دکمه‌ای که کار نمی‌کند دروغ است». ولی در نسخه دو مکث یعنی سشن هنوز زنده است
    // و همه‌ی آن دکمه‌ها واقعا کار می‌کنند، پس آن استدلال اینجا اصلا صدق نمی‌کرد و
    // نتیجه‌اش نواری بود که زیر دست کاربر نصف می‌شد. نوارِ ثابت، حافظه‌ی عضلانی.
    _btnClose.toolTip = m.busy == ZBusyPolish ? @"متن دارد تمیز می‌شود؛ چند لحظه صبر کن"
                      : m.busy == ZBusySpeech ? @"متن دارد می‌آید؛ چند لحظه صبر کن"
                      : m.review ? @"بستن (Esc)" : @"پایان دیکته و درج متن (Esc)";
    _btnTrash.toolTip = @"دور ریختن هرچه هنوز درج نشده، و صدای ضبط‌شده (D)";
    _btnInsert.hidden = NO;

    // چیپ: فقط ساعتِ ضبط، و در هر سشنِ زنده‌ای نشان داده می‌شود، نه فقط یک حالت خاص.
    // ساعتِ دورِ فعلی، درشت. و اگر دورِ قبلی‌ای بوده، مجموع کنارش و ریزتر: کاربر
    // باید بداند الان چقدر حرف زده، نه فقط اینکه روی هم چقدر شده.
    // یک عدد در چیپ، نه دو تا. دو عددِ هم‌اندازه که با یک نقطه کنار هم بنشینند
    // سلسله‌مراتب ندارند و چشم نمی‌داند کدام مهم است. چیپ فقط «الان»: عددی که زنده
    // جلو می‌رود. مجموع یک اطلاعِ آرام است و جایش خط وضعیت است، نه اینجا.
    NSString *chip = m.elapsed > 0 ? ZClock(m.elapsed)
                   : m.elapsedTotal > 0 ? ZClock(m.elapsedTotal) : @"";
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
    if (m.busy != ZBusyNone && m.workingMsg.length) {
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
        // مجموع فقط وقتی معنی دارد که دورِ دومی در کار باشد، و آن‌وقت هم آرام و
        // ته خط می‌نشیند، نه هم‌وزنِ عددِ زنده.
        if (m.rounds > 0 && m.elapsedTotal > 0) {
            s = [s stringByAppendingFormat:@"  ﹒ روی هم %@", ZClock(m.elapsedTotal)];
        }
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
        _btnPause.toolTip = @"دوباره تلاش کن (یک بار Command راست را بزن)";
    } else if (m.paused) {
        [self setButton:_btnPause symbol:@"play.fill"];
        _btnPause.toolTip = @"ادامه بده (یک بار Command راست را بزن)";
    } else {
        [self setButton:_btnPause symbol:@"pause.fill"];
        _btnPause.toolTip = @"بایست و متن تا اینجا را تحویل بده (یک بار Command راست را بزن)";
    }

    _dot.color = ZStatusColor(m);
    if (m.listening && !m.paused && !_pulsing) [self startPulse];
    if ((!m.listening || m.paused) && _pulsing) [self stopPulse];

    // نشان و چرخنده یک جا می‌نشینند و هیچ‌وقت هر دو دیده نمی‌شوند: تا کاری در جریان
    // است چرخنده حرف می‌زند، بعدش نشان.
    // نشان و نشانِ کار یک جا می‌نشینند و هیچ‌وقت هر دو دیده نمی‌شوند: تا کاری در
    // جریان است آن یکی حرف می‌زند، بعدش نشان.
    _dot.hidden = m.busy != ZBusyNone;
    _busy.mode = m.busy;

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
- (void)historyTap { if (self.onHistory) self.onHistory(); }
- (void)sensTap { if (self.onSensToggle) self.onSensToggle(); }
- (void)helpTap { if (self.onHelp) self.onHelp(); }
- (void)aiTap { if (self.onAIToggle) self.onAIToggle(); }
- (void)secondTap { if (self.onSecondPass) self.onSecondPass(); }
- (void)previewTap { if (self.onPreview) self.onPreview(); }

// اسکرین‌شات برای بازبینی طراحی (بدون نیاز به اجازه ضبط صفحه)
- (void)makeShots:(NSString *)dir {
    ZPanelModel *listening = [ZPanelModel new];
    listening.status = [@"در حال گوش کردن ﹒ " stringByAppendingString:ZStopHint];
    listening.listening = YES;

    ZPanelModel *paused = [ZPanelModel new];
    paused.status = @"مکث. برای ادامه یک بار Command راست را بزن";
    paused.paused = YES;

    ZPanelModel *error = [ZPanelModel new];
    error.status = @"اینترنت قطع و وصل می‌شود؛ برای تلاش دوباره یک بار Command راست را بزن";
    error.error = YES;

    // بازبینی: سشن تمام شده و متن نهایی در ادیتور نشسته
    ZPanelModel *review = [ZPanelModel new];
    review.mode = ZModeCollect;
    review.review = YES;
    review.status = @"متن آماده است و در کلیپ‌بورد هم هست";

    // پیش‌نمایش در حال شنیدن: دو رنگ در یک متن، که تنها حالتی است که رنگ در آن معنی
    // دارد. سفید یعنی تحویل‌شده، خاکستری یعنی هنوز تمام نشده.
    ZPanelModel *preview = [ZPanelModel new];
    preview.mode = ZModeCollect;
    preview.listening = YES;
    preview.status = [@"در حال گوش کردن ﹒ " stringByAppendingString:ZStopHint];

    // دو انتظار، دو شکل. کنار هم عکس گرفته می‌شوند چون تنها معیارِ درستِ این طراحی
    // همین است: از یک نگاه، بی‌خواندنِ خط وضعیت، معلوم باشد کدام کدام است.
    ZPanelModel *speech = [ZPanelModel new];
    speech.mode = ZModeCollect;
    speech.busy = ZBusySpeech;
    speech.workingMsg = @"یک لحظه، صدا دارد متن می‌شود…";

    ZPanelModel *polish = [ZPanelModel new];
    polish.mode = ZModeCollect;
    polish.busy = ZBusyPolish;
    polish.workingMsg = @"در حال تمیز کردن متن…";

    NSArray *states = @[@[@"listening", listening], @[@"paused", paused],
                        @[@"error", error], @[@"review", review], @[@"preview", preview],
                        @[@"busy-speech", speech], @[@"busy-polish", polish]];
    [_panel orderFrontRegardless];
    for (NSArray *pair in states) {
        ZPanelModel *m = pair[1];
        [self clearEditor];
        if (m.review) {
            // متنِ نمونه یک **دیکته‌ی واقعی** را نشان می‌دهد، نه توضیحِ خودِ پنل را:
            // عکس باید همان چیزی باشد که کاربر می‌بیند، نه راهنمای پنل.
            [self setEditorText:@"سلام، این یک دیکته‌ی نمونه است. همین‌طور که حرف می‌زنم "
                                @"متن اینجا جمع می‌شود، و هر جا لازم شد مکث می‌کنم و فکر "
                                @"می‌کنم بی اینکه چیزی خراب شود. آخرش با Esc همه‌اش یکجا "
                                @"سر کرسر می‌نشیند."];
        }
        if (m == speech || m == polish) {
            [self setEditorText:@"متنِ تا اینجا، و پنل منتظرِ بقیه‌اش."];
        }
        if (m == preview) {
            // عمدا **چند بار پشت سر هم**، همان‌طور که استریم می‌فرستد: هر بار کلِ متن
            // از نو، و بار آخر یک بازنویسیِ واقعی (interim که نظرش عوض شده). اگر لنگر
            // یا فاصله یا رنگ جایی بلغزد، دقیقا همین‌جا پیدا می‌شود.
            [self setEditorText:@"این تکه قبلا تحویل شده و سفید است."];
            for (NSString *step in @[@"و این متن",
                                     @"و این متن خام هم‌گام با حرف",
                                     @"و این متن خام هم‌گام با حرف زدن جلو می‌رود، با غلط، تا آخر."]) {
                [self setPreviewText:step];
            }
        }
        [self render:m];
        [_effect layoutSubtreeIfNeeded];
        // فرصتِ چرخیدنِ ران‌لوپ: فِیدِ دُم پیش‌نمایش تایمری است و بی این، عکس حالتِ
        // نیمه‌کاره را می‌گیرد نه حالتِ نشسته‌ای که کاربر واقعا می‌بیند.
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
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

