// تستِ طلاییِ لایه‌ی بازنویسی، و باگِ C1.
//
// باگ از آن جنسی بود که کاربر مستقیم می‌دید: وسط دیکته مکث می‌کرد، متنِ پنل را
// ویرایش می‌کرد، باز حرف می‌زد و Esc می‌زد. آنچه سر کرسر می‌نشست کاملِ حرف بود ولی
// بی ویرایش، و آنچه در کلیپ‌بورد و تاریخچه می‌نشست ویرایش‌شده بود ولی فقط تا لحظه‌ی
// ویرایش. هیچ‌کدام از آن دو، حرفِ کامل و ویرایش‌شده نبود. شاهدش سشن
// ۲۰۲۶-۰۸-۲۶-۰۳-۲۳-۵۷ است: ۱۰۵۷ نویسه سر کرسر و ۲۵۹ نویسه در کلیپ‌بورد.
//
// پس ادعای این تست یکی است و همان یکی: **هر چهار مصرف‌کننده یک متن می‌گیرند.**
// کرسر، کلیپ‌بورد، ردیف تاریخچه، و text.txt. تستی که فقط یکی‌شان را بسنجد، همین
// باگ را سبز رد می‌کرد، چون هر کدامشان جدا جدا «یک متنِ معقول» می‌گرفتند.
//
// چه چیزی واقعی است و چه چیزی بدل: session.m و rewrite.m و core.m و history.m
// کامپایل می‌شوند، یعنی همان مسیرِ تصمیم که در محصول می‌دود. بدل‌ها فقط لبه‌ها
// هستند: پنل، موتور، صف، درج‌کننده. صف بدل است چون این باگ مالِ صف نیست و ساختنِ
// یک جای «هنوز نرسیده» با صدای واقعی، تست را به شبکه و میکروفن وصل می‌کرد.
#import "zemzeme.h"
#import "rewrite.h"

static int failures = 0;

static void okEq(NSString *got, NSString *want, const char *what) {
    BOOL same = [(got ?: @"") isEqualToString:want];
    printf("%s %s\n", same ? "ok  " : "FAIL", what);
    if (!same) {
        printf("     خواستیم: %s\n     گرفتیم:  %s\n", want.UTF8String, (got ?: @"(نال)").UTF8String);
        failures++;
    }
}

static void ok(BOOL cond, const char *what) {
    printf("%s %s\n", cond ? "ok  " : "FAIL", what);
    if (!cond) failures++;
}

// ---------- حالتِ مشترکِ بدل‌ها ----------
// همه سراسری‌اند و نه داخل بدل‌ها، چون خودِ تست باید هم بنویسدشان (تایپِ کاربر، جای
// تازه‌ی صف) و هم بخواندشان (آنچه سر کرسر رفت). هر اجرا یک سناریو است و یک پروسه،
// پس چیزی از سناریوی قبلی نمی‌ماند.
static NSMutableArray<ZSlot *> *gSlots;
static NSString *gEditor;      // متنی که همین حالا در ادیتور است
static NSString *gWrote;       // آخرین متنی که **اپ** در ادیتور نوشت
static NSString *gClip;        // آخرین چیزی که روی کلیپ‌بورد نشست
static NSString *gCaret;       // آخرین چیزی که سر کرسر رفت
static NSString *gPolished;    // جوابِ بدلِ پاس هوش مصنوعی؛ نال یعنی پاس نباید بدود
static NSInteger gPassCalls;

static void push(NSString *text, ZSlotState st) {
    ZSlot *s = [ZSlot new];
    s.seq = (NSInteger)gSlots.count;
    s.state = st;
    s.text = text;
    [gSlots addObject:s];
}

// audio.m در بیلد نیست و core.m این را می‌خواهد؛ تست میکروفن ندارد
void ZMicSetHighSensitivity(BOOL on) { (void)on; }
// queue.m در بیلد نیست: مسیرِ دفترچه اینجا موضوع نیست
NSURL *ZQueueManifestIn(NSURL *sessionDir) {
    return [sessionDir URLByAppendingPathComponent:@"queue.json"];
}

#pragma clang diagnostic push
// بدل‌ها فقط همان متدهایی را دارند که مسیرِ زیرِ تست واقعا صدا می‌زند. همین کوتاهی
// خودش سند است: هرچه اینجا نیست، سشن در این مسیر لازمش ندارد.
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation ZPanelModel
@end

@implementation ZSlot
@end

