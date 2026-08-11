// پنجره‌ی تاریخچه: بیست متن آخر، هر کدام با یک دکمه‌ی درج و یک دکمه‌ی کپی
#import "zemzeme.h"

static const CGFloat kHW = 620;        // پهنای پیش‌فرض
static const CGFloat kHH = 470;
static const CGFloat kHEdge = 14;
static const CGFloat kHFull = 132;     // قد جعبه‌ی متن کامل
static const CGFloat kHRow = 26;

// Esc نباید پنجره را ببندد. دلیلش همان دلیلِ پنل رونویسی فایل است: Esc در این اپ
// معنیِ خودش را دارد (پایان دیکته) و کاربری که وسط کار عادت کرده آن را بزند،
// نباید پنجره‌ای را که دارد از آن متن برمی‌دارد از دست بدهد.
@interface ZHistoryWindow : NSPanel
@end
@implementation ZHistoryWindow
- (void)cancelOperation:(id)sender {}
@end

@interface ZHistoryPanel () <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
@end

@implementation ZHistoryPanel {
    NSPanel *_panel;
    NSVisualEffectView *_back;
    NSTableView *_table;
    NSScrollView *_tableScroll;
    NSTextView *_full;
    NSScrollView *_fullScroll;
    NSView *_fullBox;
    NSTextField *_fullCap;
    NSTextField *_status;
    NSButton *_btnReveal, *_btnRefresh;
    NSArray<ZHistoryEntry *> *_rows;
    // اپی که وقتی این پنجره باز شد جلو بود. پنجره nonactivating است، پس معمولا
    // همان هنوز جلوست و درج سر کرسرِ خودش می‌نشیند؛ این فقط تورِ ایمنی است.
    NSRunningApplication *_target;
    NSInteger _flashGen;
}

+ (instancetype)shared {
    static ZHistoryPanel *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [ZHistoryPanel new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _rows = @[];
        [self build];
        // متنِ تازه که تحویل شد، همین‌جا هم دیده شود. بی این، پنجره‌ی باز یک عکسِ
        // کهنه می‌ماند و کاربر فکر می‌کند دیکته‌اش ثبت نشده ــ دقیقا برعکسِ کاری
        // که این پنجره برایش هست.
        __weak typeof(self) ws = self;
        [NSNotificationCenter.defaultCenter addObserverForName:ZHistoryDidChangeNotification
                                                        object:nil queue:nil
                                                    usingBlock:^(NSNotification *n) {
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) me = ws;
                if (me && me->_panel.isVisible) [me reload];
            });
        }];
    }
    return self;
}

// ---------- ساخت ----------

