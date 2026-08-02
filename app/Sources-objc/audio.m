// میکروفن به PCM خام: s16le مونو ۱۶ کیلوهرتز، تکه‌های حدودا ۱۰۰ میلی‌ثانیه.
// کال‌بک‌ها روی نخ صدا صدا زده می‌شوند.
#import "zemzeme.h"
#import <CoreAudio/CoreAudio.h>

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
    printf("micdump: %lu نمونه (%.1f ثانیه)، %lu نمونه‌ی بریده، %s\n",
           (unsigned long)(body.length / 2), body.length / 2 / 16000.0,
           (unsigned long)clipped, path.UTF8String);
    return 0;
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
    float _gain;            // بهره‌ی خودکار؛ پایین همین فایل
    NSUInteger _quietBlocks; // چند تکه پشت هم زیر دروازه بوده‌اند
    double _gainSum;        // میانگین بهره در بازه، فقط برای لاگ
}

// ---------- بهره‌ی خودکار ----------
// هدست‌های بلوتوث سیگنالی می‌دهند که برای گوش خوب است و برای تشخیص گفتار بسیار
// آرام. اندازه‌گیری روی Galaxy Buds+: حرف زدن معمولی rms حدود ۰.۰۰۴ تا ۰.۰۱۳
// می‌داد، جایی که تشخیص گفتار حدود ۰.۰۵ می‌خواهد؛ یعنی ۱۵ تا ۲۵ دسی‌بل کمتر. گوگل
// صدا را «صدا» می‌دید (voice=1) ولی کلمه‌ای بیرون نمی‌داد. ولوم ورودی مک هم از قبل
// روی بیشترین مقدار بود، پس بهره‌ی بیشتری در سیستم‌عامل باقی نمانده بود.
//
// این جبران در مسیر خودمان انجام می‌شود، با سه احتیاط:
// - **دروازه‌ی نویز:** فقط وقتی واقعا صدایی هست بهره تنظیم می‌شود، وگرنه سکوتِ یک
//   اتاق ساکت تا ته تقویت می‌شد و به گوگل نویز می‌رسید نه سکوت.
// - **بالا آرام، پایین تند:** بلند شدن بهره کند است تا وسط جمله بالا و پایین نپرد،
//   ولی کم شدنش تند است تا اولین هجای بلند نبُرد.
// - **سقف:** بیشتر از این، نویزِ خودِ هدست را به اندازه‌ی حرف بزرگ می‌کند.
static const float kZGainTarget = 0.05f;    // rms هدف
static const float kZGainMax = 16.0f;
// دروازه از روی اندازه‌گیری واقعی انتخاب شد، نه از روی حدس: نویزِ اتاق روی همین
// هدست rms حدود ۰.۰۰۱۵ می‌دهد و تکه‌های حرفِ آرام حدود ۰.۰۱ به بالا. ۰.۰۰۵ بینشان
// می‌نشیند. با ۰.۰۰۲ (تلاش اول) نویزِ اتاق هم دروازه را باز می‌کرد و کفِ سکوت
// ۴.۶ دسی‌بل بالا می‌رفت.
static const float kZGainGate = 0.005f;
static const float kZGainUp = 0.04f;        // ضریب نرم‌شدن رو به بالا
static const float kZGainDown = 0.35f;      // و رو به پایین
// و برگشت به یک بعد از سکوتِ **کشدار**. بی این، یک تَقِ گذرا (کلید، در) دروازه را
// باز می‌کرد، بهره بالا می‌رفت و بعد روی همان می‌ماند: در اتاق ساکت کفِ نویز
// ۸ دسی‌بل بالا می‌رفت و همان نویزِ بزرگ‌شده بود که گوگل گاهی از آن کلمه درمی‌آورد.
// شمارش لازم است تا مکث‌های معمولیِ وسط حرف (کمتر از دو ثانیه) بهره را نریزند،
// وگرنه اول هر جمله کم‌صدا می‌شد تا دوباره بالا بیاید.
static const NSUInteger kZGainQuietBlocks = 7;   // حدود دو ثانیه
static const float kZGainRelax = 0.15f;

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
        _outFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16
                                                      sampleRate:16000 channels:1 interleaved:YES];
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
        [s installTapWithFormat:f];
        if (!s->_engine.isRunning) {
            [s->_engine prepare];
            [s->_engine startAndReturnError:nil];
        }
    }];
    return YES;
}

