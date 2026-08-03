// میکروفن به PCM خام: s16le مونو ۱۶ کیلوهرتز، تکه‌های حدودا ۱۰۰ میلی‌ثانیه.
// کال‌بک‌ها روی نخ صدا صدا زده می‌شوند.
#import "zemzeme.h"
#import <CoreAudio/CoreAudio.h>
#import <stdatomic.h>

// نامِ میکروفنی که مک همین حالا پیش‌فرض می‌داند. در لاگ لازم است چون شایع‌ترین
// خرابیِ دیکته اصلا مالِ ما نیست: مک روی میکروفن دیگری است و کاربر خبر ندارد.
NSString *ZDefaultInputName(void) {
    AudioObjectID dev = 0;
    UInt32 sz = sizeof(dev);
    AudioObjectPropertyAddress a = {kAudioHardwarePropertyDefaultInputDevice,
                                    kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, &dev) || !dev) {
        return @"?";
    }
    CFStringRef name = NULL;
    sz = sizeof(name);
    a.mSelector = kAudioObjectPropertyName;
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &name) || !name) return @"?";
    return (__bridge_transfer NSString *)name;
}

// ---------- خودآزمای میکروفن (--micdump) ----------
// همان ZMic، همان تبدیل، خروجی در یک WAV. هیچ چیزِ مسیر دیکته را دور نمی‌زند، وگرنه
// چیزی را می‌سنجید که کاربر با آن حرف نمی‌زند.

static void ZWavHeader(NSMutableData *d, uint32_t samples) {
    uint32_t rate = 16000, bytes = samples * 2;
    uint32_t riff = 36 + bytes, fmtLen = 16, byteRate = rate * 2;
    uint16_t one = 1, bits = 16, block = 2;
    [d appendBytes:"RIFF" length:4];
    [d appendBytes:&riff length:4];
    [d appendBytes:"WAVEfmt " length:8];
    [d appendBytes:&fmtLen length:4];
    [d appendBytes:&one length:2];      // PCM
    [d appendBytes:&one length:2];      // mono
    [d appendBytes:&rate length:4];
    [d appendBytes:&byteRate length:4];
    [d appendBytes:&block length:2];
    [d appendBytes:&bits length:2];
    [d appendBytes:"data" length:4];
    [d appendBytes:&bytes length:4];
}

int ZMicDumpMain(NSString *path, double seconds) {
    ZMic *mic = [ZMic new];
    NSMutableData *pcm = [NSMutableData data];
    __block NSUInteger clipped = 0;
    mic.onChunk = ^(NSData *chunk) {
        const int16_t *p = chunk.bytes;
        for (NSUInteger i = 0; i < chunk.length / 2; i++) {
            if (p[i] >= 32767 || p[i] <= -32768) clipped++;
        }
        @synchronized (pcm) { [pcm appendData:chunk]; }
    };
    NSError *err = nil;
    if (![mic startWithError:&err]) {
        fprintf(stderr, "micdump: %s\n", err.localizedDescription.UTF8String ?: "?");
        return 1;
    }
    fprintf(stderr, "micdump: %.0f ثانیه ضبط از %s...\n", seconds, ZDefaultInputName().UTF8String);
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
    [mic stop];

    NSMutableData *out = [NSMutableData data];
    NSData *body;
    @synchronized (pcm) { body = [pcm copy]; }
    ZWavHeader(out, (uint32_t)(body.length / 2));
    [out appendData:body];
    if (![out writeToFile:path atomically:YES]) {
        fprintf(stderr, "micdump: نوشتن %s نشد\n", path.UTF8String);
        return 1;
    }
    ZMicDumpReport(body, clipped, path);
    return 0;
}

