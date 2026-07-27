// پنل رونویسی فایل: صف، پیشرفت زنده، متن یکجای قابل ویرایش.
//
// چرا پنل و نه رابط وب: مسیر دسته‌ای از قبل کار می‌کرد، فقط از خط فرمان. سرور و
// HTML یعنی یک وابستگی و یک سطح حمله‌ی تازه برای کاری که خودِ AppKit می‌کند.
// چرا این پنل با نوار شناور (ZPanel) فرق دارد: آن نباید هیچ‌وقت فوکس بگیرد (وسط
// دیکته کرسر باید در اپ مقصد بماند)، ولی اینجا کاربر باید در ادیتور تایپ کند و
// ردیف‌ها را با موس جابه‌جا کند. پس این یکی پنجره‌ی واقعی است: عنوان‌دار، بستنی،
// قابل تغییر اندازه. جنسِ دیداری همان است: شیشه‌ی HUD، گوشه‌ی گرد، Vazirmatn، راست‌به‌چپ.
//
// قرارداد نخ: هر کار سنگین (دیکد، رونویسی، پاس ویرایش، حتی خواندن طول فایل) روی نخ
// پس‌زمینه است و فقط رندر روی نخ اصلی. بستن پنجره کار در جریان را نمی‌کشد: کار مال
// ZBatchJob است، نه مال پنجره.
#import "zemzeme.h"

static const CGFloat kBW = 640;        // پهنای پیش‌فرض
static const CGFloat kBH = 560;
static const CGFloat kRowStep = 30;    // گام دکمه‌های نوار بالا
static const CGFloat kEdge = 14;

// نوع اختصاصی درگ ردیف‌ها. فایل‌ها با NSPasteboardTypeFileURL می‌آیند، پس دو نوع در
// یک جدول ثبت می‌شود و از هم قابل تفکیک‌اند.
static NSString *const kZRowType = @"io.seyed.zemzeme.batchrow";

NSNotificationName const ZBatchActivity = @"ZBatchActivity";

typedef NS_ENUM(NSInteger, ZRowState) {
    ZRowQueued,
    ZRowRunning,
    ZRowDone,
    ZRowError,
    ZRowStopped,
};

// ---------- یک ردیف صف ----------

@interface ZBatchRow : NSObject
@property (nonatomic, strong) NSURL *url;
@property (nonatomic) double duration;    // ۰ یعنی هنوز خوانده نشده
@property (nonatomic) double doneSec;
@property (nonatomic) ZRowState state;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *note;    // دلیل خطا، همان‌جا روی ردیف
@property (nonatomic, copy) NSString *lang;    // زبان همین فایل؛ سر افزودن از پیش‌فرض پر می‌شود
@end

@implementation ZBatchRow

- (double)fraction {
    if (self.state == ZRowDone) return 1;
    if (self.duration <= 0) return 0;
    return MIN(1.0, MAX(0.0, self.doneSec / self.duration));
}

- (NSString *)stateLabel {
    switch (self.state) {
        case ZRowQueued:  return @"در صف";
        case ZRowRunning: return @"در حال کار";
        case ZRowDone:    return @"تمام";
        case ZRowStopped: return @"متوقف";
        case ZRowError:   return self.note.length ? self.note : @"خطا";
    }
}

@end

// زمان به دقیقه:ثانیه با رقم فارسی. خط تیره یعنی هنوز طولش را نخوانده‌ایم.
static NSString *ZClock(double sec) {
    if (!(sec > 0)) return @"—";
    int s = (int)round(sec);
    return ZFaDigits([NSString stringWithFormat:@"%d:%02d", s / 60, s % 60]);
}

// ---------- نوار پیشرفت ردیف ----------
// NSLevelIndicator و NSProgressIndicator هر دو روی شیشه‌ی HUD جسم سنگینی می‌سازند و
// رنگ سیستمی خودشان را می‌آورند. این یکی دو مستطیل است و درصد را هم خودش می‌نویسد.

@interface ZBarView : NSView
@property (nonatomic) double value;      // ۰ تا ۱
@property (nonatomic) BOOL dim;          // ردیف تمام‌شده یا متوقف: کم‌رنگ
@end

@implementation ZBarView

- (void)setValue:(double)v {
    _value = v;
    self.needsDisplay = YES;
}

// راست‌به‌چپ، مثل بقیه‌ی پنل: درصد سمت راست می‌نشیند و نوار از راست پر می‌شود.
// چپ‌به‌راست بودنش تنها چیزی بود که در کل پنجره برعکس خوانده می‌شد.
- (void)drawRect:(NSRect)r {
    CGFloat h = 5, y = (self.bounds.size.height - h) / 2;
    CGFloat labelW = 34, gap = 6;
    NSDictionary *attrs = @{NSFontAttributeName: ZFont(10, NO),
                            NSForegroundColorAttributeName: NSColor.tertiaryLabelColor};
    NSString *pct = ZFaDigits([NSString stringWithFormat:@"%d٪", (int)round(_value * 100)]);
    NSSize sz = [pct sizeWithAttributes:attrs];
    CGFloat right = self.bounds.size.width;
    [pct drawAtPoint:NSMakePoint(right - sz.width, (self.bounds.size.height - sz.height) / 2)
      withAttributes:attrs];
    NSRect track = NSMakeRect(0, y, MAX(0, right - labelW - gap), h);
    [[NSColor.labelColor colorWithAlphaComponent:0.12] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:track xRadius:h / 2 yRadius:h / 2] fill];
    if (_value > 0) {
        CGFloat w = MAX(h, track.size.width * MIN(1.0, _value));
        NSRect fill = NSMakeRect(NSMaxX(track) - w, y, w, h);
        NSColor *c = _dim ? [NSColor.labelColor colorWithAlphaComponent:0.35]
                          : [NSColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1];
        [c setFill];
        [[NSBezierPath bezierPathWithRoundedRect:fill xRadius:h / 2 yRadius:h / 2] fill];
    }
}

@end

// ---------- پس‌زمینه‌ی شیشه‌ای با پذیرش فایل ----------
// افتادن فایل روی هر جای پنل باید کار کند، نه فقط روی جدول: کسی که فایل را می‌کشد
// دقیقا نمی‌داند مرز جدول کجاست.

@interface ZBatchBackdrop : NSVisualEffectView
@property (nonatomic, copy) void (^onFiles)(NSArray<NSURL *> *urls);
@end

@implementation ZBatchBackdrop

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return [sender.draggingPasteboard canReadObjectForClasses:@[NSURL.class] options:nil]
        ? NSDragOperationCopy : NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray *urls = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class]
                                                            options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (!urls.count) return NO;
    if (self.onFiles) self.onFiles(urls);
    return YES;
}

@end

// ---------- پنل ----------

@interface ZBatchPanel () <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
@end

@implementation ZBatchPanel {
    NSPanel *_panel;
    ZBatchBackdrop *_back;
    NSTableView *_table;
    NSScrollView *_tableScroll;
    NSTextView *_editor;
    NSScrollView *_editorScroll;
    NSTextField *_status;
    NSPopUpButton *_jobsPop;
    NSPopUpButton *_langPop;
    NSButton *_btnHistory;
    NSView *_editorBox;       // قاب دورِ ادیتور، که متن «همین‌طور آن زیر» نیفتد
    NSTextField *_editorCap;
    NSButton *_btnAdd, *_btnStart, *_btnStop, *_btnRemove;
    NSButton *_btnJoin, *_btnPolish, *_btnEnhance, *_btnCopy, *_btnSave;
    // متنِ پیش از بهبود پرامپت. نال یعنی الان متنِ دیکته در ادیتور است، پرش یعنی
    // پرامپت نشسته و همان دکمه این بار برمی‌گرداندش. جای میان‌برِ `R` را می‌گیرد: این
    // پنجره میان‌بر ندارد، پس چرخش باید روی خودِ دکمه سوار شود.
    NSString *_preEnhance;
    NSArray<NSButton *> *_bar;
    NSMutableArray<ZBatchRow *> *_rows;
    ZBatchJob *_job;
    BOOL _stopping;
    BOOL _polishing;
    NSString *_autoText;      // آخرین متنی که خودمان در ادیتور گذاشتیم
    dispatch_queue_t _probeQ;
    NSInteger _flashGen;
}

+ (instancetype)shared {
    static ZBatchPanel *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [ZBatchPanel new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _rows = [NSMutableArray array];
        _probeQ = dispatch_queue_create("zemzeme.batch.probe", DISPATCH_QUEUE_SERIAL);
        [self build];
    }
    return self;
}

// ---------- ساخت ----------

