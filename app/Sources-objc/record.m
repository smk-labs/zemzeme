// ضبط صدای سشن روی دیسک، و موتور حالت یادداشت که هیچ کار دیگری نمی‌کند.
//
// چرا صدای *هر* سشن ضبط می‌شود، نه فقط یادداشت: پاس نهایی به صدا احتیاج دارد و صدا
// بعد از تمام شدن سشن دیگر پیدا نمی‌شود. با ضبط همیشگی، همان کار پایانی روی هر سشنی
// شدنی است، و `sessions/` که تا امروز فقط متن خام بود حالا اصلِ ماجرا را هم دارد.
// هزینه‌اش ~۱۲ کیلوبایت بر ثانیه‌ی گفتار است (FLAC، نصفِ خام).
#import "zemzeme.h"

// ---------- ZRecorder ----------

@implementation ZRecorder {
    NSURL *_want;               // جای فایل، پیش از ساخته شدنش
    ZFlacEncoder *_enc;
    NSFileHandle *_fh;
    NSLock *_lock;
    unsigned long long _pcmBytes;
    unsigned long long _outBytes;
    BOOL _opened;               // یک بایت هم که نوشته شد، فایل هست و می‌ماند
    BOOL _done;
    BOOL _broken;               // یک بار شکست، دیگر هر تکه را دوباره امتحان نمی‌کنیم
}

- (instancetype)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        _want = url;
        _lock = [NSLock new];
    }
    return self;
}

// نال تا اولین بایت (فایل خالی روی دیسک نمی‌ماند)، و از آن به بعد **همیشه** همان مسیر.
// باگ واقعی و دقیقا اینجا: شرط اولش `_fh != nil` بود، یعنی به *باز بودنِ* فایل بسته
// بود نه به وجودش. سر پایان اول `finish` صدا می‌خورد و بعد `url` پرسیده می‌شد، پس
// جواب نال بود و پاس نهایی بی‌سروصدا «صدایی ضبط نشده» می‌گرفت و رد می‌شد. دو سشن
// واقعی همین‌طور بی‌متن تمام شدند تا لاگ لوش داد.
- (NSURL *)url {
    [_lock lock];
    NSURL *u = _opened ? _want : nil;
    [_lock unlock];
    return u;
}

- (NSTimeInterval)seconds {
    [_lock lock];
    NSTimeInterval s = _pcmBytes / 32000.0;    // s16le مونو ۱۶ کیلوهرتز
    [_lock unlock];
    return s;
}

- (unsigned long long)fileBytes {
    [_lock lock];
    unsigned long long b = _outBytes;
    [_lock unlock];
    return b;
}

// اولین بایت که رسید، تازه فایل و انکودر ساخته می‌شوند. زیر قفل صدا زده می‌شود.
- (BOOL)openLocked {
    if (_fh) return YES;
    if (_broken) return NO;
    if (!_enc) _enc = [ZFlacEncoder new];
    if (!_enc) {
        _broken = YES;
        ZLog(@"record: انکودر FLAC راه نیفتاد؛ صدای این سشن ضبط نمی‌شود");
        return NO;
    }
    [NSFileManager.defaultManager createDirectoryAtURL:_want.URLByDeletingLastPathComponent
                          withIntermediateDirectories:YES attributes:nil error:nil];
    if (![NSFileManager.defaultManager createFileAtPath:_want.path
                                               contents:_enc.streamHeader attributes:nil]) {
        _broken = YES;
        ZLog(@"record: فایل صدا ساخته نشد: %@", _want.path);
        return NO;
    }
    _fh = [NSFileHandle fileHandleForWritingAtPath:_want.path];
    if (!_fh) {
        _broken = YES;
        return NO;
    }
    [_fh seekToEndOfFile];
    _outBytes = _enc.streamHeader.length;
    _opened = YES;
    return YES;
}

