// رونویسی دسته‌ای فایل با همان نقطه‌ی مجانی گوگل که مسیر زنده استفاده می‌کند.
//
// چرا این شکل و نه شکل مسیر زنده: بازپخش فایل قطعی است، بایت هر نمونه معلوم است.
// پس نه واچ‌داگ میکروفن لازم است، نه واچ‌داگ گیر کردن، نه دور ریختن بک‌لاگ، نه نجات
// بازپخشی. در عوض یک برش‌زن قطعی داریم: فایل روی سکوت به پاره‌های ~۲۰ ثانیه‌ای با
// ۲٫۵ ثانیه هم‌پوشانی بریده می‌شود، هر پاره یک سشن تازه‌ی خودش را می‌گیرد، و درزها با
// ادغام هم‌پوشانی (ZStitchOverlap، نسخه‌ی بامدارای ZMergeInterim) جوش می‌خورند.
//
// چرا پاره‌ی ۲۰ ثانیه‌ای (اندازه‌گیری tools/probe_markers.py روی همین نقطه):
// یک سشن ~۳۰ ثانیه صدای پیوسته را می‌شنود و بعد ~۳۰ ثانیه کر می‌شود و همین‌طور
// نوبتی ادامه می‌دهد؛ روی ۲۱۷ ثانیه صدای پیوسته فقط ۲۳ تا از ۶۰ نشانه برگشت. این
// سقف روی «ثانیه‌ی صدا» است نه ساعت دیوار: همان فایل با سرعت ۱x و یک‌جا (burst)
// دقیقا همان نشانه‌ها را می‌اندازد. پس تغذیه‌ی سریع بی‌خطر است و چرخش اجباری.
#import "zemzeme.h"

#define kZPcmBytesPerSec 32000.0

// هدف برش و پنجره‌ی گشتن سکوت. هدف ۲۰ ثانیه، همان عددی که موتور زنده (kZRotateSec)
// از روی همین سقف سرور انتخاب کرده؛ پنجره باز است که تقریبا همیشه سکوتی پیدا شود.
#define kZBatchSegSec 20.0
#define kZBatchSegMinSec 10.0
#define kZBatchSegMaxSec 26.0
#define kZBatchOverlapSec 2.5

// سکوت: میانگین توان کمتر از این (مقیاس ۰ تا ۱، مثل audio.m قبل از ضریب ۵) دست‌کم
// به این طول. آستانه دست‌ودل‌بازتر از حد شنوایی است که نویز زمینه‌ی ضبط واقعی هم
// «سکوت» به حساب بیاید.
#define kZBatchSilenceRMS 0.02
#define kZBatchSilenceMs 180

// بعد از پایان آپلود، این‌قدر ثانیه هیچ فریمی نیاید یعنی سرور کارش تمام است.
// قبلا منتظر بسته شدن /down می‌ماندیم و گاهی سرور آن را باز نگه می‌داشت: دو پاره از
// سی پاره ۴۵ ثانیه معطل شدند و یک‌چهارم کل زمان اجرا را خوردند. معیار «سکوت فریم»
// همان چیزی را می‌سنجد که واقعا مهم است و پاره‌های سالم را هم زودتر آزاد می‌کند.
#define kZBatchQuietSec 8.0

// ---------- یک پاره ----------

@interface ZBatchPiece : NSObject
@property (nonatomic) NSInteger index;
@property (nonatomic, strong) NSData *pcm;
@property (nonatomic) double startSec;     // زمان صدای اولین بایت pcm (شامل هم‌پوشانی)
@property (nonatomic) double newFromSec;   // از اینجا به بعد محتوای تازه است
@property (nonatomic) double endSec;       // زمان صدای آخرین بایت pcm
@property (nonatomic, copy) NSString *text;
@end

@implementation ZBatchPiece
@end

// ---------- کمکی‌ها ----------