- (void)build {
    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, kBW, kBH)
                                        styleMask:NSWindowStyleMaskTitled
                                                | NSWindowStyleMaskClosable
                                                | NSWindowStyleMaskResizable
                                                | NSWindowStyleMaskFullSizeContentView
                                          backing:NSBackingStoreBuffered defer:NO];
    _panel.title = @"رونویسی فایل";
    // نوار عنوان شفاف است و شیشه از زیرش دیده می‌شود، ولی عنوان و دکمه‌ی بستن سر
    // جایشان می‌مانند: این پنجره باید مثل پنجره رفتار کند، نه مثل یک نوار بی‌نام.
    _panel.titlebarAppearsTransparent = YES;
    _panel.movableByWindowBackground = YES;
    _panel.delegate = self;
    _panel.releasedWhenClosed = NO;
    // اپ اکسسوری است و پنل پیش‌فرضِ NSPanel سر غیرفعال شدن اپ پنهان می‌شود. اینجا
    // نباید: کار ممکن است ربع ساعت طول بکشد و کاربر در همان فاصله سراغ اپ دیگری برود.
    _panel.hidesOnDeactivate = NO;
    _panel.minSize = NSMakeSize(520, 420);
    _panel.alphaValue = 0.97;    // شیشه‌ای، ولی نه آن‌قدر که جدول و متن سخت خوانده شوند

    _back = [[ZBatchBackdrop alloc] initWithFrame:NSMakeRect(0, 0, kBW, kBH)];
    _back.material = NSVisualEffectMaterialHUDWindow;
    _back.state = NSVisualEffectStateActive;
    _back.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    // لایه لازم است، وگرنه شیشه در عکسِ درون‌پروسه‌ای (cacheDisplayInRect) سفید درمی‌آید
    // و بازبینی طراحی هیچ‌چیز نشان نمی‌دهد. همان کاری که نوار شناور هم می‌کند.
    _back.wantsLayer = YES;
    [_back registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    __weak typeof(self) ws = self;
    _back.onFiles = ^(NSArray<NSURL *> *urls) { [ws addFiles:urls]; };
    _panel.contentView = _back;

    _btnAdd = [self button:@"plus" tip:@"افزودن فایل صوتی یا تصویری (می‌توانی فایل را روی پنل هم بکشی)"
                    action:@selector(tapAdd)];
    _btnStart = [self button:@"play.fill" tip:@"شروع رونویسی صفِ در انتظار" action:@selector(tapStart)];
    _btnStop = [self button:@"stop.fill" tip:@"توقف؛ متن هرچه تا اینجا شنیده شده می‌ماند"
                    action:@selector(tapStop)];
    _btnRemove = [self button:@"minus" tip:@"حذف ردیف انتخاب‌شده از صف" action:@selector(tapRemove)];
    _btnJoin = [self button:@"text.append" tip:@"چسباندن متن همه‌ی فایل‌ها، به همین ترتیب صف"
                     action:@selector(tapJoin)];
    _btnPolish = [self button:@"wand.and.stars"
                          tip:@"پاس نهایی: نیم‌فاصله، نقطه‌گذاری و املا روی متن یکجا"
                       action:@selector(tapPolish)];
    // بهبود پرامپت (بتا): همان کار پنل شناور، روی متن یکجای همین پنجره.
    _btnEnhance = [self button:@"curlybraces"
                           tip:@"بهبود پرامپت (بتا): همین متن، به یک پرامپت آماده برای ایجنت"
                        action:@selector(tapEnhance)];
    _btnCopy = [self button:@"doc.on.doc" tip:@"کپی متن یکجا" action:@selector(tapCopy)];
    _btnSave = [self button:@"square.and.arrow.down" tip:@"ذخیره‌ی متن یکجا در یک فایل"
                    action:@selector(tapSave)];
    _btnHistory = [self button:@"clock.arrow.circlepath"
                           tip:@"تاریخچه: متن اجراهای قبلی را دوباره باز کن"
                        action:@selector(tapHistory)];
    _bar = @[_btnAdd, _btnStart, _btnStop, _btnRemove,
             _btnJoin, _btnPolish, _btnEnhance, _btnCopy, _btnSave, _btnHistory];

    // هم‌زمانی: پیش‌فرض ۲ می‌ماند. تولتیپ هشدار را می‌گوید، چون این عدد فقط سرعت نیست،
    // سهمِ کلید مشترک است.
    _jobsPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 56, 22) pullsDown:NO];
    _jobsPop.font = ZFont(11, NO);
    _jobsPop.bezelStyle = NSBezelStyleInline;
    // عدد خالی معنایش پیدا نبود؛ خود گزینه می‌گوید چه چیزی را می‌شمارد
    for (NSInteger n = 1; n <= 4; n++) {
        [_jobsPop addItemWithTitle:[ZFaDigits([NSString stringWithFormat:@"%ld", (long)n])
                                    stringByAppendingString:@" سشن"]];
    }
    NSInteger saved = [NSUserDefaults.standardUserDefaults objectForKey:@"batchJobs"]
        ? [NSUserDefaults.standardUserDefaults integerForKey:@"batchJobs"] : 2;
    [_jobsPop selectItemAtIndex:MAX(1, MIN(4, saved)) - 1];
    _jobsPop.target = self;
    _jobsPop.action = @selector(tapJobs);
    _jobsPop.toolTip = @"چند سشن هم‌زمان. پیش‌فرض ۲ عمدا محافظه‌کارانه است: کلید گوگل با "
                        "دیکته‌ی زنده مشترک است و اجرای سنگین برای مدتی «لالش» می‌کند، پس "
                        "دیکته‌ی زنده هم سهمش را می‌بیند. بالا بردنش سرعت می‌دهد و ریسک.";
    [_back addSubview:_jobsPop];

    // زبان پیش‌فرض صف؛ جدا از زبان دیکته‌ی زنده. عوض کردنش همه‌ی ردیف‌های در انتظار
    // را هم می‌چرخاند (خواسته‌ی صریح: «پیش‌فرض را کردم فارسی، صف هم فارسی شود»)؛
    // ردیف در حال کار و تمام‌شده دست نمی‌خورند و زبان تک‌ردیف از ستون خودش عوض می‌شود.
    _langPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 84, 22) pullsDown:NO];
    _langPop.font = ZFont(11, NO);
    _langPop.bezelStyle = NSBezelStyleInline;
    [_langPop addItemWithTitle:@"فارسی"];
    [_langPop addItemWithTitle:@"English"];
    [_langPop selectItemAtIndex:[ZSettings.shared.batchLang hasPrefix:@"en"] ? 1 : 0];
    _langPop.target = self;
    _langPop.action = @selector(tapLangDefault);
    _langPop.toolTip = @"زبان پیش‌فرض رونویسی فایل، جدا از زبان دیکته‌ی زنده. "
                        "عوض کردنش ردیف‌های در انتظار را هم به همین زبان می‌برد؛ "
                        "زبان تک‌ردیف را از ستون «زبان» عوض کن.";
    [_back addSubview:_langPop];

    _status = [NSTextField labelWithString:@"فایل صوتی را بکش و اینجا بینداز، یا دکمه‌ی + را بزن"];
    _status.font = ZFont(11.5, NO);
    _status.textColor = NSColor.tertiaryLabelColor;
    _status.alignment = NSTextAlignmentRight;
    _status.lineBreakMode = NSLineBreakByTruncatingTail;
    [_back addSubview:_status];

    [self buildTable];
    [self buildEditor];
    [self layoutViews];
    [self syncButtons];
}

// عوض کردن آیکونِ یک دکمه‌ی ساخته‌شده، با همان تنظیمِ اندازه و وزن. دکمه‌ای که دو کار
// دارد باید دو چهره هم داشته باشد.
- (void)setButton:(NSButton *)b symbol:(NSString *)symbol {
    NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:b.toolTip];
    if (!img) ZLog(@"batchui: SF Symbol پیدا نشد: %@", symbol);
    b.image = [img imageWithSymbolConfiguration:
               [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium]]
              ?: [NSImage new];
}