// گزارشِ **خودبسنده**: هر عددی که لازم است از همین یک ضبط درمی‌آید، نه از مقایسه با
// ضبطی که وقت دیگری گرفته شده. دلیلش یک اشتباه واقعی بود: دو هدست را در دو زمان
// ضبط کردم و کنار هم گذاشتم، در حالی که نمی‌دانستم در کدام‌یک کسی حرف می‌زده. آن
// مقایسه بی‌اعتبار بود. کف و اوج اگر از **یک** ضبط بیایند، شرایط اتاق برای هر دو
// یکی است و دیگر جای این اشتباه نیست.
//
// کف نویز: میانه‌ی آرام‌ترین یک‌پنجم قاب‌ها. اوج حرف: بلندترین یک‌بیستم.
void ZMicDumpReport(NSData *pcm, NSUInteger clipped, NSString *path) {
    const int16_t *p = pcm.bytes;
    NSUInteger n = pcm.length / 2, frame = 1600;   // قاب ۱۰۰ میلی‌ثانیه
    NSUInteger frames = n / frame;
    if (frames < 4) {
        printf("micdump: ضبط برای تحلیل کوتاه است\n");
        return;
    }
    double *lv = calloc(frames, sizeof(double));
    for (NSUInteger f = 0; f < frames; f++) {
        double acc = 0;
        for (NSUInteger i = 0; i < frame; i++) {
            double v = p[f * frame + i] / 32768.0;
            acc += v * v;
        }
        lv[f] = sqrt(acc / frame);
    }
    for (NSUInteger i = 1; i < frames; i++) {      // مرتب‌سازی درجی، چند صد قاب است
        double k = lv[i];
        NSUInteger j = i;
        while (j > 0 && lv[j - 1] > k) { lv[j] = lv[j - 1]; j--; }
        lv[j] = k;
    }
    double floorLv = lv[frames / 10];
    double loudLv = lv[frames - 1 - frames / 20];
    double snr = (floorLv > 1e-9 && loudLv > 1e-9) ? 20 * log10(loudLv / floorLv) : 0;
    printf("micdump: %.1f ثانیه، %lu نمونه‌ی بریده، %s\n",
           n / 16000.0, (unsigned long)clipped, path.UTF8String);
    printf("  کف نویز    rms %.5f\n", floorLv);
    printf("  بلندترین   rms %.5f\n", loudLv);
    printf("  نسبت       %.1f dB  %s\n", snr,
           snr < 6 ? "← حرفی از نویز جدا نشده؛ یا کسی حرف نزده یا میکروفن نمی‌گیرد"
                   : snr < 15 ? "← ضعیف" : "← سالم");
    free(lv);
}

@implementation ZMic {
    AVAudioEngine *_engine;
    AVAudioConverter *_converter;
    AVAudioFormat *_outFormat;
    BOOL _started;
    id _observer;
    // ---------- دیدنی کردنِ میکروفن ----------
    // این فایل تا امروز یک خط هم لاگ نمی‌کرد، و دقیقا همین‌جا بود که کار خوابید:
    // با هدست بلوتوث صدا «می‌رفت» ولی گوگل هیچ نمی‌شنید، و از بیرون هیچ راهی نبود
    // بفهمی صدای ضبط‌شده ساکت است، پر سر و صداست، یا اصلا نمی‌رسد. حالا فرمتِ ورودی
    // یک بار لاگ می‌شود و بلندی صدا هر ده ثانیه یک بار خلاصه.
    double _lvlSum;         // مجموع مربع‌ها برای RMS بازه
    double _lvlPeak;        // بلندترین نمونه‌ی بازه
    NSUInteger _lvlCount;
    NSUInteger _lvlFrames;  // چند فریم در بازه، برای ثانیه‌ی واقعی
    CFAbsoluteTime _lvlAt;
    double _gainSum;        // میانگین بهره در بازه، فقط برای لاگ
    // ---------- کالیبراسیون بلندی ----------
    float _gain;            // بهره‌ی فعلی
    float _speechPeak;      // اوجِ حرف، با حمله‌ی تند و افتِ کند
    float _noiseFloor;      // کفِ نویزِ همین دستگاه، یادگرفته نه هاردکد
    float _hpPrevIn, _hpPrevOut;   // حافظه‌ی فیلتر بالاگذرِ آشکارساز
    BOOL _sawSpeech;
    BOOL _warnedSNR;
    BOOL _gainLocked;
    NSUInteger _lockBlocks;
    NSUInteger _unlockBlocks;
}

