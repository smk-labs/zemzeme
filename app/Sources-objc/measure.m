// اندازه‌گیری: یک فایل صدا از **کل** مسیر زنده رد می‌شود، بی‌میکروفن و بی‌آدم.
//
// شرط سخت این بازنویسی. نسخه یک چنین چیزی نداشت و هر ادعای سرتاسری یعنی «حرف زدم و
// خوب به نظر رسید»؛ پنج دور وصله از همان‌جا شکست خورد. اینجا هیچ میان‌بری زده نمی‌شود:
// همان ZEngine، همان تکه‌های ۱۰۰ میلی‌ثانیه‌ای، همان برش‌زن، همان صف. تنها تفاوت با
// یک سشن واقعی این است که به‌جای میکروفن، بایت‌ها از یک WAV می‌آیند.
//
//   zemzeme --livewav <file.wav> [--lang fa-IR] [--speed 1] [--ref متن.md]
//   zemzeme --livewav --table            جدولِ RESULTS.md روی ضبط‌های محک
#import "zemzeme.h"

// ---------- شمارش واژه ----------
// «گم‌شده» یعنی واژه‌ای از متن مرجع که در خروجی نیست، همان تعریف RESULTS.md، پس
// عددها با جدول قدیمی قابل مقایسه‌اند.
//
// و همان‌جا هم نوشته شده که این عدد **کمتر از واقعیت** می‌گوید: «لاگین» را با
// `login` برابر نمی‌بیند، در حالی که معنی سر جایش است. پس عدد کف است نه حقیقت، و
// خواندنِ خودِ متن جای خودش را دارد.
static NSString *ZNorm(NSString *s) {
    NSMutableString *m = [s mutableCopy];
    // یکدست‌سازی عربی/فارسی، وگرنه «ی» و «ي» دو واژه‌ی متفاوت شمرده می‌شوند
    [m replaceOccurrencesOfString:@"ي" withString:@"ی" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"ك" withString:@"ک" options:0 range:NSMakeRange(0, m.length)];
    // نیم‌فاصله به فاصله، نه حذف: «می‌شود» و «می شود» باید یک چیز شمرده شوند
    [m replaceOccurrencesOfString:@"‌" withString:@" " options:0 range:NSMakeRange(0, m.length)];
    return m.lowercaseString;
}

static NSArray<NSString *> *ZWords(NSString *s) {
    NSMutableCharacterSet *drop = [NSMutableCharacterSet punctuationCharacterSet];
    [drop formUnionWithCharacterSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [drop formUnionWithCharacterSet:NSCharacterSet.symbolCharacterSet];
    [drop addCharactersInString:@"،؛؟«»…"];
    NSArray *raw = [ZNorm(s) componentsSeparatedByCharactersInSet:drop];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *w in raw) {
        if (w.length) [out addObject:w];
    }
    return out;
}

typedef struct {
    NSUInteger ref, got, missing;
    double match;
} ZScore;

// متنِ مرجع = فقط همان چیزی که با صدای بلند خوانده شده. بعضی از فیکسچرها زیرِ متن،
// یادداشت و جدول هم دارند (۰۱ سه ضبط از یک متن است و توضیحش همان‌جاست)، و شمردنِ
// آن‌ها مرجع را از ۱۸۴ واژه به ۴۶۵ می‌برد و تطبیق را بی‌معنی می‌کند. هر چیزی از
// اولین خطِ `---` یا سرتیتر به بعد، توضیح است نه متنِ خوانده‌شده.
static NSString *ZScript(NSString *md) {
    for (NSString *marker in @[@"\n---", @"\n#"]) {
        NSRange r = [md rangeOfString:marker];
        if (r.location != NSNotFound) md = [md substringToIndex:r.location];
    }
    return md;
}