- (void)installTapWithFormat:(AVAudioFormat *)inFormat {
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
    if (st == AVAudioConverterOutputStatus_Error || out.frameLength == 0 || !out.int16ChannelData) return;

    int16_t *p = out.int16ChannelData[0];
    NSUInteger n = out.frameLength;
    float gain = [self applyGainTo:p count:n];

    // RMS تقریبی با نمونه‌برداری هر هشتم، برای نقطه ضربان. اوج اما از همه‌ی نمونه‌ها:
    // یک تَقِ کوتاه بین نمونه‌های هشتم گم می‌شود و همان است که «صدا هست یا نه» را
    // جواب می‌دهد.
    float acc = 0, peak = 0;
    NSUInteger cnt = 0;
    for (NSUInteger i = 0; i < n; i++) {
        float v = p[i] / 32768.0f;
        float a = fabsf(v);
        if (a > peak) peak = a;
        if (i % 8 == 0) {
            acc += v * v;
            cnt++;
        }
    }
    float rms = sqrtf(acc / MAX(1u, (unsigned)cnt));
    if (self.onLevel) self.onLevel(MIN(1.0f, rms * 5));
    [self noteLevel:rms peak:peak frames:n gain:gain];
    if (self.onChunk) self.onChunk([NSData dataWithBytes:p length:n * 2]);
}

// بهره را از روی همین تکه تنظیم می‌کند و روی جا اعمال. برمی‌گرداند چه بهره‌ای خورد.
// اندازه‌گیریِ rms **پیش از** اعمال است، وگرنه حلقه خودش را دنبال می‌کرد.
- (float)applyGainTo:(int16_t *)p count:(NSUInteger)n {
    if (_gain <= 0) _gain = 1.0f;
    double acc = 0;
    for (NSUInteger i = 0; i < n; i++) {
        double v = p[i] / 32768.0;
        acc += v * v;
    }
    float rms = (float)sqrt(acc / MAX((NSUInteger)1, n));
    if (rms > kZGainGate) {
        _quietBlocks = 0;
        float want = MIN(kZGainMax, MAX(1.0f, kZGainTarget / rms));
        float k = want > _gain ? kZGainUp : kZGainDown;
        _gain += (want - _gain) * k;
    } else if (++_quietBlocks > kZGainQuietBlocks) {
        _gain += (1.0f - _gain) * kZGainRelax;
    }
    if (_gain <= 1.001f) return _gain;
    for (NSUInteger i = 0; i < n; i++) {
        float v = p[i] * _gain;
        // محدودکننده: بریدنِ سخت به‌جای پیچیدن. نادر است چون هدف rms خیلی زیر سقف است.
        p[i] = v > 32000.0f ? 32000 : (v < -32000.0f ? -32000 : (int16_t)v);
    }
    return _gain;
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
    // rms اینجا **بعد** از بهره است، یعنی همان چیزی که واقعا به گوگل می‌رسد. بهره هم
    // کنارش می‌آید تا معلوم باشد این عدد از خودِ میکروفن آمده یا از جبرانِ ما.
    ZLog(@"mic: rms %.4f peak %.3f gain %.1f×، %.1f ثانیه صدا%@",
         avg, _lvlPeak, _gainSum / _lvlCount, _lvlFrames / 16000.0,
         avg < 0.003 ? @"  ← تقریبا ساکت؛ میکروفن درست انتخاب شده؟" : @"");
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