- (void)build {
    _panel = [[ZHistoryWindow alloc] initWithContentRect:NSMakeRect(0, 0, kHW, kHH)
                                              styleMask:NSWindowStyleMaskTitled
                                                       | NSWindowStyleMaskClosable
                                                       | NSWindowStyleMaskResizable
                                                       | NSWindowStyleMaskFullSizeContentView
                                                       | NSWindowStyleMaskNonactivatingPanel
                                                backing:NSBackingStoreBuffered defer:NO];
    _panel.title = @"تاریخچه‌ی متن‌ها";
    _panel.titlebarAppearsTransparent = YES;
    _panel.movableByWindowBackground = YES;
    _panel.delegate = self;
    _panel.releasedWhenClosed = NO;
    _panel.hidesOnDeactivate = NO;
    _panel.minSize = NSMakeSize(460, 340);
    _panel.alphaValue = 0.97;
    // **nonactivating، و این مهم‌ترین انتخابِ این پنجره است.** پنجره‌ای که اپ را جلو
    // بیاورد، کرسرِ کاربر را از جایی که بود می‌کَنَد، و بعد دکمه‌ی «درج» دیگر
    // نمی‌داند کجا بنویسد. این‌طوری اپی که پشت پنجره است جلو می‌ماند و درج دقیقا
    // همان‌جا می‌نشیند که کاربر رهایش کرده بود.
    _panel.level = NSFloatingWindowLevel;
    _panel.floatingPanel = YES;
    _panel.becomesKeyOnlyIfNeeded = YES;
    _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                              | NSWindowCollectionBehaviorFullScreenAuxiliary;

    _back = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, kHW, kHH)];
    _back.material = NSVisualEffectMaterialHUDWindow;
    _back.state = NSVisualEffectStateActive;
    _back.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _back.wantsLayer = YES;
    _panel.contentView = _back;

    NSString *path = ZHistoryFile().path;
    _btnReveal = [self button:@"folder"
                          tip:[NSString stringWithFormat:@"نشان دادن فایل تاریخچه در فایندر:\n%@", path]
                       action:@selector(tapReveal)];
    _btnRefresh = [self button:@"arrow.clockwise" tip:@"تازه کردن فهرست" action:@selector(tapRefresh)];

    _status = [NSTextField labelWithString:@""];
    _status.font = ZFont(11.5, NO);
    _status.textColor = NSColor.tertiaryLabelColor;
    _status.alignment = NSTextAlignmentRight;
    _status.lineBreakMode = NSLineBreakByTruncatingTail;
    _status.toolTip = path;
    [_back addSubview:_status];

    [self buildTable];
    [self buildFull];
    [self layoutViews];
}

- (NSButton *)button:(NSString *)symbol tip:(NSString *)tip action:(SEL)action {
    NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip];
    if (!img) ZLog(@"historyui: SF Symbol پیدا نشد: %@", symbol);
    img = [img imageWithSymbolConfiguration:
           [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium]];
    NSButton *b = [NSButton buttonWithImage:img ?: [NSImage new] target:self action:action];
    b.bordered = NO;
    b.buttonType = NSButtonTypeMomentaryChange;
    b.contentTintColor = NSColor.secondaryLabelColor;
    b.toolTip = tip;
    [_back addSubview:b];
    return b;
}

- (void)buildTable {
    _tableScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    _tableScroll.hasVerticalScroller = YES;
    _tableScroll.drawsBackground = NO;
    _tableScroll.borderType = NSNoBorder;

    _table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    _table.style = NSTableViewStylePlain;
    _table.backgroundColor = NSColor.clearColor;
    _table.gridStyleMask = NSTableViewGridNone;
    _table.rowHeight = kHRow;
    _table.usesAlternatingRowBackgroundColors = NO;
    _table.allowsMultipleSelection = NO;
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.doubleAction = @selector(tapRowInsertSelected);
    _table.userInterfaceLayoutDirection = NSUserInterfaceLayoutDirectionRightToLeft;
    _table.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;

    // راست‌به‌چپ یعنی ستون اول راست‌ترین است، پس متن ــ که کاربر برایش آمده ــ اول
    // می‌آید و کشسان است. دو دکمه ته صف، چون کارند نه اطلاعات.
    //
    // عددها با کمینه‌ی پهنای پنجره (۴۶۰) جمع بسته شده‌اند، نه با پهنای پیش‌فرض: جدولِ
    // مک به ازای هر ستون حدود ۱۷ نقطه فاصله‌ی خودش را هم اضافه می‌کند، و اولین
    // نسخه‌ی همین جدول ۶۳۹ نقطه درمی‌آمد داخل قابی ۵۹۲ نقطه‌ای. نتیجه‌اش این بود که
    // لبه‌ی راستِ ستونِ متن بیرون از قاب می‌افتاد و سرستونِ «متن» ــ که راست‌چین است
    // ــ اصلا دیده نمی‌شد.
    NSArray *cols = @[@[@"text", @"متن", @240, @80], @[@"when", @"زمان", @92, @92],
                      @[@"app", @"برنامه", @96, @96],
                      @[@"insert", @"درج", @34, @34], @[@"copy", @"کپی", @34, @34]];
    for (NSArray *c in cols) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        BOOL flex = [c[0] isEqualToString:@"text"];
        col.title = c[1];
        col.width = [c[2] doubleValue];
        col.minWidth = [c[3] doubleValue];
        col.maxWidth = flex ? 10000 : [c[2] doubleValue];
        col.headerCell.font = ZFont(10.5, NO);
        col.headerCell.alignment = NSTextAlignmentRight;
        [_table addTableColumn:col];
    }
    _tableScroll.documentView = _table;
    [_back addSubview:_tableScroll];
}