- (NSButton *)button:(NSString *)symbol tip:(NSString *)tip action:(SEL)action {
    NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip];
    if (!img) ZLog(@"batchui: SF Symbol پیدا نشد: %@", symbol);
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
    _table.rowHeight = 24;
    _table.usesAlternatingRowBackgroundColors = NO;
    _table.allowsMultipleSelection = YES;
    _table.dataSource = self;
    _table.delegate = self;
    _table.doubleAction = @selector(tapReveal);
    _table.target = self;
    // راست‌به‌چپ: ترتیب ستون‌ها هم با همین برمی‌گردد، پس «نام» راست‌ترین می‌شود
    _table.userInterfaceLayoutDirection = NSUserInterfaceLayoutDirectionRightToLeft;
    [_table registerForDraggedTypes:@[kZRowType, NSPasteboardTypeFileURL]];
    [_table setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];

    // پهنای ستون‌ها دست خود AppKit است (ستون اول کشسان). حساب دستی‌اش غلط بود: جمع
    // ستون‌ها از پهنای جدول بیشتر می‌شد و ستون «نام» ــ که در چیدمان راست‌به‌چپ اولی
    // است ــ از لبه‌ی راست پنجره بیرون می‌زد، پس نام‌های کوتاه اصلا دیده نمی‌شدند.
    _table.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    NSArray *cols = @[@[@"name", @"نام فایل", @260], @[@"lang", @"زبان", @48],
                      @[@"dur", @"طول", @58],
                      @[@"state", @"وضعیت", @150], @[@"prog", @"پیشرفت", @96]];
    for (NSArray *c in cols) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        BOOL flex = [c[0] isEqualToString:@"name"];
        col.title = c[1];
        col.width = [c[2] doubleValue];
        col.minWidth = flex ? 120 : [c[2] doubleValue];
        col.maxWidth = flex ? 10000 : [c[2] doubleValue];
        col.headerCell.font = ZFont(10.5, NO);
        col.headerCell.alignment = NSTextAlignmentRight;
        [_table addTableColumn:col];
    }
    _tableScroll.documentView = _table;
    [_back addSubview:_tableScroll];
}

- (void)buildEditor {
    // قاب مجزا با پس‌زمینه و لبه: متن یکجا قبلا لخت روی شیشه می‌نشست و مرزش با جدول
    // پیدا نبود. اسکرول‌بار هم همیشه پیداست که «متن ادامه دارد» بی‌اشاره معلوم باشد.
    _editorBox = [NSView new];
    _editorBox.wantsLayer = YES;
    _editorBox.layer.cornerRadius = 8;
    [_back addSubview:_editorBox];
    _editorCap = [NSTextField labelWithString:@"متن یکجا، به ترتیب صف (قابل ویرایش)"];
    _editorCap.font = ZFont(10.5, NO);
    _editorCap.textColor = NSColor.tertiaryLabelColor;
    _editorCap.alignment = NSTextAlignmentRight;
    [_back addSubview:_editorCap];

    _editorScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    _editorScroll.hasVerticalScroller = YES;
    _editorScroll.autohidesScrollers = NO;
    _editorScroll.scrollerStyle = NSScrollerStyleLegacy;
    _editorScroll.drawsBackground = NO;
    _editorScroll.borderType = NSNoBorder;
    _editor = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    _editor.font = ZFont(14, NO);
    _editor.textColor = NSColor.labelColor;
    _editor.drawsBackground = NO;
    _editor.richText = NO;
    _editor.importsGraphics = NO;
    _editor.baseWritingDirection = NSWritingDirectionRightToLeft;
    _editor.alignment = NSTextAlignmentRight;
    _editor.textContainerInset = NSMakeSize(4, 8);
    _editor.minSize = NSMakeSize(0, 0);
    _editor.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _editor.verticallyResizable = YES;
    _editor.horizontallyResizable = NO;
    _editor.autoresizingMask = NSViewWidthSizable;
    _editor.textContainer.widthTracksTextView = YES;
    _editorScroll.documentView = _editor;
    [_editorBox addSubview:_editorScroll];
    [self applyEditorColors];
}

- (void)applyEditorColors {
    _editorBox.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.06].CGColor;
    _editorBox.layer.borderWidth = 1;
    _editorBox.layer.borderColor = [NSColor.labelColor colorWithAlphaComponent:0.12].CGColor;
}

// چیدمان دستی، مثل نوار شناور: عرضِ ثابت نداریم و پنجره قابل تغییر اندازه است، پس
// هر بار از قد و پهنای واقعی حساب می‌شود.
- (void)layoutViews {
    NSSize sz = _back.frame.size;
    CGFloat top = sz.height - 34;      // زیر نوار عنوان شفاف
    CGFloat right = sz.width - kEdge;

    // دکمه‌ها از راست به چپ، با یک فاصله‌ی گروهی بین «کار روی صف» و «کار روی متن»
    CGFloat x = right - 24;
    for (NSUInteger i = 0; i < _bar.count; i++) {
        if (i == 4) x -= 14;    // مرز دو گروه
        // دکمه‌ی پنهان جا نمی‌گیرد، وگرنه یک حفره‌ی خالی وسط نوار می‌ماند
        if (_bar[i].hidden) continue;
        _bar[i].frame = NSMakeRect(x, top - 24, 24, 24);
        x -= kRowStep;
    }
    _jobsPop.frame = NSMakeRect(kEdge, top - 24, 86, 22);
    _langPop.frame = NSMakeRect(kEdge + 90, top - 24, 84, 22);
    _status.frame = NSMakeRect(kEdge + 182, top - 24, MAX(40, x + kRowStep - kEdge - 186), 20);

    CGFloat editorH = MAX(120, floor((sz.height - 70) * 0.36));
    CGFloat listTop = top - 34;
    _editorBox.frame = NSMakeRect(kEdge, kEdge, sz.width - 2 * kEdge, editorH);
    _editorScroll.frame = NSMakeRect(1, 1, _editorBox.frame.size.width - 2, editorH - 2);
    _editorCap.frame = NSMakeRect(kEdge + 8, kEdge + editorH + 4, sz.width - 2 * kEdge - 16, 14);
    _tableScroll.frame = NSMakeRect(kEdge, kEdge + editorH + 22,
                                    sz.width - 2 * kEdge, MAX(60, listTop - kEdge - editorH - 22));
    // ستون نام کشسان است و بقیه ثابت؛ توزیع پهنا را sizeToFit می‌کند
    [_table sizeToFit];
}

- (void)windowDidResize:(NSNotification *)n { [self layoutViews]; }

// بستن پنجره کار در جریان را نمی‌کشد: فقط از چشم می‌رود. کشتنش کار دکمه‌ی توقف است.
- (BOOL)windowShouldClose:(NSWindow *)sender {
    [_panel orderOut:nil];
    [self saveOrigin];
    if (_job) ZLog(@"batchui: panel hidden while a job is running");
    return NO;
}

- (void)windowDidMove:(NSNotification *)n {
    if (_panel.isVisible) [self saveOrigin];
}

// ---------- نمایش ----------

- (void)saveOrigin {
    NSRect f = _panel.frame;
    [NSUserDefaults.standardUserDefaults setObject:
        [NSString stringWithFormat:@"%.0f,%.0f,%.0f,%.0f", f.origin.x, f.origin.y,
         f.size.width, f.size.height] forKey:@"batchPanelFrame"];
}

// میان‌بر F از این می‌آید: پنجره پیدا و کلید؟ پنهانش کن (کار پس‌زمینه ادامه دارد و
// از رنگ آیتم منوبار پیداست). وگرنه بیار جلو. یعنی یک کلید، هم رفتن هم برگشتن.
- (void)toggle {
    if (_panel.isVisible) {
        [_panel orderOut:nil];
        [self saveOrigin];
        if (_job) ZLog(@"batchui: panel hidden by toggle while a job is running");
        return;
    }
    [self show];
}

- (void)show {
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:@"batchPanelFrame"];
    if (saved && !_panel.isVisible) {
        NSArray *p = [saved componentsSeparatedByString:@","];
        if (p.count == 4) {
            NSRect f = NSMakeRect([p[0] doubleValue], [p[1] doubleValue],
                                  MAX(520, [p[2] doubleValue]), MAX(420, [p[3] doubleValue]));
            // جای ذخیره‌شده ممکن است روی مانیتوری باشد که دیگر وصل نیست
            BOOL onScreen = NO;
            for (NSScreen *sc in NSScreen.screens) {
                if (NSIntersectsRect(f, sc.visibleFrame)) onScreen = YES;
            }
            if (onScreen) [_panel setFrame:f display:NO];
        }
    } else if (!_panel.isVisible && !saved) {
        [_panel center];
    }
    // اپ اکسسوری است، پس بی این فراخوان پنجره جلو می‌آید ولی کلید نمی‌شود و تایپ در
    // ادیتور به جایی نمی‌رسد.
    [NSApp activateIgnoringOtherApps:YES];
    [_panel makeKeyAndOrderFront:nil];
    [self layoutViews];
}

// ---------- صف ----------

- (void)addFiles:(NSArray<NSURL *> *)urls {
    NSInteger added = 0, dup = 0;
    for (NSURL *u in urls) {
        NSNumber *isDir = nil;
        [u getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue) continue;
        if ([self rowFor:u]) {
            dup++;
            continue;
        }
        ZBatchRow *r = [ZBatchRow new];
        r.url = u;
        r.state = ZRowQueued;
        r.lang = ZSettings.shared.batchLang;
        // قالب ردشده همان لحظه دلیلش را می‌گوید، نه چند دقیقه بعد وسط اجرا
        NSString *why = [ZFileDecoder unsupportedReason:u];
        if (why) {
            r.state = ZRowError;
            r.note = why;
        }
        [_rows addObject:r];
        added++;
        if (!why) [self probe:r];
    }
    [_table reloadData];
    [self syncButtons];
    if (added) {
        [self flash:[NSString stringWithFormat:@"%@ فایل به صف اضافه شد",
                     ZFaDigits(@(added).stringValue)]];
        ZLog(@"batchui: %ld file(s) queued, %ld duplicate(s) skipped", (long)added, (long)dup);
    } else if (dup) {
        [self flash:@"این فایل از قبل در صف است"];
    }
}

