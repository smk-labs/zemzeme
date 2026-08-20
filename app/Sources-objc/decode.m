// هر فایل صدا/ویدیو به پی‌سی‌ام خام s16le مونو ۱۶ کیلوهرتز، تکه‌تکه.
// نه ffmpeg، نه کتابخانه‌ی تازه: خودِ macOS همه‌ی این‌ها را دیکد می‌کند، فقط از دو در
// مختلف، و همین‌جا هر دو در امتحان می‌شوند.
//
// در اول، AVAssetReader: ویدیو را هم دیمکس می‌کند (mp4/mov)، پس برای فایل تصویری
// همین لازم است. در دوم، ExtAudioFile از AudioToolbox: AVFoundation قالب Ogg و AMR
// را رد می‌کند ولی لایه‌ی پایین‌ترِ همان سیستم راحت بازشان می‌کند (`afconvert -hf`:
// 'Oggf' = Ogg (.opus/.ogg/.oga) با کدک‌های opus/vorbis/flac، و 'amrf' = AMR).
// یعنی وویس تلگرام (ogg/opus) و واتساپ (amr) بی‌هیچ تبدیل دستی کار می‌کنند.
#import "zemzeme.h"
#import <AudioToolbox/AudioToolbox.h>

// این دو تا واقعا در دسترس نیستند: کانتینر ویدیویی‌اند و macOS دیمکسرشان را ندارد.
// بقیه‌ی قالب‌های مرسوم (mp3، m4a، aac، wav، aiff، caf، flac، mp4، mov، ogg، opus،
// amr، 3gp، au) با یکی از دو در باز می‌شوند.
static NSArray<NSString *> *ZUnsupportedExts(void) {
    return @[@"mkv", @"webm"];
}

@implementation ZFileDecoder {
    AVAssetReader *_reader;
    AVAssetReaderTrackOutput *_out;
    ExtAudioFileRef _ext;          // در دوم؛ نال یعنی از در اول آمده‌ایم
    BOOL _done;
}

+ (BOOL)supportsPath:(NSString *)path {
    return ![ZUnsupportedExts() containsObject:path.pathExtension.lowercaseString];
}

// یک متن، دو فراخوان: صف رابط همان لحظه‌ی افزودن فایل نشانش می‌دهد و init هم همین را
// در NSError می‌گذارد. دو جا نوشتنش یعنی دو پیام که با هم جلو نمی‌روند.
+ (NSString *)unsupportedReason:(NSURL *)url {
    NSString *ext = url.path.pathExtension.lowercaseString;
    if (![ZUnsupportedExts() containsObject:ext]) return nil;
    return [NSString stringWithFormat:
            @"مک قالب .%@ را باز نمی‌کند. "
            @"اول به m4a یا wav تبدیلش کن.", ext];
}

- (instancetype)initWithURL:(NSURL *)url error:(NSError **)err {
    if (!(self = [super init])) return nil;
    NSString *why = [ZFileDecoder unsupportedReason:url];
    if (why) {
        if (err) *err = [NSError errorWithDomain:@"zemzeme.decode" code:10 userInfo:@{
            NSLocalizedDescriptionKey: why}];
        return nil;
    }
    if (![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
        if (err) *err = [NSError errorWithDomain:@"zemzeme.decode" code:11 userInfo:@{
            NSLocalizedDescriptionKey: @"فایل پیدا نشد"}];
        return nil;
    }

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    // بارگذاری آسنکرون است ولی اینجا هیچ نخ اصلی و رابطی در کار نیست، پس همان‌جا
    // منتظر می‌مانیم؛ نسخه‌ی همگام (tracksWithMediaType:) از macOS 15 منسوخ است.
    __block NSArray<AVAssetTrack *> *tracks = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [asset loadTracksWithMediaType:AVMediaTypeAudio
                completionHandler:^(NSArray<AVAssetTrack *> *t, NSError *e) {
        tracks = t;
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)));
    // در اول جواب نداد؟ برو در دوم. Ogg و AMR همیشه از این راه می‌آیند.
    if (!tracks.count) return [self openWithExtAudioFile:url error:err];
    _duration = CMTimeGetSeconds(asset.duration);
    if (!(_duration > 0)) {
        if (err) *err = [NSError errorWithDomain:@"zemzeme.decode" code:13 userInfo:@{
            NSLocalizedDescriptionKey: @"طول فایل خوانده نشد؛ احتمالا خراب است"}];
        return nil;
    }

    NSError *e = nil;
    _reader = [AVAssetReader assetReaderWithAsset:asset error:&e];
    if (!_reader) {
        if (err) *err = e ?: [NSError errorWithDomain:@"zemzeme.decode" code:14 userInfo:@{
            NSLocalizedDescriptionKey: @"فایل باز نشد"}];
        return nil;
    }
    // همان قالبی که استریم گوگل می‌خواهد؛ نمونه‌برداری و مونو کردن را خود ریدر می‌کند
    _out = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:tracks.firstObject
                                                     outputSettings:@{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVSampleRateKey: @16000,
        AVNumberOfChannelsKey: @1,
        AVLinearPCMBitDepthKey: @16,
        AVLinearPCMIsBigEndianKey: @NO,
        AVLinearPCMIsFloatKey: @NO,
        AVLinearPCMIsNonInterleaved: @NO,
    }];
    _out.alwaysCopiesSampleData = NO;
    if (![_reader canAddOutput:_out]) {
        if (err) *err = [NSError errorWithDomain:@"zemzeme.decode" code:15 userInfo:@{
            NSLocalizedDescriptionKey: @"صدای این فایل خوانده نمی‌شود؛ اول به m4a یا wav تبدیلش کن"}];
        return nil;
    }
    [_reader addOutput:_out];
    if (![_reader startReading]) {
        if (err) *err = _reader.error ?: [NSError errorWithDomain:@"zemzeme.decode" code:16 userInfo:@{
            NSLocalizedDescriptionKey: @"خواندن فایل شروع نشد"}];
        return nil;
    }
    return self;
}

