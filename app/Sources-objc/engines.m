// موتور اصلی گوگل (میکروفن + استریم + سوپروایزر) و موتور فال‌بک صفحه کروم.
#import "zemzeme.h"

// ---------- ZGoogleEngine ----------
// سوپروایزر همان سه پادزهر صفحه وب: backoff نمایی تا ۵ ثانیه، تسلیم بعد از
// ۸ چرخه بی‌نتیجه، واچ‌داگ ۱۲ ثانیه سکوت رویداد؛ به‌علاوه چرخش سشن قبل از سقف
// ~۵ دقیقه سرور و بافر صدا بین قطعی‌ها که چیزی گم نشود.
// چرخه بی‌صدا (سکوت کاربر) بی‌نتیجه حساب نمی‌شود تا در مکث طولانی تسلیم نشویم.

@implementation ZGoogleEngine {
    ZMic *_mic;
    BOOL _micRunning;
    ZGoogleStream *_stream;
    ZGoogleStream *_draining;   // سشن قبلی موقع چرخش: فقط final ازش قبول می‌شود
    NSString *_lang;
    BOOL _running;

    NSLock *_feedLock;
    ZGoogleStream *_feedTarget;
    NSMutableData *_preroll;
    BOOL _voiceInCycle;

    NSDate *_lastEventAt;
    NSInteger _endsSinceResult;
    BOOL _gotResultThisCycle;
    NSString *_lastInterim;
    NSTimer *_restartTimer;
    NSTimer *_watchdog;
    NSDate *_streamStartedAt;
    ZEngineState _lastState;
    NSDate *_lastLevelAt;
}

@synthesize delegate;

- (instancetype)init {
    if ((self = [super init])) {
        _mic = [ZMic new];
        _feedLock = [NSLock new];
        _preroll = [NSMutableData data];
        _lastInterim = @"";
        _lang = @"fa-IR";
        _lastLevelAt = NSDate.distantPast;
    }
    return self;
}

- (void)startWithLang:(NSString *)lang {
    if (_running) return;
    _lang = [lang copy];
    _running = YES;
    _endsSinceResult = 0;
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
            [s startMicAndStream];
        });
    }];
}

- (void)setLang:(NSString *)l {
    if ([l isEqualToString:_lang]) return;
    _lang = [l copy];
    if (!_running) return;
    [self salvage];
    _endsSinceResult = 0;
    [_stream cancel];    // مسیر close با زبان جدید ری‌استارت می‌کند
}

- (void)stop {
    BOOL was = _running;
    _running = NO;
    if (was) [self salvage];
    [_stream cancel];
    [_draining cancel];
    _stream = nil;
    _draining = nil;
    [_feedLock lock];
    _feedTarget = nil;
    _preroll.length = 0;
    [_feedLock unlock];
    [self stopMicAndTimers];
    [self state:ZEngineIdle msg:@""];
    if (was) ZLog(@"engine: stopped by user");
}

- (void)startMicAndStream {
    __weak typeof(self) ws = self;
    _mic.onChunk = ^(NSData *pcm) {
        __strong typeof(ws) s = ws;
        if (!s) return;
        [s->_feedLock lock];
        ZGoogleStream *t = s->_feedTarget;
        if (t) {
            [s->_feedLock unlock];
            [t feed:pcm];
        } else {
            [s->_preroll appendData:pcm];
            NSUInteger cap = 32000 * 10;    // سقف ۱۰ ثانیه
            if (s->_preroll.length > cap) {
                [s->_preroll replaceBytesInRange:NSMakeRange(0, s->_preroll.length - cap)
                                       withBytes:NULL length:0];
            }
            [s->_feedLock unlock];
        }
    };
    _mic.onLevel = ^(float rms) {
        __strong typeof(ws) s = ws;
        if (!s) return;
        if (rms > 0.07f) {
            [s->_feedLock lock];
            s->_voiceInCycle = YES;
            [s->_feedLock unlock];
        }
        NSDate *now = NSDate.date;
        if ([now timeIntervalSinceDate:s->_lastLevelAt] > 0.1) {
            s->_lastLevelAt = now;
            dispatch_async(dispatch_get_main_queue(), ^{ [s.delegate engineLevel:rms]; });
        }
    };
    if (!_micRunning) {
        NSError *err = nil;
        if (![_mic startWithError:&err]) {
            _running = NO;
            [self state:ZEngineGaveUp
                 msg:[NSString stringWithFormat:@"میکروفن راه نیفتاد: %@", err.localizedDescription ?: @"?"]];
            return;
        }
        _micRunning = YES;
    }
    [self openStream];
    [_watchdog invalidate];
    _watchdog = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *t) {
        [ws tick];
    }];
}