// یک خطِ فهرست هرچقدر هم پهن باشد، متنِ چند خطی را نشان نمی‌دهد. این جعبه همان
// ردیفِ انتخاب‌شده را کامل نشان می‌دهد، پس «مرور» واقعا مرور است نه حدس زدن از
// روی چند کلمه‌ی اول.
- (void)buildFull {
    _fullCap = [NSTextField labelWithString:@"متن کامل"];
    _fullCap.font = ZFont(10.5, NO);
    _fullCap.textColor = NSColor.tertiaryLabelColor;
    _fullCap.alignment = NSTextAlignmentRight;
    [_back addSubview:_fullCap];

    _fullBox = [NSView new];
    _fullBox.wantsLayer = YES;
    _fullBox.layer.cornerRadius = 8;
    _fullBox.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.06].CGColor;
    _fullBox.layer.borderWidth = 1;
    _fullBox.layer.borderColor = [NSColor.labelColor colorWithAlphaComponent:0.12].CGColor;
    [_back addSubview:_fullBox];

    _fullScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    _fullScroll.hasVerticalScroller = YES;
    _fullScroll.autohidesScrollers = NO;
    _fullScroll.scrollerStyle = NSScrollerStyleLegacy;
    _fullScroll.drawsBackground = NO;
    _fullScroll.borderType = NSNoBorder;
    _full = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    _full.font = ZFont(13, NO);
    _full.textColor = NSColor.labelColor;
    _full.drawsBackground = NO;
    _full.editable = NO;
    _full.selectable = YES;
    _full.richText = NO;
    _full.baseWritingDirection = NSWritingDirectionRightToLeft;
    _full.alignment = NSTextAlignmentRight;
    _full.textContainerInset = NSMakeSize(4, 8);
    _full.minSize = NSMakeSize(0, 0);
    _full.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _full.verticallyResizable = YES;
    _full.horizontallyResizable = NO;
    _full.autoresizingMask = NSViewWidthSizable;
    _full.textContainer.widthTracksTextView = YES;
    _fullScroll.documentView = _full;
    [_fullBox addSubview:_fullScroll];
}

- (void)layoutViews {
    NSSize sz = _back.frame.size;
    CGFloat top = sz.height - 34;              // زیر نوار عنوان شفاف
    CGFloat right = sz.width - kHEdge;

    CGFloat x = right - 24;
    _btnReveal.frame = NSMakeRect(kHEdge, top - 24, 24, 24);
    _btnRefresh.frame = NSMakeRect(kHEdge + 30, top - 24, 24, 24);
    CGFloat statusLeft = kHEdge + 64;
    _status.frame = NSMakeRect(statusLeft, top - 21, right - statusLeft, 18);
    (void)x;

    CGFloat fullTop = kHEdge + kHFull;
    _fullBox.frame = NSMakeRect(kHEdge, kHEdge, sz.width - kHEdge * 2, kHFull);
    _fullScroll.frame = NSMakeRect(2, 2, _fullBox.frame.size.width - 4, kHFull - 4);
    _fullCap.frame = NSMakeRect(kHEdge, fullTop + 4, sz.width - kHEdge * 2, 14);

    CGFloat tableTop = top - 32;
    CGFloat tableBottom = fullTop + 24;
    _tableScroll.frame = NSMakeRect(kHEdge, tableBottom,
                                    sz.width - kHEdge * 2, MAX(60, tableTop - tableBottom));
    // و بعد از هر تغییر اندازه، ستون‌ها دقیقا به پهنای قاب برگردند. جدول به‌خودی‌خود
    // پهنای مجموع ستون‌ها را می‌گیرد، نه پهنای قاب را؛ کمینه و بیشینه‌ی ستون‌ها
    // بالا قفل است، پس تنها ستونی که این خط می‌تواند بکشد یا جمع کند همان «متن» است.
    [_table sizeToFit];
}

