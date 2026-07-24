// یک جفت اتصال up/down به full-duplex گوگل با کلید عمومی Chromium.
// چرخه عمر: connect سپس feed(صدا)... سپس finishUpload یا cancel.
// onEvent روی صف دلیگیت NSURLSession صدا زده می‌شود؛ onClose دقیقا یک بار.
#import "zemzeme.h"

static NSString *const kKey = @"AIzaSyBOti4mM-6x9WDnZIjIeyEU21OpBXqWBgw";
static NSString *const kBase = @"https://www.google.com/speech-api/full-duplex/v1";

@interface ZGoogleStream () <NSURLSessionDataDelegate, NSStreamDelegate>
@end

@implementation ZGoogleStream {
    NSString *_lang;
    NSURLSession *_session;
    NSURLSessionUploadTask *_upTask;
    NSURLSessionDataTask *_downTask;

    NSLock *_lock;
    NSMutableData *_pending;     // صدای در انتظار ارسال
    BOOL _uploadDone;
    BOOL _cancelled;
    BOOL _closedOnce;

    NSOutputStream *_output;
    NSThread *_writerThread;
    BOOL _stopWriter;

    NSMutableData *_buf;         // بافر فریم‌های down (فقط روی صف دلیگیت)
    NSInteger _downHTTP;
}

- (instancetype)initWithLang:(NSString *)lang {
    if ((self = [super init])) {
        _lang = [lang copy];
        _lock = [NSLock new];
        _pending = [NSMutableData data];
        _buf = [NSMutableData data];
        NSMutableString *p = [NSMutableString string];
        for (int i = 0; i < 8; i++) [p appendFormat:@"%02x", arc4random_uniform(256)];
        _pair = p;
    }
    return self;
}

- (void)connect {
    NSString *up = [NSString stringWithFormat:
        @"%@/up?key=%@&pair=%@&lang=%@&client=chromium&continuous&interim&maxAlternatives=1&pFilter=0&output=pb",
        kBase, kKey, _pair, _lang];
    NSString *down = [NSString stringWithFormat:@"%@/down?key=%@&pair=%@&output=pb", kBase, kKey, _pair];

    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.defaultSessionConfiguration;
    cfg.timeoutIntervalForRequest = 25;    // سکوت طولانی‌تر را واچ‌داگ موتور زودتر می‌کشد
    cfg.timeoutIntervalForResource = 600;
    _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];

    _downTask = [_session dataTaskWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:down]]];
    [_downTask resume];

    NSMutableURLRequest *ureq = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:up]];
    ureq.HTTPMethod = @"POST";
    [ureq setValue:@"audio/l16; rate=16000" forHTTPHeaderField:@"Content-Type"];
    _upTask = [_session uploadTaskWithStreamedRequest:ureq];
    [_upTask resume];
}

- (void)feed:(NSData *)pcm {
    [_lock lock];
    if (_uploadDone || _cancelled) {
        [_lock unlock];
        return;
    }
    [_pending appendData:pcm];
    [_lock unlock];
    [self nudgeWriter];
}

- (void)finishUpload {
    [_lock lock];
    _uploadDone = YES;
    [_lock unlock];
    [self nudgeWriter];
}

- (void)cancel {
    [_lock lock];
    _cancelled = YES;
    _uploadDone = YES;
    [_lock unlock];
    [self nudgeWriter];
    [_upTask cancel];
    [_downTask cancel];
}

// ---------- نخ نویسنده (بدنه استریمی up) ----------

- (void)nudgeWriter {
    NSThread *t = _writerThread;
    if (t && !t.isFinished) {
        [self performSelector:@selector(drainNow) onThread:t withObject:nil waitUntilDone:NO];
    }
}

- (void)drainNow {
    [self drain];
}

// فقط روی نخ writer
- (void)drain {
    NSOutputStream *o = _output;
    if (!o) return;
    while (o.hasSpaceAvailable) {
        [_lock lock];
        if (_pending.length == 0) {
            BOOL done = _uploadDone;
            [_lock unlock];
            if (done) [self closeOutput];
            return;
        }
        NSUInteger n = MIN(_pending.length, (NSUInteger)16384);
        NSData *chunk = [_pending subdataWithRange:NSMakeRange(0, n)];
        [_lock unlock];
        NSInteger written = [o write:chunk.bytes maxLength:chunk.length];
        if (written < 0) {
            [self closeOutput];
            return;
        }
        [_lock lock];
        [_pending replaceBytesInRange:NSMakeRange(0, (NSUInteger)written) withBytes:NULL length:0];
        [_lock unlock];
    }
}