// ---------- بدلِ صف ----------
// همان قاعده‌ی queue.m: جای نرسیده هیچ نمی‌گذارد، و متنِ نشسته تا اولین جای نرسیده
// است و نه یک کلمه بیشتر.
@implementation ZQueue
- (NSArray<ZSlot *> *)snapshot { return [gSlots copy]; }
- (NSString *)text { return [self textFrom:0 extra:NO]; }
- (NSString *)textFrom:(NSInteger)seq extra:(BOOL)extra {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (ZSlot *s in gSlots) {
        if (s.seq < seq || s.extra != extra) continue;
        if (s.state == ZSlotDone && s.text.length) [parts addObject:s.text];
    }
    return [parts componentsJoinedByString:@" "];
}
- (NSString *)settledTextFrom:(NSInteger)seq {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (ZSlot *s in gSlots) {
        if (s.extra || s.seq < seq) continue;
        if (s.state == ZSlotWaiting) break;
        if (s.state == ZSlotDone && s.text.length) [parts addObject:s.text];
    }
    return [parts componentsJoinedByString:@" "];
}
- (NSInteger)nextSeq { return (NSInteger)gSlots.count; }
- (NSInteger)waiting {
    NSInteger n = 0;
    for (ZSlot *s in gSlots) if (s.state == ZSlotWaiting && !s.extra) n++;
    return n;
}
- (BOOL)drained { return self.waiting == 0; }
- (void)stop {}
- (void)discard {}
- (void)waitForFirstPass {}
@end

// ---------- بدلِ پنل ----------
// قرارداد `editorTouched` همان قرارداد panel.m است و دو خط بیشتر نیست: هرچه
// نوشته‌ایم را عینا به یاد داریم، و اگر متنِ ادیتور دیگر همان نیست یعنی مالِ کاربر است.
@implementation ZPanel
- (NSString *)editorText { return gEditor ?: @""; }
- (void)setEditorText:(NSString *)t { gEditor = [t copy]; gWrote = [t copy]; }
- (BOOL)editorTouched { return ![(gEditor ?: @"") isEqualToString:gWrote ?: @""]; }
- (void)clearEditor { gEditor = @""; gWrote = @""; }
- (void)show {}
- (void)hide {}
- (void)yieldKey {}
- (void)render:(ZPanelModel *)m { (void)m; }
- (void)pulseLevel:(float)level { (void)level; }
- (void)setPreviewText:(NSString *)text { (void)text; }
- (void)flash:(NSString *)msg { (void)msg; }
@end

@implementation ZCaretDot
- (void)show {}
- (void)hide {}
- (void)render:(ZPanelModel *)m { (void)m; }
- (void)pulseLevel:(float)level { (void)level; }
@end

@implementation ZRecorder
- (instancetype)initWithURL:(NSURL *)url { (void)url; return [super init]; }
- (void)feed:(NSData *)pcm { (void)pcm; }
- (void)finish {}
- (void)discard {}
@end

@implementation ZEngine
- (BOOL)startWithError:(NSError **)err { (void)err; return YES; }
- (void)stop {}
- (void)pause {}
- (void)resume {}
- (void)cancel {}
- (void)resetClock {}
- (void)resetPreview {}
- (void)discardText {}
- (void)switchLang:(NSString *)lang { (void)lang; }
@end

// ---------- بدلِ درج‌کننده ----------
// دو دهانه‌ی خروجی و هر دو ضبط می‌شوند: کلیپ‌بورد و کرسر. باگِ C1 دقیقا واگراییِ
// همین دو بود، پس تستی که یکی‌شان را نبیند اصلا تست نیست.
@implementation ZInjector
+ (BOOL)accessibilityOK { return YES; }
+ (void)promptAccessibility {}
+ (void)copyFinal:(NSString *)text { gClip = [text copy]; }
- (void)copyFinalAfterPending:(NSString *)text { gClip = [text copy]; }
- (void)insert:(NSString *)text pid:(pid_t)pid delayMicros:(useconds_t)d
pasteIfRefused:(BOOL)paste done:(void (^)(BOOL))done {
    (void)pid; (void)d; (void)paste;
    gCaret = [text copy];
    if (done) done(YES);
}
@end

@implementation ZFinalPass
+ (instancetype)shared {
    static ZFinalPass *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [ZFinalPass new]; });
    return s;
}
+ (BOOL)keyKnownMissing { return gPolished == nil; }
+ (NSString *)missingKeyHint { return @"کلیدی نیست"; }
- (void)runOnText:(NSString *)text second:(NSString *)second lang:(NSString *)lang
             done:(void (^)(NSString *, NSString *))done {
    (void)text; (void)second; (void)lang;
    gPassCalls++;
    if (done) done(gPolished, nil);
}
- (void)runOnText:(NSString *)raw appendingTo:(NSString *)previous lang:(NSString *)lang
             done:(void (^)(NSString *, NSString *))done {
    (void)raw; (void)previous; (void)lang;
    gPassCalls++;
    if (done) done(gPolished, nil);
}
@end