- (void)openStream {
    if (!_running) return;
    ZGoogleStream *s = [[ZGoogleStream alloc] initWithLang:_lang];
    _stream = s;
    _streamStartedAt = NSDate.date;
    _lastEventAt = NSDate.date;
    _gotResultThisCycle = NO;
    __weak typeof(self) ws = self;
    __weak ZGoogleStream *wstream = s;
    s.onEvent = ^(ZSpeechEvent *ev) {
        dispatch_async(dispatch_get_main_queue(), ^{ [ws handleEvent:ev from:wstream]; });
    };
    s.onClose = ^(NSString *reason) {
        dispatch_async(dispatch_get_main_queue(), ^{ [ws handleClose:reason from:wstream]; });
    };
    [s connect];
    [_feedLock lock];
    _feedTarget = s;
    _voiceInCycle = NO;
    NSData *pre = _preroll.length ? [_preroll copy] : nil;
    _preroll.length = 0;
    [_feedLock unlock];
    if (pre) [s feed:pre];
    ZLog(@"engine: stream open pair=%@ lang=%@ preroll=%luB", s.pair, _lang, (unsigned long)(pre.length));
}

- (void)handleEvent:(ZSpeechEvent *)ev from:(ZGoogleStream *)s {
    if (!s) return;
    if (s == _draining) {
        for (NSString *f in ev.finals) [self deliverFinal:f];
        return;
    }
    if (s != _stream) return;
    _lastEventAt = NSDate.date;
    if (_lastState != ZEngineListening) [self state:ZEngineListening msg:@""];
    if (ev.status > 0) ZLog(@"engine: server status %ld", (long)ev.status);

    if (ev.finals.count || ev.interim.length) {
        _gotResultThisCycle = YES;
        _endsSinceResult = 0;
    }
    for (NSString *f in ev.finals) {
        _lastInterim = @"";
        [self deliverFinal:f];
    }
    if (ev.finals.count || ![ev.interim isEqualToString:_lastInterim]) {
        _lastInterim = [ev.interim copy];
        [self.delegate engineInterim:_lastInterim];
    }
    if (ev.finals.count && [NSDate.date timeIntervalSinceDate:_streamStartedAt] > 240) {
        [self rotate];    // چرخش فرصت‌طلبانه سر مرز یک نتیجه قطعی
    }
}

- (void)handleClose:(NSString *)reason from:(ZGoogleStream *)s {
    if (s && s == _draining) {
        _draining = nil;
        ZLog(@"engine: drained pair=%@ (%@)", s.pair, reason);
        return;
    }
    if (!s || s != _stream) return;
    [_feedLock lock];
    if (_feedTarget == s) _feedTarget = nil;
    BOOL hadVoice = _voiceInCycle;
    [_feedLock unlock];
    _stream = nil;
    ZLog(@"engine: closed pair=%@ reason=%@ result=%d voice=%d", s.pair, reason, _gotResultThisCycle, hadVoice);
    [self salvage];
    if (!_running) return;
    if (hadVoice && !_gotResultThisCycle) _endsSinceResult++;
    [self scheduleRestart];
}