// توان یک فریم ۲۰ میلی‌ثانیه‌ای، صفر تا یک. نمونه‌برداری هر چهارم، مثل audio.m که هر
// هشتم را می‌گیرد: برای تشخیص سکوت به‌قدر کافی دقیق و چند برابر ارزان‌تر.
static float ZFrameRMS(const int16_t *p, NSUInteger n) {
    float acc = 0;
    NSUInteger cnt = 0;
    for (NSUInteger i = 0; i < n; i += 4) {
        float v = p[i] / 32768.0f;
        acc += v * v;
        cnt++;
    }
    return sqrtf(acc / MAX(1u, (unsigned)cnt));
}

// نزدیک‌ترین سکوت به target را پیدا کن و وسطش را برگردان (بایت، زوج). صفر یعنی
// سکوتی در پنجره نبود و فراخوان باید برش سخت بزند.
static NSUInteger ZFindSilenceCut(NSData *buf, NSUInteger target, NSUInteger lo, NSUInteger hi) {
    const NSUInteger frame = (NSUInteger)(0.020 * kZPcmBytesPerSec);    // ۲۰ms = ۶۴۰ بایت
    const NSUInteger need = (NSUInteger)(kZBatchSilenceMs / 20);        // چند فریم پیوسته
    hi = MIN(hi, buf.length);
    if (lo + frame * need >= hi) return 0;
    const int16_t *s = (const int16_t *)buf.bytes;

    // از هدف به هر دو طرف قدم‌به‌قدم بگرد؛ اولین برخورد نزدیک‌ترین است
    NSUInteger maxStep = MAX(hi - target, target - lo) / frame + 1;
    for (NSUInteger step = 0; step <= maxStep; step++) {
        for (int dir = 0; dir < 2; dir++) {
            NSInteger start = (NSInteger)target + (dir ? -1 : 1) * (NSInteger)(step * frame);
            if (start < (NSInteger)lo || start + (NSInteger)(frame * need) > (NSInteger)hi) continue;
            BOOL quiet = YES;
            for (NSUInteger k = 0; k < need && quiet; k++) {
                NSUInteger off = (NSUInteger)start + k * frame;
                if (ZFrameRMS(s + off / 2, frame / 2) > kZBatchSilenceRMS) quiet = NO;
            }
            if (!quiet) continue;
            // وسط سکوت را ببر، نه لبه‌اش: هیچ کلمه‌ای دو نیم نمی‌شود
            NSUInteger mid = (NSUInteger)start + frame * need / 2;
            return mid - (mid % 2);
        }
    }
    return 0;
}

// دم متن (چند کلمه‌ی آخر) را جدا می‌کند؛ ادغام درز فقط با همین دم انجام می‌شود.
// اگر با کل متن ادغام می‌کردیم، یک عبارت تکراری از دقیقه‌های قبل می‌توانست الکی
// «هم‌پوشانی» به حساب بیاید و پاره‌ی تازه را بخورد.
static void ZSplitTail(NSString *all, NSUInteger words, NSString **head, NSString **tail) {
    NSArray *w = [all componentsSeparatedByString:@" "];
    if (w.count <= words) {
        *head = @"";
        *tail = all;
        return;
    }
    NSUInteger cut = w.count - words;
    *head = [[w subarrayWithRange:NSMakeRange(0, cut)] componentsJoinedByString:@" "];
    *tail = [[w subarrayWithRange:NSMakeRange(cut, words)] componentsJoinedByString:@" "];
}

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

- (BOOL)pieceHasVoice:(ZBatchPiece *)p {
    if (p.pcm.length < 2) return NO;
    return ZFrameRMS(p.pcm.bytes, MIN(p.pcm.length / 2, (NSUInteger)320000)) > kZBatchSilenceRMS;
}

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

