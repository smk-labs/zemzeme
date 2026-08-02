// کارت میان‌برها: یک پنجره‌ی کوچک مرجع، به‌جای فهرستِ داخل منو.
//
// چرا از منو بیرون آمد: آیتم منو یک رشته‌ی یک‌خطی است با یک آیکون در سرش. یعنی نه
// ستون کلید، نه کی‌کپ، نه آیکون به ازای هر کار. فهرست قبلی هم مجبور بود همه‌ی
// ردیف‌هایش را enabled=NO کند (کاری نمی‌کنند)، و مک همان را خاکستریِ «غیرفعال»
// می‌کشید؛ متن فارسی و لاتینِ یک‌خطی هم جابه‌جا خوانده می‌شد. اینجا هر ردیف سه تکه‌ی
// جدا دارد (آیکون، شرح، کی‌کپ) و هیچ‌کدام در بازی راست‌به‌چپِ دیگری نیست.
#import "zemzeme.h"

static const CGFloat kCSW = 470;       // پهنای کارت؛ اندازه‌ی بلندترین شرح، بی‌بریدگی
static const CGFloat kCSPad = 18;
static const CGFloat kCSRow = 27;      // ارتفاع ردیف میان‌بر
static const CGFloat kCSHead = 27;     // ارتفاع تیتر بخش
static const CGFloat kCSKeyCol = 66;   // ستون کی‌کپ‌ها در لبه‌ی چپ؛ شرح‌ها از آن به بعد هم‌تراز می‌شوند
static const CGFloat kCSNote = 20;     // ارتفاع هر پانویس
static const CGFloat kCSIcon = 17;

static NSString *const kCSAutosave = @"ZemzemeCheatSheet";

@implementation ZCheatSheet {
    NSPanel *_win;
    ZDragEffectView *_card;
    BOOL _placed;    // جای کارت یک بار تعیین شده (وسط صفحه یا همان‌جای اجرای قبل)
}

+ (instancetype)shared {
    static ZCheatSheet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [ZCheatSheet new]; });
    return s;
}

+ (void)toggle { [[self shared] toggle]; }
+ (BOOL)visible { return [self shared]->_win.isVisible; }
+ (void)close {
    [[self shared]->_win orderOut:nil];
    ZLog(@"help: card closed by esc");
}

// عکس طراحی، همان مسیر panel-*.png در makeShots: با --uishot گرفته می‌شود تا چیدمان
// راست‌به‌چپ و هم‌ترازی ستون کلیدها بی‌باز کردن دستی کارت هم دیده شود.
+ (void)shot:(NSString *)dir {
    ZCheatSheet *me = [self shared];
    [me build];
    [me->_win orderFrontRegardless];
    [me->_card layoutSubtreeIfNeeded];
    NSBitmapImageRep *rep = [me->_card bitmapImageRepForCachingDisplayInRect:me->_card.bounds];
    if (rep) {
        [me->_card cacheDisplayInRect:me->_card.bounds toBitmapImageRep:rep];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:[dir stringByAppendingPathComponent:@"cheatsheet.png"] atomically:YES];
    }
    [me->_win orderOut:nil];
}