- (void)writeLocked:(NSData *)flac {
    if (!flac.length) return;
    @try {
        [_fh writeData:flac];
        _outBytes += flac.length;
    } @catch (NSException *e) {
        _broken = YES;
        ZLog(@"record: نوشتن صدا شکست خورد (%@)؛ بقیه‌ی سشن ضبط نمی‌شود", e.name);
        [_fh closeFile];
        _fh = nil;
    }
}

- (void)feed:(NSData *)pcm {
    if (!pcm.length) return;
    [_lock lock];
    if (!_done && [self openLocked]) {
        _pcmBytes += pcm.length;
        [self writeLocked:[_enc encode:pcm]];
    }
    [_lock unlock];
}

// شمارِ واقعی نمونه‌ها را در بلاک STREAMINFO می‌نشاند. هدرِ استریم با total_samples=0
// بسته می‌شود (موقع ضبط کسی طول را نمی‌داند) و طبق اسپک هم مجاز است، ولی نتیجه‌اش این
// بود که **هیچ ابزاری طول فایل را نمی‌فهمید**: afinfo برای ۵ ثانیه صدا ۷٫۸ ثانیه حدس
// زد و پنل رونویسی خودِ اپ فایل را «خراب» رد کرد. یعنی صدا روی دیسک بود ولی ابزارهای
// همین اپ نمی‌توانستند بازش کنند. حالا سرِ بستن، همان هشت بایت با عدد واقعی بازنویسی
// می‌شود و فایل یک FLAC تمام‌عیار است.
// چیدمان آن هشت بایت: sample_rate(20) | channels-1(3) | bits-1(5) | total_samples(36)
- (void)patchTotalSamplesLocked:(unsigned long long)frames {
    uint64_t chunk = (((uint64_t)16000 & 0xFFFFFULL) << 44)
                   | (((uint64_t)0 & 0x7ULL) << 41)
                   | (((uint64_t)15 & 0x1FULL) << 36)
                   | ((uint64_t)frames & 0xFFFFFFFFFULL);
    uint8_t b[8];
    for (int i = 0; i < 8; i++) b[i] = (uint8_t)(chunk >> (56 - i * 8));
    @try {
        [_fh seekToFileOffset:18];    // "fLaC"(۴) + سرِ بلاک(۴) + دو blocksize و دو frame size(۱۰)
        [_fh writeData:[NSData dataWithBytes:b length:8]];
    } @catch (NSException *e) {
        ZLog(@"record: نوشتن طول در هدر نشد (%@)؛ فایل باز می‌شود ولی طولش حدسی است", e.name);
    }
}

// سطل آشغال در حین ضبط: فایل می‌رود و ضبط از صفر ادامه پیدا می‌کند.
//
// انکودر هم از نو ساخته می‌شود و این نکته‌ی اصلی است: داخلش تا یک بلاکِ ناقص پی‌سی‌ام
// مانده و اگر همان نمونه را نگه داریم، اولین فریمِ فایلِ تازه با صدای دورریخته شروع
// می‌شود. «دور بریز» یعنی هیچ‌کدامش نماند.
- (void)discard {
    [_lock lock];
    if (!_done) {
        if (_fh) {
            @try { [_fh closeFile]; } @catch (NSException *e) {}
            _fh = nil;
        }
        if (_opened) {
            [NSFileManager.defaultManager removeItemAtURL:_want error:nil];
            ZLog(@"record: %.0f ثانیه صدا دور ریخته شد", _pcmBytes / 32000.0);
        }
        _opened = NO;
        _broken = NO;    // خرابیِ قبلی مالِ فایلِ رفته بود
        _enc = nil;
        _pcmBytes = 0;
        _outBytes = 0;
    }
    [_lock unlock];
}