// ---------- کالیبراسیون بلندی (نه AGC) ----------
// راهنمای خود گوگل صریح است: **AGC نزنید و نویز نگیرید**، چون مدل روی صدای خام
// آموزش دیده و پردازشِ قبلی دقت را پایین می‌آورد. ولی همان راهنما یک عدد هم
// می‌دهد: اوجِ حرف باید حدود منفی ۲۰ تا منفی ۱۰ دسی‌بل باشد و نبُرد.
//
// این دو با هم تناقض ندارند: آنچه ممنوع است بهره‌ی تندِ لحظه‌ایِ AGC است که وسط
// جمله بالا و پایین می‌پرد و دینامیک را می‌خورد. آنچه لازم است یک بهره‌ی **ثابت**
// است که سطح دستگاه را یک بار به آن پنجره بیاورد. پس اینجا بهره کالیبره می‌شود نه
// دنبالِ صدا: آرام حرکت می‌کند، روی یک عدد می‌نشیند، و تا وقتی دستگاه عوض نشود
// همان می‌ماند. هیچ نویزگیری و هیچ فشرده‌سازی‌ای در کار نیست.
//
// چرا اصلا لازم است: اندازه‌گیری روی سه میکروفن همین دستگاه، حینِ حرف زدن.
//   میکروفن مک   rms ۰.۰۹ تا ۰.۱۱   سالم
//   ‏Galaxy Buds+  rms ۰.۰۰۴ تا ۰.۰۶  آرام
//   ‏QCY H3        rms ۰.۰۰۰۱          تقریبا هیچ
// یعنی هزار برابر فاصله بین دو میکروفنِ همین یک مک. هر عددِ هاردکدی برای یکی از
// این‌ها درست است و برای بقیه غلط، و همین بود که «دستگاه به دستگاه» می‌شد.
static const float kZPeakTarget = 0.22f;      // حدود منفی ۱۳ دسی‌بل، وسطِ پنجره‌ی گوگل
static const float kZPeakCeil = 0.99f;        // محدودکننده؛ بریدن ممنوع است
static const float kZGainNormal = 12.0f;      // سقفِ حالت عادی
static const float kZGainSensitive = 512.0f;  // سقفِ حالت حساسیت بالا
// **قفلِ بهره.** گوگل AGC را منع می‌کند و دلیلش همین است: بهره‌ای که وسط جمله بالا و
// پایین برود پوشِ صدا را عوض می‌کند و مدل روی صدای دست‌نخورده آموزش دیده. نسخه‌ی قبل
// «آرام» بود ولی نمی‌ایستاد؛ در لاگ یک سشن بین ۷۳ و ۱۳۰ برابر نوسان داشت، یعنی
// پنج دسی‌بل بالا و پایین در حین حرف زدن. حالا وقتی کالیبراسیون به هدف رسید قفل
// می‌شود و تا آخر سشن همان می‌ماند: یک بهره‌ی ثابت، دقیقا آن چیزی که گوگل می‌خواهد.
static const float kZLockTolerance = 1.19f;   // تا ±۱.۵ دسی‌بل یعنی رسیدیم
static const NSUInteger kZLockBlocks = 7;     // حدود دو ثانیه حرفِ پایدار
// قفل باید **باز شدنی** باشد. با هشت برابر عملا هیچ‌وقت باز نمی‌شد: باز شدن یعنی
// اوجِ حرف زیر یک‌هشتمِ هدف بماند، و چون اوج با حمله‌ی فوری بالا می‌رفت، هر صدای
// بمِ کوتاهی دوباره مسلحش می‌کرد. نتیجه‌اش در لاگ: بهره تمام یک سشن روی ۱.۴ برابر
// چسبیده بود در حالی که صدا افتاده بود به rms ۰.۰۰۰۹. حالا دو و نیم برابرِ پایدار
// (نه لحظه‌ای) کافی است.
static const float kZUnlockDrop = 2.5f;
static const NSUInteger kZUnlockBlocks = 7;
static const float kZGainUpMax = 1.41f;       // حداکثر ۳ دسی‌بل در هر تکه، رو به بالا
static const float kZGainDownMax = 4.0f;      // و ۱۲ دسی‌بل رو به پایین، چون بریدن ممنوع است
// دروازه دیگر عددِ ثابت نیست: کفِ نویزِ **همین** دستگاه یاد گرفته می‌شود و حرف یعنی
// چیزی که به‌قدر کافی از آن کف بالاتر است. تلاش قبلی یک عدد ثابت (۰.۰۰۵) بود که
// روی Buds+ تنظیم شده بود؛ روی QCY هیچ‌وقت باز نمی‌شد و روی میکروفن مک همیشه.
static const float kZSpeechOverNoise = 3.0f;
static const float kZNoiseRise = 1.007f;      // کف اجازه دارد آرام بالا بیاید
// و آرام هم پایین برود. نسخه‌ی قبل کمینه‌ی **لحظه‌ای** بود: یک تکه‌ی تقریبا صفر
// (لحظه‌ی وصل شدن بلوتوث، عوض شدن دستگاه، گرم شدن مبدل) کف را تا کفِ کفِ ممکن
// می‌چسباند و برگشتن از آنجا با ۰.۷٪ در هر تکه صد ثانیه طول می‌کشید. تا آن موقع
// دروازه‌ی «این حرف است یا نویز» همیشه باز می‌ماند و نویز هم حرف حساب می‌شد. در
// لاگ نشانه‌اش snr های ۹۰ تا ۱۱۰ دسی‌بل بود، عددی که برای هیچ میکروفن واقعی ممکن
// نیست. کفِ حداقلی هم لازم است تا هیچ‌وقت به آن دره نیفتیم.
static const float kZFloorFall = 0.05f;
static const float kZFloorMin = 1e-5f;
static const float kZSpeechDecay = 0.97f;     // اوجِ حرف آرام فراموش می‌شود
// زیر این نسبت، میکروفن حرف را از نویزِ خودش جدا نمی‌کند و بزرگ کردنش فقط نویز را
// بزرگ می‌کند. آن‌وقت سکوت بهتر از دروغ است: یک بار در لاگ گفته می‌شود.
static const float kZMinSNRdB = 10.0f;