// ---------- محتوا ----------
// یک منبع حقیقت برای کارت. هر ردیف: کی‌کپ‌ها، نماد، شرح.
// عمدا اسم مودیفایر در تیتر بخش نوشته شده نه در هر ردیف: نه بار «Command راست» را
// نُه بار تکرار می‌کنیم، نه لاتین را وسط شرح فارسی می‌بریم.
- (NSArray<NSDictionary *> *)sections {
    return @[
        @{@"title": @"تپ روی Command راست",
          @"rows": @[
              @[@[@"⌘", @"⌘"], @"mic.fill",     @"شروع و پایان سشن"],
              @[@[@"⌘"],       @"pause.circle", @"مکث و ادامه"],
          ]},
        @{@"title": @"Command راست + یک حرف، در حین سشن",
          @"rows": @[
              @[@[@"C"],     @"doc.on.doc",        @"کپی متن تا اینجا"],
              @[@[@"I"],     @"text.insert",       @"درج سر کرسر همین اپ"],
              @[@[@"D"],     @"trash",             @"دور ریختن متن درج‌نشده و صدای ضبط‌شده"],
              @[@[@"L"],     @"globe",             @"عوض کردن زبان: فارسی و انگلیسی"],
              @[@[@"E"],     @"square.and.pencil", @"چرخش حالت: زنده ← جمع ← کرسر ← یادداشت"],
              @[@[@"P"],     @"wand.and.stars",    @"پاس ویرایش روی متن جمع‌شده"],
              @[@[@"N"],     @"sparkles",          @"پاس نهایی: پایان سشن و متن تمیز از خودِ صدا"],
              @[@[@"Esc"],   @"xmark.circle",      @"وسط پاس نهایی: لغو، ولی صدا سر جایش می‌ماند"],
              @[@[@"R"],     @"arrow.2.squarepath", @"چرخش نسخه‌های متن: نهایی، مو‌به‌مو، خام"],
              @[@[@"B"],     @"curlybraces",       @"بهبود پرامپت (بتا): همین متن، آماده برای یک ایجنت"],
              @[@[@"Space"], @"pause.circle",      @"مکث و ادامه، مثل تک‌تپ"],
          ]},
        // این دو به سشن ربطی ندارند، پس بخش جدا دارند: تازه‌کاری که هنوز دیکته‌ای شروع
        // نکرده هم باید بتواند راهنما را باز کند و فایل رونویسی کند.
        @{@"title": @"Command راست + این دو، سشن یا بی‌سشن",
          @"rows": @[
              @[@[@"H"], @"questionmark.circle", @"باز و بستن همین کارت"],
              @[@[@"F"], @"arrow.up.doc",        @"پنل رونویسی فایل صوتی"],
          ]},
        @{@"title": @"بدون کلید کمکی",
          @"rows": @[
              @[@[@"Esc"], @"stop.circle", @"این کارت را می‌بندد، وگرنه پایان سشن و درج متن"],
          ]},
        @{@"title": @"بدون کیبورد",
          @"rows": @[
              @[@[], @"hand.draw", @"پنل را از هر جای خالی‌اش بکش تا جابه‌جا شود"],
              @[@[], @"link",      @"آدرس zemzeme://toggle برای Karabiner و Shortcuts"],
          ]},
    ];
}

// پانویس‌ها وضعیت همین لحظه را می‌گویند، پس کارت هر بار که باز می‌شود ساخته می‌شود:
// اگر «هاتکی داخلی» خاموش باشد، دابل‌تپ واقعا کار نمی‌کند و کارت باید همین را بگوید،
// نه یک راهنمای درستِ همیشگی که با دستگاه کاربر جور نیست.
- (NSArray<NSArray *> *)notes {
    NSMutableArray *n = [NSMutableArray array];
    // مسیر دوم ⌥ برداشته شد: یک تپ سراسری هر ترکیبی را که بگیرد از اپ‌های دیگر
    // می‌دزدد، و ⌥ جای شلوغی بود (⌥V و ⌥P مال مککی، ⌥V داخل ریموت مال Win+V).
    [n addObject:@[@"command", @"همه‌ی میان‌برها فقط با Command راست‌اند؛ ⌥ دیگر کاری نمی‌کند", @NO]];
    [n addObject:@[@"info.circle", @"جز H و F، بقیه‌ی حرف‌ها فقط در حین سشن کار می‌کنند", @NO]];
    if (ZSettings.shared.finalPassEnabled && !ZFinalPass.hasKey) {
        [n addObject:@[@"exclamationmark.triangle",
                       @"پاس نهایی روشن است ولی کلید جمینای نیست، پس N کاری نمی‌کند؛ از منو «کلید Gemini…» را بزن",
                       @YES]];
    } else if (ZSettings.shared.finalPassEnabled && !ZSettings.shared.recordSessions) {
        // دو شرط جدا برای یک کار: N بی صدا چیزی برای شنیدن ندارد. کاربری که تاگل پاس
        // نهایی را روشن کرده حق دارد بداند چرا در زنده دکمه‌اش را نمی‌بیند.
        [n addObject:@[@"exclamationmark.triangle",
                       @"N الان فقط در یادداشت کار می‌کند؛ برای بقیه «ضبط صدای سشن» را روشن کن",
                       @YES]];
    }
    // B بتاست و تاگلش پیش‌فرض خاموش، پس کارت باید بگوید چرا کار نمی‌کند. دو حالت جدا،
    // چون درمانشان جداست: یکی تاگل است، یکی کلید.
    if (!ZSettings.shared.enhanceEnabled) {
        [n addObject:@[@"info.circle",
                       @"B (بهبود پرامپت) بتاست و خاموش؛ از منوی زمزمه روشنش کن", @NO]];
    } else if (!ZFinalPass.hasKey) {
        [n addObject:@[@"exclamationmark.triangle",
                       @"بهبود پرامپت روشن است ولی کلید جمینای نیست، پس B کاری نمی‌کند؛ از منو «کلید Gemini…» را بزن",
                       @YES]];
    }
    // هشدارِ واقعی و نه احتیاطی: تا اپ بالاست رول Karabiner کنار کشیده، پس اگر این هم
    // خاموش باشد هیچ‌کس دابل‌تپ را نمی‌شنود و کاربر فکر می‌کند هاتکی خراب شده.
    if (!ZSettings.shared.internalHotkey) {
        [n addObject:@[@"exclamationmark.triangle",
                       @"دابل‌تپ الان خاموش است: در پیشرفته «هاتکی داخلی» را روشن کن", @YES]];
    }
    return n;
}