// چندمجموعه‌ای، نه مجموعه‌ای: واژه‌ای که در مرجع سه بار آمده و در خروجی یک بار،
// دو تا گم‌شده دارد. با مجموعه‌ی ساده، افتادنِ تکرارها اصلا دیده نمی‌شد.
static ZScore ZScoreText(NSString *reference, NSString *output) {
    NSArray *ref = ZWords(reference), *got = ZWords(output);
    NSCountedSet *have = [NSCountedSet setWithArray:got];
    NSUInteger missing = 0;
    for (NSString *w in ref) {
        if ([have countForObject:w]) {
            [have removeObject:w];
        } else {
            missing++;
        }
    }
    ZScore s = {ref.count, got.count, missing, 0};
    s.match = ref.count ? 100.0 * (ref.count - missing) / ref.count : 0;
    return s;
}

// ---------- خواندن WAV ----------
// عمدا فقط PCM ۱۶ بیتی مونو ۱۶ کیلوهرتز، همان چیزی که --micdump می‌سازد. هر چیز
// دیگری کار مسیر رونویسی فایل است (--transcribe) که دیکدر کامل دارد.
static NSData *ZReadWav(NSString *path, NSString **err) {
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d) {
        *err = [NSString stringWithFormat:@"خوانده نشد: %@", path];
        return nil;
    }
    if (d.length < 44 || memcmp(d.bytes, "RIFF", 4) || memcmp((const char *)d.bytes + 8, "WAVE", 4)) {
        *err = @"WAV نیست";
        return nil;
    }
    // پیمایش چانک‌ها: بعضی نوشتارها بین fmt و data چیز دیگری هم می‌گذارند، پس
    // پریدنِ ثابتِ ۴۴ بایت همیشه درست نیست.
    const uint8_t *b = d.bytes;
    NSUInteger i = 12;
    uint16_t ch = 0, bits = 0;
    uint32_t rate = 0;
    while (i + 8 <= d.length) {
        uint32_t sz;
        memcpy(&sz, b + i + 4, 4);
        NSUInteger body = i + 8;
        if (!memcmp(b + i, "fmt ", 4) && body + 16 <= d.length) {
            memcpy(&ch, b + body + 2, 2);
            memcpy(&rate, b + body + 4, 4);
            memcpy(&bits, b + body + 14, 2);
        } else if (!memcmp(b + i, "data", 4)) {
            NSUInteger n = MIN((NSUInteger)sz, d.length - body);
            if (ch != 1 || rate != 16000 || bits != 16) {
                *err = [NSString stringWithFormat:@"باید مونو ۱۶ کیلوهرتز ۱۶ بیتی باشد، این %u کانال %u هرتز %u بیت است",
                                                  ch, rate, bits];
                return nil;
            }
            return [d subdataWithRange:NSMakeRange(body, n)];
        }
        i = body + sz + (sz & 1);
    }
    *err = @"چانک data پیدا نشد";
    return nil;
}

// ---------- یک اجرا ----------

// سقفِ صبر برای خالی شدنِ صف در اندازه‌گیری. آدمی پشتِ این مسیر نیست، ولی انتظارِ
// بی‌سقف هم ممنوع است.
#define kZMeasureSettleSec 60.0

@interface ZMeasureRun : NSObject <ZEngineDelegate>
@property (nonatomic, copy) NSString *text, *second;
@property (nonatomic, copy) NSString *preview;      // آخرین متنِ خامِ پیش‌نمایش
@property (nonatomic) NSInteger previewUpdates;
@property (nonatomic) BOOL echoPreview;
@property (nonatomic) NSTimeInterval took;
@property (nonatomic) NSInteger degraded;
@property (nonatomic) BOOL done;
@end