// ---------- هیچ کارِ کُند روی نخِ صدا ----------
// نخِ تپ یک مهلتِ سختِ حدودا صد میلی‌ثانیه‌ای دارد؛ از آن که رد شود CoreAudio تکه‌های
// ورودی را دور می‌ریزد و آن صدا دیگر برنمی‌گردد. `ZLog` یک open و seek و write و
// close است، و `NSUserDefaults` می‌تواند تا cfprefsd برود؛ خواندنش در هر تکه یعنی
// ده بار در ثانیه روی همان نخ. هر دو از اینجا بیرون رفتند.
static void ZLogAsync(NSString *line) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ ZLog(@"%@", line); });
}

// نسخه‌ی کش‌شده‌ی «حساسیت بالا». نوشتنش از نخ اصلی است و خواندنش از نخ صدا، پس اتمیک.
static atomic_bool gZHighSens = ATOMIC_VAR_INIT(false);

void ZMicSetHighSensitivity(BOOL on) { atomic_store(&gZHighSens, on ? true : false); }

// فرمت به زبان آدم: چند هرتز، چند کانال، شناور یا صحیح، چند بیت.
static NSString *ZFormatDesc(AVAudioFormat *f) {
    const AudioStreamBasicDescription *d = f.streamDescription;
    BOOL isFloat = (d->mFormatFlags & kAudioFormatFlagIsFloat) != 0;
    return [NSString stringWithFormat:@"%.0fHz %uch %@%u",
            d->mSampleRate, (unsigned)d->mChannelsPerFrame,
            isFloat ? @"f" : @"i", (unsigned)d->mBitsPerChannel];
}

- (instancetype)init {
    if ((self = [super init])) {
        _engine = [AVAudioEngine new];
        // خروجیِ مبدل شناور است نه صحیح، و این عمدی است: بهره **پیش از** کوانتیزه
        // شدن اعمال می‌شود. روی میکروفنی که اوجش ۰.۰۰۹ است، سیگنال فقط شش بیت از
        // شانزده بیت را پر می‌کند؛ بزرگ کردنِ بعد از تبدیل، نویزِ کوانتیزاسیون را هم
        // با خودش بزرگ می‌کرد. در شناور این هزینه صفر است.
        _outFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                      sampleRate:16000 channels:1 interleaved:NO];
        _gain = 1.0f;
        _noiseFloor = -1.0f;
    }
    return self;
}

