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
}

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

    const int16_t *p = out.int16ChannelData[0];
    NSUInteger n = out.frameLength;
    NSData *data = [NSData dataWithBytes:p length:n * 2];

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
    [self noteLevel:rms peak:peak frames:n];
    if (self.onChunk) self.onChunk(data);
}

// خلاصه‌ی بلندی صدا، هر ده ثانیه یک خط. سه عدد و هر سه لازم‌اند: rms می‌گوید
// به‌طور متوسط چقدر صدا هست، peak می‌گوید بلندترین لحظه چقدر بوده (rms پایین با
// peak بالا یعنی صدا هست ولی کم و دور)، و ثانیه می‌گوید اصلا چقدر صدا رسیده.
// rms نزدیک صفر یعنی میکروفن ساکت است، هرچه بایت به گوگل برود.
- (void)noteLevel:(float)rms peak:(float)peak frames:(NSUInteger)frames {
    _lvlSum += (double)rms * rms;
    _lvlPeak = MAX(_lvlPeak, peak);
    _lvlCount++;
    _lvlFrames += frames;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - _lvlAt < 10.0 || !_lvlCount) return;
    double avg = sqrt(_lvlSum / _lvlCount);
    ZLog(@"mic: rms %.4f peak %.3f، %.1f ثانیه صدا%@",
         avg, _lvlPeak, _lvlFrames / 16000.0,
         avg < 0.003 ? @"  ← تقریبا ساکت؛ میکروفن درست انتخاب شده؟" : @"");
    _lvlSum = 0;
    _lvlPeak = 0;
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