- (ZBatchRow *)rowFor:(NSURL *)url {
    for (ZBatchRow *r in _rows) {
        if ([r.url.path isEqualToString:url.path]) return r;
    }
    return nil;
}

// طول فایل روی نخ پس‌زمینه خوانده می‌شود: باز کردن asset تا ۳۰ ثانیه بلوکه می‌شود و
// نخ اصلی حق یخ زدن ندارد. همین‌جا فایل خراب هم لو می‌رود، یعنی خطا سر افزودن دیده
// می‌شود نه بعد از چند دقیقه انتظار.
- (void)probe:(ZBatchRow *)row {
    NSURL *u = row.url;
    __weak typeof(self) ws = self;
    dispatch_async(_probeQ, ^{
        NSError *err = nil;
        ZFileDecoder *dec = [[ZFileDecoder alloc] initWithURL:u error:&err];
        double dur = dec.duration;
        [dec cancel];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) s = ws;
            if (!s) return;
            if (row.state != ZRowQueued) return;    // وسط کار عوض شده؛ دست نمی‌زنیم
            if (!dec) {
                row.state = ZRowError;
                row.note = err.localizedDescription ?: @"فایل باز نشد";
                ZLog(@"batchui: probe failed %@: %@", u.lastPathComponent, row.note);
            } else {
                row.duration = dur;
            }
            [s refreshRow:row];
            [s syncButtons];
        });
    });
}

- (void)refreshRow:(ZBatchRow *)row {
    NSUInteger i = [_rows indexOfObject:row];
    if (i == NSNotFound) return;
    [_table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:i]
                      columnIndexes:[NSIndexSet indexSetWithIndexesInRange:
                                     NSMakeRange(0, _table.numberOfColumns)]];
}

// ---------- دکمه‌ها ----------

- (void)tapAdd {
    NSOpenPanel *op = [NSOpenPanel openPanel];
    op.allowsMultipleSelection = YES;
    op.canChooseDirectories = NO;
    op.canChooseFiles = YES;
    op.message = @"فایل‌های صوتی یا تصویری را انتخاب کن";
    op.prompt = @"افزودن";
    // قالب را محدود نمی‌کنیم: تشخیصِ «باز می‌شود یا نه» کار خودِ دیکدر است و همان
    // لحظه‌ی افزودن روی ردیف نوشته می‌شود. فهرست سفیدِ دستی فقط قالب‌های سالم را هم رد می‌کرد.
    __weak typeof(self) ws = self;
    [op beginSheetModalForWindow:_panel completionHandler:^(NSModalResponse resp) {
        if (resp == NSModalResponseOK) [ws addFiles:op.URLs];
    }];
}

- (void)tapStart {
    if (_job) return;
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    NSMutableArray<NSString *> *langs = [NSMutableArray array];
    for (ZBatchRow *r in _rows) {
        if (r.state == ZRowQueued || r.state == ZRowStopped) {
            r.state = ZRowQueued;
            r.doneSec = 0;
            [urls addObject:r.url];
            [langs addObject:r.lang ?: ZSettings.shared.batchLang];
        }
    }
    if (!urls.count) {
        ZLog(@"batchui: start tapped with nothing runnable (%lu rows)", (unsigned long)_rows.count);
        [self flash:@"چیزی در صف نیست"];
        return;
    }
    _stopping = NO;
    ZBatchJob *job = [[ZBatchJob alloc] initWithFiles:urls lang:ZSettings.shared.batchLang];
    job.langs = langs;
    job.jobs = _jobsPop.indexOfSelectedItem + 1;
    // پاس ویرایش اینجا اجرا نمی‌شود: متن هر فایل خام روی دیسک می‌رود و پاس نهایی روی
    // متن یکجا می‌نشیند. ترتیبش در batch.m نوشته شده: اول جوش خام، بعد ویرایش.
    job.polishFiles = NO;
    __weak typeof(self) ws = self;
    job.onFileProgress = ^(NSURL *f, double doneSec, double totalSec) {
        [ws progress:f done:doneSec total:totalSec];
    };
    job.onFileDone = ^(NSURL *f, NSString *text, NSError *err) {
        [ws fileDone:f text:text err:err];
    };
    job.onAllDone = ^{ [ws allDone]; };
    _job = job;
    [job start];
    [NSNotificationCenter.defaultCenter postNotificationName:ZBatchActivity object:self
                                                    userInfo:@{@"running": @YES}];
    [self syncButtons];
    [self flash:[NSString stringWithFormat:@"شروع شد · %@ فایل · %@ سشن هم‌زمان",
                 ZFaDigits(@(urls.count).stringValue),
                 ZFaDigits(@(job.jobs).stringValue)]];
    ZLog(@"batchui: started %lu file(s) jobs=%ld", (unsigned long)urls.count, (long)job.jobs);
}

- (void)tapStop {
    if (!_job) return;
    _stopping = YES;
    [_job cancel];
    _status.stringValue = @"در حال ایستادن… (سشن در جریان تا آخرش صبر می‌کند)";
    [self syncButtons];
}

- (void)tapRemove {
    NSIndexSet *sel = _table.selectedRowIndexes;
    if (!sel.count) {
        [self flash:@"اول ردیفی را انتخاب کن"];
        return;
    }
    NSMutableArray *keep = [NSMutableArray array];
    NSInteger skipped = 0;
    for (NSUInteger i = 0; i < _rows.count; i++) {
        ZBatchRow *r = _rows[i];
        BOOL wanted = [sel containsIndex:i];
        // ردیفی که همین حالا در جریان است حذف نمی‌شود: کارش بیرون از دست پنل است
        if (wanted && r.state == ZRowRunning) {
            skipped++;
            wanted = NO;
        }
        if (!wanted) [keep addObject:r];
    }
    NSInteger gone = (NSInteger)(_rows.count - keep.count);
    _rows = keep;
    [_table deselectAll:nil];
    [_table reloadData];
    [self syncButtons];
    if (skipped) [self flash:@"ردیف در حال کار حذف نمی‌شود؛ اول توقف را بزن"];
    else if (gone) [self flash:[NSString stringWithFormat:@"%@ ردیف حذف شد",
                                ZFaDigits(@(gone).stringValue)]];
}

- (void)tapLangDefault {
    NSString *lang = _langPop.indexOfSelectedItem == 1 ? @"en-US" : @"fa-IR";
    ZSettings.shared.batchLang = lang;
    // ردیف‌های در انتظار هم به زبان تازه می‌روند؛ در حال کار و تمام‌شده نه، چون
    // زبانشان یا قفل کار است یا دیگر اثری ندارد.
    NSInteger flipped = 0;
    for (ZBatchRow *r in _rows) {
        if (r.state == ZRowQueued || r.state == ZRowStopped || r.state == ZRowError) {
            r.lang = lang;
            flipped++;
        }
    }
    [_table reloadData];
    [self flash:flipped
        ? [NSString stringWithFormat:@"زبان پیش‌فرض و %@ ردیفِ در انتظار: %@",
           ZFaDigits(@(flipped).stringValue), [lang hasPrefix:@"en"] ? @"انگلیسی" : @"فارسی"]
        : [NSString stringWithFormat:@"زبان پیش‌فرض: %@",
           [lang hasPrefix:@"en"] ? @"انگلیسی" : @"فارسی"]];
}

// چرخش زبان یک ردیف از ستون خودش؛ فقط ردیفی که هنوز کارش شروع نشده
- (void)rowLangTap:(NSButton *)sender {
    NSInteger i = sender.tag;
    if (i < 0 || i >= (NSInteger)_rows.count) return;
    ZBatchRow *r = _rows[i];
    if (r.state == ZRowRunning || r.state == ZRowDone) {
        [self flash:@"زبان این ردیف دیگر عوض نمی‌شود"];
        return;
    }
    r.lang = [r.lang hasPrefix:@"en"] ? @"fa-IR" : @"en-US";
    [self refreshRow:r];
}

- (void)tapJobs {
    [NSUserDefaults.standardUserDefaults setInteger:_jobsPop.indexOfSelectedItem + 1
                                             forKey:@"batchJobs"];
    if (_jobsPop.indexOfSelectedItem + 1 > 2) {
        [self flash:@"بیشتر از ۲ سشن: سریع‌تر، ولی کلید مشترک با دیکته‌ی زنده زودتر لال می‌شود"];
    }
}

