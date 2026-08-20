// رونویسی دسته‌ای فایل: همان خط لوله‌ی دیکته‌ی زنده، فقط با یک منبع صدای دیگر.
//
// در نسخه یک این فایل موتور دومِ کاملی بود: برش‌زن خودش، هم‌پوشانی خودش، دوختِ
// خودش. یعنی هر باگ باید دو بار درست می‌شد و عملا نمی‌شد. حالا برش (`ZSegFind`) و
// رونویسیِ یک تکه (`ZTranscribeSegment`) مشترک‌اند و اینجا فقط چیزی می‌ماند که
// واقعا مالِ فایل است: دیکد کردن، موازی‌سازی، زیرنویس، و صف چند فایلی.
//
// دو چیز از نسخه یک اینجا هم رفت و دلیلش همان است که سر pipe.m نوشته شده: هم‌پوشانی
// و دوخت. اندازه‌گیری روی ضبط ۰۱ نشان داد همان دو تا پنج کلمه را بی‌صدا می‌خوردند.
// تکه‌ها با یک فاصله به هم می‌چسبند و تمام.
//
// تفاوت واقعی با مسیر زنده فقط زمان‌بندی است: آنجا یک سشن در هر لحظه (کاربر منتظر
// است و نقطه‌ی رایگان نباید اذیت شود)، اینجا چند تا با هم، چون فایل نود دقیقه‌ای با
// سشن تک‌به‌تک تمام نمی‌شود.
#import "zemzeme.h"

// ---------- یک پاره ----------

@interface ZBatchPiece : NSObject
@property (nonatomic) NSInteger index;
@property (nonatomic, strong) NSData *pcm;
@property (nonatomic) double startSec;     // زمان صدای اولین بایت pcm
@property (nonatomic) double endSec;       // زمان صدای آخرین بایت pcm
@property (nonatomic, copy) NSString *text;
@end

@implementation ZBatchPiece
@end

// ---------- رونویس ----------

@interface ZBatchTranscriber : NSObject
@property (nonatomic, copy) NSString *lang;
@property (nonatomic) double speed;      // ضریب سرعت تغذیه؛ ۰ یعنی بی‌مکث
@property (nonatomic) NSInteger jobs;
@property (nonatomic) BOOL rawUp;        // آپلود خام l16 به جای FLAC (فقط عیب‌یابی)
@property (atomic, readonly) unsigned long long bytesUp;   // بایت واقعی روی سیم
@property (atomic) BOOL cancelled;       // لغو تعاملی؛ همه‌ی حلقه‌های طولانی نگاهش می‌کنند
// ثانیه‌ی صدای رونویسی‌شده تا الان (جمع محتوای تازه‌ی پاره‌های تمام‌شده). سر هر پاره
// صدا زده می‌شود، نه سر هر دسته: رابط باید هر ۲۰ ثانیه صدا یک قدم جلو برود، نه هر دسته.
@property (nonatomic, copy) void (^onPieceDone)(double secDone);
@end

@implementation ZBatchTranscriber {
    NSInteger _nextIndex;
    NSInteger _retries;
    NSLock *_stateLock;
    unsigned long long _bytesUp;
    double _secDone;
    NSInteger _deafStreak;      // پاره‌های پشت‌سرهمی که سشنشان لال برگشت
    NSInteger _degraded;        // برش‌هایی که مکثی پیدا نکردند
    NSDate *_lastCooldownLog;
}

- (instancetype)init {
    if ((self = [super init])) _stateLock = [NSLock new];
    return self;
}

// خوابِ تکه‌تکه: لغو نباید تا ته یک مکث ۳۰ ثانیه‌ای معطل بماند
- (BOOL)nap:(NSTimeInterval)sec {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:sec];
    while ([NSDate.date compare:until] == NSOrderedAscending) {
        if (self.cancelled) return NO;
        usleep(200000);
    }
    return !self.cancelled;
}

