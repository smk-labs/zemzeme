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
        if ([NSFileManager.defaultManager fileExistsAtPath:[b URLByAppendingPathComponent:@"serve.py"].path]) {
            res = b;
            return;
        }
        // حالت توسعه: باینری خام app/.build/zemzeme، اسکریپت‌ها سه پله بالاتر
        NSURL *u = [NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]].URLByResolvingSymlinksInPath;
        for (int i = 0; i < 3; i++) u = u.URLByDeletingLastPathComponent;
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

void ZLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    static NSDateFormatter *df;
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"HH:mm:ss";
        lock = [NSLock new];
    });
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:NSDate.date], msg];
    NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
    [lock lock];
    NSString *path = [ZSupport() URLByAppendingPathComponent:@"app.log"].path;
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
                  @(ZSoundPolish): @"Hero"};    // پاس نشست
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

- (NSString *)engineName { return [self.d stringForKey:@"engine"] ?: @"google"; }
- (void)setEngineName:(NSString *)v { [self.d setObject:v forKey:@"engine"]; }

- (ZInsertMode)insertMode {
    NSInteger v = [self.d integerForKey:@"insertMode"];
    return v == ZInsertPaste ? ZInsertPaste : ZInsertType;    // مقدار قدیمی «جمع» به تایپ برمی‌گردد
}
- (void)setInsertMode:(ZInsertMode)m { [self.d setInteger:m forKey:@"insertMode"]; }

// کلید همان «collect» قدیمی است و عمدا عوض نشده: مقدار BOOL ذخیره‌شده‌ی نسخه‌های
// قبل با integerForKey دقیقا ۰ و ۱ خوانده می‌شود، یعنی همان ZModeLive و ZModeCollect،
// پس انتخاب کاربر قدیمی بدون هیچ کد مهاجرتی سر جایش می‌ماند. مقدار بیرون از بازه
// (کلید دستکاری‌شده) به زنده برمی‌گردد، نه به حالتی که کاربر نمی‌شناسد.
- (ZMode)mode {
    NSInteger v = [self.d integerForKey:@"collect"];
    return (v >= ZModeLive && v <= ZModeNote) ? (ZMode)v : ZModeLive;
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

- (BOOL)polishEnabled {
    NSObject *o = [self.d objectForKey:@"polish"];
    return o ? [self.d boolForKey:@"polish"] : YES;    // پیش‌فرض روشن
}
- (void)setPolishEnabled:(BOOL)v { [self.d setBool:v forKey:@"polish"]; }

// پیش‌فرض خاموش: تصمیم اولیه این بود که وام‌واژه دست نخورد، پس برگرداندنش باید
// انتخاب صریح کاربر باشد نه رفتار پیش‌فرض.
- (BOOL)latinTerms { return [self.d boolForKey:@"latinTerms"]; }
- (void)setLatinTerms:(BOOL)v { [self.d setBool:v forKey:@"latinTerms"]; }

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

- (BOOL)plainNotes { return [self.d boolForKey:@"plainNotes"]; }
- (void)setPlainNotes:(BOOL)v { [self.d setBool:v forKey:@"plainNotes"]; }

// بتا، پس پیش‌فرض خاموش و بی‌هیچ استثنایی: تا کاربر صریحا روشنش نکند، نه دکمه‌ای
// دیده می‌شود، نه میان‌بری کار می‌کند، نه تماسی گرفته می‌شود.
- (BOOL)enhanceEnabled { return [self.d boolForKey:@"enhance"]; }
- (void)setEnhanceEnabled:(BOOL)v { [self.d setBool:v forKey:@"enhance"]; }

// پیش‌فرض خاموش، و جدا از تاگل پاس نهایی: ضبطِ ناخواسته‌ی صدا بدترین پیش‌فرض ممکن است.
// حالت یادداشت به این کاری ندارد؛ آنجا ضبط تنها کاری است که انجام می‌شود.
- (BOOL)recordSessions { return [self.d boolForKey:@"recordSessions"]; }
- (void)setRecordSessions:(BOOL)v { [self.d setBool:v forKey:@"recordSessions"]; }

- (BOOL)upstreamFLAC {
    NSObject *o = [self.d objectForKey:@"upstreamFLAC"];
    return o ? [self.d boolForKey:@"upstreamFLAC"] : YES;    // پیش‌فرض روشن
}
- (void)setUpstreamFLAC:(BOOL)v { [self.d setBool:v forKey:@"upstreamFLAC"]; }

- (ZInsertMode)insertModeForBundleId:(NSString *)bundleId {
    // استثنای هر اپ؛ Windows App پیش‌فرض پیست می‌گیرد چون فوروارد یونیکد مصنوعی در RDP نامطمئن است.
    // ادغام، نه جایگزینی: اولین چیزی که روزی در perApp نوشته شود نباید این پیش‌فرض را ببلعد.
    NSMutableDictionary *perApp = [@{kZRDPBundleId: @(ZInsertPaste)} mutableCopy];
    [perApp addEntriesFromDictionary:[self.d dictionaryForKey:@"perApp"] ?: @{}];
    NSNumber *n = bundleId ? perApp[bundleId] : nil;
    return n ? n.integerValue : self.insertMode;
}

- (void)setInsertMode:(ZInsertMode)m forBundleId:(NSString *)bundleId {
    if (!bundleId.length) return;
    NSMutableDictionary *perApp = [[self.d dictionaryForKey:@"perApp"] mutableCopy] ?: [NSMutableDictionary dictionary];
    perApp[bundleId] = @(m);
    [self.d setObject:perApp forKey:@"perApp"];
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