// چسباندن به ترتیب صف. جدا کردن با خط خالی، نه ادغام هم‌پوشانی: هم‌پوشانی فقط داخل
// یک فایل معنا دارد و دو فایل جدا ربطی به هم ندارند.
- (NSString *)joinedText {
    NSMutableArray *parts = [NSMutableArray array];
    for (ZBatchRow *r in _rows) {
        NSString *t = [r.text stringByTrimmingCharactersInSet:
                       NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (t.length) [parts addObject:t];
    }
    return [parts componentsJoinedByString:@"\n\n"];
}

- (void)tapJoin {
    NSString *t = [self joinedText];
    if (!t.length) {
        [self flash:@"هنوز متنی نیست"];
        return;
    }
    [self setEditorText:t];
    [self flash:[NSString stringWithFormat:@"چسبانده شد · %@ نویسه",
                 ZFaDigits(@(t.length).stringValue)]];
}

- (void)setEditorText:(NSString *)t {
    _editor.string = t ?: @"";
    _autoText = _editor.string;
    // هر نوشتنِ تازه، برگشتِ بهبود پرامپت را باطل می‌کند. یک جا و نه هفت جا: چسباندن،
    // پاس نهایی، تاریخچه و پایان کار همه از همین رد می‌شوند، و «متن دیکته را برگردان»
    // که متنِ یک صفِ دیگر را برگرداند، بدترین شکلِ ممکن است.
    _preEnhance = nil;
    [_editor scrollRangeToVisible:NSMakeRange(0, 0)];
    [self syncButtons];
}

// قالب‌هایی که خودِ جمینای مستقیم می‌گیرد. تبدیلی در کار نیست: فایلی که در این فهرست
// نباشد از مسیر قاعده‌ای رد می‌شود و پیامش را هم می‌گوید.
static NSString *ZGeminiMime(NSURL *url) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{@"flac": @"audio/flac", @"wav": @"audio/wav", @"mp3": @"audio/mpeg",
                @"m4a": @"audio/mp4", @"aac": @"audio/aac", @"ogg": @"audio/ogg",
                @"oga": @"audio/ogg", @"opus": @"audio/ogg", @"aiff": @"audio/aiff",
                @"aif": @"audio/aiff"};
    });
    return map[url.pathExtension.lowercaseString];
}

// پاس نهایی، دو مسیر و یک دکمه:
//   · با هوش مصنوعی روشن و کلید موجود و فایل‌های صوتیِ قابل‌قبول: کل صدا از نو شنیده
//     می‌شود. اندازه‌گیری روی یک ویس ۶ دقیقه‌ای فارسی: متن خام گوگل ۱۱ تکه محتوا را
//     انداخته بود و هیچ پاس متنی برشان نمی‌گرداند، چون در ورودی نبودند.
//   · وگرنه همان پاس قاعده‌ای روی متنِ چسبانده‌شده.
// هر دو روی نخ پس‌زمینه: پاس قاعده‌ای صدها تکه دارد و پاس هوش مصنوعی دقیقه‌ها طول
// می‌کشد؛ روی نخ اصلی یعنی پنجره‌ی یخ‌زده.
- (void)tapPolish {
    if (_polishing) return;
    NSString *raw = _editor.string;
    if (!raw.length) {
        [self flash:@"اول متنی بچسبان"];
        return;
    }
    if (ZSettings.shared.finalPassEnabled && ZFinalPass.hasKey) {
        NSMutableArray<NSURL *> *files = [NSMutableArray array];
        NSMutableArray<NSString *> *bad = [NSMutableArray array];
        for (ZBatchRow *r in _rows) {
            if (!r.url) continue;
            if (ZGeminiMime(r.url)) [files addObject:r.url];
            else [bad addObject:r.url.pathExtension.lowercaseString ?: @"?"];
        }
        if (files.count && !bad.count) {
            [self aiPolish:files];
            return;
        }
        [self flash:bad.count
            ? [NSString stringWithFormat:@"پاس هوش مصنوعی این قالب را نمی‌گیرد (%@)؛ پاس قاعده‌ای اجرا شد",
               [[NSSet setWithArray:bad].allObjects componentsJoinedByString:@"، "]]
            : @"فایلی در صف نیست؛ پاس قاعده‌ای روی همین متن اجرا شد"];
    }
    _polishing = YES;
    [self syncButtons];
    _status.stringValue = @"پاس نهایی…";
    NSString *lang = ZSettings.shared.batchLang;
    if (ZSettings.shared.polishEnabled) [ZPolish.shared prepare];
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *out = ZSettings.shared.polishEnabled ? ZBatchPolishText(raw, lang) : raw;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) s = ws;
            if (!s) return;
            s->_polishing = NO;
            BOOL changed = out.length && ![out isEqualToString:raw];
            if (changed) [s setEditorText:out];
            ZPlay(ZSoundPolish);
            [s flash:changed ? @"پاس نهایی انجام شد"
                             : @"پاس چیزی عوض نکرد (دیمن ویرایش بالا نیست؟)"];
            [s syncButtons];
        });
    });
}

// فایل‌به‌فایل و به همان ترتیب صف، چون خروجی هم به همان ترتیب چسبانده می‌شود. صفِ
// چندفایلی سریالی می‌رود نه موازی: سهم مجانی سقف ۲۰ درخواست در دقیقه دارد و هر فایل
// دو تماس می‌خورد.
- (void)aiPolish:(NSArray<NSURL *> *)files {
    _polishing = YES;
    [self syncButtons];
    NSString *lang = ZSettings.shared.batchLang;
    __weak typeof(self) ws = self;
    __block NSMutableArray<NSString *> *out = [NSMutableArray array];
    __block NSInteger at = 0;
    __block void (^next)(void);
    next = ^{
        __strong typeof(ws) s = ws;
        if (!s) return;
        if (at >= (NSInteger)files.count) {
            s->_polishing = NO;
            NSString *joined = [out componentsJoinedByString:@"\n\n"];
            if (joined.length) [s setEditorText:joined];
            ZPlay(ZSoundPolish);
            [s flash:joined.length ? @"پاس نهایی با هوش مصنوعی انجام شد"
                                   : @"پاس نهایی چیزی برنگرداند؛ متن قبلی سر جایش است"];
            [s syncButtons];
            next = nil;
            return;
        }
        NSURL *f = files[at];
        s->_status.stringValue = [NSString stringWithFormat:@"پاس نهایی %@ از %@: %@",
            ZFaDigits(@(at + 1).stringValue), ZFaDigits(@(files.count).stringValue),
            f.lastPathComponent];
        [ZFinalPass.shared runOnAudio:f lang:lang progress:^(NSString *msg) {
            __strong typeof(ws) s2 = ws;
            if (s2) s2->_status.stringValue = [NSString stringWithFormat:@"%@ · %@",
                                               f.lastPathComponent, msg];
        } done:^(ZFinalPassResult *r) {
            if (r.text.length) [out addObject:r.text];
            else ZLog(@"batchui: پاس نهایی %@ نشد — %@", f.lastPathComponent, r.error ?: @"?");
            at++;
            if (next) next();
        }];
    };
    next();
}

// ---------- بهبود پرامپت (بتا) ----------
// یک دکمه، دو کار، و همان قاعده‌ی پنل شناور: متن دیکته همیشه می‌ماند. بار اول پرامپت
// می‌سازد، بار دوم متن دیکته را برمی‌گرداند. اینجا میان‌بری نیست که مثل `R` بچرخد، پس
// چرخش روی خودِ دکمه سوار شده و آیکون هم عوض می‌شود تا دروغ نگوید.
- (void)tapEnhance {
    if (_polishing) return;
    if (_preEnhance) {
        NSString *back = _preEnhance;
        _preEnhance = nil;
        [self setEditorText:back];
        [self flash:@"متن دیکته برگشت"];
        return;
    }
    NSString *raw = _editor.string;
    if (!raw.length) {
        [self flash:@"اول متنی بچسبان"];
        return;
    }
    if (!ZFinalPass.hasKey) {
        [self flash:@"کلید جمینای نیست؛ بهبود پرامپت اجرا نشد"];
        ZLog(@"enhance: %@", ZFinalPass.missingKeyHint);
        return;
    }
    // همان پرچمِ «کاری در جریان است» که پاس نهایی استفاده می‌کند، و عمدا: انتقالِ زیرین
    // یکی است و یک تماس در هر لحظه بیشتر نمی‌پذیرد.
    _polishing = YES;
    [self syncButtons];
    _status.stringValue = @"بهبود پرامپت…";
    __weak typeof(self) ws = self;
    [ZEnhance.shared runOnText:raw lang:ZSettings.shared.batchLang progress:^(NSString *msg) {
        __strong typeof(ws) s = ws;
        if (s) s->_status.stringValue = msg;
    } done:^(ZEnhanceResult *r) {
        __strong typeof(ws) s = ws;
        if (!s) return;
        s->_polishing = NO;
        if (r.cancelled || r.error.length || r.gated || !r.text.length) {
            [s flash:r.cancelled ? @"لغو شد؛ متن سر جایش است"
                : r.gated ? @"پرامپت رد شد (ناقص یا پرحرف)؛ متن قبلی سر جایش است"
                : (r.error ?: @"پرامپتی نیامد؛ متن قبلی سر جایش است")];
            ZLog(@"enhance: batch failed — %@", r.gated ? r.summary : (r.error ?: @"?"));
            [s syncButtons];
            return;
        }
        [s setEditorText:r.text];
        s->_preEnhance = raw;    // بعد از setEditorText، چون آن یکی صفرش می‌کند
        ZPlay(ZSoundPolish);
        [s flash:[NSString stringWithFormat:@"پرامپت آماده شد · %@ ثانیه (همین دکمه، متن دیکته را برمی‌گرداند)",
                  ZFaDigits([NSString stringWithFormat:@"%.0f", r.seconds])]];
        [s syncButtons];
    }];
}