@implementation ZMeasureRun
- (void)engineState:(ZEngineState)state message:(NSString *)msg {}
- (void)engineLevel:(float)rms {}
// پیش‌نمایش هم باید بی‌میکروفن دیده شود، وگرنه «کار می‌کند» یعنی «حرف زدم و خوب به
// نظر رسید»، و همان جمله بود که نسخه یک را پنج دور به وصله کشاند.
- (void)enginePreview:(NSString *)text {
    _preview = text;
    _previewUpdates++;
    if (_echoPreview) fprintf(stderr, "preview> %s\n", (text ?: @"").UTF8String);
}
- (void)engineDidFinish:(NSString *)text second:(NSString *)second took:(NSTimeInterval)took {
    _text = text;
    _second = second;
    _took = took;
    _done = YES;
}
@end

// برشِ **ثابت**، فقط برای بازتولید شرایط جدول قدیمی. خط لوله را دور می‌زند و عمدا:
// تنها راهِ مقایسه‌ی منصفانه این است که خطِ مبنا با همین شمارنده سنجیده شود، نه با
// اسکریپتی که دیگر وجود ندارد. اگر برشِ سر سکوت از همین عدد جلو بزند، جلو زدنش
// واقعی است؛ وگرنه ایراد از برش‌زن است نه از شمارنده.
static NSString *ZFixedCuts(NSData *pcm, NSString *lang, double sec) {
    NSUInteger step = (NSUInteger)(sec * kZPcmBytesPerSec);
    step -= step % 2;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSUInteger off = 0; off < pcm.length; off += step) {
        NSData *piece = [pcm subdataWithRange:NSMakeRange(off, MIN(step, pcm.length - off))];
        if (!ZSegHasVoice(piece)) continue;
        NSString *t = ZTranscribeSegment(piece, lang, NO, NULL, NULL);
        if (t.length) [parts addObject:t];
    }
    return [parts componentsJoinedByString:@" "];
}