// متن خاکستری معلق را قبل از هر مرگ/ری‌استارت قطعی کن که هیچ‌وقت گم نشود
- (void)salvage {
    NSString *t = [_lastInterim stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    _lastInterim = @"";
    [self.delegate engineInterim:@""];
    if (!t.length) return;
    ZLog(@"engine: salvaged %lu chars", (unsigned long)t.length);
    [self deliverFinal:t];
}

- (void)scheduleRestart {
    if (!_running) return;
    if (_endsSinceResult >= 8) {
        _running = NO;
        [self stopMicAndTimers];
        [self state:ZEngineGaveUp msg:@"شبکه ناپایداره؛ برای تلاش دوباره دابل‌تپ کن"];
        ZLog(@"engine: gave up after %ld fruitless cycles", (long)_endsSinceResult);
        return;
    }
    if (_endsSinceResult >= 3) [self state:ZEngineReconnecting msg:@""];
    NSTimeInterval delay = MIN(0.3 * pow(2, MAX(0, (double)_endsSinceResult - 1)), 5.0);
    [_restartTimer invalidate];
    __weak typeof(self) ws = self;
    _restartTimer = [NSTimer scheduledTimerWithTimeInterval:delay repeats:NO block:^(NSTimer *t) {
        [ws openStream];
    }];
}

- (void)tick {
    if (!_running || !_stream) return;
    NSTimeInterval quiet = [NSDate.date timeIntervalSinceDate:_lastEventAt];
    NSTimeInterval age = [NSDate.date timeIntervalSinceDate:_streamStartedAt];
    if (quiet > 12) {
        ZLog(@"engine: watchdog quiet %.0fs, recycling pair=%@", quiet, _stream.pair);
        [self salvage];
        [_stream cancel];    // مسیر close ری‌استارت را می‌برد
        return;
    }
    if (age > 285) [self rotate];    // چرخش اجباری قبل از سقف سرور
}

- (void)rotate {
    if (!_running || !_stream) return;
    ZGoogleStream *old = _stream;
    ZLog(@"engine: rotate pair=%@ age=%.0fs", old.pair, [NSDate.date timeIntervalSinceDate:_streamStartedAt]);
    [_draining cancel];
    _draining = old;
    [old finishUpload];
    __weak typeof(self) ws = self;
    __weak ZGoogleStream *wold = old;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(ws) s = ws;
        __strong ZGoogleStream *o = wold;
        if (s && o && s->_draining == o) {
            [o cancel];
            s->_draining = nil;
        }
    });
    [self openStream];
}

- (void)deliverFinal:(NSString *)text {
    NSString *t = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!t.length) return;
    [self.delegate engineFinal:t];
}

- (void)stopMicAndTimers {
    if (_micRunning) {
        [_mic stop];
        _micRunning = NO;
    }
    [_watchdog invalidate];
    _watchdog = nil;
    [_restartTimer invalidate];
    _restartTimer = nil;
}

- (void)state:(ZEngineState)st msg:(NSString *)msg {
    _lastState = st;
    [self.delegate engineState:st message:msg];
}

@end

// ---------- ZChromeRelayEngine ----------
// موتور ۲ (فال‌بک): صفحه کروم موتور تشخیص می‌ماند؛ متن زنده از کانال SSE سرور
// لوکال (/events) می‌آید و فرمان‌ها با POST /live (kind=cmd) به صفحه می‌روند.
// اگر کلید Chromium مرد، با همین موتور محصول زنده می‌ماند.

static NSString *const kRelayBase = @"http://127.0.0.1:17635";

@interface ZChromeRelayEngine () <NSURLSessionDataDelegate>
@end

@implementation ZChromeRelayEngine {
    NSString *_lang;
    BOOL _running;
    NSURLSession *_session;
    NSURLSessionDataTask *_sseTask;
    NSMutableData *_sseBuf;
    NSTimer *_hbTimer;
    NSDate *_lastPageSeen;
}