- (void)tapCopy {
    NSString *t = _editor.string;
    if (!t.length) {
        [self flash:@"متنی برای کپی نیست"];
        return;
    }
    [ZInjector copyFinal:t];
    ZPlay(ZSoundCopy);
    [self flash:[NSString stringWithFormat:@"کپی شد · %@ نویسه", ZFaDigits(@(t.length).stringValue)]];
}

- (void)tapSave {
    NSString *t = _editor.string;
    if (!t.length) {
        [self flash:@"متنی برای ذخیره نیست"];
        return;
    }
    NSSavePanel *sp = [NSSavePanel savePanel];
    sp.nameFieldStringValue = [NSString stringWithFormat:@"zemzeme-%@.txt", ZTimestampId()];
    sp.prompt = @"ذخیره";
    __weak typeof(self) ws = self;
    [sp beginSheetModalForWindow:_panel completionHandler:^(NSModalResponse resp) {
        __strong typeof(ws) s = ws;
        if (!s || resp != NSModalResponseOK || !sp.URL) return;
        NSError *err = nil;
        if ([t writeToURL:sp.URL atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
            [s flash:[@"ذخیره شد: " stringByAppendingString:sp.URL.lastPathComponent]];
        } else {
            [s flash:[@"ذخیره نشد: " stringByAppendingString:
                      err.localizedDescription ?: @"دلیل نامعلوم"]];
        }
    }];
}

// دابل‌کلیک روی ردیف: فایل txt همان ورودی را در Finder نشان بده (اگر ساخته شده)
- (void)tapReveal {
    NSInteger i = _table.clickedRow;
    if (i < 0 || i >= (NSInteger)_rows.count) return;
    ZBatchRow *r = _rows[i];
    NSURL *txt = [[[ZBatchJob alloc] initWithFiles:@[] lang:@"fa-IR"] outputURLFor:r.url ext:@"txt"];
    NSURL *target = [NSFileManager.defaultManager fileExistsAtPath:txt.path] ? txt : r.url;
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[target]];
}

// ---------- کال‌بک‌های کار (همه روی نخ اصلی) ----------

- (void)progress:(NSURL *)f done:(double)done total:(double)total {
    ZBatchRow *r = [self rowFor:f];
    if (!r) return;
    if (r.state == ZRowQueued) r.state = ZRowRunning;
    if (total > 0) r.duration = total;
    r.doneSec = done;
    [self refreshRow:r];
    if (!_stopping) {
        _status.stringValue = [NSString stringWithFormat:@"در حال کار · %@ از %@ · %@",
                               ZClock(done), ZClock(total), f.lastPathComponent];
    }
}

- (void)fileDone:(NSURL *)f text:(NSString *)text err:(NSError *)err {
    ZBatchRow *r = [self rowFor:f];
    if (!r) return;
    r.text = text;
    if (err) {
        r.state = ZRowError;
        r.note = err.localizedDescription ?: @"خطا";
        ZPlay(ZSoundTrash);
        ZLog(@"batchui: %@ failed: %@", f.lastPathComponent, r.note);
    } else if (_stopping) {
        // متن نیمه می‌ماند و روی دیسک نوشته نشده؛ دکمه‌ی شروع دوباره از صفر می‌خواندش
        r.state = ZRowStopped;
        r.note = nil;
    } else {
        r.state = ZRowDone;
        r.note = nil;
        r.doneSec = r.duration;
    }
    [self refreshRow:r];
    [self syncButtons];
}

- (BOOL)running { return _job != nil; }

- (void)allDone {
    _job = nil;
    BOOL stopped = _stopping;
    _stopping = NO;
    [NSNotificationCenter.defaultCenter postNotificationName:ZBatchActivity object:self
                                                    userInfo:@{@"running": @NO}];
    // متن یکجا خودش پر می‌شود، ولی فقط اگر ویرایش دستی‌ای رویش نرفته باشد: نوشته‌ی
    // خودِ کاربر را با جوش تازه نمی‌شوییم. آن‌وقت دکمه‌ی چسباندن کارِ خودش را می‌کند.
    NSString *joined = [self joinedText];
    BOOL untouched = !_editor.string.length || [_editor.string isEqualToString:_autoText ?: @""];
    if (joined.length && untouched) [self setEditorText:joined];
    // تاریخچه: هر اجرا که متنی داشت، یک فایل تاریخ‌دار در Application Support.
    // txt کنار فایل مال «الان» است و ممکن است پاک یا جابه‌جا شود؛ این یکی دفتر است.
    if (joined.length) [self saveHistory:joined stopped:stopped];
    NSInteger ok = 0, bad = 0;
    for (ZBatchRow *r in _rows) {
        if (r.state == ZRowDone) ok++;
        if (r.state == ZRowError) bad++;
    }
    _status.stringValue = stopped
        ? @"ایستاد. متن نیمه در پایین مانده؛ شروع دوباره از اول فایل می‌خواند."
        : [NSString stringWithFormat:@"تمام · %@ فایل، %@ خطا%@",
           ZFaDigits(@(ok).stringValue), ZFaDigits(@(bad).stringValue),
           untouched ? @"" : @" · متن یکجا دست‌نخورده ماند، دکمه‌ی چسباندن را بزن"];
    if (!stopped) ZPlay(ZSoundFinish);
    [self syncButtons];
    ZLog(@"batchui: job finished ok=%ld failed=%ld stopped=%d", (long)ok, (long)bad, stopped);
}

// ---------- وضعیت دکمه‌ها و پیام کوتاه ----------

- (void)syncButtons {
    BOOL running = _job != nil;
    NSInteger pending = 0;
    BOOL anyText = NO;
    for (ZBatchRow *r in _rows) {
        if (r.state == ZRowQueued || r.state == ZRowStopped) pending++;
        if (r.text.length) anyText = YES;
    }
    _btnAdd.enabled = YES;
    _btnStart.enabled = !running && pending > 0;
    _btnStop.enabled = running && !_stopping;
    _btnRemove.enabled = _rows.count > 0;
    _btnJoin.enabled = anyText;
    _btnPolish.enabled = _editor.string.length > 0 && !_polishing;
    // بتا و پیش‌فرض خاموش: تا تاگل روشن نشود، دکمه‌اش هم وجود ندارد. آیکونش می‌گوید
    // الان کدام کار را می‌کند، وگرنه دکمه‌ای که دو کار دارد و یک چهره، دروغ می‌گوید.
    _btnEnhance.hidden = !ZSettings.shared.enhanceEnabled;
    _btnEnhance.enabled = _editor.string.length > 0 && !_polishing;
    [self setButton:_btnEnhance symbol:_preEnhance ? @"arrow.uturn.backward" : @"curlybraces"];
    _btnEnhance.toolTip = _preEnhance
        ? @"برگشت به متن دیکته (پرامپت از دست نمی‌رود، دوباره همین دکمه)"
        : @"بهبود پرامپت (بتا): همین متن، به یک پرامپت آماده برای ایجنت";
    _btnCopy.enabled = _editor.string.length > 0;
    _btnSave.enabled = _editor.string.length > 0;
    _btnHistory.enabled = YES;
    _jobsPop.enabled = !running;
    for (NSButton *b in _bar) {
        b.contentTintColor = b.enabled ? NSColor.secondaryLabelColor : NSColor.quaternaryLabelColor;
    }
    [self layoutViews];    // پیدا و ناپیدا شدنِ دکمه، چیدمان نوار را عوض می‌کند
}