// ---------- ساخت ----------

- (void)toggle {
    if (_win.isVisible) {
        [_win orderOut:nil];
        ZLog(@"help: card hidden");
        return;
    }
    [self build];
    [_win orderFrontRegardless];    // اپ اکسسوری است و پنل نان‌اکتیویتینگ: فوکس اپ مقصد دست‌نخورده می‌ماند
    ZLog(@"help: card shown");
}

- (void)build {
    NSArray<NSDictionary *> *sections = [self sections];
    NSArray<NSArray *> *notes = [self notes];
    CGFloat H = [self heightFor:sections notes:notes];

    if (!_win) {
        // همان جنس پنل شناور: بی‌قاب، نان‌اکتیویتینگ، شیشه‌ای. نان‌اکتیویتینگ مهم است:
        // اگر کارت فوکس بگیرد، «اپ مقصدِ» سشن در جریان خودِ زمزمه می‌شود و متن جای
        // اشتباه درج می‌شود. پس کارت هیچ‌وقت کلیدی نمی‌شود و Esc هم دستش نیست (Esc در
        // حین سشن کار خودش را دارد: پایان و درج).
        _win = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, kCSW, H)
                                          styleMask:NSWindowStyleMaskBorderless
                                                    | NSWindowStyleMaskNonactivatingPanel
                                            backing:NSBackingStoreBuffered defer:NO];
        _win.level = NSFloatingWindowLevel;   // بالای پنجره‌های معمولی، ولی زیر منوها
        _win.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                                | NSWindowCollectionBehaviorFullScreenAuxiliary
                                | NSWindowCollectionBehaviorIgnoresCycle;
        _win.floatingPanel = YES;
        _win.hidesOnDeactivate = NO;
        _win.becomesKeyOnlyIfNeeded = YES;
        _win.releasedWhenClosed = NO;
        _win.opaque = NO;
        _win.backgroundColor = NSColor.clearColor;
        _win.hasShadow = YES;
        _win.movableByWindowBackground = YES;
        // جای انتخابی کاربر بین اجراها می‌ماند. frameAutosaveName خودش فریم را
        // برنمی‌گرداند، فقط ذخیره می‌کند؛ برگرداندن کار setFrameUsingName است.
        _win.frameAutosaveName = kCSAutosave;
        _placed = [_win setFrameUsingName:kCSAutosave];
    }
    NSPoint topLeft = NSMakePoint(NSMinX(_win.frame), NSMaxY(_win.frame));

    _card = [[ZDragEffectView alloc] initWithFrame:NSMakeRect(0, 0, kCSW, H)];
    _card.material = NSVisualEffectMaterialHUDWindow;
    _card.state = NSVisualEffectStateActive;
    _card.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _card.wantsLayer = YES;
    _card.layer.cornerRadius = 16;
    _card.layer.masksToBounds = YES;
    _card.layer.borderWidth = 0.5;
    _card.layer.borderColor = [NSColor.labelColor colorWithAlphaComponent:0.12].CGColor;

    CGFloat y = H - kCSPad;

    // سرصفحه: تیتر و دو خط توضیح، راست‌چین. خط دوم عمدا صریح است: کاربر Command چپ را
    // امتحان می‌کند، هیچ اتفاقی نمی‌افتد، و فکر می‌کند میان‌بر خراب است.
    y -= 22;
    [self label:@"راهنمای میان‌برها" font:ZFont(15, YES) color:NSColor.labelColor
          frame:NSMakeRect(kCSPad, y, kCSW - 2 * kCSPad, 20)];
    y -= 19;
    [self label:@"همه‌ی میان‌برها روی Command راست سوارند، همان کنار فلش‌ها"
           font:ZFont(11.5, NO) color:NSColor.secondaryLabelColor
          frame:NSMakeRect(kCSPad, y, kCSW - 2 * kCSPad, 16)];
    y -= 18;
    [self label:@"هر ⌘ روی این کارت یعنی همان راستی؛ Command چپ هیچ کاری نمی‌کند"
           font:ZFont(11.5, YES) color:NSColor.secondaryLabelColor
          frame:NSMakeRect(kCSPad, y, kCSW - 2 * kCSPad, 16)];

    // دکمه‌ی بستن، گوشه‌ی چپِ بالا: دور از تیترِ راست‌چین
    NSImage *x = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"بستن"];
    x = [x imageWithSymbolConfiguration:
         [NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightSemibold]];
    NSButton *close = [NSButton buttonWithImage:x ?: [NSImage new] target:self action:@selector(closeTap)];
    close.bordered = NO;
    close.buttonType = NSButtonTypeMomentaryChange;
    close.contentTintColor = NSColor.secondaryLabelColor;
    close.frame = NSMakeRect(kCSPad - 4, H - kCSPad - 18, 22, 22);
    [_card addSubview:close];

    y -= 12;
    for (NSDictionary *s in sections) {
        y -= kCSHead;
        [self sectionHead:s[@"title"] atY:y];
        for (NSArray *r in s[@"rows"]) {
            y -= kCSRow;
            [self row:r atY:y];
        }
        y -= 8;
    }

    // خط جدا کننده‌ی پانویس‌ها: از اینجا به بعد میان‌بر نیست، توضیح است
    y -= 5;
    NSView *rule = [[NSView alloc] initWithFrame:NSMakeRect(kCSPad, y, kCSW - 2 * kCSPad, 1)];
    rule.wantsLayer = YES;
    rule.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.10].CGColor;
    [_card addSubview:rule];
    y -= 5;
    for (NSArray *n in notes) {
        y -= kCSNote;
        [self note:n atY:y];
    }

    [_win setContentSize:NSMakeSize(kCSW, H)];
    _win.contentView = _card;
    // قد کارت با پانویس‌ها کم‌وزیاد می‌شود. setContentSize لبه‌ی پایین را ثابت نگه
    // می‌دارد، یعنی کارت زیر دست کاربر تکان می‌خورد؛ اینجا لبه‌ی بالا ثابت می‌ماند.
    if (_placed && NSIntersectsRect(_win.frame, NSScreen.mainScreen.visibleFrame)) {
        [_win setFrameTopLeftPoint:topLeft];
    } else {
        [_win center];
        _placed = YES;
    }
}