- (void)finish {
    [_lock lock];
    if (!_done && _fh) {
        // ته‌مانده‌ی کمتر از یک بلاک را انکودر هیچ‌وقت فریم نمی‌کند، پس تا ~۲۹۰
        // میلی‌ثانیه‌ی آخر (یعنی احتمالا آخرین کلمه) در فایل نمی‌آمد. با سکوت پرش
        // می‌کنیم؛ سکوتِ ته فایل بی‌آزار است، افتادنِ آخرین کلمه نه.
        unsigned long long frames = _pcmBytes / 2;
        NSUInteger have = (NSUInteger)(frames % MAX(1u, (unsigned)_enc.blockFrames));
        if (have) {
            NSUInteger padFrames = _enc.blockFrames - have;
            [self writeLocked:[_enc encode:[NSMutableData dataWithLength:padFrames * 2]]];
            frames += padFrames;
        }
        // و هرچه در صف داخلی انکودر مانده
        for (int i = 0; i < 8; i++) {
            NSData *more = [_enc encode:[NSData data]];
            if (!more.length) break;
            [self writeLocked:more];
        }
        if (_fh) [self patchTotalSamplesLocked:frames];
        [_fh closeFile];
        _fh = nil;
        ZLog(@"record: %@ · %.0f ثانیه · %.1f مگابایت", _want.lastPathComponent,
             _pcmBytes / 32000.0, _outBytes / 1048576.0);
    }
    _done = YES;
    [_lock unlock];
}

@end

// ---------- ZNoteEngine ----------
// میکروفن و ضبط، و بس. نه اتصالی، نه رونوشتی، نه سوپروایزری: هیچ‌کدام از پنج مسیرِ
// اندازه‌گیری‌شده‌ی موتور گوگل (چرخش، گیر، بازپخش، نجات، جوش) اینجا معنا ندارند، چون
// چیزی روی سیم نمی‌رود. تنها قرارداد این است که «committed خالی، pending خالی»، پس
// دفتر و رونوشت و سه حالت دیگر هیچ فرقی حس نمی‌کنند.
//
// واچ‌داگ میکروفن مرده اما لازم است، و دقیقا همان‌قدر لازم: در حالت یادداشت هیچ متنی
// روی صفحه نمی‌آید، پس اگر میکروفن لال شود کاربر تا آخر سشن هم نمی‌فهمد.

@implementation ZNoteEngine {
    ZMic *_mic;
    BOOL _micRunning;
    BOOL _running;
    BOOL _paused;
    NSTimer *_watchdog;
    NSDate *_lastChunkAt;
    NSDate *_lastLevelAt;
    NSInteger _micRetries;
}

@synthesize delegate;
@synthesize paused = _paused;
@synthesize recorder;

- (instancetype)init {
    if ((self = [super init])) {
        _mic = [ZMic new];
        _lastLevelAt = NSDate.distantPast;
    }
    return self;
}

- (void)state:(ZEngineState)s msg:(NSString *)m {
    id<ZEngineDelegate> d = self.delegate;
    dispatch_async(dispatch_get_main_queue(), ^{ [d engineState:s message:m]; });
}

- (void)startWithLang:(NSString *)lang {
    if (_running) return;
    _running = YES;
    [self state:ZEngineConnecting msg:@""];
    __weak typeof(self) ws = self;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) s = ws;
            if (!s || !s->_running) return;
            if (!granted) {
                s->_running = NO;
                [s state:ZEngineGaveUp
                     msg:@"اجازه میکروفن نیست. تنظیمات سیستم، بخش حریم خصوصی، میکروفن را برای زمزمه روشن کن."];
                return;
            }
            [s startMic];
        });
    }];
}

- (void)startMic {
    __weak typeof(self) ws = self;
    _mic.onChunk = ^(NSData *pcm) {
        __strong typeof(ws) s = ws;
        if (!s) return;
        s->_lastChunkAt = NSDate.date;
        s->_micRetries = 0;
        if (s->_paused) return;    // مکث یعنی نشنو، پس ضبط هم نکن
        [s.recorder feed:pcm];
    };
    _mic.onLevel = ^(float rms) {
        __strong typeof(ws) s = ws;
        if (!s || s->_paused) return;
        NSDate *now = NSDate.date;
        if ([now timeIntervalSinceDate:s->_lastLevelAt] <= 0.1) return;
        s->_lastLevelAt = now;
        id<ZEngineDelegate> d = s.delegate;
        dispatch_async(dispatch_get_main_queue(), ^{ [d engineLevel:rms]; });
    };
    if (!_micRunning) {
        NSError *err = nil;
        if (![_mic startWithError:&err]) {
            _running = NO;
            [self state:ZEngineGaveUp
                 msg:[NSString stringWithFormat:@"میکروفن راه نیفتاد: %@",
                      err.localizedDescription ?: @"?"]];
            return;
        }
        _micRunning = YES;
    }
    _lastChunkAt = NSDate.date;
    _micRetries = 0;
    [self state:ZEngineListening msg:@""];
    [_watchdog invalidate];
    __weak typeof(self) w2 = self;
    _watchdog = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *t) {
        [w2 tick];
    }];
    ZLog(@"note: recording started");
}