- (void)windowDidResize:(NSNotification *)n { [self layoutViews]; }

// بستن یعنی پنهان شدن، نه نابودی: پنجره سنگین نیست و باز کردن دوباره‌اش باید آنی باشد
- (BOOL)windowShouldClose:(NSWindow *)sender {
    [_panel orderOut:nil];
    [self saveFrame];
    return NO;
}

- (void)windowDidMove:(NSNotification *)n {
    if (_panel.isVisible) [self saveFrame];
}

// ---------- نمایش ----------

- (void)saveFrame {
    NSRect f = _panel.frame;
    [NSUserDefaults.standardUserDefaults setObject:
     [NSString stringWithFormat:@"%.0f,%.0f,%.0f,%.0f", f.origin.x, f.origin.y, f.size.width, f.size.height]
                                            forKey:@"historyPanelFrame"];
}

- (BOOL)visible { return _panel.isVisible; }

- (void)toggle {
    if (_panel.isVisible) {
        [_panel orderOut:nil];
        [self saveFrame];
        return;
    }
    [self show];
}

- (void)show {
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:@"historyPanelFrame"];
    if (saved && !_panel.isVisible) {
        NSArray *p = [saved componentsSeparatedByString:@","];
        if (p.count == 4) {
            NSRect f = NSMakeRect([p[0] doubleValue], [p[1] doubleValue],
                                  MAX(460, [p[2] doubleValue]), MAX(340, [p[3] doubleValue]));
            // جای ذخیره‌شده ممکن است روی مانیتوری باشد که دیگر وصل نیست
            BOOL onScreen = NO;
            for (NSScreen *sc in NSScreen.screens) {
                if (NSIntersectsRect(f, sc.visibleFrame)) onScreen = YES;
            }
            if (onScreen) [_panel setFrame:f display:NO];
        }
    } else if (!_panel.isVisible) {
        [_panel center];
    }
    [self rememberTarget];
    [self reload];
    // orderFrontRegardless و نه makeKeyAndOrderFront: اپِ کاربر باید جلو بماند
    [_panel orderFrontRegardless];
    [self layoutViews];
}

- (void)hide {
    if (!_panel.isVisible) return;
    [_panel orderOut:nil];
    [self saveFrame];
}

// عکسِ بازبینی طراحی. پنجره را بی‌اجازه‌ی ضبطِ صفحه فقط از داخل خودِ پروسه می‌شود
// دید، پس هر پنجره‌ی این اپ راهِ خودش را دارد؛ این هم مالِ همین یکی.
//
// جدولِ ویو-محور با یک reloadData پر نمی‌شود: ردیف‌ها را ران‌لوپ می‌سازد. برای همین
// عکس یک چرخِ ران‌لوپ بعد گرفته می‌شود، وگرنه یک قابِ خالی درمی‌آید.
- (void)makeShots:(NSString *)dir then:(void (^)(void))done {
    [self show];
    [_back layoutSubtreeIfNeeded];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSBitmapImageRep *rep = [self->_back bitmapImageRepForCachingDisplayInRect:self->_back.bounds];
        if (rep) {
            [self->_back cacheDisplayInRect:self->_back.bounds toBitmapImageRep:rep];
            NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            [png writeToFile:[dir stringByAppendingPathComponent:@"history.png"] atomically:YES];
        }
        [self->_panel orderOut:nil];
        if (done) done();
    });
}

// ---------- داده ----------