- (CGFloat)heightFor:(NSArray *)sections notes:(NSArray *)notes {
    CGFloat h = kCSPad + 22 + 19 + 18 + 12;    // پد بالا، تیتر، دو خط زیرتیتر، فاصله
    for (NSDictionary *s in sections) {
        h += kCSHead + [s[@"rows"] count] * kCSRow + 8;
    }
    h += 11 + notes.count * kCSNote + kCSPad;    // ۱۱ = فاصله و خط جدا کننده‌ی پانویس‌ها
    return ceil(h);
}

// ---------- تکه‌های کارت ----------

// راست‌چین به‌همراه baseWritingDirection راست‌به‌چپ: بدون این دومی، شرحی که تکه‌ی
// لاتین دارد (Space، zemzeme://toggle) سرِ خط را به لاتین می‌دهد و جمله جابه‌جا خوانده
// می‌شود. همان چیزی که در فهرست منو خراب بود.
- (NSTextField *)label:(NSString *)text font:(NSFont *)f color:(NSColor *)c frame:(NSRect)fr {
    NSTextField *l = [NSTextField labelWithString:text];
    l.font = f;
    l.textColor = c;
    l.alignment = NSTextAlignmentRight;
    l.cell.baseWritingDirection = NSWritingDirectionRightToLeft;
    l.frame = fr;
    [_card addSubview:l];
    return l;
}