@synthesize delegate;

- (instancetype)init {
    if ((self = [super init])) {
        _sseBuf = [NSMutableData data];
        _lastPageSeen = NSDate.distantPast;
        _lang = @"fa-IR";
    }
    return self;
}

- (void)startWithLang:(NSString *)lang {
    _lang = [lang copy];
    _running = YES;
    [self.delegate engineState:ZEngineConnecting message:@""];
    [self ensureServer:0];
}

- (void)setLang:(NSString *)l {
    _lang = [l copy];
    [self cmd:@{@"kind": @"cmd", @"cmd": @"lang", @"lang": l}];
}

- (void)stop {
    _running = NO;
    [self cmd:@{@"kind": @"cmd", @"cmd": @"stop"}];
    [_hbTimer invalidate];
    _hbTimer = nil;
    [_sseTask cancel];
    _sseTask = nil;
    [_session invalidateAndCancel];
    _session = nil;
    [self.delegate engineState:ZEngineIdle message:@""];
}

+ (BOOL)ping {
    __block BOOL ok = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.timeoutIntervalForRequest = 1;
    NSURLSession *s = [NSURLSession sessionWithConfiguration:cfg];
    [[s dataTaskWithURL:[NSURL URLWithString:[kRelayBase stringByAppendingString:@"/alive"]]
      completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        ok = [resp isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)resp).statusCode == 200;
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)));
    [s invalidateAndCancel];
    return ok;
}

+ (void)spawnServer {
    NSTask *p = [NSTask new];
    p.executableURL = [NSURL fileURLWithPath:@"/usr/bin/env"];
    p.arguments = @[@"python3", [ZRoot() URLByAppendingPathComponent:@"serve.py"].path];
    p.currentDirectoryURL = ZRoot();
    p.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    p.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSError *e = nil;
    if ([p launchAndReturnError:&e]) {
        ZLog(@"relay: spawned serve.py pid=%d", p.processIdentifier);
    } else {
        ZLog(@"relay: serve.py spawn failed: %@", e.localizedDescription);
    }
}

+ (void)openPage {
    if (![self ping]) [self spawnServer];
    NSTask *p = [NSTask new];
    p.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"];
    p.arguments = @[@"-g", @"-na", @"Google Chrome", @"--args",
                    [NSString stringWithFormat:@"--app=%@/?relay=1", kRelayBase]];
    [p launchAndReturnError:nil];
}

- (void)ensureServer:(NSInteger)attempt {
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if ([ZChromeRelayEngine ping]) {
            dispatch_async(dispatch_get_main_queue(), ^{ [ws serverReady]; });
            return;
        }
        if (attempt == 0) [ZChromeRelayEngine spawnServer];
        if (attempt >= 6) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(ws) s = ws;
                if (!s || !s->_running) return;
                [s.delegate engineState:ZEngineGaveUp
                                message:@"سرور لوکال بالا نیامد؛ serve.py را دستی اجرا کن"];
            });
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [ws ensureServer:attempt + 1];
        });
    });
}

- (void)serverReady {
    if (!_running) return;
    [self openSSE];
    [self cmd:@{@"kind": @"cmd", @"cmd": @"lang", @"lang": _lang}];
    [self cmd:@{@"kind": @"cmd", @"cmd": @"start"}];
    // اگر صفحه‌ای زنده نباشد، ضربان نمی‌آید و pageNeeded می‌شود
    [_hbTimer invalidate];
    __weak typeof(self) ws = self;
    _hbTimer = [NSTimer scheduledTimerWithTimeInterval:4 repeats:YES block:^(NSTimer *t) {
        __strong typeof(ws) s = ws;
        if (!s || !s->_running) return;
        if ([NSDate.date timeIntervalSinceDate:s->_lastPageSeen] > 12) {
            [s.delegate engineState:ZEnginePageNeeded message:@""];
        }
    }];
}