- (BOOL)startWithError:(NSError **)err {
    AVAudioInputNode *input = _engine.inputNode;
    AVAudioFormat *inFormat = [input inputFormatForBus:0];
    if (inFormat.sampleRate <= 0 || inFormat.channelCount == 0) {
        if (err) *err = [NSError errorWithDomain:@"zemzeme" code:1
                                        userInfo:@{NSLocalizedDescriptionKey: @"میکروفنی در دسترس نیست"}];
        return NO;
    }
    // **هر سشن از صفر کالیبره می‌شود.** این شیء بین سشن‌ها زنده می‌ماند، و تا امروز
    // بهره و قفل و کف نویز هم با آن می‌ماندند. یعنی یک سشنِ بدکالیبره تمام سشن‌های
    // بعدی را تا بسته شدن اپ مسموم می‌کرد، و همین بود آن «گاهی عالی کار می‌کند و
    // یک‌دفعه وسطش می‌میرد»: قرعه‌ی اولین سشن بعد از هر بار باز شدن اپ.
    [self resetCalibration];
    ZMicSetHighSensitivity(ZSettings.shared.highSensitivity);
    [self installTapWithFormat:inFormat];
    [_engine prepare];
    if (![_engine startAndReturnError:err]) return NO;
    _started = YES;
    _lvlAt = CFAbsoluteTimeGetCurrent();
    ZLog(@"mic: %@ in=%@ out=%@", ZDefaultInputName(), ZFormatDesc(inFormat), ZFormatDesc(_outFormat));

    // تعویض دستگاه صدا (هدست وصل/قطع): تپ را از نو بچین
    __weak typeof(self) ws = self;
    _observer = [NSNotificationCenter.defaultCenter
        addObserverForName:AVAudioEngineConfigurationChangeNotification object:_engine queue:nil
                usingBlock:^(NSNotification *n) {
        __strong typeof(ws) s = ws;
        if (!s || !s->_started) return;
        [s->_engine.inputNode removeTapOnBus:0];
        AVAudioFormat *f = [s->_engine.inputNode inputFormatForBus:0];
        if (f.sampleRate <= 0) {
            ZLog(@"mic: configuration change، ولی ورودی فرمت ندارد؛ تپ نصب نشد");
            return;
        }
        ZLog(@"mic: configuration change، تپ از نو: %@ in=%@", ZDefaultInputName(), ZFormatDesc(f));
        // دستگاه عوض شده، پس کالیبراسیونِ دستگاه قبلی بی‌معنی است. بین میکروفن مک و
        // یک هدست بلوتوث هزار برابر فاصله است؛ بردنِ بهره‌ی یکی روی دیگری یعنی یا
        // کر شدن یا بریدن.
        [s resetCalibration];
        [s installTapWithFormat:f];
        if (!s->_engine.isRunning) {
            [s->_engine prepare];
            [s->_engine startAndReturnError:nil];
        }
    }];
    return YES;
}

- (void)resetCalibration {
    _gain = 1.0f;
    _gainLocked = NO;
    _lockBlocks = 0;
    _unlockBlocks = 0;
    _speechPeak = 0;
    _noiseFloor = -1.0f;    // هنوز کاشته نشده؛ اولین تکه می‌کاردش
    _hpPrevIn = 0;
    _hpPrevOut = 0;
    _sawSpeech = NO;
    _warnedSNR = NO;
}

- (void)installTapWithFormat:(AVAudioFormat *)inFormat {
    // حافظه‌ی فیلتر مالِ دستگاهِ قبلی است؛ با آن، اولین تکه‌ی دستگاه تازه یک گذرای
    // ساختگی می‌گیرد، دقیقا روی تکه‌ای که باید کف نویز را از نو یاد بگیرد.
    _hpPrevIn = 0;
    _hpPrevOut = 0;
    _converter = [[AVAudioConverter alloc] initFromFormat:inFormat toFormat:_outFormat];
    __weak typeof(self) ws = self;
    [_engine.inputNode installTapOnBus:0 bufferSize:4800 format:inFormat
                                 block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        [ws handleBuffer:buffer];
    }];
}