// نقطه‌ی مجانی، بعد از چند صد سشن در یک ساعت، آرام‌آرام «لال» جواب می‌دهد: /down با
// کد ۲۰۰ باز می‌شود ولی یک فریم هم نمی‌فرستد. اندازه‌گیری‌شده: همان فایل ۳ دقیقه‌ای
// که اول اجرا ۸۸٪ پوشش داشت، بعد از ~۴۰۰ سشن به ۶۰٪ افتاد، حتی با jobs=1.
// پس وقتی لالی پیاپی دیدیم عقب می‌کشیم. این‌طور اجرا کند می‌شود، نه بی‌صدا ناقص.
- (void)coolDownIfDeaf {
    [_stateLock lock];
    NSInteger streak = _deafStreak;
    BOOL shouldLog = streak >= 3 &&
        (!_lastCooldownLog || [NSDate.date timeIntervalSinceDate:_lastCooldownLog] > 20);
    if (shouldLog) _lastCooldownLog = NSDate.date;
    [_stateLock unlock];
    if (streak < 3) return;
    NSTimeInterval wait = MIN(5.0 * (streak - 2), 30.0);
    if (shouldLog) ZLog(@"batch: %ld deaf sessions in a row, backing off %.0fs", (long)streak, wait);
    [self nap:wait];
}

- (void)noteDeaf:(BOOL)deaf {
    [_stateLock lock];
    _deafStreak = deaf ? _deafStreak + 1 : 0;
    [_stateLock unlock];
}

// آیا این پاره واقعا حرف دارد؟ پاره‌ی سکوت حق دارد بی‌متن برگردد و نباید تکرار شود.
- (unsigned long long)bytesUp {
    [_stateLock lock];
    unsigned long long v = _bytesUp;
    [_stateLock unlock];
    return v;
}

- (BOOL)pieceHasVoice:(ZBatchPiece *)p { return ZSegHasVoice(p.pcm); }

// یک پاره، با تا سه تلاش و عقب‌کشیدن بین تلاش‌ها. بهترین نتیجه‌ی تلاش‌ها برمی‌گردد،
// نه آخری: تلاش دوم هم ممکن است لال باشد.
- (NSString *)runPiece:(ZBatchPiece *)p {
    NSString *best = @"";
    double sec = p.pcm.length / kZPcmBytesPerSec;
    BOOL voiced = [self pieceHasVoice:p];
    NSUInteger prevWords = NSNotFound;
    for (int attempt = 0; attempt < 3; attempt++) {
        if (self.cancelled) return best;
        if (attempt && ![self nap:4.0 * attempt]) return best;
        [self coolDownIfDeaf];
        NSString *t = [self attemptPiece:p];
        if (t.length > best.length) best = t;
        // پاره‌ی لغوشده نه لال است نه کم‌حرف؛ شمردنش در آمار لالی و تلاش دوباره دروغ بود
        if (self.cancelled) return best;
        NSUInteger words = best.length ? [best componentsSeparatedByString:@" "].count : 0;
        // گفتار عادی ~۲٫۵ کلمه در ثانیه است؛ زیر ۰٫۴ یعنی سشن لال بوده، نه کم‌حرف
        BOOL thin = words < (NSUInteger)(0.4 * sec);
        [self noteDeaf:thin && voiced && words == 0];
        if (!thin || !voiced) return best;
        // همان تعداد کلمه در تلاش دوباره یعنی صدا واقعا همین‌قدر حرف دارد (پچ‌پچ،
        // نویز، صدای دور)، نه این‌که سشن لال باشد: بازپخش فایل قطعی است، پس نتیجه‌ی
        // تکراری خودش جواب است. بی این شرط، یک پاره‌ی کم‌حرف سه بار فرستاده می‌شد و
        // عقب‌کشیدنِ الکی هم راه می‌انداخت (روی وویس ۶ دقیقه‌ای: ۳۰ ثانیه از ۸۱).
        if (words > 0 && words == prevWords) return best;
        prevWords = words;
        _retries++;
        ZLog(@"batch: piece %ld thin (%lu words in %.0fs), attempt %d",
             (long)p.index, (unsigned long)words, sec, attempt + 2);
    }
    return best;
}