- (void)reload {
    _rows = ZHistoryRecent(kZHistoryPanelRows);
    [_table reloadData];
    if (_rows.count && _table.selectedRow < 0) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
    [self showFullForSelection];
    [self setHint];
}

- (void)setHint {
    if (!_rows.count) {
        _status.stringValue = @"هنوز متنی تحویل نشده. بعد از اولین دیکته اینجا پر می‌شود.";
        return;
    }
    // اشاره به انبارِ کامل، همیشه: این فهرست بیست‌تایی است ولی فایل همه را دارد،
    // و کاربری که دنبال متنِ سه هفته پیش است باید بداند کجا را بگردد.
    _status.stringValue = [NSString stringWithFormat:
        @"%@ متن آخر. همه‌ی متن‌ها %@ روز در فایل تاریخچه می‌مانند؛ با دکمه‌ی پوشه بازش کن.",
        ZFaDigits(@(_rows.count).stringValue),
        ZFaDigits(@(ZSettings.shared.historyKeepDays).stringValue)];
}

- (void)showFullForSelection {
    NSInteger i = _table.selectedRow;
    _full.string = (i >= 0 && i < (NSInteger)_rows.count) ? _rows[i].text : @"";
    [_full scrollRangeToVisible:NSMakeRange(0, 0)];
}

- (void)tableViewSelectionDidChange:(NSNotification *)n { [self showFullForSelection]; }

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)_rows.count; }

// متنِ چندخطی در یک ردیفِ یک‌خطی: فاصله‌ها و خطوط جدید به یک فاصله جمع می‌شوند،
// وگرنه ردیف با یک حفره‌ی بی‌معنی شروع می‌شد.
static NSString *zOneLine(NSString *s) {
    NSMutableArray *keep = [NSMutableArray array];
    for (NSString *p in [s componentsSeparatedByCharactersInSet:
                         NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (p.length) [keep addObject:p];
    }
    return [keep componentsJoinedByString:@" "];
}

// تاریخِ شمسی و ساعت، ولی فقط آن‌قدر که لازم است: متنِ امروز ساعت می‌خواهد نه تاریخ.
static NSString *zWhen(NSDate *d) {
    static NSDateFormatter *clock, *older;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSLocale *fa = [NSLocale localeWithLocaleIdentifier:@"fa_IR"];
        NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierPersian];
        clock = [NSDateFormatter new];
        clock.locale = fa; clock.calendar = cal; clock.dateFormat = @"HH:mm";
        older = [NSDateFormatter new];
        older.locale = fa; older.calendar = cal; older.dateFormat = @"d MMMM، HH:mm";
    });
    if (!d) return @"";
    if ([NSCalendar.currentCalendar isDateInToday:d]) return [clock stringFromDate:d];
    if ([NSCalendar.currentCalendar isDateInYesterday:d]) {
        return [NSString stringWithFormat:@"دیروز %@", [clock stringFromDate:d]];
    }
    return [older stringFromDate:d];
}

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)_rows.count) return nil;
    ZHistoryEntry *e = _rows[i];

    BOOL isInsert = [col.identifier isEqualToString:@"insert"];
    if (isInsert || [col.identifier isEqualToString:@"copy"]) {
        // همان دو آیکونی که روی نوار شناور هم همین دو کار را می‌کنند. یک معنی،
        // یک شکل: کاربر لازم نیست دو بار یاد بگیرد.
        NSString *sym = isInsert ? @"text.insert" : @"doc.on.doc";
        NSString *tip = isInsert ? @"درج این متن سر کرسر، در برنامه‌ای که پشت این پنجره است"
                                 : @"کپی این متن";
        NSImage *img = [NSImage imageWithSystemSymbolName:sym accessibilityDescription:tip];
        img = [img imageWithSymbolConfiguration:
               [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightMedium]];
        NSButton *b = [NSButton buttonWithImage:img ?: [NSImage new] target:self
                                         action:isInsert ? @selector(tapRowInsert:) : @selector(tapRowCopy:)];
        b.bordered = NO;
        b.buttonType = NSButtonTypeMomentaryChange;
        b.contentTintColor = NSColor.secondaryLabelColor;
        b.toolTip = tip;
        b.tag = i;
        b.frame = NSMakeRect(0, 0, col.width, kHRow);
        return b;
    }

    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, col.width, kHRow)];
    f.bezeled = NO;
    f.editable = NO;
    f.selectable = NO;
    f.drawsBackground = NO;
    f.autoresizingMask = NSViewWidthSizable;
    f.font = ZFont(11.5, NO);
    f.alignment = NSTextAlignmentRight;
    f.lineBreakMode = NSLineBreakByTruncatingTail;
    if ([col.identifier isEqualToString:@"text"]) {
        f.stringValue = zOneLine(e.text);
        f.textColor = NSColor.labelColor;
    } else if ([col.identifier isEqualToString:@"when"]) {
        f.stringValue = zWhen(e.at);
        f.textColor = NSColor.secondaryLabelColor;
        f.toolTip = e.sid.length ? [NSString stringWithFormat:@"پوشه‌ی سشن: %@", e.sid] : nil;
    } else {
        f.stringValue = e.app ?: @"";
        f.textColor = NSColor.secondaryLabelColor;
    }
    return f;
}

