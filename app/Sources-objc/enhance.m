// بهبود پرامپت (بتا): متنی که دیکته شده، به پرامپتی که بشود همان لحظه به یک ایجنت داد.
//
// چرا این کار جداست و چرا به بقیه شبیه نیست: ورودی‌اش **متن آماده** است، نه صدا. پس
// تنها کارِ این خانواده است که به میکروفن و ضبط و پاس نهایی کاری ندارد، و همین است
// که در هر چهار حالت و در پنل رونویسی فایل یکسان کار می‌کند: هر جا متنی آماده هست،
// این هم هست.
//
// و چرا انتقالِ خودش را نمی‌سازد: کلید، تلاش دوباره، رفتار ۴۲۹ و پارس پاسخِ اندپوینتِ
// مستندنشده همه در `final.m` نشسته‌اند و هر کدامشان از یک آزمایش واقعی درآمده‌اند.
// نسخه‌ی دومِ آن کد یعنی نسخه‌ی دومِ همان باگ‌ها. اینجا فقط چهار متدِ قرضی صدا زده
// می‌شود (`askText:`، `promptNamed:`، `cancelled`، `resetCancel`).
//
// قاعده‌های سختی که این فایل رعایت می‌کند:
//   · هیچ‌وقت خودکار نیست: فقط دکمه یا میان‌بر، فقط روی متنِ از قبل آماده.
//   · متن اصلی همیشه می‌ماند. خروجی یک نسخه‌ی تازه است، نه جایگزین.
//   · دروازه رد کند یعنی هیچ اتفاقی نیفتاد، نه اینکه نصفه‌اش بنشیند.
//   · پاس مکانیکی فارسی **اجرا نمی‌شود**، و این عمدی‌ترین تصمیم این فایل است. آن پاس
//     ارقام را فارسی می‌کند و خروجی اینجا متنی است که به یک ماشین داده می‌شود:
//     `gemini-3.6-flash` که بشود `gemini-۳٫۶-flash` یک پرامپتِ خراب است. نیم‌فاصله را
//     خودِ مدل بد نمی‌گذارد و ارزشش را ندارد که مسیر فنی را بشکنیم.
#import "zemzeme.h"

// `key` عمدا در هدر نیست (کلید از `final.m` بیرون نمی‌رود)، ولی مسیر خط فرمان همین
// پایین لازمش دارد: آنجا پرسشِ بلوکه درست است. همان قرارداد خودِ `final.m`.
@interface ZFinalPass (ZBlockingKey)
- (NSString *)key;
@end

// `low` نه `minimal`، و فرقش با پاس نهایی همین است: آنجا کاربر منتظر متنِ سه دقیقه
// حرفِ خودش است و هر ثانیه به چشم می‌آید، اینجا خودش دکمه را زده و منتظر یک کارِ
// فکری است. عددهای واقعیِ هر دو در README نوشته شده‌اند.
// متغیر محیطی فقط برای همان اندازه‌گیری است، نه تنظیم کاربر.
static NSString *ZEnhThinking(void) {
    NSString *t = NSProcessInfo.processInfo.environment[@"ZEMZEME_ENHANCE_THINKING"];
    return t.length ? t : @"low";
}

// ---------- نتیجه ----------

@implementation ZEnhanceResult
@end

@implementation ZEnhance {
    NSLock *_logLock;
}

+ (instancetype)shared {
    static ZEnhance *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [ZEnhance new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) _logLock = [NSLock new];
    return self;
}

- (void)cancel { [ZFinalPass.shared cancel]; }

- (void)runOnText:(NSString *)text lang:(NSString *)lang
         progress:(void (^)(NSString *msg))progress
             done:(void (^)(ZEnhanceResult *r))done {
    void (^say)(NSString *) = ^(NSString *m) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (progress) progress(m); });
    };
    NSString *raw = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [ZFinalPass.shared resetCancel];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        ZEnhanceResult *r = [self work:raw lang:lang say:say];
        dispatch_async(dispatch_get_main_queue(), ^{ done(r); });
    });
}

