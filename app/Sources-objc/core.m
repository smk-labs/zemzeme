// مسیرها، لاگ، اعداد فارسی، تنظیمات، پارسر protobuf
#import "zemzeme.h"
#import <CoreText/CoreText.h>

// ---------- مسیرها ----------

// دو ریشه جدا، و هیچ مسیر هاردکدی: خواندنی‌ها داخل بسته، نوشتنی‌ها در
// Application Support. پس بسته هرجا بنشیند (مثلا /Applications) کار می‌کند و
// پوشه پروژه هم فقط پوشه پروژه می‌ماند.

NSURL *ZRes(void) {
    static NSURL *res;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *b = NSBundle.mainBundle.resourceURL;
        if ([NSFileManager.defaultManager fileExistsAtPath:[b URLByAppendingPathComponent:@"prompts"].path]) {
            res = b;
            return;
        }
        // حالت توسعه: باینری خام app/.build/zemzeme، خواندنی‌ها دو پله بالاتر (app/).
        // قبلا سه پله بود چون serve.py و index.html ریشه‌ی ریپو بودند؛ هر دو رفتند و
        // تنها خواندنیِ باقی‌مانده app/prompts است. یک پله اشتباه یعنی پاس هوش
        // مصنوعی روی باینریِ توسعه بی‌صدا پرامپتش را پیدا نکند.
        NSURL *u = [NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]].URLByResolvingSymlinksInPath;
        for (int i = 0; i < 2; i++) u = u.URLByDeletingLastPathComponent;
        res = u;
    });
    return res;
}

NSURL *ZSupport(void) {
    static NSURL *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                          inDomains:NSUserDomainMask].firstObject;
        dir = [base URLByAppendingPathComponent:@"Zemzeme"];
        [NSFileManager.defaultManager createDirectoryAtURL:dir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return dir;
}

NSURL *ZSessionsDir(void) {
    return [ZSupport() URLByAppendingPathComponent:@"sessions"];
}

// ---------- لاگ ----------

NSString *const ZLogDayPrefix = @"--- ";

static NSLock *zLogLock(void) {
    static NSLock *l;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ l = [NSLock new]; });
    return l;
}

static NSURL *zLogFile(void) {
    return [ZSupport() URLByAppendingPathComponent:@"app.log"];
}

static NSDateFormatter *zLogDayFormatter(void) {
    static NSDateFormatter *df;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"yyyy-MM-dd";
    });
    return df;
}

void ZLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    static NSDateFormatter *df;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"HH:mm:ss";
    });
    NSDate *now = NSDate.date;
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:now], msg];

    NSLock *lock = zLogLock();
    [lock lock];
    // نشانه‌ی روز، سرِ هر روزِ تازه و سرِ هر اجرا. دو کار می‌کند: خواندنِ دستیِ لاگ
    // معنی پیدا می‌کند (ساعتِ تنها نمی‌گوید مالِ کدام روز است)، و جاروی روزانه
    // می‌فهمد از کجا ببرد. بی این، app.log تنها فایلی بود که هیچ‌وقت کوچک نمی‌شد.
    static NSString *lastDay;
    NSString *day = [zLogDayFormatter() stringFromDate:now];
    if (![day isEqualToString:lastDay]) {
        lastDay = day;
        line = [NSString stringWithFormat:@"%@%@ ---\n%@", ZLogDayPrefix, day, line];
    }
    NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = zLogFile().path;
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
    [lock unlock];
    fprintf(stderr, "%s", line.UTF8String);
}