// پیام کوتاه روی خط وضعیت، بعد خودش می‌رود. همان قرارداد نوار شناور: زدن دکمه باید
// روی صفحه اثری داشته باشد، وگرنه آدم شک می‌کند کار کرد یا نه.
- (void)flash:(NSString *)msg {
    _status.stringValue = msg;
    _flashGen++;
    NSInteger gen = _flashGen;
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(ws) s = ws;
        if (!s || s->_flashGen != gen) return;
        if (s->_job) return;    // پیام پیشرفت خودش جا را می‌گیرد
        s->_status.stringValue = s->_rows.count ? @"" :
            @"فایل صوتی را بکش و اینجا بینداز، یا دکمه‌ی + را بزن";
    });
}

// ---------- تاریخچه ----------

static NSURL *ZBatchHistoryDir(void) {
    NSURL *d = [ZSupport() URLByAppendingPathComponent:@"transcripts"];
    [NSFileManager.defaultManager createDirectoryAtURL:d withIntermediateDirectories:YES
                                            attributes:nil error:nil];
    return d;
}

- (void)saveHistory:(NSString *)text stopped:(BOOL)stopped {
    NSString *name = [NSString stringWithFormat:@"batch-%@%@.txt", ZTimestampId(),
                      stopped ? @"-half" : @""];
    NSURL *u = [ZBatchHistoryDir() URLByAppendingPathComponent:name];
    [text writeToURL:u atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // نام ورودی‌ها در یک ایندکس جدا، نه در خود فایل: متنِ ذخیره‌شده باید خالص بماند
    // که لود دوباره‌اش چیزی اضافه نیاورد، ولی فهرست تاریخچه بی‌نام گنگ است.
    NSMutableArray *names = [NSMutableArray array];
    for (ZBatchRow *r in _rows) {
        if (r.text.length) [names addObject:r.url.lastPathComponent];
    }
    NSString *line = [NSString stringWithFormat:@"%@\t%@\n", name,
                      [names componentsJoinedByString:@"، "]];
    NSURL *idx = [ZBatchHistoryDir() URLByAppendingPathComponent:@"index.tsv"];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:idx.path];
    if (!h) {
        [[line dataUsingEncoding:NSUTF8StringEncoding] writeToURL:idx atomically:YES];
    } else {
        @try {
            [h seekToEndOfFile];
            [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        } @catch (NSException *e) {}
        [h closeFile];
    }
    ZLog(@"batchui: history saved %@ (%lu chars, %lu files)", name,
         (unsigned long)text.length, (unsigned long)names.count);
}

// ایندکس تاریخچه: نام فایل ذخیره → نام ورودی‌هایش. نبودن ایندکس عیب نیست، فقط
// عنوان به تاریخ خالی برمی‌گردد (تاریخچه‌های قبل از این قابلیت).
static NSDictionary<NSString *, NSString *> *ZBatchHistoryIndex(void) {
    NSURL *idx = [ZBatchHistoryDir() URLByAppendingPathComponent:@"index.tsv"];
    NSString *all = [NSString stringWithContentsOfURL:idx encoding:NSUTF8StringEncoding error:nil];
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (NSString *line in [all componentsSeparatedByString:@"\n"]) {
        NSRange tab = [line rangeOfString:@"\t"];
        if (tab.location == NSNotFound) continue;
        map[[line substringToIndex:tab.location]] = [line substringFromIndex:NSMaxRange(tab)];
    }
    return map;
}

// فهرست اجراهای قبلی زیر دکمه؛ انتخاب، متن را در ادیتور می‌گذارد (جای متن فعلی،
// پس اگر متن فعلی ویرایش دستی دارد اول هشدار همان فلش کافی است: کپی ماندگار همیشه
// با دکمه‌ی کپی در دسترس بود و تاریخچه هم خودش سر جایش می‌ماند).
- (void)tapHistory {
    NSArray *items = [NSFileManager.defaultManager contentsOfDirectoryAtURL:ZBatchHistoryDir()
                                                includingPropertiesForKeys:nil options:0 error:nil];
    NSArray *sorted = [items sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [b.lastPathComponent compare:a.lastPathComponent];   // نام تاریخ‌دار: نو اول
    }];
    NSDictionary *names = ZBatchHistoryIndex();
    NSMenu *menu = [NSMenu new];
    NSInteger n = 0;
    for (NSURL *u in sorted) {
        if (![u.pathExtension isEqualToString:@"txt"]) continue;
        if (++n > 15) break;
        // نام فایل: batch-yyyy-MM-dd-HH-mm-ss[-half].txt → همان وسطش خواناست
        NSString *base = u.lastPathComponent.stringByDeletingPathExtension;
        NSString *when = [base stringByReplacingOccurrencesOfString:@"batch-" withString:@""];
        BOOL half = [when hasSuffix:@"-half"];
        if (half) when = [when substringToIndex:when.length - 5];
        // نام ورودی‌ها جلوی تاریخ؛ بلندش بریده می‌شود که منو از پهنای پنجره نگذرد
        NSString *who = names[u.lastPathComponent] ?: @"";
        if (who.length > 44) who = [[who substringToIndex:43] stringByAppendingString:@"…"];
        NSString *title = who.length
            ? [NSString stringWithFormat:@"%@  ·  %@%@", who, ZFaDigits(when),
               half ? @" · نیمه" : @""]
            : [NSString stringWithFormat:@"%@%@", ZFaDigits(when), half ? @" · نیمه" : @""];
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:title
                                                    action:@selector(historyPick:)
                                             keyEquivalent:@""];
        mi.target = self;
        mi.representedObject = u;
        mi.toolTip = names[u.lastPathComponent];
        [menu addItem:mi];
    }
    if (!menu.numberOfItems) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:@"هنوز اجرایی تمام نشده"
                                                    action:nil keyEquivalent:@""];
        mi.enabled = NO;
        [menu addItem:mi];
    }
    [menu popUpMenuPositioningItem:nil
                        atLocation:NSMakePoint(NSMinX(_btnHistory.frame),
                                               NSMinY(_btnHistory.frame) - 4)
                            inView:_back];
}

- (void)historyPick:(NSMenuItem *)sender {
    NSURL *u = sender.representedObject;
    NSString *t = [NSString stringWithContentsOfURL:u encoding:NSUTF8StringEncoding error:nil];
    if (!t.length) {
        [self flash:@"این فایل تاریخچه خالی یا ناخوانا بود"];
        return;
    }
    [self setEditorText:t];
    [self flash:[NSString stringWithFormat:@"از تاریخچه آمد · %@ نویسه",
                 ZFaDigits(@(t.length).stringValue)]];
}

// ---------- جدول ----------

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)_rows.count; }

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)_rows.count) return nil;
    ZBatchRow *r = _rows[i];
    if ([col.identifier isEqualToString:@"prog"]) {
        ZBarView *bar = [[ZBarView alloc] initWithFrame:NSMakeRect(0, 0, col.width, _table.rowHeight)];
        bar.dim = r.state != ZRowRunning;
        bar.value = [r fraction];
        return bar;
    }
    // فریم به اندازه‌ی کل ستون، نه به اندازه‌ی متن: labelWithString فریمش را از متن
    // می‌گیرد و متنِ راست‌چین در فریم باریک، جایی بیرون از دید ستون می‌نشست.
    if ([col.identifier isEqualToString:@"lang"]) {
        // دکمه، نه لیبل: یک کلیک زبان همین ردیف را می‌چرخاند
        BOOL en = [r.lang hasPrefix:@"en"];
        NSButton *b = [NSButton buttonWithTitle:en ? @"EN" : @"فا" target:self
                                         action:@selector(rowLangTap:)];
        b.bordered = NO;
        b.font = ZFont(10.5, YES);
        b.contentTintColor = NSColor.secondaryLabelColor;
        b.tag = i;
        b.toolTip = en ? @"انگلیسی؛ کلیک کن تا فارسی شود" : @"فارسی؛ کلیک کن تا انگلیسی شود";
        b.frame = NSMakeRect(0, 0, col.width, _table.rowHeight);
        return b;
    }
    NSTextField *f = [[NSTextField alloc] initWithFrame:
                      NSMakeRect(0, 0, col.width, _table.rowHeight)];
    f.bezeled = NO;
    f.editable = NO;
    f.selectable = NO;
    f.drawsBackground = NO;
    f.autoresizingMask = NSViewWidthSizable;
    f.font = ZFont(11.5, NO);
    f.alignment = NSTextAlignmentRight;
    f.lineBreakMode = NSLineBreakByTruncatingTail;
    f.textColor = NSColor.labelColor;
    if ([col.identifier isEqualToString:@"name"]) {
        f.stringValue = r.url.lastPathComponent ?: @"";
        f.toolTip = r.url.path;
    } else if ([col.identifier isEqualToString:@"dur"]) {
        f.stringValue = ZClock(r.duration);
        f.textColor = NSColor.secondaryLabelColor;
    } else {
        f.stringValue = [r stateLabel];
        f.toolTip = r.note;
        f.textColor = r.state == ZRowError ? NSColor.systemRedColor
                    : r.state == ZRowDone ? NSColor.secondaryLabelColor
                    : NSColor.labelColor;
    }
    return f;
}