// در دوم: ExtAudioFile خودش دیکد و نمونه‌برداری و مونو کردن را با هم انجام می‌دهد،
// پس فقط قالب مقصد را می‌گوییم و می‌خوانیم.
- (instancetype)openWithExtAudioFile:(NSURL *)url error:(NSError **)err {
    OSStatus st = ExtAudioFileOpenURL((__bridge CFURLRef)url, &_ext);
    if (st != noErr || !_ext) {
        if (err) *err = [NSError errorWithDomain:@"zemzeme.decode" code:20 userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:
                @"این فایل باز نشد (کد %d). مک قالبش را نمی‌شناسد یا فایل خراب است.",
                (int)st]}];
        return nil;
    }
    AudioStreamBasicDescription fileFmt = {0};
    UInt32 sz = sizeof(fileFmt);
    if (ExtAudioFileGetProperty(_ext, kExtAudioFileProperty_FileDataFormat, &sz, &fileFmt) != noErr
        || fileFmt.mSampleRate <= 0) {
        if (err) *err = [NSError errorWithDomain:@"zemzeme.decode" code:21 userInfo:@{
            NSLocalizedDescriptionKey: @"قالب صدای این فایل خوانده نشد"}];
        return nil;
    }
    SInt64 frames = 0;
    sz = sizeof(frames);
    ExtAudioFileGetProperty(_ext, kExtAudioFileProperty_FileLengthFrames, &sz, &frames);
    // فریم‌ها به نرخ خودِ فایل شمرده می‌شوند، نه نرخ مقصد
    _duration = frames > 0 ? frames / fileFmt.mSampleRate : 0;

    AudioStreamBasicDescription want = {
        .mSampleRate = 16000,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        .mBitsPerChannel = 16,
        .mChannelsPerFrame = 1,
        .mFramesPerPacket = 1,
        .mBytesPerFrame = 2,
        .mBytesPerPacket = 2,
    };
    if (ExtAudioFileSetProperty(_ext, kExtAudioFileProperty_ClientDataFormat,
                                sizeof(want), &want) != noErr) {
        if (err) *err = [NSError errorWithDomain:@"zemzeme.decode" code:22 userInfo:@{
            NSLocalizedDescriptionKey: @"صدای این فایل خوانده نمی‌شود؛ اول به m4a یا wav تبدیلش کن"}];
        return nil;
    }
    if (!(_duration > 0)) {
        if (err) *err = [NSError errorWithDomain:@"zemzeme.decode" code:23 userInfo:@{
            NSLocalizedDescriptionKey: @"طول فایل خوانده نشد؛ احتمالا خراب است"}];
        return nil;
    }
    return self;
}

- (NSData *)nextExtChunk:(NSError **)err {
    const UInt32 want = 16000;    // ۱ ثانیه در هر خواندن
    NSMutableData *d = [NSMutableData dataWithLength:want * 2];
    AudioBufferList abl = {
        .mNumberBuffers = 1,
        .mBuffers[0] = { .mNumberChannels = 1, .mDataByteSize = want * 2, .mData = d.mutableBytes },
    };
    UInt32 got = want;
    OSStatus st = ExtAudioFileRead(_ext, &got, &abl);
    if (st != noErr) {
        _done = YES;
        if (err) *err = [NSError errorWithDomain:@"zemzeme.decode" code:24 userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"خواندن فایل وسط کار قطع شد (کد %d)",
                                        (int)st]}];
        return nil;
    }
    if (got == 0) {
        _done = YES;
        return nil;
    }
    d.length = got * 2;
    return d;
}