// جاروی لاگ. اینجاست و نه در history.m چون قفل مالِ نویسنده است: بریدنِ فایل بی این
// قفل یعنی خطی که همان لحظه نوشته می‌شود روی نسخه‌ی رهاشده بنشیند و گم شود.
//
// از روی نشانه‌های روز می‌برد، نه از روی اندازه: اولین نشانه‌ای که از روزِ مرز
// جوان‌تر باشد سرِ فایلِ تازه می‌شود. نشانه‌ای پیدا نشد یعنی نمی‌دانیم کجا را ببریم،
// پس دست نمی‌زنیم؛ نبریدن همیشه از بریدنِ کورکورانه بهتر است.
NSUInteger ZLogTrimBefore(NSDate *cutoff) {
    if (!cutoff) return 0;
    NSDate *cutDay = [NSCalendar.currentCalendar startOfDayForDate:cutoff];
    NSLock *lock = zLogLock();
    [lock lock];
    NSUInteger cut = NSNotFound;
    NSURL *log = zLogFile();
    NSString *all = [NSString stringWithContentsOfURL:log encoding:NSUTF8StringEncoding error:nil];
    NSArray<NSString *> *lines = all.length ? [all componentsSeparatedByString:@"\n"] : @[];
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *ln = lines[i];
        if (![ln hasPrefix:ZLogDayPrefix] || ln.length < ZLogDayPrefix.length + 10) continue;
        NSDate *day = [zLogDayFormatter() dateFromString:
                       [ln substringWithRange:NSMakeRange(ZLogDayPrefix.length, 10)]];
        if (!day) continue;
        // روزِ نشانه با **روزِ** مرز سنجیده می‌شود نه با ساعتش، وگرنه هر جارو نیمی
        // از یک روز را می‌برد و خطوطِ صبحِ همان روز بی‌دلیل می‌رفتند.
        if ([day compare:cutDay] != NSOrderedAscending) { cut = i; break; }
    }
    if (cut != NSNotFound && cut > 0) {
        NSString *keep = [[lines subarrayWithRange:NSMakeRange(cut, lines.count - cut)]
                          componentsJoinedByString:@"\n"];
        [keep writeToURL:log atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    [lock unlock];
    return (cut == NSNotFound) ? 0 : cut;
}

// ---------- صدای کارها ----------
// نمونه‌ها کش می‌شوند چون ساختن NSSound هر بار از دیسک می‌خواند و روی مسیر کلید
// تاخیر می‌دهد. قبل از هر پخش stop، وگرنه فشار دادن سریع دو دکمه صدای اول را
// نصفه رها می‌کند و پخش دوم بی‌صدا می‌ماند.
void ZPlay(ZSound s) {
    if (!ZSettings.shared.soundsEnabled) return;
    static NSDictionary<NSNumber *, NSString *> *names;
    static NSMutableDictionary<NSString *, NSSound *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{@(ZSoundStart):  @"Bottle",    // روشن شدن
                  @(ZSoundPause):  @"Tink",      // کوتاه و خنثی
                  @(ZSoundResume): @"Pop",
                  @(ZSoundFinish): @"Glass",     // تمام شد و نشست
                  @(ZSoundInsert): @"Morse",     // درج، ولی هنوز بازیم
                  @(ZSoundTrash):  @"Basso",     // دور ریختن، عمدا ناخوشایند
                  @(ZSoundCopy):   @"Purr",
                  @(ZSoundMode):   @"Submarine",
                  @(ZSoundLang):   @"Frog",
                  @(ZSoundPolish): @"Hero",     // پاس نشست
                  @(ZSoundHole):   @"Basso"};   // تکه‌ای جا ماند؛ همان ناخوشایندِ دور ریختن
        cache = [NSMutableDictionary dictionary];
    });
    NSString *n = names[@(s)];
    if (!n) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSSound *snd = cache[n];
        if (!snd) {
            snd = [NSSound soundNamed:n];
            if (!snd) return;
            cache[n] = snd;
        }
        snd.volume = 0.35f;
        if (snd.isPlaying) [snd stop];
        [snd play];
    });
}

NSString *ZTimestampId(void) {
    static NSDateFormatter *df;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"yyyy-MM-dd-HH-mm-ss";
    });
    return [df stringFromDate:NSDate.date];
}

NSString *ZFaDigits(NSString *s) {
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{@"0": @"۰", @"1": @"۱", @"2": @"۲", @"3": @"۳", @"4": @"۴",
                @"5": @"۵", @"6": @"۶", @"7": @"۷", @"8": @"۸", @"9": @"۹"};
    });
    NSMutableString *out = [s mutableCopy];
    [map enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        [out replaceOccurrencesOfString:k withString:v options:0 range:NSMakeRange(0, out.length)];
    }];
    return out;
}

// ---------- فونت ----------

void ZRegisterFonts(void) {
    NSURL *res = NSBundle.mainBundle.resourceURL;
    if (!res) return;
    for (NSString *name in @[@"Vazirmatn-Regular.ttf", @"Vazirmatn-Medium.ttf"]) {
        NSURL *u = [res URLByAppendingPathComponent:name];
        if ([NSFileManager.defaultManager fileExistsAtPath:u.path]) {
            CTFontManagerRegisterFontsForURL((__bridge CFURLRef)u, kCTFontManagerScopeProcess, NULL);
        }
    }
}

NSFont *ZFont(CGFloat size, BOOL medium) {
    NSFont *f = [NSFont fontWithName:medium ? @"Vazirmatn-Medium" : @"Vazirmatn-Regular" size:size];
    return f ?: [NSFont systemFontOfSize:size weight:medium ? NSFontWeightMedium : NSFontWeightRegular];
}