#pragma clang diagnostic pop

// ---------- داربستِ سشن ----------

static ZSession *gSession;
static ZQueue *gQueue;

static void bootSession(void) {
    gSlots = [NSMutableArray array];
    gEditor = gWrote = @"";
    ZSettings.shared.soundsEnabled = NO;      // تست صدا در نمی‌آورد
    ZSettings.shared.signatureEnabled = NO;   // امضا موضوعِ این تست نیست
    ZSettings.shared.previewStream = NO;
    ZSettings.shared.recordSessions = YES;    // صدا پاک نشود؛ ضبط‌کننده بدل است
    ZSettings.shared.mode = ZModeCollect;     // ادیتور فقط در حالت جمع هست
    ZEngine *eng = [ZEngine new];
    ZPanel *panel = [ZPanel new];
    gSession = [[ZSession alloc] initWithEngine:eng panel:panel];
    [gSession start];
    gQueue = eng.queue;
}

// «صدا تمام شد و متن آماده است»: همان دری که موتور از آن متن را تحویل می‌دهد.
static void speechDone(void) {
    [(id<ZEngineDelegate>)gSession engineDidFinish:@"" second:nil took:0.1];
}

// «یک جای دیگر همین حالا رسید»: همان دری که صف از آن خبر می‌دهد.
static void slotLanded(void) { if (gQueue.onChange) gQueue.onChange(); }

// text.txt، از تازه‌ترین پوشه‌ی سشن. سشن مسیرش را بیرون نمی‌دهد و لازم هم نیست:
// این همان راهی است که آدم هم برای پیدا کردنِ متنِ یک دیکته می‌رود.
static NSString *transcriptOnDisk(void) {
    NSArray<NSURL *> *dirs = [NSFileManager.defaultManager
        contentsOfDirectoryAtURL:ZSessionsDir()
      includingPropertiesForKeys:nil options:0 error:nil];
    NSArray<NSURL *> *sorted = [dirs sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [a.lastPathComponent compare:b.lastPathComponent];
    }];
    NSURL *last = sorted.lastObject;
    if (!last) return nil;
    return [NSString stringWithContentsOfURL:[last URLByAppendingPathComponent:@"text.txt"]
                                    encoding:NSUTF8StringEncoding error:nil];
}

static NSString *historyText(void) {
    NSArray<ZHistoryEntry *> *rows = ZHistoryRecent(1);
    return rows.firstObject.text;
}

// چهار مصرف‌کننده، یک ادعا.
static void assertAllFour(NSString *want, const char *tag) {
    okEq(gCaret, want, tag);
    okEq(gClip, want, tag);
    okEq(historyText(), want, tag);
    okEq(transcriptOnDisk(), want, tag);
}

// ---------- سناریو ۱: خودِ C1 ----------
// متن می‌آید، کاربر ویرایش می‌کند، متنِ بیشتری می‌آید، تحویل. تا دیروز اینجا سر کرسر
// «سلام دنیا و این نصفه‌ی دوم است» می‌رفت و در کلیپ‌بورد «سلام رفیق» می‌نشست.
static void scenarioC1(void) {
    bootSession();
    push(@"سلام دنیا", ZSlotDone);
    speechDone();
    okEq(gWrote, @"سلام دنیا", "C1: دور اول در پنل نشست");

    gEditor = @"سلام رفیق";                       // کاربر در پنل تایپ کرد
    push(@"و این نصفه‌ی دوم است", ZSlotDone);
    slotLanded();
    okEq(gWrote, @"سلام رفیق و این نصفه‌ی دوم است", "C1: پنل ویرایش را نگه داشت و تکه‌ی تازه را هم گرفت");

    [gSession finish];                            // Esc
    assertAllFour(@"سلام رفیق و این نصفه‌ی دوم است", "C1: هر چهار مصرف‌کننده یک متن");
}

// ---------- سناریو ۲: جای وسط، که دیرتر می‌رسد ----------
// متنِ زنده افزودنی نیست. اینجا جای وسطی هنوز در راه است، کاربر همان متنِ ناقص را
// ویرایش می‌کند، و بعد آن جا می‌رسد. ادعا این است که **چیزی گم نمی‌شود**: نه ویرایشِ
// کاربر، نه آن جای دیررس. فیکسی که روی «متنِ قبلی پیشوندِ متنِ تازه است» بنا شده
// باشد، دقیقا همین‌جا می‌شکند.
static void scenarioGap(void) {
    bootSession();
    push(@"الف", ZSlotDone);
    push(@"ب", ZSlotWaiting);      // وسطِ صف، هنوز در راه
    push(@"ج", ZSlotDone);
    speechDone();
    okEq(gWrote, @"الف ج", "درز: جای نرسیده هیچ نمی‌گذارد");

    gEditor = @"الف ویرایش ج";
    gSlots[1].state = ZSlotDone;   // و حالا رسید
    slotLanded();
    [gSession finish];
    ok([gClip containsString:@"ویرایش"], "درز: ویرایشِ کاربر ماند");
    ok([gClip containsString:@"ب"], "درز: جای دیررس هم ماند");
    assertAllFour(@"الف ویرایش ج ب", "درز: هر چهار مصرف‌کننده یک متن");
}

