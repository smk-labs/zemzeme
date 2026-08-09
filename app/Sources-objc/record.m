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