// ---------- تنظیمات ----------

@implementation ZSettings

+ (instancetype)shared {
    static ZSettings *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [ZSettings new]; });
    return s;
}

- (NSUserDefaults *)d { return NSUserDefaults.standardUserDefaults; }

- (NSString *)lang { return [self.d stringForKey:@"lang"] ?: @"fa-IR"; }
- (void)setLang:(NSString *)v { [self.d setObject:v forKey:@"lang"]; }

- (ZInsertMode)insertMode {
    NSInteger v = [self.d integerForKey:@"insertMode"];
    return v == ZInsertPaste ? ZInsertPaste : ZInsertType;    // مقدار قدیمی «جمع» به تایپ برمی‌گردد
}
- (void)setInsertMode:(ZInsertMode)m { [self.d setInteger:m forKey:@"insertMode"]; }

// کلید همان «collect» قدیمی است و عمدا عوض نشده، پس انتخاب کاربر بین جمع و کرسر از
// نسخه یک بی‌هیچ کد مهاجرتی سر جایش می‌ماند.
//
// دو حالتِ حذف‌شده هم از همین‌جا مهاجرت می‌کنند: کسی که روی «درج زنده» (۰) یا
// «یادداشت» (۳) بوده، به «جمع» می‌آید. جمع و نه کرسر، چون جمع متن را نشان می‌دهد و
// کاربری که حالتش زیر پایش عوض شده باید ببیند چه شد، نه اینکه متن بی‌خبر جایی درج شود.
- (ZMode)mode {
    NSInteger v = [self.d integerForKey:@"collect"];
    return v == ZModeCursor ? ZModeCursor : ZModeCollect;
}
- (void)setMode:(ZMode)v { [self.d setInteger:v forKey:@"collect"]; }

// پیش‌فرض روشن. قبلا خاموش بود چون کارابینر دابل‌تپ را می‌گرفت و دو تشخیصِ هم‌زمان
// یعنی مسابقه. حالا رول کارابینر تا وقتی اپ بالاست اصلا دست به کلید نمی‌زند، پس
// اگر این خاموش بماند هیچ‌کس دابل‌تپ را نمی‌شنود و اپ روی نصبِ تازه بی‌هاتکی است.
- (BOOL)internalHotkey {
    NSObject *o = [self.d objectForKey:@"internalHotkey"];
    return o ? [self.d boolForKey:@"internalHotkey"] : YES;
}
- (void)setInternalHotkey:(BOOL)v { [self.d setBool:v forKey:@"internalHotkey"]; }

// حساسیت بالا: سقفِ کالیبراسیون بلندی را خیلی بالاتر می‌برد، برای پچ‌پچ کردن در
// اتاق ساکت و برای میکروفنی که سیگنالش ذاتا کم‌جان است. پیش‌فرض خاموش، چون روی
// میکروفن سالم لازم نیست و نویزِ میکروفنِ کم‌جان را هم به همان اندازه بزرگ می‌کند.
- (BOOL)highSensitivity { return [self.d boolForKey:@"highSensitivity"]; }
- (void)setHighSensitivity:(BOOL)v {
    [self.d setBool:v forKey:@"highSensitivity"];
    ZMicSetHighSensitivity(v);    // نخ صدا از کش می‌خواند، نه از دیفالتز
}

- (BOOL)soundsEnabled {
    NSObject *o = [self.d objectForKey:@"sounds"];
    return o ? [self.d boolForKey:@"sounds"] : YES;    // پیش‌فرض روشن
}
- (void)setSoundsEnabled:(BOOL)v { [self.d setBool:v forKey:@"sounds"]; }

// زبان پیش‌فرض رونویسی فایل، عمدا جدا از lang دیکته‌ی زنده: کسی که همیشه فارسی
// دیکته می‌کند ممکن است پادکست انگلیسی رونویسی کند، و عوض کردن یکی نباید آن یکی
// را بچرخاند.
- (NSString *)batchLang { return [self.d stringForKey:@"batchLang"] ?: @"fa-IR"; }
- (void)setBatchLang:(NSString *)v { [self.d setObject:v forKey:@"batchLang"]; }

// پیش‌فرض خاموش، و عمدا: بی‌کلید روشن بودنش فقط یک پیام خطا در پایان هر سشن است.
// روشن کردنش هم انتخاب صریح کاربر است، چون یک تماس شبکه‌ای و پولی به کار اضافه می‌کند.
- (BOOL)finalPassEnabled { return [self.d boolForKey:@"finalPass"]; }
- (void)setFinalPassEnabled:(BOOL)v { [self.d setBool:v forKey:@"finalPass"]; }

