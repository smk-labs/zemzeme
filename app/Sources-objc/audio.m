// میکروفن به PCM خام: s16le مونو ۱۶ کیلوهرتز، تکه‌های حدودا ۱۰۰ میلی‌ثانیه.
// کال‌بک‌ها روی نخ صدا صدا زده می‌شوند.
#import "zemzeme.h"

@implementation ZMic {
    AVAudioEngine *_engine;
    AVAudioConverter *_converter;
    AVAudioFormat *_outFormat;
    BOOL _started;
    id _observer;
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

    // تعویض دستگاه صدا (هدست وصل/قطع): تپ را از نو بچین
    __weak typeof(self) ws = self;
    _observer = [NSNotificationCenter.defaultCenter
        addObserverForName:AVAudioEngineConfigurationChangeNotification object:_engine queue:nil
                usingBlock:^(NSNotification *n) {
        __strong typeof(ws) s = ws;
        if (!s || !s->_started) return;
        ZLog(@"mic: configuration change, restarting tap");
        [s->_engine.inputNode removeTapOnBus:0];
        AVAudioFormat *f = [s->_engine.inputNode inputFormatForBus:0];
        if (f.sampleRate <= 0) return;
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

    // RMS تقریبی با نمونه‌برداری هر هشتم، برای نقطه ضربان
    float acc = 0;
    NSUInteger cnt = 0;
    for (NSUInteger i = 0; i < n; i += 8) {
        float v = p[i] / 32768.0f;
        acc += v * v;
        cnt++;
    }
    if (self.onLevel) self.onLevel(MIN(1.0f, sqrtf(acc / MAX(1u, (unsigned)cnt)) * 5));
    if (self.onChunk) self.onChunk(data);
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
