// تستِ طلاییِ «جای خالی». یک باگِ واقعی را قفل می‌کند و باگ ساکت بود، که بدترین نوعش
// است: تکه‌ای که بی‌متن برمی‌گشت از `_parts` می‌افتاد و بقیه به هم می‌چسبیدند. یعنی یک
// جمله‌ی گم‌شده **هیچ ردی** نمی‌گذاشت؛ نه در متن، نه روی صفحه، نه در لاگ. هفته‌ی گذشته
// ۱۲ دقیقه از ۲۲۴ دقیقه دیکته (۱۳۹ تکه) همین‌طور پاک شد و ۳۴ سشن با سوراخِ دوخته‌شده
// درج شدند، و هیچ‌کس تا خواندنِ متن نفهمید.
//
// قاعده‌ای که همه‌چیز روی آن سوار است: `ZSegHasVoice` تکه‌های ساکت را **پیش از** هر
// تماس شبکه‌ای رد می‌کند، پس هر تکه‌ای که به شبکه می‌رسد حرف دارد و متنِ خالی همیشه
// شکست است، نه جوابِ درست. با همین یک قاعده نه سنجشِ اینترنت لازم است نه حدس.
//
// چرا این تست شبکه نمی‌خواهد: خودِ `pipe.m` کامپایل می‌شود (همان کدی که در محصول
// می‌دود)، ولی `ZGoogleStream` اینجا یک بدلِ چند خطی است که جوابش از یک فیلم‌نامه
// می‌آید. پس مسیرِ واقعیِ تصمیم زیر تست است و فقط سیمِ آخر به بیرون قطع شده.
#import "zemzeme.h"

static int failures = 0;

static void ok(BOOL cond, const char *what) {
    printf("%s %s\n", cond ? "ok  " : "FAIL", what);
    if (!cond) failures++;
}

static void okEq(NSString *got, NSString *want, const char *what) {
    BOOL same = [got isEqualToString:want];
    printf("%s %s\n", same ? "ok  " : "FAIL", what);
    if (!same) {
        printf("     خواستیم: %s\n     گرفتیم:  %s\n", want.UTF8String, got.UTF8String);
        failures++;
    }
}

// core.m این را از audio.m می‌خواهد و تست میکروفن ندارد
void ZMicSetHighSensitivity(BOOL on) { (void)on; }

// ---------- بدلِ شبکه ----------
// فیلم‌نامه: جوابِ هر تماس، به ترتیب. رشته‌ی خالی یعنی «سشن لال»، همان چیزی که نقطه‌ی
// رایگان واقعا گاهی می‌دهد. شمارنده‌ی تماس هم نگه داشته می‌شود، چون تعدادِ رفت‌وبرگشت
// خودش یک ادعاست: تلاشِ دوباره‌ی آنیِ داخل خط لوله باید دقیقا یک بار باشد، نه دو بار.
static NSMutableArray<NSString *> *gScript;
static NSInteger gCalls;

static NSString *ZTestReply(void) {
    gCalls++;
    if (!gScript.count) return @"";
    NSString *r = gScript.firstObject;
    [gScript removeObjectAtIndex:0];
    return r;
}

static void ZTestScript(NSArray<NSString *> *lines) {
    gScript = [lines mutableCopy];
    gCalls = 0;
}

// و `ZSpeechEvent` بدل نمی‌خواهد: یک شیءِ داده‌ی ساده در core.m است و همان‌جا لینک
// می‌شود. فقط سیمِ آخر به بیرون بدل دارد، نه چیزی بیشتر.
@implementation ZGoogleStream {
    NSString *_lang;
    NSUInteger _fed;
    BOOL _closed;
}
- (instancetype)initWithLang:(NSString *)lang {
    if ((self = [super init])) _lang = [lang copy];
    return self;
}
- (void)connect {}
- (void)feed:(NSData *)pcm { _fed += pcm.length; }
- (void)finishUpload {
    _bytesFed = _fed;
    NSString *reply = ZTestReply();
    // آسنکرون، چون مسیر واقعی هم همین است: `ZTranscribeSegment` روی سمافور می‌نشیند و
    // فقط با `onClose` بلند می‌شود. اگر اینجا همه‌چیز همان‌جا صدا زده شود، آن انتظار
    // اصلا امتحان نمی‌شود.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        if (reply.length && self.onEvent) {
            ZSpeechEvent *ev = [ZSpeechEvent new];
            ev.hasResults = YES;
            ev.finals = [NSMutableArray arrayWithObject:reply];
            self.onEvent(ev);
        }
        [self close:@"ok"];
    });
}
- (void)cancel { [self close:@"cancelled"]; }
- (void)close:(NSString *)reason {
    if (_closed) return;
    _closed = YES;
    if (self.onClose) self.onClose(reason);
}
@end