// ---------- کارها ----------

- (void)rememberTarget {
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (front && front.processIdentifier != NSProcessInfo.processInfo.processIdentifier) _target = front;
}

- (ZHistoryEntry *)entryAt:(NSInteger)i {
    return (i >= 0 && i < (NSInteger)_rows.count) ? _rows[i] : nil;
}

- (void)tapRowCopy:(NSButton *)b {
    ZHistoryEntry *e = [self entryAt:b.tag];
    if (!e) return;
    [ZInjector copyFinal:e.text];
    ZPlay(ZSoundCopy);
    [self flash:@"کپی شد"];
}

- (void)tapRowInsert:(NSButton *)b { [self insertEntry:[self entryAt:b.tag]]; }

- (void)tapRowInsertSelected { [self insertEntry:[self entryAt:_table.selectedRow]]; }

// همان مسیرِ درجِ سشن، مو به مو: کپیِ بیمه‌ای اول، بعد درج، و کپیِ پایانی پشتِ صف
// درج (وگرنه در ریموت دسکتاپ نشانه‌ی transient آخرین چیزِ کلیپ‌بورد می‌ماند).
- (void)insertEntry:(ZHistoryEntry *)e {
    if (!e.text.length) return;
    [self rememberTarget];
    NSRunningApplication *to = _target ?: NSWorkspace.sharedWorkspace.frontmostApplication;
    if (!to) { [self flash:@"برنامه‌ای برای درج پیدا نشد"]; return; }
    [ZInjector copyFinal:e.text];
    ZInjector *inj = [ZInjector new];
    ZInsertMode im = [ZSettings.shared insertModeForBundleId:to.bundleIdentifier];
    [inj insert:e.text pid:to.processIdentifier
    delayMicros:ZSettings.shared.typeDelayMicros
 pasteIfRefused:im == ZInsertPaste
           done:^(BOOL viaAX) {
        ZLog(@"historyui: درج شد (ax=%d، %lu نویسه)", viaAX, (unsigned long)e.text.length);
    }];
    [inj copyFinalAfterPending:e.text];
    ZPlay(ZSoundInsert);
    [self flash:[NSString stringWithFormat:@"درج شد در %@", to.localizedName ?: @"برنامه‌ی جلویی"]];
}

- (void)tapRefresh { [self reload]; }

- (void)tapReveal {
    NSURL *f = ZHistoryFile();
    if ([NSFileManager.defaultManager fileExistsAtPath:f.path]) {
        [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[f]];
    } else {
        [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[ZSupport()]];
    }
}