- (ZEnhanceResult *)work:(NSString *)raw lang:(NSString *)lang say:(void (^)(NSString *))say {
    ZEnhanceResult *r = [ZEnhanceResult new];
    NSDate *t0 = NSDate.date;
    if (!raw.length) {
        r.error = @"متنی برای بهبود نیست";
        return r;
    }
    NSString *system = [ZFinalPass.shared promptNamed:@"enhance"];
    if (!system.length) {
        r.error = @"پرامپت بهبود در بسته‌ی اپ نیست";
        return r;
    }
    if ([ZFinalPass.shared cancelled]) {
        r.cancelled = YES;
        return r;
    }
    NSMutableDictionary *usage = [NSMutableDictionary dictionary];
    NSString *err = nil;
    // دو تکه‌ی جدا، نه یک رشته: مرزِ «دستور» و «متنِ کاربر» باید صریح باشد، وگرنه یک
    // دیکته که خودش شبیه دستور حرف می‌زند می‌تواند جای پرامپت سیستم را بگیرد.
    NSArray<NSString *> *parts = @[
        @"این متن با حرف زدن دیکته شده و ویرایش نشده است. خروجی فقط خودِ پرامپت باشد.",
        [@"متن دیکته‌شده:\n\n" stringByAppendingString:raw]];
    say(@"بهبود پرامپت…");
    NSString *out = [ZFinalPass.shared askText:system parts:parts label:@"enhance"
                                     thinking:ZEnhThinking() usage:usage error:&err];
    if ([ZFinalPass.shared cancelled]) {
        r.cancelled = YES;
        return r;
    }
    if (!out.length) {
        r.error = err ?: @"پرامپتی برنگشت";
        [self log:@"failed" draft:raw out:r.error];
        return r;
    }

    // ---------- دروازه ----------
    ZEnhGate *g = [ZEnhGate ofDraft:raw output:out];
    if (!g.passed) {
        ZLog(@"enhance: دروازه بست — %@", g.summary);
        say(@"بررسی کامل بودن: یک بار دیگر…");
        NSArray *parts2 = [parts arrayByAddingObject:[self strictAddendum:g]];
        NSString *again = [ZFinalPass.shared askText:system parts:parts2 label:@"enhance-strict"
                                           thinking:ZEnhThinking() usage:usage error:&err];
        if ([ZFinalPass.shared cancelled]) {
            r.cancelled = YES;
            return r;
        }
        ZEnhGate *g2 = again.length ? [ZEnhGate ofDraft:raw output:again] : nil;
        if (g2 && g2.passed) {
            out = again;
            g = g2;
        } else {
            // تسلیم، و متن قبلی سر جایش. «نصفه‌اش بنشیند» بدترین جواب ممکن است: کاربر
            // نمی‌فهمد چه چیزی از خواسته‌اش افتاده و همان پرامپت را به ایجنت می‌دهد.
            ZLog(@"enhance: تلاش دوم هم رد شد (%@)؛ متن قبلی ماند",
                 g2 ? g2.summary : @"پرامپتی نیامد");
            r.gated = YES;
            r.summary = (g2 ?: g).summary;
            r.seconds = [NSDate.date timeIntervalSinceDate:t0];
            r.inTokens = [usage[@"in"] integerValue];
            r.outTokens = [usage[@"out"] integerValue];
            [self log:@"gated" draft:raw out:again.length ? again : out];
            return r;
        }
    }

    r.text = out;
    r.summary = g.summary;
    r.inTokens = [usage[@"in"] integerValue];
    r.outTokens = [usage[@"out"] integerValue];
    r.seconds = [NSDate.date timeIntervalSinceDate:t0];
    [self log:@"ok" draft:raw out:out];
    ZLog(@"enhance: تمام در %.0f ثانیه، %ld+%ld توکن، %@", r.seconds,
         (long)r.inTokens, (long)r.outTokens, g.summary);
    return r;
}

// فهرست همان چیزی که افتاد، به زبان خودِ پرامپت. همان درسِ پاس نهایی: «سخت‌گیرتر باش»
// کم‌اثر بود و نام بردنِ خودِ توکن‌ها کارِ مدل را از حدس زدن به برگرداندن بُرد.
- (NSString *)strictAddendum:(ZEnhGate *)g {
    NSMutableString *s = [NSMutableString stringWithString:@"تلاش قبلی‌ات رد شد."];
    NSArray *hard = [[g.lostNumbers arrayByAddingObjectsFromArray:g.lostLatin]
                     arrayByAddingObjectsFromArray:g.lostPaths];
    if (hard.count) {
        [s appendFormat:@"\n\nاین‌ها در پرامپتت نبودند و باید مو‌به‌مو باشند: %@",
         [hard componentsJoinedByString:@"، "]];
    }
    if (g.tooLong) {
        [s appendFormat:@"\n\nو پرحرف بود: %lu واژه نوشتی، سقف %lu واژه است. تیتر و بولت "
                        @"سر جایشان بمانند، حرفِ اضافه و توضیحِ خودت بروند.",
         (unsigned long)g.outWords, (unsigned long)g.allowedWords];
    }
    return s;
}