// یک تلاش: یک سشن تازه، همان تابعی که مسیر زنده هم صدا می‌زند.
- (NSString *)attemptPiece:(ZBatchPiece *)p {
    if (self.cancelled) return @"";
    unsigned long long up = 0;
    NSString *text = ZTranscribeSegment(p.pcm, self.lang, self.rawUp, &up, NULL);
    [_stateLock lock];
    _bytesUp += up;
    [_stateLock unlock];
    if (!text.length) ZLog(@"batch: پاره‌ی %ld سشنِ لال داد", (long)p.index);
    return text;
}

// یک دسته پاره را موازی اجرا کن (سقف jobs) و متن هرکدام را سر جایش بنشان.
- (void)runBatch:(NSArray<ZBatchPiece *> *)pieces {
    dispatch_group_t g = dispatch_group_create();
    dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    for (ZBatchPiece *p in pieces) {
        dispatch_group_async(g, q, ^{
            p.text = [self runPiece:p];
            // پی‌سی‌ام دیگر لازم نیست و باید همین‌جا آزاد شود، وگرنه هر پاره‌ی
            // ۲۰ ثانیه‌ای (~۶۴۰ کیلوبایت) تا آخر اجرا می‌ماند و فایل ۹۰ دقیقه‌ای
            // چند صد مگابایت می‌شد. زمان‌های SRT از عددهای پاره می‌آیند، نه از صدا.
            p.pcm = nil;
            [self->_stateLock lock];
            self->_secDone += MAX(0.0, p.endSec - p.startSec);
            double done = self->_secDone;
            [self->_stateLock unlock];
            if (self.onPieceDone) self.onPieceDone(done);
        });
    }
    dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
}

// برش‌زن: از دیکدر می‌خواند، روی سکوت می‌برد، و دسته‌دسته (به اندازه jobs) اجرا
// می‌کند. حافظه کراندار است: در هر لحظه فقط jobs پاره‌ی ~۲۰ ثانیه‌ای در دست است،
// پس فایل ۹۰ دقیقه‌ای هم به همان چند مگابایت فایل ۵ دقیقه‌ای کار می‌کند.
// لغو وسط کار: هرچه تا اینجا رونویسی شده برمی‌گردد (نیمه، ولی همان است که واقعا
// شنیده شده). فراخوان خودش می‌داند لغو کرده، پس نیازی به خطای جداگانه نیست.
- (NSArray<ZBatchPiece *> *)transcribe:(ZFileDecoder *)dec error:(NSError **)err {
    const NSUInteger hi = (NSUInteger)(kZSegMaxSec * kZPcmBytesPerSec);

    NSMutableArray<ZBatchPiece *> *all = [NSMutableArray array];
    NSMutableArray<ZBatchPiece *> *pending = [NSMutableArray array];
    NSMutableData *buf = [NSMutableData data];
    double bufStartSec = 0;        // زمان صدای buf[0]
    BOOL eof = NO;

    while ((!eof || buf.length) && !self.cancelled) {
        while (!eof && buf.length < hi && !self.cancelled) {
            NSError *de = nil;
            NSData *chunk = [dec nextChunk:&de];
            if (!chunk) {
                if (de) {
                    if (err) *err = de;
                    return nil;
                }
                eof = YES;
                break;
            }
            [buf appendData:chunk];
        }

        ZSegCut c = ZSegFind(buf.bytes, buf.length, eof);
        if (!c.cut) break;         // فقط وقتی buf خالی است ممکن است
        if (c.degraded) {
            _degraded++;
            ZLog(@"batch: برش تحمیلی سر %.0f ثانیه، مکثی نبود و rms=%.4f", bufStartSec, c.rms);
        }

        ZBatchPiece *p = [ZBatchPiece new];
        p.index = _nextIndex++;
        p.pcm = [buf subdataWithRange:NSMakeRange(0, c.cut)];
        p.startSec = bufStartSec;
        p.endSec = bufStartSec + c.cut / kZPcmBytesPerSec;
        [pending addObject:p];
        [all addObject:p];

        bufStartSec = p.endSec;
        [buf replaceBytesInRange:NSMakeRange(0, c.cut) withBytes:NULL length:0];

        if (pending.count >= (NSUInteger)self.jobs || (eof && !buf.length)) {
            [self runBatch:pending];
            [pending removeAllObjects];
        }
        if (eof && !buf.length) break;
    }
    if (pending.count && !self.cancelled) [self runBatch:pending];
    if (_retries) ZLog(@"batch: %ld پاره تلاش دوباره خواست", (long)_retries);
    if (_degraded) ZLog(@"batch: %ld برش تحمیلی از %lu", (long)_degraded, (unsigned long)all.count);
    return all;
}