// پیش‌فرض خاموش، و جدا از تاگل پاس نهایی: ضبطِ ناخواسته‌ی صدا بدترین پیش‌فرض ممکن است.
// حالت یادداشت به این کاری ندارد؛ آنجا ضبط تنها کاری است که انجام می‌شود.
- (BOOL)recordSessions { return [self.d boolForKey:@"recordSessions"]; }
- (void)setRecordSessions:(BOOL)v { [self.d setBool:v forKey:@"recordSessions"]; }

// پیش‌فرض خاموش: یک سشن دوم به ازای هر تکه، و سودش فقط روی متنِ پر از اصطلاح فنی
// دیده می‌شود. اندازه‌گیری: روی ضبط ۰۲ کل بلوک‌هایی را برگرداند که پاس فارسی انداخته
// بود، روی ضبط ۰۷ تقریبا هیچ.
- (BOOL)secondPass { return [self.d boolForKey:@"secondPass"]; }
- (void)setSecondPass:(BOOL)v { [self.d setBool:v forKey:@"secondPass"]; }

// پیش‌نمایش. پیش‌فرض خاموش، و این یکی نه به‌خاطر هزینه که به‌خاطر **حواس‌پرتی**:
// هیچ بایتِ اضافه‌ای فرستاده نمی‌شود و هیچ چیزی در مسیر تشخیص عوض نمی‌شود (همان
// تکه‌های خط لوله، فقط زودتر دیده می‌شوند)، ولی خواندنِ حرفِ خود آدم در حالی که دارد
// همان را می‌گوید، رشته‌ی کلام را پاره می‌کند. پس انتخابِ صریح، نه پیش‌فرض.
- (BOOL)previewStream { return [self.d boolForKey:@"previewStream"]; }
- (void)setPreviewStream:(BOOL)v { [self.d setBool:v forKey:@"previewStream"]; }

// نبودنِ کلید یعنی پیش‌فرض، نه صفر. صفر اینجا معنیِ خودش را دارد («هرگز جارو نکن»)،
// پس اگر مثل بقیه‌ی عددها مستقیم خوانده می‌شد، هر نصبِ تازه بی‌صدا با جاروی خاموش
// بالا می‌آمد و همان چیزی که این تنظیم برایش هست اتفاق نمی‌افتاد.
- (NSInteger)historyKeepDays {
    NSObject *o = [self.d objectForKey:@"historyKeepDays"];
    return o ? [self.d integerForKey:@"historyKeepDays"] : kZHistoryKeepDays;
}
- (void)setHistoryKeepDays:(NSInteger)v { [self.d setInteger:v forKey:@"historyKeepDays"]; }

- (BOOL)upstreamFLAC {
    NSObject *o = [self.d objectForKey:@"upstreamFLAC"];
    return o ? [self.d boolForKey:@"upstreamFLAC"] : YES;    // پیش‌فرض روشن
}
- (void)setUpstreamFLAC:(BOOL)v { [self.d setBool:v forKey:@"upstreamFLAC"]; }

// Windows App همیشه پیست می‌گیرد. این دیگر یک پیش‌فرضِ قابلِ عوض کردن نیست، قانون است.
//
// چرا تایپ آنجا **ذاتا** غلط است، نه «نامطمئن»: رویدادِ تایپِ ما کیکد صفر است با متنِ
// یونیکد چسبیده به آن (zPostUnicode در inject.m)، و کیکد صفر روی کیبورد مک همان A است.
// کلاینت ریموت وقتی Keyboard Mode رویش Scancode باشد اصلا به محتوای یونیکد نگاه نمی‌کند و
// فقط اسکن‌کدِ همان کیکد را به ویندوز می‌فرستد. نتیجه: به‌ازای هر رویداد یک a. متنِ ۶۴
// نویسه‌ای در هجده‌تایی‌ها می‌شکند و آن‌طرف «aaaa» می‌نشیند. کیبوردِ این دستگاه همیشه روی
// Scancode است، پس این «شاید جواب ندهد» نیست، «هیچ‌وقت جواب نمی‌دهد» است.
//
// اینجا قبلا یک استثنای per-app بود که از منو تاگل می‌شد و مقدارش روی دیسک می‌ماند. یک
// کلیک روی آن ردیف کافی بود تا از آن لحظه به بعد هر درجی در ریموت «aaaa» بدهد، بی هیچ
// نشانه‌ای که چه شد و چرا. تنظیمی که تنها کارِ ممکنش خراب کردن است تنظیم نیست، تله است.
- (ZInsertMode)insertModeForBundleId:(NSString *)bundleId {
    if ([bundleId isEqualToString:kZRDPBundleId]) return ZInsertPaste;
    return self.insertMode;
}