// یک تلاش: یک سشن تازه. متن معلق آخر (interim که هیچ‌وقت قطعی نشد) هم با
// ZMergeInterim به دم متن می‌چسبد، وگرنه آخر هر پاره چند کلمه می‌افتاد.
- (NSString *)attemptPiece:(ZBatchPiece *)p {
    if (self.cancelled) return @"";
    ZGoogleStream *s = [[ZGoogleStream alloc] initWithLang:self.lang];
    // FLAC پیش‌فرض است، مثل مسیر زنده: روی وویس ۶ دقیقه‌ای واقعی حجم آپلود از ۱۳ به
    // ۷ مگابایت رسید و متن ۹۹٫۴٪ همان بود (۷۷۹ کلمه در برابر ۷۸۱، یعنی در حد نوسان
    // خود تشخیص). ته‌مانده‌ی ~۲۵۰ میلی‌ثانیه‌ای انکودر سر پایان آپلود را هم هم‌پوشانی
    // ۲٫۵ ثانیه‌ای پاره‌ی بعدی می‌پوشاند. --raw فقط برای عیب‌یابی است.
    s.rawUpload = self.rawUp;
    NSMutableArray<NSString *> *finals = [NSMutableArray array];
    __block NSString *interim = @"";
    __block NSString *bestInterim = @"";
    __block NSDate *lastEvent = NSDate.date;
    NSLock *lock = [NSLock new];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    s.onEvent = ^(ZSpeechEvent *ev) {
        [lock lock];
        lastEvent = NSDate.date;
        for (NSString *f in ev.finals) {
            if (f.length) [finals addObject:f];
            interim = @"";
            bestInterim = @"";
        }
        if (ev.hasResults && ev.interim.length) {
            interim = ev.interim;
            if (interim.length > bestInterim.length) bestInterim = interim;
        }
        [lock unlock];
    };
    __block NSString *closeReason = nil;
    s.onClose = ^(NSString *reason) {
        closeReason = reason;
        dispatch_semaphore_signal(sem);
    };
    [s connect];

    double sec = p.pcm.length / kZPcmBytesPerSec;
    if (self.speed > 0) {
        // تغذیه با ضریب سرعت: تکه‌های ۱۰۰ میلی‌ثانیه‌ای، همان دانه‌بندی مسیر زنده
        NSUInteger step = 3200;
        NSDate *t0 = NSDate.date;
        for (NSUInteger off = 0; off < p.pcm.length && !self.cancelled; off += step) {
            NSUInteger n = MIN(step, p.pcm.length - off);
            [s feed:[p.pcm subdataWithRange:NSMakeRange(off, n)]];
            double due = (off + n) / (kZPcmBytesPerSec * self.speed);
            double behind = due - [NSDate.date timeIntervalSinceDate:t0];
            if (behind > 0) usleep((useconds_t)(behind * 1e6));
        }
    } else {
        [s feed:p.pcm];    // اندازه‌گیری شده: یک‌جا دادن هم همان متن را می‌دهد
    }
    [s finishUpload];

    // زهکشی: تا بسته شدن /down، یا تا وقتی سرور kZBatchQuietSec ثانیه هیچ فریمی
    // نفرستد. سقف سخت هم داریم که یک سشن نامتعارف کل اجرا را گرو نگیرد.
    NSDate *hard = [NSDate dateWithTimeIntervalSinceNow:25.0 + sec];
    NSDate *uploadEnd = NSDate.date;
    // ساعت سکوت از پایان آپلود شروع می‌شود، نه از ساخت استریم. با --speed ۱ آپلود
    // خودش ۲۰ ثانیه طول می‌کشد و اگر سرور در آن فاصله فریمی نداده باشد، همان لحظه‌ی
    // finishUpload «ته‌نشین‌شده» به نظر می‌رسید و سشن قبل از رسیدن نتیجه لغو می‌شد.
    [lock lock];
    if ([lastEvent compare:uploadEnd] == NSOrderedAscending) lastEvent = uploadEnd;
    [lock unlock];
    while (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW,
                                                      (int64_t)(0.4 * NSEC_PER_SEC)))) {
        [lock lock];
        NSTimeInterval quiet = [NSDate.date timeIntervalSinceDate:lastEvent];
        [lock unlock];
        BOOL settled = quiet > kZBatchQuietSec &&
                       [NSDate.date timeIntervalSinceDate:uploadEnd] > 2.0;
        if (settled || self.cancelled || [NSDate.date compare:hard] != NSOrderedAscending) {
            if (!settled && !self.cancelled) {
                ZLog(@"batch: piece %ld hit the hard deadline, cancelling pair=%@",
                     (long)p.index, s.pair);
            }
            [s cancel];
            dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
            break;
        }
    }

    [lock lock];
    NSString *text = [finals componentsJoinedByString:@" "];
    // دو snapshot از یک استریم: همان پرسشِ راچت، نه چسباندنِ دو تکه‌ی جدا
    NSString *hanging = ZInterimRatchet(bestInterim, interim);
    [lock unlock];
    if (hanging.length) text = ZMergeInterim(text, hanging);
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    [_stateLock lock];
    _bytesUp += s.bytesFed;
    [_stateLock unlock];
    if (!text.length) ZLog(@"batch: piece %ld silent session (%@)", (long)p.index, closeReason ?: @"?");
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
            // پیشرفت از «محتوای تازه»ی پاره حساب می‌شود نه از طولش، پس هم‌پوشانی دو
            // بار شمرده نمی‌شود و جمعِ همه دقیقا طول فایل است.
            [self->_stateLock lock];
            self->_secDone += MAX(0.0, p.endSec - p.newFromSec);
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
    const NSUInteger overlapBytes = (NSUInteger)(kZBatchOverlapSec * kZPcmBytesPerSec);
    const NSUInteger target = (NSUInteger)(kZBatchSegSec * kZPcmBytesPerSec);
    const NSUInteger lo = (NSUInteger)(kZBatchSegMinSec * kZPcmBytesPerSec);
    const NSUInteger hi = (NSUInteger)(kZBatchSegMaxSec * kZPcmBytesPerSec);

    NSMutableArray<ZBatchPiece *> *all = [NSMutableArray array];
    NSMutableArray<ZBatchPiece *> *pending = [NSMutableArray array];
    NSMutableData *buf = [NSMutableData data];
    double bufStartSec = 0;        // زمان صدای buf[0]
    double newFromSec = 0;         // اولین ثانیه‌ی محتوای تازه در buf
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

        NSUInteger cut = buf.length;
        if (buf.length > hi) {
            cut = ZFindSilenceCut(buf, target, lo, hi);
            if (!cut) cut = target;    // سکوتی نبود: برش سخت، هم‌پوشانی درز را می‌گیرد
        }

        ZBatchPiece *p = [ZBatchPiece new];
        p.index = _nextIndex++;
        p.pcm = [buf subdataWithRange:NSMakeRange(0, cut)];
        p.startSec = bufStartSec;
        p.newFromSec = newFromSec;
        p.endSec = bufStartSec + cut / kZPcmBytesPerSec;
        [pending addObject:p];
        [all addObject:p];

        // دم را برای هم‌پوشانی نگه دار: کلمه‌ی سر درز در هر دو پاره هست، پس یکی از
        // دو سشن قطعا کاملش را می‌شنود و ادغام تکراری‌اش را می‌اندازد. «آخرین پاره»
        // باید قبل از دست زدن به buf سنجیده شود؛ وگرنه طول کوتاه‌شده‌ی buf با cut
        // مقایسه می‌شد و هر دور دم فایل را دور می‌ریخت.
        BOOL last = cut >= buf.length;
        NSUInteger keep = last ? 0 : MIN(overlapBytes, cut);
        newFromSec = bufStartSec + cut / kZPcmBytesPerSec;
        bufStartSec += (cut - keep) / kZPcmBytesPerSec;
        [buf replaceBytesInRange:NSMakeRange(0, cut - keep) withBytes:NULL length:0];

        if (pending.count >= (NSUInteger)self.jobs || (eof && !buf.length)) {
            [self runBatch:pending];
            [pending removeAllObjects];
        }
        if (eof && !buf.length) break;
    }
    if (pending.count && !self.cancelled) [self runBatch:pending];
    if (_retries) ZLog(@"batch: %ld piece(s) needed a retry", (long)_retries);
    return all;
}