- (void)handleBuffer:(AVAudioPCMBuffer *)buffer {
    AVAudioConverter *conv = _converter;
    if (!conv) return;
    double ratio = 16000.0 / buffer.format.sampleRate;
    AVAudioFrameCount cap = (AVAudioFrameCount)(buffer.frameLength * ratio) + 64;
    AVAudioPCMBuffer *out = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_outFormat frameCapacity:cap];
    if (!out) return;
    __block BOOL fed = NO;
    NSError *err = nil;
    AVAudioConverterOutputStatus st = [conv convertToBuffer:out error:&err
        withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount count, AVAudioConverterInputStatus *outStatus) {
        if (fed) {
            *outStatus = AVAudioConverterInputStatus_NoDataNow;
            return nil;
        }
        fed = YES;
        *outStatus = AVAudioConverterInputStatus_HaveData;
        return buffer;
    }];
    // خطای مبدل تا امروز یک `return` خالی بود: صدا ناپدید می‌شد و هیچ ردی نمی‌ماند.
    // شایع‌ترین راهش هم عوض شدن دستگاه است، چون removeTapOnBus منتظر بلاکِ در پرواز
    // نمی‌ماند و یک بافرِ ۴۸ کیلوهرتزی می‌تواند به مبدلی برسد که برای فرمت دیگری
    // ساخته شده. فریمِ صفر عادی است (مبدل هنوز بلاک کامل ندارد) و لاگ نمی‌خواهد.
    if (st == AVAudioConverterOutputStatus_Error) {
        ZLogAsync(@"mic: تبدیل شکست خورد، این تکه صدا از دست رفت");
        return;
    }
    if (out.frameLength == 0 || !out.floatChannelData) return;

    float *p = out.floatChannelData[0];
    NSUInteger n = out.frameLength;

    // ۱) آشکارساز: اوجِ همین تکه، روی نسخه‌ی بالاگذرشده.
    float peak = [self detectPeakOf:p count:n];
    // ۲) کالیبراسیون بهره از روی همان اوج.
    float gain = [self calibrateForPeak:peak];
    // ۳) اعمال در شناور، با محدودکننده، و تبدیل به s16.
    NSMutableData *data = [NSMutableData dataWithLength:n * 2];
    int16_t *q = data.mutableBytes;
    float outPeak = 0, acc = 0;
    NSUInteger cnt = 0;
    for (NSUInteger i = 0; i < n; i++) {
        float v = p[i] * gain;
        if (v > kZPeakCeil) v = kZPeakCeil;
        else if (v < -kZPeakCeil) v = -kZPeakCeil;
        float a = fabsf(v);
        if (a > outPeak) outPeak = a;
        if (i % 8 == 0) { acc += v * v; cnt++; }
        q[i] = (int16_t)lrintf(v * 32767.0f);
    }
    float rms = sqrtf(acc / MAX(1u, (unsigned)cnt));
    if (self.onLevel) self.onLevel(MIN(1.0f, rms * 5));
    [self noteLevel:rms peak:outPeak frames:n gain:gain];
    if (self.onChunk) self.onChunk(data);
}

// فیلتر بالاگذرِ یک‌قطبی حدود ۸۰ هرتز، **فقط برای اندازه‌گیری**. صدایی که به گوگل
// می‌رود دست‌نخورده می‌ماند، چون راهنمای گوگل پردازشِ قبلی را منع می‌کند.
// چرا لازم است: روی همین هدست‌ها ۹۱ درصد انرژیِ نویزِ اتاق زیر ۵۰۰ هرتز بود، یعنی
// غرشی که هیچ حرفی در آن نیست. بی این فیلتر، سنجه غرش را «صدا» می‌دید و بهره را
// از روی چیزی تنظیم می‌کرد که اصلا گفتار نیست.
- (float)detectPeakOf:(const float *)p count:(NSUInteger)n {
    const float a = 0.9695f;    // ۸۰ هرتز در ۱۶ کیلوهرتز
    float peak = 0, prevIn = _hpPrevIn, prevOut = _hpPrevOut;
    for (NSUInteger i = 0; i < n; i++) {
        float y = a * (prevOut + p[i] - prevIn);
        prevIn = p[i];
        prevOut = y;
        float m = fabsf(y);
        if (m > peak) peak = m;
    }
    _hpPrevIn = prevIn;
    _hpPrevOut = prevOut;
    return peak;
}