// ---------- خودآزمای پنجره ----------
// zemzeme --historycheck
//
// چرا داخل خودِ اپ و نه از بیرون: زدنِ یک دکمه از پوسته «دسترسی کمکی» می‌خواهد و
// این دستگاه آن را به پوسته نداده. اپ خودش دارد، و به دکمه‌های خودش از همه
// نزدیک‌تر است. پس دقیقا همان کاری را می‌کند که انگشتِ کاربر می‌کند: ردیفِ واقعی از
// انبارِ واقعی، دکمه‌ای که خودِ جدول ساخته، و performClick که همان target/action را
// می‌زند. بعد می‌پرسد روی کلیپ‌بورد **دقیقا** چه نشست.
//
// کلیپ‌بورد کاربر سر جایش برمی‌گردد: این آزمون است، نه دزدی از میز کار کسی.
- (void)runCheck:(void (^)(int fails))done {
    [self show];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __block int fails = 0;
        NSPasteboard *pb = NSPasteboard.generalPasteboard;
        NSString *saved = [pb stringForType:NSPasteboardTypeString];

        if (!self->_rows.count) {
            ZLog(@"historycheck: ✗ تاریخچه خالی است؛ اول یک دیکته لازم است");
            if (done) done(1);
            return;
        }
        ZHistoryEntry *e = self->_rows[0];
        void (^clickAndCheck)(NSString *, NSString *) = ^(NSString *colId, NSString *label) {
            NSInteger c = [self->_table columnWithIdentifier:colId];
            NSView *v = [self->_table viewAtColumn:c row:0 makeIfNecessary:YES];
            if (![v isKindOfClass:NSButton.class]) {
                ZLog(@"historycheck: ✗ دکمه‌ی %@ در ردیف پیدا نشد", label);
                fails++;
                return;
            }
            [pb clearContents];
            [pb declareTypes:@[NSPasteboardTypeString] owner:nil];
            [pb setString:@"<هیچ>" forType:NSPasteboardTypeString];
            [(NSButton *)v performClick:nil];
            NSString *got = [pb stringForType:NSPasteboardTypeString];
            if ([got isEqualToString:e.text]) {
                ZLog(@"historycheck: ok %@ ــ %lu نویسه، بایت‌به‌بایت همان متنِ انبار",
                     label, (unsigned long)e.text.length);
            } else {
                ZLog(@"historycheck: ✗ %@ ــ متن یکی نشد (%lu نویسه آمد، %lu انتظار می‌رفت)",
                     label, (unsigned long)got.length, (unsigned long)e.text.length);
                fails++;
            }
        };
        // کپی: کلیپ‌بورد باید همان متن شود.
        clickAndCheck(@"copy", @"کپی");
        // درج: پیش از هر تزریقی همان متن را روی کلیپ‌بورد می‌گذارد (بیمه‌ی پایانی)،
        // پس همین ادعا اینجا هم برقرار است ــ و تزریق روی اپِ جلویی می‌رود، که
        // اجرای بیرونی مقصدش را تعیین می‌کند.
        clickAndCheck(@"insert", @"درج");

        // مهلت، چون درج آسنکرون است و روی صف خودش می‌نشیند: خروجِ زودهنگام تزریق را
        // نصفه رها می‌کند و آزمون چیزی را می‌سنجد که هنوز نیفتاده.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (saved) {
                [pb clearContents];
                [pb declareTypes:@[NSPasteboardTypeString] owner:nil];
                [pb setString:saved forType:NSPasteboardTypeString];
            }
            if (done) done(fails);
        });
    });
}

// پیام کوتاه روی همان خط وضعیت، و بعد برگشت به جمله‌ی همیشگی. شمارنده لازم است
// وگرنه دو کلیکِ پشت هم، اولی جمله را زودتر از موعد برمی‌گرداند.
- (void)flash:(NSString *)msg {
    _status.stringValue = msg;
    NSInteger gen = ++_flashGen;
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) me = ws;
        if (me && me->_flashGen == gen) [me setHint];
    });
}

@end