- (void)closeOutput {
    NSOutputStream *o = _output;
    if (!o) return;
    [o close];
    [o removeFromRunLoop:NSRunLoop.currentRunLoop forMode:NSDefaultRunLoopMode];
    o.delegate = nil;
    _output = nil;
    _stopWriter = YES;
}

- (void)writerMain:(NSOutputStream *)o {
    o.delegate = self;
    [o scheduleInRunLoop:NSRunLoop.currentRunLoop forMode:NSDefaultRunLoopMode];
    [o open];
    while (!_stopWriter &&
           [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:NSDate.distantFuture]) {
    }
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    if (aStream != _output) return;
    if (eventCode == NSStreamEventHasSpaceAvailable) {
        [self drain];
    } else if (eventCode == NSStreamEventErrorOccurred || eventCode == NSStreamEventEndEncountered) {
        [self closeOutput];
    }
}

// ---------- بستن یک‌باره ----------

- (void)reportClose:(NSString *)reason {
    [_lock lock];
    BOOL already = _closedOnce;
    _closedOnce = YES;
    [_lock unlock];
    if (already) return;
    [_session finishTasksAndInvalidate];
    if (self.onClose) self.onClose(reason);
}

// ---------- NSURLSession ----------

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 needNewBodyStream:(void (^)(NSInputStream *))completionHandler {
    NSInputStream *input = nil;
    NSOutputStream *output = nil;
    [NSStream getBoundStreamsWithBufferSize:65536 inputStream:&input outputStream:&output];
    if (!output) {
        completionHandler(nil);
        return;
    }
    _output = output;
    _stopWriter = NO;
    NSThread *t = [[NSThread alloc] initWithTarget:self selector:@selector(writerMain:) object:output];
    t.name = [@"zemzeme.up.writer." stringByAppendingString:_pair];
    _writerThread = t;
    [t start];
    completionHandler(input);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    if (dataTask == _downTask && [response isKindOfClass:NSHTTPURLResponse.class]) {
        _downHTTP = ((NSHTTPURLResponse *)response).statusCode;
        if (_downHTTP != 200) ZLog(@"stream %@ down http %ld", _pair, (long)_downHTTP);
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    if (dataTask != _downTask) return;
    [_buf appendData:data];
    NSUInteger off = 0;
    const uint8_t *b = _buf.bytes;
    while (_buf.length - off >= 4) {
        NSUInteger len = ((NSUInteger)b[off] << 24) | ((NSUInteger)b[off + 1] << 16)
                       | ((NSUInteger)b[off + 2] << 8) | b[off + 3];
        if (len > 1000000) {
            ZLog(@"stream %@ framing error len=%lu", _pair, (unsigned long)len);
            [self cancel];
            return;
        }
        if (_buf.length - off - 4 < len) break;
        NSData *body = [_buf subdataWithRange:NSMakeRange(off + 4, len)];
        off += 4 + len;
        if (self.onEvent) self.onEvent(ZProtoDecodeEvent(body));
    }
    if (off > 0) [_buf replaceBytesInRange:NSMakeRange(0, off) withBytes:NULL length:0];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    NSString *reason = @"ok";
    if (error) {
        reason = error.code == NSURLErrorCancelled
            ? @"cancelled"
            : [NSString stringWithFormat:@"err %ld %@", (long)error.code, error.localizedDescription];
    } else if ([task.response isKindOfClass:NSHTTPURLResponse.class]
               && ((NSHTTPURLResponse *)task.response).statusCode != 200) {
        reason = [NSString stringWithFormat:@"%@ http %ld", task == _upTask ? @"up" : @"down",
                  (long)((NSHTTPURLResponse *)task.response).statusCode];
    } else if (task == _upTask) {
        return;    // پایان عادی آپلود؛ صبر برای نتیجه‌های آخر down
    }
    [self reportClose:reason];
}

@end