// بهره را آرام به سمتِ «اوجِ حرف روی هدف» می‌برد. سه چیز اینجا اتفاق می‌افتد و هر
// سه لازم‌اند: یادگرفتنِ کفِ نویزِ این دستگاه، تشخیص اینکه این تکه حرف است یا کف،
// و حرکتِ آرامِ بهره.
- (float)calibrateForPeak:(float)peak {
    // کف نویز: تند پایین می‌آید (هر سکوتی کف تازه است) و آرام بالا، تا اتاقی که
    // کم‌کم شلوغ می‌شود هم دنبال شود بی آنکه یک تَق کف را برای همیشه بالا ببرد.
    // **کاشتِ فوری، بعد ردیابیِ آرام.** افتِ آرام جلوی فروریختنِ کف را می‌گیرد، ولی
    // اگر از یک شروع شود همان آرامی خودش فاجعه است: از ۱.۰ تا کفِ واقعیِ یک هدست
    // (حدود ۰.۰۰۱) با پنج درصد در هر تکه چهل ثانیه طول می‌کشد، و در تمام آن مدت
    // هیچ چیز سه برابرِ کف نمی‌شود، پس هیچ حرفی تشخیص داده نمی‌شود و بهره روی یک
    // می‌ماند. دقیقا همین در لاگ افتاد: gain 1.0× و snr 0dB برای کل سشن.
    // پس اولین تکه کف را می‌کارد و از آن به بعد آرام دنبال می‌شود.
    if (_noiseFloor < 0) _noiseFloor = MAX(peak, kZFloorMin);
    else if (peak < _noiseFloor) _noiseFloor += (peak - _noiseFloor) * kZFloorFall;
    else _noiseFloor = MIN(_noiseFloor * kZNoiseRise, peak);
    if (_noiseFloor < kZFloorMin) _noiseFloor = kZFloorMin;

    // **بهره فقط وقتی حرف هست تکان می‌خورد.** نسخه‌ی اول اوجِ حرف را در سکوت هم آب
    // می‌کرد؛ چون هدف تقسیم بر آن است، هرچه آب می‌شد بهره بالاتر می‌رفت و در سکوت
    // خودش را تا سقف بالا می‌کشید. یعنی همان نویزِ بزرگ‌شده‌ای که گوگل از آن کلمه
    // درمی‌آورد. حالا سکوت یعنی بهره سر جایش می‌ماند، نه بالا و نه پایین.
    if (peak <= _noiseFloor * kZSpeechOverNoise) return _gain;
    _sawSpeech = YES;
    // حمله‌ی فوری رو به بالا، دنبال‌کردنِ آرام رو به پایین: یک هجای بلند همان لحظه
    // دیده می‌شود (تا نبُرد)، ولی یک لحظه سکوتِ وسط جمله اوج را پاک نمی‌کند.
    if (peak > _speechPeak) _speechPeak = peak;
    else _speechPeak = _speechPeak * 0.98f + peak * 0.02f;
    if (_speechPeak < 1e-6f) return _gain;

    float ceiling = atomic_load(&gZHighSens) ? kZGainSensitive : kZGainNormal;
    float want = MIN(ceiling, MAX(1.0f, kZPeakTarget / _speechPeak));
    // قفل: رسیدیم و ماندیم، پس دیگر تکان نخور. باز شدنش فقط وقتی است که واقعا دور
    // شده باشیم (کاربر فاصله‌اش را عوض کرد، یا میکروفن عوض شد)، نه با هر نوسان.
    if (_gainLocked) {
        float off = want > _gain ? want / _gain : _gain / want;
        if (off < kZUnlockDrop) {
            _unlockBlocks = 0;
            return _gain;
        }
        if (++_unlockBlocks < kZUnlockBlocks) return _gain;   // پایدار باشد، نه یک تَق
        _gainLocked = NO;
        _lockBlocks = 0;
        _unlockBlocks = 0;
        ZLogAsync([NSString stringWithFormat:@"mic: بهره از قفل درآمد (هدف %.0f×)", want]);
    }
    // حرکت در مقیاس دسی‌بل با سرعت سقف‌دار، نه کسری از فاصله. با نسخه‌ی کسری،
    // رسیدن از یک به بیست برابر سیزده ثانیه طول می‌کشید و جمله‌های کوتاه هیچ‌وقت به
    // هدف نمی‌رسیدند. بالا رفتن آرام است تا کالیبراسیون بماند نه AGC؛ پایین آمدن
    // چهار برابر تندتر، چون دیر پایین آمدن یعنی بریدن، و بریدن ممنوع است.
    float ratio = want / _gain;
    if (ratio > kZGainUpMax) ratio = kZGainUpMax;
    else if (ratio < 1.0f / kZGainDownMax) ratio = 1.0f / kZGainDownMax;
    _gain *= ratio;
    if (_gain < 1.0f) _gain = 1.0f;
    float off = want > _gain ? want / _gain : _gain / want;
    if (off < kZLockTolerance) {
        if (++_lockBlocks >= kZLockBlocks) {
            _gainLocked = YES;
            ZLogAsync([NSString stringWithFormat:@"mic: بهره روی %.1f× قفل شد", _gain]);
        }
    } else {
        _lockBlocks = 0;
    }
    return _gain;
}