// همان واچ‌داگ موتور گوگل، با همان آستانه‌ها: صدا نمی‌آید یعنی ضبط بی‌فایده است.
- (void)tick {
    if (!_running || _paused || !_micRunning) return;
    NSTimeInterval since = [NSDate.date timeIntervalSinceDate:_lastChunkAt];
    if (since <= 5) return;
    if (_micRetries < 2) {
        _micRetries++;
        _lastChunkAt = NSDate.date;
        ZLog(@"note: mic silent %.0fs, restarting mic (try %ld)", since, (long)_micRetries);
        [_mic stop];
        _micRunning = NO;
        NSError *err = nil;
        if ([_mic startWithError:&err]) _micRunning = YES;
        return;
    }
    _running = NO;
    [self stopMic];
    [self state:ZEngineGaveUp msg:@"میکروفن صدا نمی‌ده؛ ورودی صدای سیستم را چک کن و دوباره شروع کن"];
    ZLog(@"note: gave up, mic dead");
}

- (void)setLang:(NSString *)l {}    // زبان اینجا هیچ اثری ندارد: چیزی تشخیص داده نمی‌شود

- (void)pause {
    if (!_running || _paused) return;
    _paused = YES;
    [self state:ZEnginePaused msg:@""];
    ZLog(@"note: paused");
}

- (void)resume {
    if (!_running || !_paused) return;
    _paused = NO;
    _lastChunkAt = NSDate.date;
    [self state:ZEngineListening msg:@""];
    ZLog(@"note: resumed");
}

- (void)stop {
    BOOL was = _running;
    _running = NO;
    _paused = NO;
    [self stopMic];
    // بستنِ فایل کارِ سشن است نه موتور: سشن ساختش و فقط او می‌داند پاس نهایی هنوز
    // سراغش می‌آید یا نه. موتور فقط تغذیه می‌کند، و اینجا دیگر تغذیه‌ای نمی‌کند.
    [self state:ZEngineIdle msg:@""];
    if (was) ZLog(@"note: stopped, %.0f seconds recorded", self.recorder.seconds);
}

- (void)stopMic {
    [_watchdog invalidate];
    _watchdog = nil;
    if (_micRunning) [_mic stop];
    _micRunning = NO;
}

// در حالت یادداشت متنِ معلقی وجود ندارد که دور برود، و صدا هم عمدا دور ریخته نمی‌شود:
// قاعده‌ی «هیچ چیز گم نمی‌شود» از همه‌ی دکمه‌ها بالاتر است. سطل آشغال در این حالت
// فقط متنِ ادیتور را می‌برد، که کار خود سشن است نه موتور.
- (void)dropPending {}

@end

// ---------- انتخاب موتور ----------
// حالت یادداشت همیشه موتور ضبط را می‌گیرد، حتی اگر تنظیمِ موتور روی رله‌ی کروم باشد:
// آن موتور میکروفن ندارد و در این حالت هیچ کاری برایش نمی‌ماند.
id<ZEngine> ZMakeEngine(ZMode mode) {
    if (mode == ZModeNote) return (id<ZEngine>)[ZNoteEngine new];
    if ([ZSettings.shared.engineName isEqualToString:@"chrome"]) {
        return (id<ZEngine>)[ZChromeRelayEngine new];
    }
    return (id<ZEngine>)[ZGoogleEngine new];
}