// جفت قبل/بعد، کنار polish.log و با همان قرارداد. فایل در .gitignore است.
// بتا بودنِ یک فیچر تا وقتی جفت قبل و بعدش جایی ننشیند، فقط یک برچسب است.
- (void)log:(NSString *)outcome draft:(NSString *)draft out:(NSString *)out {
    static NSDateFormatter *df;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    NSString *entry = [NSString stringWithFormat:@"%@ %@ (%@)\n< %@\n> %@\n\n",
                       [df stringFromDate:NSDate.date], outcome, ZEnhThinking(),
                       draft ?: @"", out ?: @""];
    NSData *d = [entry dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = [ZSupport() URLByAppendingPathComponent:@"enhance.log"].path;
    [_logLock lock];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!h) {
        [NSFileManager.defaultManager createFileAtPath:path contents:d attributes:nil];
    } else {
        @try {
            [h seekToEndOfFile];
            [h writeData:d];
        } @catch (NSException *e) {}
        [h closeFile];
    }
    [_logLock unlock];
}

@end

// ---------- خط فرمان ----------
// zemzeme --enhance <file|-> [--lang fa-IR]
// دلیل وجودش ست طلایی است: بی این، سنجیدنِ شش دیکته یعنی شش بار حرف زدن و امیدوار
// بودن. پرامپت روی stdout می‌رود و بقیه روی stderr، پس مستقیم به فایل لوله می‌شود.
int ZEnhanceMain(NSArray<NSString *> *args) {
    NSUInteger i = [args indexOfObject:@"--enhance"];
    if (i == NSNotFound || i + 1 >= args.count) {
        printf("usage: zemzeme --enhance <file|-> [--lang fa-IR]\n");
        return 2;
    }
    NSString *path = args[i + 1];
    NSString *text = nil;
    if ([path isEqualToString:@"-"]) {
        NSData *d = [NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile];
        text = [[NSString alloc] initWithData:d ?: [NSData data] encoding:NSUTF8StringEncoding];
    } else {
        text = [NSString stringWithContentsOfFile:path.stringByExpandingTildeInPath
                                        encoding:NSUTF8StringEncoding error:nil];
    }
    if (!text.length) {
        printf("enhance: متنی خوانده نشد: %s\n", path.UTF8String);
        return 2;
    }
    NSUInteger li = [args indexOfObject:@"--lang"];
    NSString *lang = (li != NSNotFound && li + 1 < args.count) ? args[li + 1] : @"fa-IR";
    // پرسشِ بلوکه، عمدا و مثل `--finalpass`: `hasKey` برای رابط است و روی نخ اصلی
    // هیچ‌وقت Keychain را نمی‌پرسد، پس اینجا همیشه «نه» می‌گفت.
    if (![ZFinalPass.shared key]) {
        printf("enhance: %s\n", ZFinalPass.missingKeyHint.UTF8String);
        return 1;
    }
    __block ZEnhanceResult *res = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [ZEnhance.shared runOnText:text lang:lang
                      progress:^(NSString *msg) { fprintf(stderr, "  %s\n", msg.UTF8String); }
                          done:^(ZEnhanceResult *r) {
        res = r;
        dispatch_semaphore_signal(sem);
    }];
    // کال‌بک روی نخ اصلی می‌آید و اینجا ران‌لوپی نمی‌چرخد، پس خودمان می‌چرخانیمش
    while (dispatch_semaphore_wait(sem, DISPATCH_TIME_NOW)) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                               beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    fprintf(stderr, "  %.0f ثانیه، %ld+%ld توکن، %s%s\n", res.seconds,
            (long)res.inTokens, (long)res.outTokens,
            res.summary.length ? res.summary.UTF8String : "بی‌سنجش",
            res.gated ? " (دروازه بست)" : "");
    if (res.error.length) {
        printf("enhance: %s\n", res.error.UTF8String);
        return 1;
    }
    if (res.gated || !res.text.length) return 1;
    printf("%s\n", res.text.UTF8String);
    return 0;
}