// ---------- سناریو ۳: پاس هوش مصنوعی و ویرایش، با هم ----------
// دو نویسنده‌ی یک لایه. قاعده صریح است: متن مالِ کاربر است و برنده هم همان، پس
// ویرایش که آمد، پاس تا آخرِ سشن خاموش می‌ماند. بی این، مدل کلِ متن را از نو
// می‌نویسد و «برنده» می‌شود یک حرف.
static void scenarioPass(void) {
    gPolished = @"سلامِ تمیزشده";
    bootSession();
    ZSettings.shared.finalPassEnabled = YES;
    push(@"سلام", ZSlotDone);
    speechDone();
    ok(gPassCalls == 1, "پاس: روی متنِ دست‌نخورده دوید");
    okEq(gWrote, @"سلامِ تمیزشده", "پاس: نتیجه‌اش در پنل نشست");

    gEditor = @"سلامِ خودم";
    push(@"و ادامه‌اش", ZSlotDone);
    slotLanded();
    ok(gPassCalls == 1, "پاس: بعد از ویرایش دیگر ندوید");
    [gSession finish];
    ok(gPassCalls == 1, "پاس: سر پایان هم ندوید");
    assertAllFour(@"سلامِ خودم و ادامه‌اش", "پاس: هر چهار مصرف‌کننده یک متن");
}

// ---------- سناریو ۴: خودِ دو تابع ----------
// مجموعه، نه مرزِ عددی. با مرزِ عددی جای شماره‌ی یک برای همیشه می‌افتاد.
static void scenarioPure(void) {
    gSlots = [NSMutableArray array];
    push(@"یک", ZSlotDone);
    push(@"دو", ZSlotWaiting);
    push(@"سه", ZSlotDone);
    NSIndexSet *covers = ZRewriteCovers(nil, gSlots);
    ok(covers.count == 2 && ![covers containsIndex:1], "خالص: جای نرسیده در پوشش نیست");
    okEq(ZRewriteText(@"بازنویسی", covers, gSlots, NO), @"بازنویسی", "خالص: دُمی نمانده");
    gSlots[1].state = ZSlotDone;
    okEq(ZRewriteText(@"بازنویسی", covers, gSlots, NO), @"بازنویسی دو",
         "خالص: جای دیررس پشتِ بازنویسی می‌نشیند، نه اینکه بیفتد");
    okEq(ZRewriteText(nil, nil, gSlots, NO), @"یک دو سه", "خالص: بی لایه، همان متنِ صف");

    gSlots[1].state = ZSlotWaiting;
    okEq(ZRewriteText(nil, nil, gSlots, YES), @"یک", "خالص: متنِ کرسر سرِ جای نرسیده می‌ایستد");
    okEq(ZRewriteText(nil, covers, gSlots, YES), @"", "خالص: جای پوشیده سدِ راه نیست ولی چیزی هم اضافه نمی‌کند");
}

// بدلِ سپردنِ صف. این تست فقط لایه‌ی بازنویسی را می‌سنجد و صفش هم بدل است، پس
// سپردنِ واقعی اینجا معنایی ندارد؛ ولی `endNow` صدایش می‌زند و بی این، لینک نمی‌شود.
// گاردِ خودِ سپردن جای دیگری است: tools/queue_test.sh بندهای ۱۶ و ۱۷.
void ZAdoptOrphanQueue(ZQueue *q, NSString *sid, NSString *rewrite, NSIndexSet *covers) {
    (void)q; (void)sid; (void)rewrite; (void)covers;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *which = argc > 1 ? @(argv[1]) : @"c1";
        if ([which isEqualToString:@"c1"]) scenarioC1();
        else if ([which isEqualToString:@"gap"]) scenarioGap();
        else if ([which isEqualToString:@"pass"]) scenarioPass();
        else if ([which isEqualToString:@"pure"]) scenarioPure();
        else { printf("FAIL سناریوی ناشناخته: %s\n", which.UTF8String); return 1; }
        if (failures) printf("\n%d ادعا شکست\n", failures);
        return failures ? 1 : 0;
    }
}