- (NSInteger)degradedCuts { return _degraded; }

@end

// ---------- سرهم کردن متن ----------

// پاره‌ها را به ترتیب به هم بچسبان، با یک فاصله. **این کل الگوریتم است.**
// نسخه یک اینجا هم‌پوشانی ۲٫۵ ثانیه‌ای داشت و درزها را با ZStitchOverlapMax جوش
// می‌داد. اندازه‌گیری روی ضبط ۰۱: همان جوش پنج کلمه را بی‌صدا و تکرارپذیر خورد، در
// حالی که همان صدا در یک پنجره‌ی جدا سالم رونویسی می‌شد.
static NSString *ZBatchJoin(NSArray<ZBatchPiece *> *pieces) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (ZBatchPiece *p in pieces) {
        NSString *t = [p.text stringByTrimmingCharactersInSet:
                       NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (t.length) [out addObject:t];
    }
    return [out componentsJoinedByString:@" "];
}

// زیرنویس: نقطه هیچ زمانی برنمی‌گرداند، پس زمان‌ها فقط از بایت‌های داده‌شده ساخته
// می‌شوند (۳۲۰۰۰ بایت = ۱ ثانیه). داخل هر پاره هم به تناسب طول متن تقسیم می‌شود.
// یعنی تقریبی است و در --help و README همین‌طور هم گفته شده.
static NSString *ZBatchSRT(NSArray<ZBatchPiece *> *pieces) {
    NSMutableString *out = [NSMutableString string];
    NSInteger n = 0;
    for (ZBatchPiece *p in pieces) {
        NSString *t = [p.text stringByTrimmingCharactersInSet:
                       NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!t.length) continue;
        double from = p.startSec;
        double to = p.endSec;
        if (to <= from) to = from + 0.5;
        NSArray *w = [t componentsSeparatedByString:@" "];
        const NSUInteger per = 12;
        NSUInteger lines = (w.count + per - 1) / per;
        for (NSUInteger i = 0; i < lines; i++) {
            NSRange r = NSMakeRange(i * per, MIN(per, w.count - i * per));
            double a = from + (to - from) * ((double)i / lines);
            double b = from + (to - from) * ((double)(i + 1) / lines);
            [out appendFormat:@"%ld\n%02d:%02d:%02d,%03d --> %02d:%02d:%02d,%03d\n%@\n\n",
             (long)++n,
             (int)a / 3600, ((int)a / 60) % 60, (int)a % 60, (int)((a - (int)a) * 1000),
             (int)b / 3600, ((int)b / 60) % 60, (int)b % 60, (int)((b - (int)b) * 1000),
             [[w subarrayWithRange:r] componentsJoinedByString:@" "]];
        }
    }
    return out;
}

// ---------- کار دسته‌ای: همان موتور، از بیرون قابل استفاده ----------
// چرا این لایه: منطق بالا اندازه‌گیری‌شده و درست است، ولی تنها فراخوانش خط فرمان بود
// و همه‌چیز (پیشرفت، خطا، ترتیب) در fprintf گره خورده بود. اینجا فقط قرارداد بیرونی
// اضافه می‌شود: صف فایل، کال‌بک، لغو. هیچ عددی از الگوریتم عوض نشده.

@implementation ZBatchJob {
    NSArray<NSURL *> *_files;
    NSString *_lang;
    NSLock *_lock;              // فقط سر لغو: بین نخ کار و نخ فراخوان
    ZBatchTranscriber *_tr;     // فایلِ در جریان
    ZFileDecoder *_dec;
    BOOL _cancelled;
    BOOL _onMain;
    unsigned long long _bytesUp;
}

