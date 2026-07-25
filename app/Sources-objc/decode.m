// هر فایل صدا/ویدیو به پی‌سی‌ام خام s16le مونو ۱۶ کیلوهرتز، تکه‌تکه.
// از AVAssetReader سیستم استفاده می‌کند، پس نه ffmpeg لازم است نه کتابخانه‌ی تازه؛
// در عوض هر چه macOS دیمکس نمی‌کند (ogg/opus/mkv/webm) هم اینجا در دسترس نیست و
// همان اول با پیام روشن رد می‌شود، نه با یک خطای گنگ در میانه کار.
#import "zemzeme.h"

// فقط دیمکسر مهم است نه کدک: mp3/m4a/aac/wav/aiff/caf/mp4/mov/flac همه با
// AVFoundation باز می‌شوند. این‌ها لیست سیاه‌اند چون هیچ‌وقت باز نمی‌شوند.
static NSArray<NSString *> *ZUnsupportedExts(void) {
    return @[@"ogg", @"oga", @"opus", @"mkv", @"webm"];
}

@implementation ZFileDecoder {
    AVAssetReader *_reader;
    AVAssetReaderTrackOutput *_out;
    BOOL _done;
}

+ (BOOL)supportsPath:(NSString *)path {
    return ![ZUnsupportedExts() containsObject:path.pathExtension.lowercaseString];
}

- (instancetype)initWithURL:(NSURL *)url error:(NSError **)err {
    if (!(self = [super init])) return nil;
    NSString *ext = url.path.pathExtension.lowercaseString;
    if ([ZUnsupportedExts() containsObject:ext]) {
        if (err) *err = [NSError errorWithDomain:@"zemzeme.decode" code:10 userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:
                @"قالب .%@ را macOS باز نمی‌کند (دیمکسری برایش ندارد). "
                @"اول به m4a یا wav تبدیلش کن.", ext]}];
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
    if (!tracks.count) {
        if (err) *err = [NSError errorWithDomain:@"zemzeme.decode" code:12 userInfo:@{
            NSLocalizedDescriptionKey: @"این فایل باند صدا ندارد"}];
        return nil;
    }
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
            NSLocalizedDescriptionKey: @"کدک این فایل به پی‌سی‌ام تبدیل نمی‌شود"}];
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

// یک تکه (اندازه‌اش را خود ریدر تعیین می‌کند، معمولا چند ده کیلوبایت). نال یعنی
// پایان فایل یا خطا؛ *err فقط در حالت خطا پر می‌شود. کل فایل هیچ‌وقت در حافظه نمی‌آید.
- (NSData *)nextChunk:(NSError **)err {
    if (_done) return nil;
    CMSampleBufferRef sb = [_out copyNextSampleBuffer];
    while (sb && !CMSampleBufferGetDataBuffer(sb)) {    // فریم خالی (مثلا مارکر): رد کن
        CFRelease(sb);
        sb = [_out copyNextSampleBuffer];
    }
    if (!sb) {
        _done = YES;
        if (_reader.status == AVAssetReaderStatusFailed && err) {
            *err = _reader.error ?: [NSError errorWithDomain:@"zemzeme.decode" code:17 userInfo:@{
                NSLocalizedDescriptionKey: @"دیکد وسط فایل شکست"}];
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
            NSLocalizedDescriptionKey: @"کپی نمونه‌های صدا شکست"}];
        return nil;
    }
    return d;
}

- (void)cancel {
    _done = YES;
    [_reader cancelReading];
}

@end