- (useconds_t)typeDelayMicros {
    NSObject *o = [self.d objectForKey:@"typeDelayMs"];
    double ms = o ? [self.d doubleForKey:@"typeDelayMs"] : 1.0;
    return (useconds_t)(MAX(0, ms) * 1000);
}

- (useconds_t)pasteDelayMicros {
    // پیش‌فرض ۶۰۰: کلیپ‌بورد ریموت دسکتاپ با ۳۵۰ به موقع سینک نمی‌شد (تست واقعی 2026-07-24)
    NSObject *o = [self.d objectForKey:@"pasteDelayMs"];
    double ms = o ? [self.d doubleForKey:@"pasteDelayMs"] : 600.0;
    return (useconds_t)(MAX(0, ms) * 1000);
}

@end

// ---------- پارسر protobuf ----------
// اسکیمای google_streaming_api.proto در Chromium:
// event{status=1, result=2, endpoint=4} / result{alternative=1, final=2, stability=3}
// alternative{transcript=1, confidence=2}

@implementation ZSpeechEvent
- (instancetype)init {
    if ((self = [super init])) {
        _status = -1;
        _endpoint = -1;
        _finals = [NSMutableArray array];
        _interim = @"";
    }
    return self;
}
@end

static BOOL zVarint(const uint8_t *b, NSUInteger len, NSUInteger *i, uint64_t *out) {
    uint64_t v = 0;
    int s = 0;
    while (*i < len) {
        uint8_t x = b[(*i)++];
        v |= (uint64_t)(x & 0x7F) << s;
        if (!(x & 0x80)) {
            *out = v;
            return YES;
        }
        s += 7;
        if (s > 63) return NO;
    }
    return NO;
}

// callback ازای هر فیلد؛ برای فیلدهای تودرتو بازگشتی صدا زده می‌شود
typedef void (^ZFieldVisitor)(uint64_t field, int wire, uint64_t scalar, const uint8_t *sub, NSUInteger subLen);

static void zWalkFields(const uint8_t *b, NSUInteger len, ZFieldVisitor visit) {
    NSUInteger i = 0;
    while (i < len) {
        uint64_t key;
        if (!zVarint(b, len, &i, &key)) return;
        uint64_t f = key >> 3;
        int w = key & 7;
        if (w == 0) {
            uint64_t v;
            if (!zVarint(b, len, &i, &v)) return;
            visit(f, w, v, NULL, 0);
        } else if (w == 2) {
            uint64_t n;
            if (!zVarint(b, len, &i, &n) || i + n > len) return;
            visit(f, w, 0, b + i, (NSUInteger)n);
            i += n;
        } else if (w == 5) {
            if (i + 4 > len) return;
            visit(f, w, 0, b + i, 4);
            i += 4;
        } else if (w == 1) {
            if (i + 8 > len) return;
            visit(f, w, 0, b + i, 8);
            i += 8;
        } else {
            return;
        }
    }
}

ZSpeechEvent *ZProtoDecodeEvent(NSData *body) {
    ZSpeechEvent *ev = [ZSpeechEvent new];
    NSMutableString *interim = [NSMutableString string];
    zWalkFields(body.bytes, body.length, ^(uint64_t f, int w, uint64_t v, const uint8_t *sub, NSUInteger subLen) {
        if (f == 1 && w == 0) {
            ev.status = (NSInteger)v;
        } else if (f == 4 && w == 0) {
            ev.endpoint = (NSInteger)v;
        } else if (f == 2 && w == 2) {
            ev.hasResults = YES;
            __block BOOL isFinal = NO;
            __block NSString *txt = @"";
            zWalkFields(sub, subLen, ^(uint64_t f2, int w2, uint64_t v2, const uint8_t *sub2, NSUInteger sub2Len) {
                if (f2 == 1 && w2 == 2) {
                    zWalkFields(sub2, sub2Len, ^(uint64_t f3, int w3, uint64_t v3, const uint8_t *sub3, NSUInteger sub3Len) {
                        if (f3 == 1 && w3 == 2 && txt.length == 0) {
                            NSString *s = [[NSString alloc] initWithBytes:sub3 length:sub3Len encoding:NSUTF8StringEncoding];
                            if (s) txt = s;
                        }
                    });
                } else if (f2 == 2 && w2 == 0) {
                    isFinal = v2 != 0;
                }
            });
            if (isFinal) [ev.finals addObject:txt];
            else [interim appendString:txt];
        }
    });
    ev.interim = interim;
    return ev;
}