// یک تکه (اندازه‌اش را خود ریدر تعیین می‌کند، معمولا چند ده کیلوبایت). نال یعنی
// پایان فایل یا خطا؛ *err فقط در حالت خطا پر می‌شود. کل فایل هیچ‌وقت در حافظه نمی‌آید.
- (NSData *)nextChunk:(NSError **)err {
    if (_done) return nil;
    if (_ext) return [self nextExtChunk:err];
    CMSampleBufferRef sb = [_out copyNextSampleBuffer];
    while (sb && !CMSampleBufferGetDataBuffer(sb)) {    // فریم خالی (مثلا مارکر): رد کن
        CFRelease(sb);
        sb = [_out copyNextSampleBuffer];
    }
    if (!sb) {
        _done = YES;
        if (_reader.status == AVAssetReaderStatusFailed && err) {
            *err = _reader.error ?: [NSError errorWithDomain:@"zemzeme.decode" code:17 userInfo:@{
                NSLocalizedDescriptionKey: @"خواندن فایل وسط کار قطع شد"}];
        }
        return nil;
    }
    CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
    size_t n = CMBlockBufferGetDataLength(bb);
    NSMutableData *d = [NSMutableData dataWithLength:n];
    OSStatus st = CMBlockBufferCopyDataBytes(bb, 0, n, d.mutableBytes);
    CFRelease(sb);
    if (st != kCMBlockBufferNoErr) {
        _done = YES;
        if (err) *err = [NSError errorWithDomain:@"zemzeme.decode" code:18 userInfo:@{
            NSLocalizedDescriptionKey: @"خواندن صدای فایل نشد"}];
        return nil;
    }
    return d;
}

- (void)cancel {
    _done = YES;
    [_reader cancelReading];
}

- (void)dealloc {
    if (_ext) ExtAudioFileDispose(_ext);
}

@end

// ---------- یک بازه از فایل ----------
// تکه‌ی در انتظار صدای خودش را ذخیره نمی‌کند: audio.flac همه‌ی نمونه‌ها را از قبل
// دارد و تکه فقط یک افست و یک طول است. این تابع همان بازه را برمی‌گرداند.
//
// و از **اول** فایل می‌خواند و تا رسیدن به افست دور می‌ریزد، به‌جای پرشِ واقعی. چرا:
// دو درِ دیکد دو جور پرش دارند (`ExtAudioFileSeek` در برابر `AVAssetReader`، که
// اصلا پرش ندارد و باید با یک بازه‌ی زمانیِ تازه از نو ساخته شود)، و هر کدام روی
// قالبی که خودش نمی‌گیرد رفتار دیگری دارد. سشنِ این اپ سقفِ پنج دقیقه دارد، یعنی
// بدترین حالتِ خواندن حدود ۹٫۶ مگابایت پی‌سی‌ام است و کسری از ثانیه طول می‌کشد؛
// هزینه‌اش در برابر یک مسیرِ پرشِ دوشاخه‌ی سخت‌آزمون، هیچ است.
NSData *ZDecodePCMRange(NSURL *url, unsigned long long frame, unsigned long long frames,
                        NSError **err) {
    if (!frames) return [NSData data];
    ZFileDecoder *d = [[ZFileDecoder alloc] initWithURL:url error:err];
    if (!d) return nil;
    const unsigned long long want = frames * 2, skip = frame * 2;   // s16le مونو
    NSMutableData *out = [NSMutableData dataWithCapacity:(NSUInteger)want];
    unsigned long long seen = 0;
    for (;;) {
        NSError *e = nil;
        NSData *c = [d nextChunk:&e];
        if (!c) {
            if (e) {
                if (err) *err = e;
                return nil;
            }
            break;      // پایان فایل
        }
        unsigned long long end = seen + c.length;
        if (end > skip) {
            unsigned long long from = seen > skip ? 0 : skip - seen;
            unsigned long long n = MIN((unsigned long long)c.length - from, want - out.length);
            [out appendBytes:(const uint8_t *)c.bytes + from length:(NSUInteger)n];
            if (out.length >= want) break;
        }
        seen = end;
    }
    // کوتاه‌تر از خواسته یعنی فایل به آن‌جا نرسیده. خطا نیست و نباید باشد: صدای سر
    // پایان با سکوت پر و فریم می‌شود، پس یکی دو فریمِ آخر می‌تواند کم بیاید. ولی
    // **هیچ** یعنی افست بیرون از فایل است و آن واقعا خراب است.
    if (!out.length) {
        if (err) *err = [NSError errorWithDomain:@"zemzeme.decode" code:19 userInfo:@{
            NSLocalizedDescriptionKey: @"این بازه در فایل صدا نیست"}];
        return nil;
    }
    return out;
}