// یک فایل، کل خط لوله. برمی‌گرداند: متن، و ثانیه‌ی «از پایان صدا تا آماده شدن متن».
//
// switchAt: ثانیه‌ای از صدا که وسطش زبان عوض می‌شود، صفر یعنی هیچ. تنها راهِ سنجیدنِ
// «وسط دیکته زبان را عوض کن» بی‌میکروفن و بی‌آدم است: کاربر گزارش داد که رابط زبان
// تازه را نشان می‌داد و متن به زبان قبلی می‌آمد، و چنین چیزی نباید دوباره بی‌صدا
// برگردد. با speed=۰ (تندترین) این تست چند ثانیه بیشتر طول نمی‌کشد.
static ZMeasureRun *ZRunWav(NSData *pcm, NSString *lang, double speed, BOOL preview,
                            NSArray<NSArray *> *switches, NSArray<NSNumber *> *drops,
                            BOOL asSession) {
    ZMeasureRun *run = [ZMeasureRun new];
    run.echoPreview = preview;
    ZEngine *eng = [[ZEngine alloc] initWithLang:lang];
    eng.delegate = run;
    eng.previewInFileMode = preview;
    // یک سشنِ واقعی روی دیسک، با ضبط و دفترچه. تنها راهِ آزمودنِ «تکه‌ی در انتظار از
    // بسته شدنِ اپ هم جان سالم می‌برد» بی‌میکروفن و بی‌آدم: پروسه وسطِ قطعی کشته
    // می‌شود و لانچِ بعدی باید همان صف را تمام کند.
    if (asSession) {
        NSURL *dir = [ZSessionsDir() URLByAppendingPathComponent:ZTimestampId()];
        [NSFileManager.defaultManager createDirectoryAtURL:dir
                              withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *audio = [dir URLByAppendingPathComponent:@"audio.flac"];
        eng.recorder = [[ZRecorder alloc] initWithURL:audio];
        eng.queue.audio = audio;
        eng.queue.manifest = ZQueueManifestIn(dir);
        eng.queue.lang = lang;
        fprintf(stderr, "--- سشن: %s ---\n", dir.path.UTF8String);
    }
    NSError *e = nil;
    if (![eng startFromPCM:pcm speed:speed error:&e]) {
        fprintf(stderr, "شروع نشد: %s\n", e.localizedDescription.UTF8String ?: "?");
        return nil;
    }
    // سر ثانیه‌ی **صدا**، نه سر ساعت دیوار: eng.seconds همان شمارنده‌ای است که خودِ
    // موتور از بایت‌ها می‌سازد، پس مرز با هر speed در جای درستِ فایل می‌افتد.
    //
    // یک تله که یک بار خورده شد: با speed=۰ کل فایل داخل یک بلوکِ پس‌زمینه و بی هیچ
    // مکثی بلعیده می‌شود، پس این حلقه تازه بعد از تمام شدنِ صدا نوبتش می‌رسد و مرز
    // همیشه آخرِ فایل می‌افتد. برای این تست speed باید متناهی باشد (۱ تا ۴).
    NSUInteger nextSwitch = 0, nextDrop = 0;
    while (!run.done) {
        while (nextSwitch < switches.count
               && eng.seconds >= [switches[nextSwitch][0] doubleValue]) {
            NSString *to = switches[nextSwitch][1];
            nextSwitch++;
            fprintf(stderr, "--- ثانیه %.1f: زبان → %s ---\n", eng.seconds, to.UTF8String);
            [eng switchLang:to];
        }
        // سطل آشغال سر همان ثانیه‌ی صدا. معیار پذیرش عینی است و نه چشمی: متنِ چاپ‌شده
        // باید **فقط** حرف‌های بعد از این مرز را داشته باشد. تا امروز نداشت، و همان
        // باگ بود: تکه‌های قبلِ مرز داخل خط لوله می‌ماندند و سر پایان برمی‌گشتند.
        while (nextDrop < drops.count && eng.seconds >= drops[nextDrop].doubleValue) {
            nextDrop++;
            fprintf(stderr, "--- ثانیه %.1f: دور ریختن ---\n", eng.seconds);
            [eng discardText];
        }
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    // متن باید **کامل** گزارش شود، نه نصفه. موتور سر پایان فقط تا دورِ اول صبر
    // می‌کند (تحویل به آدم نباید گروگانِ یک تکه بماند)، ولی اندازه‌گیری آدمی پشتش
    // ندارد که منتظر بماند: بی این حلقه، یک قطعیِ گذرای ده ثانیه‌ای وسط اجرا به یک
    // عددِ پایین‌ترِ دروغ تبدیل می‌شد. سقف دارد، مثل هر انتظار دیگری در این اپ.
    if (eng.queue.waiting) {
        fprintf(stderr, "--- %ld تکه در راه؛ تا خالی شدن صف صبر می‌کنیم ---\n",
                (long)eng.queue.waiting);
        NSDate *ceiling = [NSDate dateWithTimeIntervalSinceNow:kZMeasureSettleSec];
        while (eng.queue.waiting && [NSDate.date compare:ceiling] == NSOrderedAscending) {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        }
        fprintf(stderr, "--- %ld تکه هنوز در راه ---\n", (long)eng.queue.waiting);
        run.text = [eng.queue textFrom:0 extra:NO];
        run.second = [eng.queue textFrom:0 extra:YES];
    }
    run.degraded = eng.degradedCuts;
    return run;
}

// ---------- جدول محک ----------
// همان شکلِ RESULTS.md، که عددها کنار هم قابل مقایسه باشند. ۰۷ و ۰۲ عددهای هدف‌اند
// (۷۷٪ و ۷۰٪، یعنی نتیجه‌ی برشِ **ثابتِ** هفت ثانیه‌ای)، بقیه برای اینکه معلوم شود
// جای دیگری خراب نشده.
static int ZTable(NSArray<NSString *> *takes, NSString *lang, double speed) {
    printf("\n| ضبط | طول | واژه مرجع | واژه خروجی | گم‌شده | تطبیق | تحمیلی | تا متن |\n");
    printf("|---|---|---|---|---|---|---|---|\n");
    for (NSString *take in takes) {
        NSString *wav = [NSString stringWithFormat:@"tools/fixtures/read-aloud/%@.wav", take];
        // ضبط‌های ۰۱ سه نسخه‌ی صوتی از یک متن‌اند (عادی، تند، قاطی)، پس نامِ متن
        // پسوندِ نسخه را ندارد. بی این، مرجع خالی خوانده می‌شد و ستون تطبیق صفر.
        NSString *base = take;
        NSRange dash = [take rangeOfString:@"-" options:NSBackwardsSearch];
        if ([take hasPrefix:@"01-"] && dash.location != NSNotFound) base = [take substringToIndex:dash.location];
        NSString *md = [NSString stringWithFormat:@"tools/fixtures/read-aloud/%@.md", base];
        NSString *err = nil;
        NSData *pcm = ZReadWav(wav, &err);
        if (!pcm) {
            fprintf(stderr, "%s: %s\n", take.UTF8String, err.UTF8String);
            return 1;
        }
        NSString *ref = [NSString stringWithContentsOfFile:md encoding:NSUTF8StringEncoding error:nil];
        ZMeasureRun *r = ZRunWav(pcm, lang, speed, NO, nil, nil, NO);
        if (!r) return 1;
        ZScore s = ZScoreText(ZScript(ref ?: @""), r.text ?: @"");
        double sec = pcm.length / kZPcmBytesPerSec;
        printf("| %s | %.0f ثانیه | %lu | %lu | %lu | %.0f٪ | %ld | %.1f ثانیه |\n",
               take.UTF8String, sec, (unsigned long)s.ref, (unsigned long)s.got,
               (unsigned long)s.missing, s.match, (long)r.degraded, r.took);
        fflush(stdout);
        // متن کامل روی stderr: عدد تنها کافی نیست و خودِ متن باید خوانده شود.
        fprintf(stderr, "\n--- %s ---\n%s\n", take.UTF8String, (r.text ?: @"").UTF8String);
        if (r.second.length) fprintf(stderr, "--- %s (en-US) ---\n%s\n", take.UTF8String, r.second.UTF8String);
    }
    return 0;
}

// ---------- پاس هوش مصنوعی، بی‌رابط ----------
// zemzeme --aipass <متن.txt|-> [--second متن-انگلیسی.txt] [--lang fa-IR]
//
// همان دلیلِ --livewav: بی این، تنها راهِ سنجیدنِ این پاس «یک سشن حرف بزن و امیدوار
// باش» بود. و چون این تنها جایی است که چیزی از دستگاه بیرون می‌رود، باید بشود
// دقیقا دید چه رفت و چه برگشت.
int ZAIPassMain(NSArray<NSString *> *args) {
    NSString *lang = @"fa-IR", *file = nil, *secondPath = nil, *prevPath = nil;
    NSUInteger i = [args indexOfObject:@"--aipass"] + 1;
    for (; i < args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--lang"] && i + 1 < args.count) lang = args[++i];
        else if ([a isEqualToString:@"--second"] && i + 1 < args.count) secondPath = args[++i];
        else if ([a isEqualToString:@"--prev"] && i + 1 < args.count) prevPath = args[++i];
        else if (!file) file = a;
    }
    if (!file) {
        fprintf(stderr, "zemzeme --aipass <متن.txt|-> [--second متن-en.txt] [--lang fa-IR]\n");
        return 2;
    }
    NSString *text = [file isEqualToString:@"-"]
        ? [[NSString alloc] initWithData:[NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile]
                                encoding:NSUTF8StringEncoding]
        : [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
    if (!text.length) {
        fprintf(stderr, "متنی نبود\n");
        return 1;
    }
    NSString *second = secondPath
        ? [NSString stringWithContentsOfFile:secondPath encoding:NSUTF8StringEncoding error:nil] : nil;

    __block BOOL done = NO;
    __block int rc = 0;
    NSDate *t0 = NSDate.date;
    // مسیرِ ادامه: متنِ تمیزِ قبلی به‌اضافه‌ی تکه‌ی خامِ تازه. همان کاری که سشن در
    // دورِ دوم می‌کند، ولی بی‌میکروفن و بی‌آدم، تا بشود واقعا دیدش.
    NSString *prev = prevPath
        ? [NSString stringWithContentsOfFile:prevPath encoding:NSUTF8StringEncoding error:nil] : nil;
    void (^landed)(NSString *, NSString *) = ^(NSString *out, NSString *err) {
        if (out.length) {
            printf("%s\n", out.UTF8String);
        } else {
            fprintf(stderr, "پاس نشد: %s\n", err.UTF8String ?: "?");
            rc = 1;
        }
        done = YES;
    };
    if (prev.length) [ZFinalPass.shared runOnText:text appendingTo:prev lang:lang done:landed];
    else [ZFinalPass.shared runOnText:text second:second lang:lang done:landed];
    while (!done) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    fprintf(stderr, "%.1f ثانیه\n", [NSDate.date timeIntervalSinceDate:t0]);
    return rc;
}

int ZLiveWavMain(NSArray<NSString *> *args) {
    NSString *lang = @"fa-IR", *file = nil, *refPath = nil;
    double speed = 0;      // صفر یعنی تندترین ممکن؛ ۱ یعنی زمان واقعی
    double fixed = 0;      // برش ثابت، فقط برای بازتولید خط مبنا
    BOOL table = NO;
    BOOL preview = NO;     // استریم نمایشی را هم روشن کن و متنش را چاپ کن
    BOOL session = NO;     // سشنِ واقعی روی دیسک: ضبط، دفترچه، و برداشتن سر لانچ
    // هر بار --switchlang یک مرز اضافه می‌کند، پس «هر چند بار که خواستی» هم آزمودنی
    // است نه فقط یک بار. هر عضو: @[@(ثانیه), @"زبان"].
    NSMutableArray<NSArray *> *switches = [NSMutableArray array];
    // و هر بار --drop یک «سطل آشغال» سر همان ثانیه‌ی صدا. جفتِ --switchlang است و
    // برای همان دلیل: ادعای «دور ریختن واقعا پاک می‌کند» باید بی‌میکروفن دیده شود.
    NSMutableArray<NSNumber *> *drops = [NSMutableArray array];
    NSUInteger i = [args indexOfObject:@"--livewav"] + 1;
    for (; i < args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--lang"] && i + 1 < args.count) lang = args[++i];
        else if ([a isEqualToString:@"--speed"] && i + 1 < args.count) speed = args[++i].doubleValue;
        else if ([a isEqualToString:@"--ref"] && i + 1 < args.count) refPath = args[++i];
        else if ([a isEqualToString:@"--fixed"] && i + 1 < args.count) fixed = args[++i].doubleValue;
        else if ([a isEqualToString:@"--table"]) table = YES;
        else if ([a isEqualToString:@"--preview"]) preview = YES;
        else if ([a isEqualToString:@"--session"]) session = YES;
        else if ([a isEqualToString:@"--switchlang"] && i + 2 < args.count) {
            double at = args[++i].doubleValue;
            [switches addObject:@[@(at), args[++i]]];
        }
        else if ([a isEqualToString:@"--drop"] && i + 1 < args.count) {
            [drops addObject:@(args[++i].doubleValue)];
        }
        else if (![a hasPrefix:@"--"] && !file) file = a;
    }

    if (table) {
        return ZTable(@[@"07-estelahat-sade", @"02-estelahat", @"01-bi-vaghfe-normal",
                        @"03-maks", @"04-pechpech", @"05-adad", @"06-mohavere"],
                      lang, speed);
    }
    if (!file) {
        fprintf(stderr, "zemzeme --livewav <file.wav> [--lang fa-IR] [--speed 1] [--ref متن.md] [--preview]\n"
                        "                        [--switchlang <ثانیه> <fa-IR|en-US>] [--drop <ثانیه>] [--session] ...\n"
                        "zemzeme --livewav --table\n");
        return 2;
    }

    NSString *err = nil;
    NSData *pcm = ZReadWav(file, &err);
    if (!pcm) {
        fprintf(stderr, "%s\n", err.UTF8String);
        return 1;
    }
    if (fixed > 0) {
        NSString *t = ZFixedCuts(pcm, lang, fixed);
        printf("%s\n", t.UTF8String);
        if (refPath) {
            NSString *ref = [NSString stringWithContentsOfFile:refPath encoding:NSUTF8StringEncoding error:nil];
            ZScore s2 = ZScoreText(ZScript(ref ?: @""), t);
            fprintf(stderr, "برش ثابت %.0f ثانیه: مرجع %lu، خروجی %lu، گم‌شده %lu، تطبیق %.0f٪\n",
                    fixed, (unsigned long)s2.ref, (unsigned long)s2.got,
                    (unsigned long)s2.missing, s2.match);
        }
        return 0;
    }
    ZMeasureRun *r = ZRunWav(pcm, lang, speed, preview, switches, drops, session);
    if (!r) return 1;
    printf("%s\n", (r.text ?: @"").UTF8String);
    if (r.second.length) fprintf(stderr, "\n[en-US] %s\n", r.second.UTF8String);
    fprintf(stderr, "\nصدا %.1f ثانیه، از پایان صدا تا متن %.1f ثانیه، %ld برش تحمیلی\n",
            pcm.length / kZPcmBytesPerSec, r.took, (long)r.degraded);
    if (preview) {
        fprintf(stderr, "\nپیش‌نمایش: %ld بازنویسی، %lu نویسه در آخر\n",
                (long)r.previewUpdates, (unsigned long)(r.preview ?: @"").length);
    }
    if (refPath) {
        NSString *ref = [NSString stringWithContentsOfFile:refPath encoding:NSUTF8StringEncoding error:nil];
        ZScore s = ZScoreText(ZScript(ref ?: @""), r.text ?: @"");
        fprintf(stderr, "مرجع %lu واژه، خروجی %lu، گم‌شده %lu، تطبیق %.0f٪\n",
                (unsigned long)s.ref, (unsigned long)s.got, (unsigned long)s.missing, s.match);
    }
    return 0;
}

// ---------- zemzeme --resume ----------
// همان کاری که لانچ بی‌صدا می‌کند، ولی از خط فرمان و با انتظار: صف‌های نیمه‌کاره‌ی
// سشن‌های قبلی برداشته و تمام می‌شوند. دلیل وجودش همان شرط سختِ بقیه‌ی اپ است:
// ادعای «اپ که بسته شود حرف گم نمی‌شود» باید بی‌میکروفن و بی‌آدم تکرارپذیر باشد.
int ZResumeMain(NSArray<NSString *> *args) {
    double ceiling = 120;
    NSUInteger i = [args indexOfObject:@"--resume"] + 1;
    if (i < args.count && ![args[i] hasPrefix:@"--"]) ceiling = args[i].doubleValue;
    ZResumePendingQueues();
    // بی سقف صبر نمی‌کنیم، مثل هر انتظار دیگری در این اپ.
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:ceiling];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (;;) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        NSUInteger left = 0;
        for (NSURL *d in [fm contentsOfDirectoryAtURL:ZSessionsDir()
                           includingPropertiesForKeys:nil options:0 error:nil]) {
            if ([fm fileExistsAtPath:ZQueueManifestIn(d).path]) left++;
        }
        if (!left) {
            printf("صفی نماند\n");
            return 0;
        }
        if ([NSDate.date compare:end] != NSOrderedAscending) {
            fprintf(stderr, "%lu سشن هنوز تکه‌ی در راه دارد\n", (unsigned long)left);
            return 1;
        }
    }
}