// ---------- جابه‌جایی ردیف با کشیدن ----------
// این فقط راحتی نیست: ترتیب صف همان ترتیبی است که متن‌ها به هم چسبانده می‌شوند، و
// «چسباندن» هر بار ترتیب همین لحظه‌ی جدول را می‌خواند. پس جابه‌جایی وسط کار هم درست
// جواب می‌دهد؛ متن هر فایل مال ردیف خودش است، نه مال جای قبلی‌اش.

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tv pasteboardWriterForRow:(NSInteger)row {
    NSPasteboardItem *item = [NSPasteboardItem new];
    [item setString:[@(row) stringValue] forType:kZRowType];
    return item;
}

- (NSDragOperation)tableView:(NSTableView *)tv validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)op {
    if ([info.draggingPasteboard stringForType:kZRowType]) {
        if (op == NSTableViewDropOn) [tv setDropRow:row dropOperation:NSTableViewDropAbove];
        return NSDragOperationMove;
    }
    if ([info.draggingPasteboard canReadObjectForClasses:@[NSURL.class] options:nil]) {
        [tv setDropRow:-1 dropOperation:NSTableViewDropOn];    // فایل تازه ته صف می‌نشیند
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)tv acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)op {
    NSString *from = [info.draggingPasteboard stringForType:kZRowType];
    if (from) {
        NSInteger src = from.integerValue;
        if (src < 0 || src >= (NSInteger)_rows.count) return NO;
        ZBatchRow *r = _rows[src];
        NSInteger dst = row > src ? row - 1 : row;
        dst = MAX(0, MIN((NSInteger)_rows.count - 1, dst));
        if (dst == src) return NO;
        [_rows removeObjectAtIndex:src];
        [_rows insertObject:r atIndex:dst];
        [_table reloadData];
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:dst] byExtendingSelection:NO];
        // متن یکجا با ترتیب تازه دوباره چسبانده می‌شود، ولی فقط اگر دست‌نخورده باشد
        if (_autoText.length && [_editor.string isEqualToString:_autoText]) {
            NSString *t = [self joinedText];
            if (t.length) [self setEditorText:t];
        }
        [self flash:@"ترتیب صف عوض شد؛ متن یکجا هم به همین ترتیب چسبانده می‌شود"];
        return YES;
    }
    NSArray *urls = [info.draggingPasteboard readObjectsForClasses:@[NSURL.class]
                                                          options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (!urls.count) return NO;
    [self addFiles:urls];
    return YES;
}

- (void)tableViewSelectionDidChange:(NSNotification *)n { [self syncButtons]; }

// ---------- اسکرین‌شات طراحی ----------

- (void)shotTo:(NSString *)dir name:(NSString *)name {
    [_back layoutSubtreeIfNeeded];
    NSBitmapImageRep *rep = [_back bitmapImageRepForCachingDisplayInRect:_back.bounds];
    if (!rep) return;
    [_back cacheDisplayInRect:_back.bounds toBitmapImageRep:rep];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:[dir stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"batch-%@.png", name]] atomically:YES];
}

// حالت‌های نمونه، بی‌شبکه: چیدمان و بریدن متن با داده‌ی واقعی‌نما سنجیده می‌شود.
// چرا پله‌پله و با تاخیر: جدولِ ویو-محور ردیف‌هایش را فقط در یک پاس نمایش واقعی
// می‌سازد. عکس گرفتن بی‌آنکه ران‌لوپ چرخیده باشد یک پنجره‌ی خالی می‌داد.
- (void)makeShots:(NSString *)dir then:(void (^)(void))done {
    [_panel setFrame:NSMakeRect(140, 140, kBW, kBH) display:YES];
    [NSApp activateIgnoringOtherApps:YES];
    [_panel makeKeyAndOrderFront:nil];
    [self layoutViews];
    [_rows removeAllObjects];
    [self setEditorText:@""];
    [_table reloadData];
    [self syncButtons];

    __weak typeof(self) ws = self;
    [self after:0.6 do:^{
        __strong typeof(ws) s = ws;
        if (!s) return;
        [s shotTo:dir name:@"empty"];
        [s fillSampleRows];
        [s after:0.6 do:^{
            [s shotTo:dir name:@"queue"];
            [s->_rows removeAllObjects];
            [s setEditorText:@""];
            [s->_table reloadData];
            [s syncButtons];
            [s->_panel orderOut:nil];
            if (done) done();
        }];
    }];
}

- (void)makeShots:(NSString *)dir { [self makeShots:dir then:nil]; }

- (void)after:(NSTimeInterval)sec do:(void (^)(void))block {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sec * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), block);
}

- (void)fillSampleRows {
    NSArray *specs = @[@[@"جلسه-محصول-دوشنبه.m4a", @2712.0, @(ZRowDone), @""],
                       @[@"voice.ogg", @363.0, @(ZRowRunning), @""],
                       @[@"مصاحبه-بخش-دوم.mp3", @1840.0, @(ZRowQueued), @""],
                       @[@"clip.mkv", @0.0, @(ZRowError),
                         @"قالب .mkv را macOS باز نمی‌کند؛ اول به m4a یا wav تبدیلش کن"],
                       @[@"یادداشت-صوتی.amr", @95.0, @(ZRowStopped), @""]];
    for (NSArray *sp in specs) {
        ZBatchRow *r = [ZBatchRow new];
        r.url = [NSURL fileURLWithPath:[@"/Users/seyed/Downloads"
                                        stringByAppendingPathComponent:sp[0]]];
        r.duration = [sp[1] doubleValue];
        r.state = (ZRowState)[sp[2] integerValue];
        r.note = [sp[3] length] ? sp[3] : nil;
        if (r.state == ZRowRunning) r.doneSec = r.duration * 0.42;
        if (r.state == ZRowDone) r.doneSec = r.duration;
        if (r.state == ZRowStopped) r.doneSec = r.duration * 0.6;
        if (r.state == ZRowDone || r.state == ZRowStopped) r.text = @"متن نمونه";
        [_rows addObject:r];
    }
    [_table reloadData];
    [self setEditorText:
        @"سلام، این متن نمونه است تا ببینیم ادیتور متن یکجا چطور دیده می‌شود. "
        @"متن هر فایل به ترتیب صف اینجا می‌نشیند و همین‌جا قابل ویرایش است، "
        @"بعد پاس نهایی را می‌زنی و آخرش کپی یا ذخیره می‌کنی.\n\n"
        @"پاره‌ی دوم از فایل بعدی، با یک خط خالی فاصله، که معلوم باشد کجا عوض شد."];
    _status.stringValue = @"در حال کار · ۲:۳۰ از ۶:۰۳ · voice.ogg";
    [self syncButtons];
}

// اجرای واقعی زیر ذره‌بین: فایل واقعی، شبکه‌ی واقعی، و چند عکس در طول کار.
// چرا اینجا و نه در تست بیرونی: پنجره بی‌اجازه‌ی ضبط صفحه فقط از داخل خودِ پروسه
// قابل عکس گرفتن است (cacheDisplayInRect)، همان راهی که نوار شناور هم می‌رود.
- (void)runShots:(NSString *)dir files:(NSArray<NSURL *> *)files {
    [self show];
    [self addFiles:files];
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [ws tapStart];
        [ws watchShots:dir tick:0];
    });
}

- (void)watchShots:(NSString *)dir tick:(NSInteger)tick {
    [self shotTo:dir name:[NSString stringWithFormat:@"live-%02ld", (long)tick]];
    // سناریوی آزمون توقف و بستن، فقط با متغیر محیطی تست: وسط کار پنجره بسته می‌شود
    // (کار باید ادامه بدهد) و یک تیک بعد توقف زده می‌شود (کار باید تمیز بایستد).
    if (getenv("ZEMZEME_SHOT_STOP") && _job && tick == 1) {
        [self tapStop];
        ZLog(@"batchui-test: stop tapped mid-run");
    }
    if (!_job || tick > 60) {
        [self shotTo:dir name:@"final"];
        ZLog(@"batchui: shot run done after %ld ticks", (long)tick);
        // متن نهایی هم بیرون بیاید که بشود با چشم خواندش
        [_editor.string writeToFile:[dir stringByAppendingPathComponent:@"batch-final.txt"]
                        atomically:YES encoding:NSUTF8StringEncoding error:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
        return;
    }
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [ws watchShots:dir tick:tick + 1]; });
}

@end
