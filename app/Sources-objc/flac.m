// فشرده‌سازی آپلود: پی‌سی‌ام خام s16le مونو ۱۶ کیلوهرتز -> فریم‌های FLAC با
// AudioConverter سیستم (بدون هیچ کتابخانه‌ی بیرونی). چرا FLAC؟ همانی‌ست که خود
// کروم به همین سرور می‌فرستد؛ روی گفتار معمولا ۴۵-۶۰٪ حجم خام می‌شود.
// اگر AudioConverterNew این‌جا شکست بخورد (بستر بدون این codec)، init نال
// برمی‌گرداند و ZGoogleStream باید بی‌سروصدا به l16 خام برگردد (شیر اطمینان).
//
// دو کشف رفتاری با تست واقعی (نه مستندات، که این‌جا گمراه‌کننده‌اند):
// ۱) برگرداندن صفر پکت از input proc را این کدک «پایان قطعی جریان» می‌فهمد، نه
//    «فعلا صدا نیست، بعدا دوباره بپرس»؛ یک بار صفر برگردانی، دیگر هیچ‌وقت input
//    proc دوباره صدا زده نمی‌شود. برای همین کانورتر را «امتحانی» صدا نمی‌زنیم؛
//    فقط وقتی _inBuf به‌اندازه‌ی حداقل یک بلاک کامل رسیده و دقیقا به تعداد
//    بلاک‌های کاملی که مطمئنیم موجودند درخواست می‌دهیم.
// ۲) با همین‌هم، این کدک هر ~۲ فراخوانی موفق یک بار AudioConverterFillComplexBuffer
//    را بدون خطای واقعی صفر پکت برمی‌گرداند (احتمالا صف داخلی کوچک‌شمار خودش را
//    پر می‌کند)؛ AudioConverterReset فورا حلش می‌کند و فراخوانی بعدی باز جواب
//    می‌دهد. Reset را فقط بعد از شکست صدا می‌زنیم و فقط یک‌بار retry می‌کنیم؛
//    Reset کردن بعد از هر موفقیت (پروآکتیو) در تست واقعی قفل کرد (کانورتر
//    هنگ کرد)، پس فقط reactive/on-failure درست است.
#import "zemzeme.h"
#import <AudioToolbox/AudioToolbox.h>

#define kZFlacReqPackets 8

@implementation ZFlacEncoder {
    AudioConverterRef _conv;
    NSMutableData *_inBuf;      // پی‌سی‌ام در انتظار حداقل یک بلاک کامل FLAC
    NSUInteger _cursor;         // چقدر از _inBuf همین الان به کانورتر پیشنهاد شده
    UInt32 _blockSize;          // فریم/بلاک: چند نمونه لازم است برای یک پکت خروجی
    void *_outBuf;
    UInt32 _maxOutPacketSize;
    AudioStreamPacketDescription _pktDesc[kZFlacReqPackets];
    NSData *_streamHeader;
}

- (instancetype)init {
    if ((self = [super init])) {
        AudioStreamBasicDescription inFmt;
        bzero(&inFmt, sizeof(inFmt));
        inFmt.mSampleRate = 16000;
        inFmt.mFormatID = kAudioFormatLinearPCM;
        inFmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        inFmt.mBitsPerChannel = 16;
        inFmt.mChannelsPerFrame = 1;
        inFmt.mFramesPerPacket = 1;
        inFmt.mBytesPerFrame = 2;
        inFmt.mBytesPerPacket = 2;

        AudioStreamBasicDescription outFmt;
        bzero(&outFmt, sizeof(outFmt));
        outFmt.mFormatID = kAudioFormatFLAC;
        outFmt.mSampleRate = 16000;
        outFmt.mChannelsPerFrame = 1;
        UInt32 sz = sizeof(outFmt);
        if (AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &sz, &outFmt) != noErr) {
            return nil;
        }

        if (AudioConverterNew(&inFmt, &outFmt, &_conv) != noErr || !_conv) return nil;

        AudioStreamBasicDescription actual;
        bzero(&actual, sizeof(actual));
        UInt32 asz = sizeof(actual);
        if (AudioConverterGetProperty(_conv, kAudioConverterCurrentOutputStreamDescription, &asz, &actual) != noErr
            || actual.mFramesPerPacket == 0) {
            AudioConverterDispose(_conv);
            _conv = NULL;
            return nil;
        }
        _blockSize = actual.mFramesPerPacket;

        UInt32 msz = sizeof(_maxOutPacketSize);
        if (AudioConverterGetProperty(_conv, kAudioConverterPropertyMaximumOutputPacketSize, &msz, &_maxOutPacketSize)
                != noErr
            || _maxOutPacketSize == 0) {
            _maxOutPacketSize = 8192;    // سقف امن اگر پرسیدنش شکست خورد
        }
        _outBuf = malloc((size_t)kZFlacReqPackets * _maxOutPacketSize);
        if (!_outBuf) {
            AudioConverterDispose(_conv);
            _conv = NULL;
            return nil;
        }
        _inBuf = [NSMutableData data];
        _streamHeader = [self buildStreamHeaderWithBlockSize:_blockSize];
    }
    return self;
}