- (void)openSSE {
    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.defaultSessionConfiguration;
    cfg.timeoutIntervalForRequest = 3600;
    cfg.timeoutIntervalForResource = 24 * 3600;
    _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:[kRelayBase stringByAppendingString:@"/events"]]];
    [req setValue:@"text/event-stream" forHTTPHeaderField:@"Accept"];
    _sseTask = [_session dataTaskWithRequest:req];
    [_sseTask resume];
}

- (void)handleLine:(NSString *)line {
    if (![line hasPrefix:@"data: "]) return;
    NSData *d = [[line substringFromIndex:6] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    if (![obj isKindOfClass:NSDictionary.class]) return;
    NSString *kind = obj[@"kind"];
    if (![kind isKindOfClass:NSString.class]) return;
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(ws) s = ws;
        if (!s || !s->_running) return;
        s->_lastPageSeen = NSDate.date;
        if ([kind isEqualToString:@"interim"]) {
            NSString *t = [obj[@"text"] isKindOfClass:NSString.class] ? obj[@"text"] : @"";
            [s.delegate engineInterim:t];
            [s.delegate engineLevel:0.4f];
        } else if ([kind isEqualToString:@"final"]) {
            NSString *t = [obj[@"text"] isKindOfClass:NSString.class] ? obj[@"text"] : @"";
            if (t.length) [s.delegate engineFinal:t];
        } else if ([kind isEqualToString:@"state"]) {
            NSString *st = [obj[@"state"] isKindOfClass:NSString.class] ? obj[@"state"] : @"";
            if ([st isEqualToString:@"listening"]) {
                [s.delegate engineState:ZEngineListening message:@""];
            } else if ([st isEqualToString:@"reconnecting"]) {
                [s.delegate engineState:ZEngineReconnecting message:@""];
            } else if ([st isEqualToString:@"gaveup"]) {
                [s.delegate engineState:ZEngineGaveUp message:@"شبکه ناپایداره (صفحه کروم)؛ دوباره دابل‌تپ کن"];
            }
        } else if ([kind isEqualToString:@"hb"]) {
            NSNumber *listening = [obj[@"listening"] isKindOfClass:NSNumber.class] ? obj[@"listening"] : nil;
            if (listening && !listening.boolValue) {
                // صفحه زنده است ولی گوش نمی‌دهد؛ دوباره فرمان بده
                [s cmd:@{@"kind": @"cmd", @"cmd": @"start"}];
            }
        }
    });
}

- (void)cmd:(NSDictionary *)obj {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!d) return;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:[kRelayBase stringByAppendingString:@"/live"]]];
    req.HTTPMethod = @"POST";
    req.HTTPBody = d;
    req.timeoutInterval = 2;
    [[NSURLSession.sharedSession dataTaskWithRequest:req] resume];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    [_sseBuf appendData:data];
    while (YES) {
        const uint8_t *b = _sseBuf.bytes;
        NSUInteger nl = NSNotFound;
        for (NSUInteger i = 0; i < _sseBuf.length; i++) {
            if (b[i] == 0x0A) { nl = i; break; }
        }
        if (nl == NSNotFound) break;
        NSData *lineData = [_sseBuf subdataWithRange:NSMakeRange(0, nl)];
        [_sseBuf replaceBytesInRange:NSMakeRange(0, nl + 1) withBytes:NULL length:0];
        NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
        if (line) {
            [self handleLine:[line stringByTrimmingCharactersInSet:
                              NSCharacterSet.whitespaceAndNewlineCharacterSet]];
        }
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (!_running || task != _sseTask) return;
    ZLog(@"relay: sse dropped (%@), reopening", error.localizedDescription ?: @"eof");
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        __strong typeof(ws) s = ws;
        if (!s || !s->_running) return;
        [s openSSE];
    });
}

@end