// ---------- صدای ساختگی ----------
// موجِ مربعیِ ±۶۰۰۰ یعنی rms ≈ ۰٫۱۸، خیلی بالای هر دو آستانه؛ و سکوت واقعا صفر است.
// طول‌ها هم‌تراز با فریمِ ۲۰ میلی‌ثانیه‌ایِ برش‌زن انتخاب شده‌اند، وگرنه یک فریمِ نیمه
// می‌تواند مرزِ مکث را جابه‌جا کند و تست به عددهای شکننده گره بخورد.
static void ZTestTone(NSMutableData *d, double sec) {
    NSUInteger n = (NSUInteger)(sec * 16000);
    int16_t *p = malloc(n * 2);
    for (NSUInteger i = 0; i < n; i++) p[i] = (i % 2) ? 6000 : -6000;
    [d appendBytes:p length:n * 2];
    free(p);
}

static void ZTestHush(NSMutableData *d, double sec) {
    [d increaseLengthBy:(NSUInteger)(sec * 16000) * 2];
}

// سه تکه‌ی حرف‌دار، با مکث‌هایی که برش‌زن سرشان می‌بُرد. ۶٫۶ ثانیه حرف و ۰٫۴ ثانیه
// مکث، سه بار: خط لوله دو بار وسط راه می‌بُرد و سومی سر `finish` به‌عنوان ته‌مانده
// می‌رود، پس دقیقا سه تکه به «شبکه» می‌رسد.
static NSData *ZTestThreePieces(void) {
    NSMutableData *d = [NSMutableData data];
    for (int i = 0; i < 3; i++) {
        ZTestTone(d, 6.6);
        ZTestHush(d, 0.4);
    }
    return d;
}

// یک دورِ کامل روی خط لوله. جای خالی‌ها و «اینترنت رفت»ها بیرون داده می‌شوند.
static NSString *ZTestPipe(NSArray<NSString *> *script,
                           NSMutableArray<ZHole *> *holes,
                           NSInteger *lostOut,
                           NSInteger *holeCountOut) {
    ZTestScript(script);
    ZPipe *p = [[ZPipe alloc] initWithLang:@"fa-IR"];
    __block NSInteger lost = 0;
    p.onHole = ^(ZHole *h) { @synchronized (holes) { [holes addObject:h]; } };
    p.onLost = ^{ lost++; };
    [p feed:ZTestThreePieces()];
    [p finish];
    if (lostOut) *lostOut = lost;
    if (holeCountOut) *holeCountOut = p.holes;
    return p.text;
}