@end

// ---------- سرهم کردن متن ----------

// پاره‌ها را به ترتیب جوش بده. هم‌پوشانی ۲٫۵ ثانیه‌ای یعنی چند کلمه‌ی سر هر پاره
// تکراری‌اند؛ ZMergeInterim روی دم متن (نه کلش) همان‌ها را می‌اندازد.
static NSString *ZBatchJoin(NSArray<ZBatchPiece *> *pieces) {
    NSMutableString *out = [NSMutableString string];
    for (ZBatchPiece *p in pieces) {
        NSString *t = [p.text stringByTrimmingCharactersInSet:
                       NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!t.length) continue;
        if (!out.length) {
            [out appendString:t];
            continue;
        }
        NSString *head = nil, *tail = nil;
        ZSplitTail(out, 25, &head, &tail);
        NSString *merged = ZStitchOverlapMax(tail, t, ZStitchWords(kZBatchOverlapSec));
        [out setString:head.length ? [NSString stringWithFormat:@"%@ %@", head, merged] : merged];
    }
    return out;
}

// پاس ویرایش فارسی روی متن نهایی، تکه‌تکه (~۴۰ کلمه) که هم‌اندازه‌ی تکه‌های مسیر
// زنده باشد. ترتیب مهم است: اول جوش خام، بعد ویرایش. برعکسش، نیم‌فاصله و نقطه‌گذاری
// دو پاره‌ی هم‌پوشان را ناهم‌شکل می‌کرد و ادغام درز را کور می‌کرد.
// عمومی است چون دکمه‌ی «پاس نهایی» پنل رونویسی هم دقیقا همین را روی متن یکجا می‌خواهد،
// و دو پیاده‌سازی از یک قاعده یعنی دو رفتار واگرا.
NSString *ZBatchPolishText(NSString *raw, NSString *lang) {
    if (!raw.length || [lang hasPrefix:@"en"]) return raw;
    NSArray *w = [raw componentsSeparatedByString:@" "];
    NSMutableArray *out = [NSMutableArray array];
    const NSUInteger per = 40;
    NSInteger slow = 0;
    BOOL gaveUp = NO;
    for (NSUInteger i = 0; i < w.count; i += per) {
        NSRange r = NSMakeRange(i, MIN(per, w.count - i));
        NSString *chunk = [[w subarrayWithRange:r] componentsJoinedByString:@" "];
        if (gaveUp) {
            [out addObject:chunk];
            continue;
        }
        NSDate *t0 = NSDate.date;
        [out addObject:[ZPolish.shared polishSync:chunk lang:lang]];
        // فایل ۹۰ دقیقه‌ای ~۴۰۰ تکه دارد؛ دیمن کند یعنی ویرایش از خودِ رونویسی
        // طولانی‌تر شود. سه تکه‌ی کند پشت‌سرهم و بی‌خیالِ ویرایش می‌شویم: متن خام
        // بدترین حالتِ قابل قبول است، معطلی نیم‌ساعته نه.
        slow = [NSDate.date timeIntervalSinceDate:t0] > 3.0 ? slow + 1 : 0;
        if (slow >= 3) {
            gaveUp = YES;
            ZLog(@"batch: polish daemon too slow, leaving the rest of the text raw");
        }
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
        // فقط بازه‌ی محتوای تازه؛ هم‌پوشانی سر پاره مال پاره‌ی قبلی است
        double from = p.newFromSec;
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
    // دیمن ویرایش را از همین حالا گرم کن؛ نبودنش خطا نیست، فقط متن خام می‌ماند
    if (self.polishFiles && [_lang hasPrefix:@"fa"] && ZSettings.shared.polishEnabled) {
        [ZPolish.shared prepare];
    }
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
    if (self.polishFiles) text = ZBatchPolishText(text, lang);
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
    job.polishFiles = YES;    // یک فایل یعنی یک خروجی، پس پاس همین‌جا آخرِ کار است
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