// تیتر بخش: متن راست، و یک خط مو تا لبه‌ی چپ که بخش‌ها دیداری از هم جدا شوند
- (void)sectionHead:(NSString *)title atY:(CGFloat)y {
    NSFont *f = ZFont(11, YES);
    CGFloat tw = ceil([title sizeWithAttributes:@{NSFontAttributeName: f}].width) + 2;
    tw = MIN(tw, kCSW - 2 * kCSPad - 40);
    [self label:title font:f color:NSColor.secondaryLabelColor
          frame:NSMakeRect(kCSW - kCSPad - tw, y + 5, tw, 15)];
    CGFloat lineW = kCSW - kCSPad - tw - 10 - kCSPad;
    if (lineW > 8) {
        NSView *line = [[NSView alloc] initWithFrame:NSMakeRect(kCSPad, y + 12, lineW, 1)];
        line.wantsLayer = YES;
        line.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.10].CGColor;
        [_card addSubview:line];
    }
}

// ردیف: نماد در لبه‌ی راست، شرح دنبالش به چپ، کی‌کپ‌ها در لبه‌ی چپ.
- (void)row:(NSArray *)r atY:(CGFloat)y {
    NSArray<NSString *> *keys = r[0];
    [self icon:r[1] atY:y tint:NSColor.secondaryLabelColor];
    CGFloat right = kCSW - kCSPad - kCSIcon - 8;
    CGFloat left = keys.count ? kCSPad + kCSKeyCol : kCSPad;
    [self label:r[2] font:ZFont(13, NO) color:NSColor.labelColor
          frame:NSMakeRect(left, y + 4, right - left, 18)];

    CGFloat kx = kCSPad;
    for (NSString *k in keys) {
        NSView *cap = [self keycap:k];
        cap.frameOrigin = NSMakePoint(kx, y + 3);
        [_card addSubview:cap];
        kx += cap.frame.size.width + 4;
    }
}

- (void)note:(NSArray *)n atY:(CGFloat)y {
    BOOL warn = [n[2] boolValue];
    NSColor *c = warn ? NSColor.systemOrangeColor : NSColor.secondaryLabelColor;
    [self icon:n[0] atY:y tint:c];
    CGFloat right = kCSW - kCSPad - kCSIcon - 7;
    [self label:n[1] font:ZFont(11, NO) color:c
          frame:NSMakeRect(kCSPad, y + 2, right - kCSPad, 16)];
}

- (void)icon:(NSString *)symbol atY:(CGFloat)y tint:(NSColor *)tint {
    NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    if (!img) ZLog(@"cheatsheet: SF Symbol پیدا نشد: %@", symbol);
    img = [img imageWithSymbolConfiguration:
           [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightRegular]];
    NSImageView *v = [NSImageView imageViewWithImage:img ?: [NSImage new]];
    v.contentTintColor = tint;
    v.imageScaling = NSImageScaleProportionallyDown;
    v.frame = NSMakeRect(kCSW - kCSPad - kCSIcon, y + 4, kCSIcon, 17);
    [_card addSubview:v];
}

// کی‌کپ: قاب گرد با حرف مونواسپیس وسطش. دو کی‌کپ پشت هم یعنی دو بار زدن.
- (NSView *)keycap:(NSString *)text {
    NSFont *f = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
    CGFloat tw = ceil([text sizeWithAttributes:@{NSFontAttributeName: f}].width);
    CGFloat w = MAX(23, tw + 14);
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, 21)];
    v.wantsLayer = YES;
    v.layer.cornerRadius = 5;
    v.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.10].CGColor;
    v.layer.borderWidth = 0.5;
    v.layer.borderColor = [NSColor.labelColor colorWithAlphaComponent:0.18].CGColor;
    NSTextField *l = [NSTextField labelWithString:text];
    l.font = f;
    l.textColor = NSColor.labelColor;
    l.alignment = NSTextAlignmentCenter;
    l.frame = NSMakeRect(0, 4, w, 14);
    [v addSubview:l];
    return v;
}

- (void)closeTap { [_win orderOut:nil]; }

@end