- (instancetype)initWithFiles:(NSArray<NSURL *> *)files lang:(NSString *)lang {
    if ((self = [super init])) {
        _files = [files copy];
        _lang = [lang copy] ?: @"fa-IR";
        _lock = [NSLock new];
        _jobs = 2;              // مشترک با دیکته‌ی زنده؛ دلیل محافظه‌کاری سر ZBatchMain نوشته شده
        _writeTXT = YES;
        _onMain = YES;
    }
    return self;
}

- (unsigned long long)bytesUp {
    [_lock lock];
    unsigned long long v = _bytesUp;
    [_lock unlock];
    return v;
}

- (BOOL)isCancelled {
    [_lock lock];
    BOOL c = _cancelled;
    [_lock unlock];
    return c;
}

- (void)cancel {
    [_lock lock];
    _cancelled = YES;
    ZBatchTranscriber *tr = _tr;
    ZFileDecoder *dec = _dec;
    [_lock unlock];
    tr.cancelled = YES;
    [dec cancel];    // خواندن همان‌جا می‌ایستد، پس حلقه‌ی برش هم زود تمام می‌شود
    ZLog(@"batch: cancelled by the caller");
}

// کال‌بک‌ها یا روی نخ اصلی‌اند (رابط) یا روی همین نخ (خط فرمان). یک جا تصمیم گرفته
// می‌شود، پس هیچ کال‌بکی دو رفتار ندارد.
- (void)hop:(void (^)(void))block {
    if (!_onMain) {
        block();
        return;
    }
    if (NSThread.isMainThread) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

- (NSURL *)outputURLFor:(NSURL *)file ext:(NSString *)ext {
    NSString *dir = self.outDir.length ? self.outDir.stringByExpandingTildeInPath
                                       : file.URLByDeletingLastPathComponent.path;
    NSString *base = file.lastPathComponent.stringByDeletingPathExtension;
    return [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:
                                   [base stringByAppendingPathExtension:ext]]];
}

- (void)start {
    _onMain = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [self loop]; });
}

- (void)runOnThisThread {
    _onMain = NO;
    [self loop];
}

- (void)loop {
    for (NSUInteger i = 0; i < _files.count; i++) {
        if ([self isCancelled]) break;
        [self runFile:_files[i] lang:i < self.langs.count ? self.langs[i] : _lang];
    }
    [_lock lock];
    _tr = nil;
    _dec = nil;
    [_lock unlock];
    [self hop:^{ if (self.onAllDone) self.onAllDone(); }];
}

- (void)runFile:(NSURL *)url lang:(NSString *)lang {
    NSError *err = nil;
    ZFileDecoder *dec = [[ZFileDecoder alloc] initWithURL:url error:&err];
    if (!dec) {
        [self hop:^{ if (self.onFileDone) self.onFileDone(url, nil, err); }];
        return;
    }
    double total = dec.duration;
    NSDate *t0 = NSDate.date;
    ZBatchTranscriber *tr = [ZBatchTranscriber new];
    tr.lang = lang;
    tr.jobs = MAX(1, MIN(8, self.jobs));
    tr.speed = self.speed;
    tr.rawUp = self.rawUpload;
    __weak typeof(self) ws = self;
    tr.onPieceDone = ^(double secDone) {
        __strong typeof(ws) s = ws;
        if (!s) return;
        [s hop:^{
            if (s.onFileProgress) s.onFileProgress(url, MIN(secDone, total), total);
        }];
    };
    [_lock lock];
    if (_cancelled) {
        [_lock unlock];
        return;
    }
    _tr = tr;
    _dec = dec;
    [_lock unlock];

    ZLog(@"batch: start %@ dur=%.0fs lang=%@ jobs=%ld speed=%.0f",
         url.lastPathComponent, total, lang, (long)tr.jobs, self.speed);
    // صفرِ اول: ردیف همان لحظه «در حال کار» می‌شود و طولش را می‌فهمد، بی‌آنکه منتظر
    // اولین پاره (~۲۰ ثانیه صدا) بماند.
    [self hop:^{ if (self.onFileProgress) self.onFileProgress(url, 0, total); }];

    NSArray<ZBatchPiece *> *pieces = [tr transcribe:dec error:&err];
    [_lock lock];
    _bytesUp += tr.bytesUp;
    _tr = nil;
    _dec = nil;
    [_lock unlock];

    if (!pieces) {
        [self hop:^{ if (self.onFileDone) self.onFileDone(url, nil, err); }];
        return;
    }
    NSString *text = ZBatchJoin(pieces);
    double el = [NSDate.date timeIntervalSinceDate:t0];
    ZLog(@"batch: done %@ pieces=%ld chars=%lu wall=%.0fs ratio=%.1fx up=%.1fMB (%@)",
         url.lastPathComponent, (long)pieces.count, (unsigned long)text.length, el,
         el > 0 ? total / el : 0, tr.bytesUp / 1048576.0, self.rawUpload ? @"raw l16" : @"flac");

    // لغو یعنی متن نیمه است. نوشتنش روی دیسک یعنی یک txt ناقص که بعدا کسی
    // نمی‌فهمد ناقص است؛ پس متن برمی‌گردد ولی فایلی ساخته نمی‌شود.
    if ([self isCancelled]) {
        [self hop:^{ if (self.onFileDone) self.onFileDone(url, text, nil); }];
        return;
    }
    if (!text.length) {
        NSError *e = [NSError errorWithDomain:@"zemzeme.batch" code:1 userInfo:@{
            NSLocalizedDescriptionKey: @"هیچ متنی برنگشت"}];
        [self hop:^{ if (self.onFileDone) self.onFileDone(url, nil, e); }];
        return;
    }
    NSError *werr = [self write:text pieces:pieces for:url];
    [self hop:^{ if (self.onFileDone) self.onFileDone(url, text, werr); }];
}