// نسبت سیگنال به نویزِ همین دستگاه، به دسی‌بل. عددی که می‌گوید بزرگ کردن فایده
// دارد یا نه: بهره هم سیگنال و هم نویز را با هم بزرگ می‌کند، پس اگر این عدد کوچک
// باشد هیچ بهره‌ای نجاتش نمی‌دهد.
- (float)snrDB {
    if (_speechPeak <= 1e-6f || _noiseFloor <= 1e-7f) return 0;
    return 20.0f * log10f(_speechPeak / _noiseFloor);
}

// خلاصه‌ی بلندی صدا، هر ده ثانیه یک خط. سه عدد و هر سه لازم‌اند: rms می‌گوید
// به‌طور متوسط چقدر صدا هست، peak می‌گوید بلندترین لحظه چقدر بوده (rms پایین با
// peak بالا یعنی صدا هست ولی کم و دور)، و ثانیه می‌گوید اصلا چقدر صدا رسیده.
// rms نزدیک صفر یعنی میکروفن ساکت است، هرچه بایت به گوگل برود.
- (void)noteLevel:(float)rms peak:(float)peak frames:(NSUInteger)frames gain:(float)gain {
    _lvlSum += (double)rms * rms;
    _lvlPeak = MAX(_lvlPeak, peak);
    _gainSum += gain;
    _lvlCount++;
    _lvlFrames += frames;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - _lvlAt < 10.0 || !_lvlCount) return;
    double avg = sqrt(_lvlSum / _lvlCount);
    // rms و peak اینجا **بعد** از بهره‌اند، یعنی همان چیزی که واقعا به گوگل می‌رسد.
    // بهره کنارشان می‌آید تا معلوم باشد این عدد از خودِ میکروفن آمده یا از جبرانِ ما،
    // و snr می‌گوید اصلا جبران فایده دارد یا نه.
    float snr = [self snrDB];
    ZLogAsync([NSString stringWithFormat:@"mic: rms %.4f peak %.3f gain %.1f× snr %.0fdB%@، %.1f ثانیه صدا",
         avg, _lvlPeak, _gainSum / _lvlCount, snr,
         atomic_load(&gZHighSens) ? @" [حساسیت بالا]" : @"",
         _lvlFrames / 16000.0]);
    // یک بار در هر سشن، و فقط وقتی واقعا حرفی شنیده شده: اگر حرف از نویزِ خودِ
    // میکروفن جدا نمی‌شود، مقصر بلندی نیست و هیچ بهره‌ای درستش نمی‌کند.
    if (!_warnedSNR && _sawSpeech && snr > 0 && snr < kZMinSNRdB) {
        _warnedSNR = YES;
        ZLogAsync([NSString stringWithFormat:
            @"mic: ⚠︎ نسبت سیگنال به نویز %.0f دسی‌بل است. این میکروفن حرف را از "
             "نویز خودش جدا نمی‌کند و بزرگ کردنش هم فقط نویز را بزرگ می‌کند؛ "
             "میکروفن دیگری را امتحان کن", snr]);
    }
    _lvlSum = 0;
    _lvlPeak = 0;
    _gainSum = 0;
    _lvlCount = 0;
    _lvlFrames = 0;
    _lvlAt = now;
}

- (void)stop {
    if (!_started) return;
    _started = NO;
    if (_observer) [NSNotificationCenter.defaultCenter removeObserver:_observer];
    _observer = nil;
    [_engine.inputNode removeTapOnBus:0];
    [_engine stop];
}

@end