- (void)dealloc {
    if (_conv) AudioConverterDispose(_conv);
    if (_outBuf) free(_outBuf);
}

- (NSData *)streamHeader { return _streamHeader; }
- (UInt32)blockFrames { return _blockSize; }

// "fLaC" + یک بلاک متادیتای STREAMINFO (۳۴ بایت، طبق اسپک FLAC). چون استریم زنده
// است min/max frame size و total_samples را «نامعلوم» (صفر) می‌گذاریم؛ هر دوی
// این‌ها طبق اسپک برای مقدار ۰ مجازند. min=max blocksize همان چیزی‌ست که خود
// AudioConverter انتخاب کرده (kAudioConverterCurrentOutputStreamDescription).
- (NSData *)buildStreamHeaderWithBlockSize:(UInt32)blockSize {
    uint8_t h[42];
    memcpy(h, "fLaC", 4);
    h[4] = 0x80;         // last-metadata-block=1، type=0 (STREAMINFO)
    h[5] = 0; h[6] = 0; h[7] = 34;    // طول بلاک: ۳۴ بایت (۲۴ بیتی big-endian)

    uint8_t *p = h + 8;
    p[0] = (uint8_t)((blockSize >> 8) & 0xFF); p[1] = (uint8_t)(blockSize & 0xFF);   // min blocksize
    p[2] = (uint8_t)((blockSize >> 8) & 0xFF); p[3] = (uint8_t)(blockSize & 0xFF);   // max blocksize
    p[4] = 0; p[5] = 0; p[6] = 0;    // min frame size: نامعلوم
    p[7] = 0; p[8] = 0; p[9] = 0;    // max frame size: نامعلوم

    // ۶۴ بیت بعدی: sample_rate(20) | channels-1(3) | bits_per_sample-1(5) | total_samples(36)
    uint64_t chunk = (((uint64_t)16000 & 0xFFFFFULL) << 44)
                    | (((uint64_t)0 & 0x7ULL) << 41)             // channels-1 = 1-1 = 0
                    | (((uint64_t)15 & 0x1FULL) << 36)           // bits_per_sample-1 = 16-1 = 15
                    | ((uint64_t)0 & 0xFFFFFFFFFULL);            // total_samples: نامعلوم (زنده)
    for (int i = 0; i < 8; i++) p[10 + i] = (uint8_t)(chunk >> (56 - i * 8));
    bzero(p + 18, 16);    // md5: نامعلوم

    return [NSData dataWithBytes:h length:sizeof(h)];
}

static OSStatus ZFlacInputProc(AudioConverterRef inConv, UInt32 *ioNumberDataPackets,
                                AudioBufferList *ioData, AudioStreamPacketDescription **outDesc,
                                void *inUserData) {
    ZFlacEncoder *enc = (__bridge ZFlacEncoder *)inUserData;
    return [enc supplyInput:ioNumberDataPackets bufferList:ioData];
}