int main(void) {
    @autoreleasepool {

    NSString *hole = ZHoleMark;

    // ادعای یک: تکه‌ای که حرف داشت و بی‌متن برگشت، **جایش می‌ماند**. نه حذف، نه دوخت.
    // این همان خطی است که ۱۲ دقیقه حرف را خورد.
    {
        NSMutableArray<ZHole *> *holes = [NSMutableArray array];
        NSInteger lost = 0, count = 0;
        // تکه‌ی دوم دو بار خالی برمی‌گردد: یک تماس و یک تلاشِ دوباره‌ی آنی.
        NSString *t = ZTestPipe(@[@"یک", @"", @"", @"سه"], holes, &lost, &count);
        okEq(t, [NSString stringWithFormat:@"یک %@ سه", hole],
             "تکه‌ی بی‌متن سر جای خودش علامت می‌خورد، نه اینکه بیفتد");
        ok(count == 1, "شمارنده‌ی جای خالی یکی بالا رفت");
        ok(holes.count == 1, "و صدایش بیرون داده شد تا بشود دوباره فرستادش");
        ok(holes.count == 1 && holes[0].pcm.length > 0, "صدای جامانده خالی نیست");
        ok(gCalls == 4, "چهار رفت‌وبرگشت: سه تکه، به‌اضافه‌ی یک تلاشِ دوباره‌ی آنی");
        ok(lost == 0, "یک شکستِ تنها آژیرِ اینترنت نمی‌زند");
    }

    // ادعای دو: تلاشِ دوباره‌ی آنیِ داخل خط لوله سر جایش است و کار می‌کند. حدود ۱۳٪ از
    // تکه‌های خالی را همین یکی نجات می‌دهد و همین است که هق‌هقِ کوتاهِ وی‌پی‌ان را
    // می‌بلعد. اگر روزی برداشته شود، اینجا قرمز می‌شود.
    {
        NSMutableArray<ZHole *> *holes = [NSMutableArray array];
        NSInteger lost = 0, count = 0;
        NSString *t = ZTestPipe(@[@"یک", @"", @"دو", @"سه"], holes, &lost, &count);
        okEq(t, @"یک دو سه", "تلاشِ دوباره‌ی آنی که گرفت، هیچ جای خالی‌ای نمی‌ماند");
        ok(count == 0 && holes.count == 0, "و شمارنده دست‌نخورده می‌ماند");
    }

    // ادعای سه: دو شکستِ پشت سر هم یعنی اینترنت رفته، و باید یک بار گفته شود. اینجا
    // فقط شکستِ **دوم** آژیر می‌زند: اولی می‌تواند بدشانسی باشد.
    NSMutableArray<ZHole *> *twoHoles = [NSMutableArray array];
    NSString *twoText = nil;
    {
        NSInteger lost = 0, count = 0;
        twoText = ZTestPipe(@[@"یک", @"", @"", @"", @""], twoHoles, &lost, &count);
        okEq(twoText, [NSString stringWithFormat:@"یک %@ %@", hole, hole],
             "دو تکه‌ی پشت سر هم، دو نشانه، به ترتیب");
        ok(count == 2 && twoHoles.count == 2, "شمارنده دو شد");
        ok(lost == 1, "آژیرِ اینترنت دقیقا یک بار زد، نه سرِ اولی و نه دو بار");
        ok(gCalls == 5, "پنج رفت‌وبرگشت: سه تکه، به‌اضافه‌ی دو تلاشِ دوباره‌ی آنی");
    }

    // ادعای چهار، و مهم‌ترینشان: تلاشِ دوباره متن را سر جای **خودش** می‌نشاند، نه سر
    // جای اولین نشانه. اینجا جای خالیِ اول باز هم نمی‌رسد و دومی می‌رسد؛ اگر متنِ دومی
    // جای اولی بنشیند، ترتیبِ حرفِ کاربر جابه‌جا شده و کسی هم نمی‌فهمد.
    NSMutableString *text = [twoText mutableCopy];
    {
        ZTestScript(@[@"", @"سه"]);
        NSInteger left = ZRetryHoles(twoHoles, @[text]);
        okEq(text, [NSString stringWithFormat:@"یک %@ سه", hole],
             "متنِ رسیده سر جای نشانه‌ی خودش نشست، نه سر جای اولی");
        ok(left == 1 && twoHoles.count == 1, "جای خالیِ نرسیده هنوز در صف است");
        ok(gCalls == 2, "فقط جاهای خالی دوباره رفتند، نه کلِ سشن");
    }

    // ادعای پنج: و وقتی همان یکی هم رسید، نشانه در جا با متنش عوض می‌شود و چیزی از
    // صف نمی‌ماند. این پایانِ سالمِ «اینترنت برگشت، Esc را زدم».
    {
        ZTestScript(@[@"دو"]);
        NSInteger left = ZRetryHoles(twoHoles, @[text]);
        okEq(text, @"یک دو سه", "نشانه در جا با متنِ رسیده عوض شد");
        ok(left == 0 && twoHoles.count == 0, "صفِ جای خالی خالی شد");
    }

    // ادعای شش: بیش از یک متن هم با هم پر می‌شوند. متنِ تحویل و رونوشتِ خام هر دو
    // همان نشانه‌ها را دارند و اگر فقط یکی پر شود، raw.txt برای همیشه دروغ می‌گوید.
    {
        NSMutableArray<ZHole *> *holes = [NSMutableArray array];
        NSInteger lost = 0, count = 0;
        NSString *base = ZTestPipe(@[@"یک", @"", @"", @"سه"], holes, &lost, &count);
        NSMutableString *a = [base mutableCopy];
        NSMutableString *b = [base mutableCopy];
        ZTestScript(@[@"دو"]);
        NSInteger left = ZRetryHoles(holes, @[a, b]);
        ok(left == 0, "جای خالی پر شد");
        okEq(a, @"یک دو سه", "متنِ تحویل پر شد");
        okEq(b, @"یک دو سه", "و رونوشتِ خام هم همان‌جا پر شد");
    }

    // ---------- قاعده‌های ریشه، روی سورس ----------
    // این‌ها ادعای رفتاری نیستند، مرزند: چیزهایی که اگر برداشته شوند تست‌های بالا
    // ممکن است هنوز سبز بمانند ولی محصول همان باگِ ساکت را پس بدهد.
    NSString *src = [NSString stringWithContentsOfFile:@"app/Sources-objc/pipe.m"
                                              encoding:NSUTF8StringEncoding error:nil];
    ok(src.length > 0, "pipe.m خوانده شد");

    // دلیلِ بسته شدنِ اتصال باید به لاگ برسد. تا امروز `onClose` آن را دور می‌ریخت، پس
    // یک خطای TLS هیچ ردی نمی‌گذاشت و تنها چیزی که می‌دیدیم «متن نیامد» بود.
    ok([src containsString:@"s.onClose = ^(NSString *reason) {"] &&
       [src containsString:@"ZLog(@\"seg[%@]: اتصال بسته شد: %@\", lang, reason);"],
       "دلیلِ بسته شدنِ اتصال به لاگ می‌رود، نه به سطل");

    // و تلاشِ دوباره‌ی آنی، دقیقا یکی. نه صفر (که ۱۳٪ نجات را می‌بازد) و نه ladder.
    ok([src containsString:@"سشن لال، یک بار دیگر"],
       "تلاشِ دوباره‌ی آنی سر جایش است");

    // آنچه **نباید** باشد. هر کدام از این‌ها یک بار وسوسه شد و هر بار جواب یکی است:
    // پشت پروکسی و مسیر tun این دستگاه، سیستم‌عامل «آنلاین» می‌گوید در حالی که گوگل
    // در دسترس نیست. پس هر سنجشِ خودکاری دروغ درمی‌آید و آدم تصمیم می‌گیرد.
    NSString *eng = [NSString stringWithContentsOfFile:@"app/Sources-objc/engine.m"
                                              encoding:NSUTF8StringEncoding error:nil];
    NSString *ses = [NSString stringWithContentsOfFile:@"app/Sources-objc/session.m"
                                              encoding:NSUTF8StringEncoding error:nil];
    ok(eng.length > 0 && ses.length > 0, "engine.m و session.m خوانده شدند");
    for (NSString *ban in @[@"SCNetworkReachability", @"nw_path_monitor", @"NWPathMonitor"]) {
        ok(![src containsString:ban] && ![eng containsString:ban] && ![ses containsString:ban],
           [[NSString stringWithFormat:@"ناظرِ دسترسیِ شبکه (%@) اضافه نشده", ban] UTF8String]);
    }

    // و سرِ دیگرِ سیم: جای خالی باید همان لحظه به کاربر برسد و سر Esc دوباره برود.
    ok([eng containsString:@"_fa.onHole = ^(ZHole *h) {"] &&
       [eng containsString:@"engineHole:"],
       "جای خالی از موتور به رابط کاربری می‌رسد");
    ok([eng containsString:@"- (void)netLost {"] && [eng containsString:@"ZEngineGaveUp"],
       "دو شکستِ پشت سر هم شنیدن را می‌خواباند و خطای دیدنی می‌دهد");
    ok([ses containsString:@"[self retryHoles];"] &&
       [ses containsString:@"BOOL insert = wouldInsert && !_holes.count;"],
       "سر Esc اول دوباره فرستاده می‌شود و متنِ سوراخ‌دار درج نمی‌شود");

    printf(failures ? "\nhole: %d ادعا افتاد\n" : "\nhole: همه‌ی ادعاها درست\n", failures);
    return failures ? 1 : 0;
} }