// txt (و اگر خواسته شده srt) کنار خود فایل یا در outDir. خطای نوشتن به همان ردیف
// برمی‌گردد، چون فایل بعدی ممکن است جای نوشتنی داشته باشد.
- (NSError *)write:(NSString *)text pieces:(NSArray<ZBatchPiece *> *)pieces for:(NSURL *)url {
    if (!self.writeTXT) return nil;
    NSURL *txt = [self outputURLFor:url ext:@"txt"];
    [NSFileManager.defaultManager createDirectoryAtPath:txt.URLByDeletingLastPathComponent.path
                           withIntermediateDirectories:YES attributes:nil error:nil];
    NSError *err = nil;
    if (![text writeToURL:txt atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        return err ?: [NSError errorWithDomain:@"zemzeme.batch" code:2 userInfo:@{
            NSLocalizedDescriptionKey: @"نوشتن فایل متن نشد"}];
    }
    if (self.writeSRT) {
        [ZBatchSRT(pieces) writeToURL:[self outputURLFor:url ext:@"srt"]
                           atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return nil;
}

@end

// ---------- خط فرمان ----------

static void ZBatchUsage(void) {
    fprintf(stderr,
        "zemzeme --transcribe <files...> [--lang fa-IR] [--jobs N] [--out DIR] [--srt] [--raw] [--speed X]\n"
        "\n"
        "  --lang   fa-IR (پیش‌فرض) یا en-US\n"
        "  --jobs   چند سشن هم‌زمان؛ پیش‌فرض ۲\n"
        "  --out    پوشه خروجی؛ پیش‌فرض کنار خود فایل\n"
        "  --raw    آپلود خام l16 به جای FLAC؛ فقط برای عیب‌یابی (حجم دو برابر)\n"
        "  --srt    زیرنویس هم بساز. توجه: نقطه‌ی گوگل زمان برنمی‌گرداند، پس زمان‌های\n"
        "           SRT تقریبی‌اند (از روی بایت‌های صدا حساب می‌شوند)\n"
        "  --speed  ضریب سرعت تغذیه؛ ۰ یعنی بی‌مکث (پیش‌فرض) و اندازه‌گیری‌شده بی‌خطر\n"
        "\n"
        "قالب‌های ogg/opus/mkv/webm پشتیبانی نمی‌شوند: macOS دیمکسری برایشان ندارد.\n");
}

int ZBatchMain(NSArray<NSString *> *args) {
    NSString *lang = @"fa-IR";
    NSString *outDir = nil;
    NSInteger jobs = 2;      // محافظه‌کارانه: کلید مشترک است و دیکته‌ی زنده هم ممکن
                             // است همان لحظه در جریان باشد. اندازه‌گیری تا ۸ را سالم
                             // دید، ولی پیش‌فرض جا برای مسیر زنده باز می‌گذارد.
    BOOL srt = NO;
    BOOL rawUp = NO;
    double speed = 0;
    NSMutableArray<NSString *> *files = [NSMutableArray array];

    NSUInteger i = [args indexOfObject:@"--transcribe"] + 1;
    for (; i < args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--lang"] && i + 1 < args.count) lang = args[++i];
        else if ([a isEqualToString:@"--out"] && i + 1 < args.count) outDir = args[++i];
        else if ([a isEqualToString:@"--jobs"] && i + 1 < args.count) jobs = args[++i].integerValue;
        else if ([a isEqualToString:@"--speed"] && i + 1 < args.count) speed = args[++i].doubleValue;
        else if ([a isEqualToString:@"--srt"]) srt = YES;
        else if ([a isEqualToString:@"--raw"]) rawUp = YES;
        else if ([a hasPrefix:@"--"]) {
            fprintf(stderr, "گزینه ناشناس: %s\n\n", a.UTF8String);
            ZBatchUsage();
            return 2;
        } else [files addObject:a];
    }
    if (!files.count) {
        ZBatchUsage();
        return 2;
    }
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *path in files) {
        [urls addObject:[NSURL fileURLWithPath:path.stringByExpandingTildeInPath]];
    }

    // همان موتور رابط، فقط با کال‌بک‌های چاپی و روی همین نخ: نه NSApplication در کار
    // است نه ران‌لوپی که بچرخد، پس کال‌بکِ نخ اصلی هیچ‌وقت اجرا نمی‌شد.
    ZBatchJob *job = [[ZBatchJob alloc] initWithFiles:urls lang:lang];
    job.jobs = jobs;
    job.speed = speed;
    job.rawUpload = rawUp;
    job.writeSRT = srt;
    job.outDir = outDir;

    __block int failed = 0;
    __block NSDate *t0 = NSDate.date;
    __block NSString *cur = nil;
    __block unsigned long long upSeen = 0;    // bytesUp کارِ کل است؛ تفاضلش سهم همین فایل
    __weak ZBatchJob *wj = job;               // کار خودش بلاک را نگه می‌دارد؛ چرخه نشود
    job.onFileProgress = ^(NSURL *f, double doneSec, double totalSec) {
        if (![cur isEqualToString:f.lastPathComponent]) {
            cur = f.lastPathComponent;
            t0 = NSDate.date;
            fprintf(stderr, "%s: %.1f دقیقه، lang=%s jobs=%ld\n",
                    cur.UTF8String, totalSec / 60, lang.UTF8String, (long)jobs);
        }
        fprintf(stderr, "\r%s: %.1f از %.1f دقیقه، %.0f ثانیه گذشته   ",
                cur.UTF8String, doneSec / 60, totalSec / 60,
                [NSDate.date timeIntervalSinceDate:t0]);
        fflush(stderr);
    };
    job.onFileDone = ^(NSURL *f, NSString *text, NSError *err) {
        fprintf(stderr, "\n");
        if (err || !text.length) {
            fprintf(stderr, "%s: %s\n", f.lastPathComponent.UTF8String,
                    err ? err.localizedDescription.UTF8String : "هیچ متنی برنگشت");
            failed++;
            return;
        }
        printf("%s\n", [wj outputURLFor:f ext:@"txt"].path.UTF8String);
        if (srt) printf("%s\n", [wj outputURLFor:f ext:@"srt"].path.UTF8String);
        unsigned long long up = wj.bytesUp - upSeen;
        upSeen = wj.bytesUp;
        fprintf(stderr, "%s: تمام. %.0f ثانیه، %.0f مگابایت آپلود %s\n",
                f.lastPathComponent.UTF8String, [NSDate.date timeIntervalSinceDate:t0],
                up / 1048576.0, rawUp ? "(خام)" : "(flac)");
    };
    [job runOnThisThread];

    if (failed) fprintf(stderr, "%d فایل ناتمام ماند\n", failed);
    return failed ? 1 : 0;
}