// طبق قرارداد AudioConverterComplexInputDataProc: هرچه از طریق ioNumberDataPackets
// پیشنهاد بدهیم «مصرف‌شده» حساب می‌شود؛ پس هر بار از _cursor به بعد (نه از صفر)
// عرضه می‌کنیم و _cursor را جلو می‌بریم. encode: تضمین می‌کند قبل از صدا زدن
// کانورتر همیشه به‌اندازه‌ی کافی در _inBuf هست، پس اینجا هرگز نباید به صفر برسیم.
- (OSStatus)supplyInput:(UInt32 *)ioNumberDataPackets bufferList:(AudioBufferList *)ioData {
    NSUInteger availFrames = (_inBuf.length - _cursor) / 2;
    NSUInteger offer = MIN(availFrames, (NSUInteger)(*ioNumberDataPackets ? *ioNumberDataPackets : availFrames));
    ioData->mNumberBuffers = 1;
    ioData->mBuffers[0].mNumberChannels = 1;
    ioData->mBuffers[0].mData = (uint8_t *)_inBuf.mutableBytes + _cursor;
    ioData->mBuffers[0].mDataByteSize = (UInt32)(offer * 2);
    *ioNumberDataPackets = (UInt32)offer;
    _cursor += offer * 2;
    return noErr;
}

// یک تلاش خام: دقیقا count بلاک از _inBuf (که فراخوان تضمین کرده موجود است)
// می‌خواهد. نتیجه را در result اضافه می‌کند و true برمی‌گرداند اگر پکتی گرفت.
- (BOOL)fillOnce:(UInt32)count intoResult:(NSMutableData *)result {
    _cursor = 0;
    AudioBufferList abl;
    abl.mNumberBuffers = 1;
    abl.mBuffers[0].mNumberChannels = 1;
    abl.mBuffers[0].mData = _outBuf;
    abl.mBuffers[0].mDataByteSize = (UInt32)((NSUInteger)kZFlacReqPackets * _maxOutPacketSize);
    bzero(_pktDesc, sizeof(_pktDesc));
    AudioConverterFillComplexBuffer(_conv, ZFlacInputProc, (__bridge void *)self, &count, &abl, _pktDesc);
    if (count == 0) return NO;
    const uint8_t *base = (const uint8_t *)_outBuf;
    for (UInt32 i = 0; i < count; i++) {
        [result appendBytes:base + _pktDesc[i].mStartOffset length:_pktDesc[i].mDataByteSize];
    }
    return YES;
}

- (NSData *)encode:(NSData *)pcm {
    if (pcm.length) [_inBuf appendData:pcm];
    NSMutableData *result = [NSMutableData data];

    // فقط وقتی کانورتر را صدا بزن که مطمئنیم حداقل یک بلاک کامل موجود است، و دقیقا
    // به تعداد بلاک‌های کاملی که همین الان داریم درخواست بده (نه بیشتر).
    NSUInteger availFrames = _inBuf.length / 2;
    NSUInteger blocksAvail = _blockSize ? availFrames / _blockSize : 0;
    if (blocksAvail == 0) return result;
    UInt32 count = (UInt32)MIN(blocksAvail, (NSUInteger)kZFlacReqPackets);

    if (![self fillOnce:count intoResult:result]) {
        // این کدک هر چند فراخوان موفق یک‌بار صفر برمی‌گرداند بدون خطای واقعی؛
        // AudioConverterReset فورا جانش می‌دهد. فقط reactive و فقط یک retry
        // (retry نامحدود یا reset پیش‌گیرانه‌ی بعد از هر موفقیت در عمل قفل کرد).
        NSUInteger before = _cursor;
        AudioConverterReset(_conv);
        if (![self fillOnce:count intoResult:result]) {
            // **هر دو تلاش شکست خورد.** تا امروز `_cursor` که در supplyInput جلو
            // رفته بود همان پایین بی‌قیدوشرط از بافر بریده می‌شد، پس همان صدا نه
            // کد می‌شد، نه فرستاده می‌شد، و نه حتی یک خط لاگ می‌داد. با تکه‌های
            // ۱۶ کیلوبایتی یعنی تا نیم ثانیه حرف، بی‌صدا، وسط جمله.
            // حالا آنچه واقعا مصرف نشده سر جایش می‌ماند تا دور بعد دوباره امتحان شود.
            if (_cursor > before) _cursor = before;
            ZLog(@"flac: هر دو تلاش کدک شکست خورد، %lu بایت صدا نگه داشته شد",
                 (unsigned long)(_inBuf.length - _cursor));
        }
    }

    if (_cursor > 0) {
        [_inBuf replaceBytesInRange:NSMakeRange(0, _cursor) withBytes:NULL length:0];
        _cursor = 0;
    }
    return result;
}

@end
