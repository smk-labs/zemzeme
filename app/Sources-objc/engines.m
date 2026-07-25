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
    NSMutableData *_replay;      // صدای بعد از آخرین نتیجه؛ سر هر ری‌استارت دوباره پخش می‌شود
    BOOL _voiceInCycle;

    NSDate *_lastEventAt;
    NSDate *_lastResultAt;       // آخرین فریمِ نتیجه‌دار، نه هر فریمی
    NSTimeInterval _voiceSinceResult;   // جمع ثانیه‌های صدای واقعی از آخرین نتیجه
    NSDate *_prevLevelAt;        // برای اندازه‌گیری همان جمع
    NSDate *_stallGraceUntil;    // تا این لحظه استریمِ تازه متهم به گیر کردن نمی‌شود
    NSString *_drainCarry;       // متن معلقِ سر چرخش، اگر سشن قدیمی final نداد
    BOOL _drainGotFinal;
    NSInteger _endsSinceResult;
    BOOL _gotResultThisCycle;
    NSString *_lastInterim;
    NSString *_salvageBest;      // بلندترین interim از آخرین final؛ بیمه پنجره لغزان گوگل
    NSTimer *_restartTimer;
    NSTimer *_watchdog;
    NSDate *_streamStartedAt;
    ZEngineState _lastState;
    NSDate *_lastLevelAt;
    NSDate *_lastChunkAt;        // واچ‌داگ میکروفن مرده
    NSInteger _micRetries;
    BOOL _paused;

    NSDate *_lastRateLogAt;              // برای لاگ دوره‌ای نرخ آپلود
    unsigned long long _lastRateLogBytes;
}

@synthesize delegate;
@synthesize paused = _paused;

// ادغام دو interim با هم‌پوشانی توکنی: گوگل گاهی پیشوند تثبیت‌شده را از interim های
// بعدی می‌اندازد؛ موقع نجات، بلندترین نسخه با دم فعلی ادغام می‌شود که کلمه‌ای گم نشود.
static NSString *ZMergeInterim(NSString *best, NSString *cur) {
    best = [best stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    cur = [cur stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!best.length) return cur;
    if (!cur.length) return best;
    if ([best containsString:cur]) return best;
    NSArray *a = [best componentsSeparatedByString:@" "];
    NSArray *b = [cur componentsSeparatedByString:@" "];
    NSUInteger maxK = MIN(a.count, b.count);
    for (NSUInteger k = maxK; k > 0; k--) {
        NSArray *tailA = [a subarrayWithRange:NSMakeRange(a.count - k, k)];
        NSArray *headB = [b subarrayWithRange:NSMakeRange(0, k)];
        if ([tailA isEqualToArray:headB]) {
            NSArray *rest = [b subarrayWithRange:NSMakeRange(k, b.count - k)];
            return rest.count
                ? [best stringByAppendingFormat:@" %@", [rest componentsJoinedByString:@" "]]
                : best;
        }
    }
    return [NSString stringWithFormat:@"%@ %@", best, cur];
}

- (instancetype)init {
    if ((self = [super init])) {
        _mic = [ZMic new];
        _feedLock = [NSLock new];
        _replay = [NSMutableData data];
        _lastInterim = @"";
        _salvageBest = @"";
        _lang = @"fa-IR";
        _lastLevelAt = NSDate.distantPast;
        _voiceSinceResult = 0;
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

// مکث: شنیدن می‌ایستد، میکروفن گرم می‌ماند که ادامه آنی باشد
- (void)pause {
    if (!_running || _paused) return;
    _paused = YES;
    [self salvage];
    [_stream cancel];    // مسیر close با گارد paused ری‌استارت نمی‌کند
    [self state:ZEnginePaused msg:@""];
    ZLog(@"engine: paused");
}

- (void)resume {
    if (!_running || !_paused) return;
    _paused = NO;
    _endsSinceResult = 0;
    _lastChunkAt = NSDate.date;
    [self state:ZEngineConnecting msg:@""];
    [self openStream];
    ZLog(@"engine: resumed");
}

- (void)stop {
    BOOL was = _running;
    _running = NO;
    _paused = NO;
    if (was) [self salvage];
    [_stream cancel];
    [_draining cancel];
    _stream = nil;
    _draining = nil;
    [_feedLock lock];
    _feedTarget = nil;
    _replay.length = 0;
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
        s->_lastChunkAt = NSDate.date;
        s->_micRetries = 0;
        if (s->_paused) return;    // در مکث، صدا دور ریخته می‌شود (بافر هم نه)
        // هر تکه هم به استریم می‌رود هم در بافر بازپخش می‌ماند تا اولین نتیجه برسد.
        // قبلا فقط صدای «هنوز روی سیم نرفته» نگه داشته می‌شد، که موقع گیر کردن سرور
        // همیشه خالی بود (سیم سالم بود، سرور جواب نمی‌داد)، پس همان حرف‌ها گم می‌شدند.
        [s->_feedLock lock];
        [s->_replay appendData:pcm];
        if (s->_replay.length > kZReplayCapBytes) {
            [s->_replay replaceBytesInRange:NSMakeRange(0, s->_replay.length - kZReplayCapBytes)
                                  withBytes:NULL length:0];
        }
        ZGoogleStream *t = s->_feedTarget;
        [s->_feedLock unlock];
        if (t) [t feed:pcm];
    };
    _mic.onLevel = ^(float rms) {
        __strong typeof(ws) s = ws;
        if (!s) return;
        if (rms > 0.07f) {
            [s->_feedLock lock];
            s->_voiceInCycle = YES;
            // جمع زمان صدای واقعی. سقف ۰٫۵ ثانیه روی هر گام، که بعد از یک وقفه‌ی
            // طولانی یک‌باره پر نشود و مکث را صدا حساب نکند.
            NSDate *n = NSDate.date;
            NSTimeInterval step = s->_prevLevelAt ? [n timeIntervalSinceDate:s->_prevLevelAt] : 0;
            s->_voiceSinceResult += MIN(MAX(step, 0), 0.5);
            [s->_feedLock unlock];
        }
        [s->_feedLock lock];
        s->_prevLevelAt = NSDate.date;
        [s->_feedLock unlock];
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
    _lastChunkAt = NSDate.date;
    _micRetries = 0;
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
    _lastResultAt = NSDate.date;
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
    // بازپخش: هرچه بعد از آخرین نتیجه گفته شده دوباره از اول به استریم تازه می‌رود.
    // پاک نمی‌شود، چون اگر این استریم هم بی‌نتیجه بمیرد باید باز هم دستمان باشد؛
    // پاک شدنش فقط سر رسیدن نتیجه است، پس نه چیزی گم می‌شود نه تکراری درج می‌شود.
    NSData *pre = _replay.length ? [_replay copy] : nil;
    [_feedLock unlock];
    if (pre) [s feed:pre];
    // استریمی که با بازپخش شروع می‌شود اول باید همان صدای کهنه را بالا بفرستد و
    // بشنود؛ در آن فاصله نتیجه‌ای نمی‌آید و این «گیر کردن» نیست. بدون این مهلت،
    // خودِ بازپخش باعث تشخیص گیرِ بعدی می‌شد و حلقه هر دور بدتر می‌شد.
    _stallGraceUntil = [NSDate dateWithTimeIntervalSinceNow:pre.length / 32000.0 + 2.0];
    _lastRateLogAt = NSDate.date;
    _lastRateLogBytes = 0;
    ZLog(@"engine: stream open pair=%@ lang=%@ engine=google codec=%@ preroll=%luB",
         s.pair, _lang, s.codecName, (unsigned long)(pre.length));
}

- (void)handleEvent:(ZSpeechEvent *)ev from:(ZGoogleStream *)s {
    if (!s) return;
    if (s == _draining) {
        for (NSString *f in ev.finals) {
            _drainGotFinal = YES;
            [self deliverFinal:f];
        }
        return;
    }
    if (s != _stream) return;
    _lastEventAt = NSDate.date;
    if (_lastState != ZEngineListening) [self state:ZEngineListening msg:@""];
    if (ev.status > 0) ZLog(@"engine: server status %ld", (long)ev.status);

    if (ev.finals.count || ev.interim.length) {
        _gotResultThisCycle = YES;
        _endsSinceResult = 0;
        _lastResultAt = NSDate.date;
        // گوگل تا همین لحظه شنیده و جواب داده؛ بازپخش این صدا از این به بعد فقط
        // متن تکراری می‌سازد. (تاخیر ~۳۰۰ms نتیجه یعنی همین‌قدر صدا بی‌بیمه می‌ماند،
        // که هزینه‌اش از ریسک دوباره‌درج شدن یک جمله کمتر است.)
        [_feedLock lock];
        _replay.length = 0;
        _voiceSinceResult = 0;
        [_feedLock unlock];
    }
    for (NSString *f in ev.finals) {
        _lastInterim = @"";
        _salvageBest = @"";
        [self deliverFinal:f];
    }
    // باگ‌فیکس حذف متن: فریم بدون result (endpointer/status) دیگر interim را پاک نمی‌کند؛
    // فقط فریم‌های نتیجه‌دار حق دست زدن به متن خاکستری دارند.
    if (ev.hasResults && (ev.finals.count || ![ev.interim isEqualToString:_lastInterim])) {
        _lastInterim = [ev.interim copy];
        if (_lastInterim.length > _salvageBest.length) _salvageBest = [_lastInterim copy];
        [self.delegate engineInterim:_lastInterim];
    }
    // مرز یک متن قطعی بهترین جای چرخش است: هیچ متن معلقی در کار نیست. اگر تا سقف
    // اجباری (tick) چنین مرزی پیش بیاید، همان‌جا عوض می‌کنیم.
    if (ev.finals.count && [NSDate.date timeIntervalSinceDate:_streamStartedAt] > kZRotateAtFinalSec) {
        [self rotate];
    }
}

- (void)handleClose:(NSString *)reason from:(ZGoogleStream *)s {
    if (s && s == _draining) {
        _draining = nil;
        // سشن قدیمی هیچ متن قطعی نداد؟ آن‌وقت متن معلقِ لحظه‌ی چرخش را خودمان درج
        // می‌کنیم. بدون این، متن خاکستریِ سر چرخش با interim سشن تازه پاک می‌شد.
        if (!_drainGotFinal && _drainCarry.length) {
            ZLog(@"engine: drain gave nothing, carrying %lu chars", (unsigned long)_drainCarry.length);
            [self deliverFinal:_drainCarry];
        }
        _drainCarry = nil;
        ZLog(@"engine: drained pair=%@ (%@)", s.pair, reason);
        return;
    }
    if (!s || s != _stream) return;
    // حمل صدای سیم‌نرفته لازم نبود و برداشته شد: _replay از آن کامل‌تر است، چون صدای
    // روی‌سیم‌رفته‌ی بی‌جواب را هم دارد و همان بود که گم می‌شد.
    [_feedLock lock];
    if (_feedTarget == s) _feedTarget = nil;
    BOOL hadVoice = _voiceInCycle;
    NSUInteger replayBytes = _replay.length;
    [_feedLock unlock];
    _stream = nil;
    ZLog(@"engine: closed pair=%@ reason=%@ result=%d voice=%d replay=%.1fs",
         s.pair, reason, _gotResultThisCycle, hadVoice, replayBytes / 32000.0);
    [self salvage];
    if (!_running || _paused) return;
    if (hadVoice && !_gotResultThisCycle) _endsSinceResult++;
    [self scheduleRestart];
}

// متن خاکستری معلق را قبل از هر مرگ/ری‌استارت قطعی کن که هیچ‌وقت گم نشود.
// بلندترین interim این پاره هم با دم فعلی ادغام می‌شود (پنجره لغزان گوگل کلمه نخورد).
- (void)salvage {
    NSString *t = ZMergeInterim(_salvageBest, _lastInterim);
    _lastInterim = @"";
    _salvageBest = @"";
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
    if (!_running || _paused) return;
    // واچ‌داگ میکروفن مرده: صدا اصلا نمی‌رسد یعنی تشخیص هم بی‌معناست؛
    // بی‌صدا ماندنش قبلا شبیه «سکوت کاربر» دیده می‌شد و اپ بی‌سروصدا کر می‌ماند.
    NSTimeInterval sinceChunk = [NSDate.date timeIntervalSinceDate:_lastChunkAt];
    if (_micRunning && sinceChunk > 5) {
        if (_micRetries < 2) {
            _micRetries++;
            _lastChunkAt = NSDate.date;
            ZLog(@"engine: mic silent %.0fs, restarting mic (try %ld)", sinceChunk, (long)_micRetries);
            [_mic stop];
            _micRunning = NO;
            NSError *err = nil;
            if ([_mic startWithError:&err]) _micRunning = YES;
        } else {
            _running = NO;
            [self stopMicAndTimers];
            [self state:ZEngineGaveUp msg:@"میکروفن صدا نمی‌ده؛ ورودی صدای سیستم را چک کن و دوباره شروع کن"];
            ZLog(@"engine: gave up, mic dead");
            return;
        }
    }
    if (!_stream) return;
    // هر ~۵ ثانیه نرخ واقعی آپلود را لاگ کن که کاهش حجم دیده شود (روی همین تایمر ۲ ثانیه‌ای).
    NSDate *rnow = NSDate.date;
    NSTimeInterval sinceRateLog = [rnow timeIntervalSinceDate:_lastRateLogAt];
    if (sinceRateLog >= 5.0) {
        unsigned long long cur = _stream.bytesFed;
        double kbps = sinceRateLog > 0 ? ((double)(cur - _lastRateLogBytes) / 1024.0) / sinceRateLog : 0;
        ZLog(@"engine: upstream ~%.1f KB/s (codec=%@)", kbps, _stream.codecName);
        _lastRateLogAt = rnow;
        _lastRateLogBytes = cur;
    }
    NSDate *now = NSDate.date;
    NSTimeInterval quiet = [now timeIntervalSinceDate:_lastEventAt];
    NSTimeInterval age = [now timeIntervalSinceDate:_streamStartedAt];
    // گیر کردن واقعی: سرور زنده است و فریم می‌فرستد، ولی دیگر متنی نمی‌دهد. واچ‌داگ
    // «سکوت رویداد» این را هیچ‌وقت نمی‌دید، چون فریم endpointer/status حساب رویداد
    // می‌شد و تایمر را تازه می‌کرد؛ کاربر مجبور بود دستی مکث و ادامه بزند. حالا
    // معیار درست است: دارد حرف می‌زند ولی نتیجه‌ای نمی‌آید.
    [_feedLock lock];
    NSTimeInterval voiced = _voiceSinceResult;
    [_feedLock unlock];
    NSTimeInterval sinceResult = [now timeIntervalSinceDate:_lastResultAt];
    BOOL graced = _stallGraceUntil && [now compare:_stallGraceUntil] == NSOrderedAscending;
    if (!graced && voiced > kZStallVoiceSec && sinceResult > kZStallSec) {
        ZLog(@"engine: stalled %.0fs (voice %.1fs) with no result, recycling pair=%@",
             sinceResult, voiced, _stream.pair);
        // مسیر close خودش salvage می‌کند و آن درست است: salvage متنی را می‌گیرد که
        // تا آخرین نتیجه تشخیص داده شده بود، و بازپخش صدای بعد از همان نتیجه است.
        // مرزشان یکی است، پس نه کلمه‌ای گم می‌شود نه دو بار درج می‌شود.
        [_stream cancel];
        return;
    }
    if (quiet > 12) {
        ZLog(@"engine: watchdog quiet %.0fs, recycling pair=%@", quiet, _stream.pair);
        [self salvage];
        [_stream cancel];    // مسیر close ری‌استارت را می‌برد
        return;
    }
    // چرخش اجباری قبل از سقف ~۳۰ ثانیه‌ای صدای سرور. این مسیر عادی است، نه استثنا:
    // اگر همیشه قبل از سقف عوض کنیم، هیچ‌وقت به گیر کردن و بازپخش نمی‌رسیم.
    if (age > kZRotateSec) [self rotate];
}

// چرخش نرم: برعکس مسیر گیر کردن، اینجا آپلود سالم تمام می‌شود، پس سرور همه‌ی صدا را
// دارد و متن قطعی‌اش را می‌دهد. یعنی بازپخش نباید انجام شود، وگرنه همان حرف‌ها دو بار
// درج می‌شوند. متن معلق هم به‌عنوان بیمه کنار گذاشته می‌شود، برای وقتی که سشن قدیمی
// دست‌خالی بست.
- (void)rotate {
    if (!_running || !_stream) return;
    ZGoogleStream *old = _stream;
    ZLog(@"engine: rotate pair=%@ age=%.0fs", old.pair, [NSDate.date timeIntervalSinceDate:_streamStartedAt]);
    [_draining cancel];
    _draining = old;
    _drainGotFinal = NO;
    _drainCarry = ZMergeInterim(_salvageBest, _lastInterim);
    // مسئولیت این متن از این لحظه با مسیر drain است، پس دفترِ salvage پاک می‌شود که
    // بعدا همان حرف‌ها را دوباره درج نکند. نمایش دست‌نخورده می‌ماند و interim سشن
    // تازه جایش را می‌گیرد، پس چیزی روی صفحه پرت‌وپلا نمی‌شود.
    _lastInterim = @"";
    _salvageBest = @"";
    [_feedLock lock];
    _replay.length = 0;
    _voiceSinceResult = 0;
    [_feedLock unlock];
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
    BOOL _paused;
    NSURLSession *_session;
    NSURLSessionDataTask *_sseTask;
    NSMutableData *_sseBuf;
    NSTimer *_hbTimer;
    NSDate *_lastPageSeen;
}

@synthesize delegate;
@synthesize paused = _paused;

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

- (void)pause {
    if (!_running || _paused) return;
    _paused = YES;
    [self cmd:@{@"kind": @"cmd", @"cmd": @"stop"}];
    [self.delegate engineState:ZEnginePaused message:@""];
}

- (void)resume {
    if (!_running || !_paused) return;
    _paused = NO;
    [self cmd:@{@"kind": @"cmd", @"cmd": @"start"}];
    [self.delegate engineState:ZEngineConnecting message:@""];
}

- (void)stop {
    _running = NO;
    _paused = NO;
    [self cmd:@{@"kind": @"cmd", @"cmd": @"stop"}];
    [_hbTimer invalidate];
    _hbTimer = nil;
    [_sseTask cancel];
    _sseTask = nil;
    [_session invalidateAndCancel];
    _session = nil;
    [self.delegate engineState:ZEngineIdle message:@""];
}

// ۲۰۰ خالی هویت نیست: /alive باید root همین نسخه را برگرداند، وگرنه یک پروسه
// جامانده (نسخه قدیمی یا چک‌اوت دیگر) جای سرور ما جواب می‌دهد، GET / از پوشه غلط
// می‌آید و spawn تازه هم چون bind نمی‌شود بی‌صدا می‌میرد.
typedef NS_ENUM(NSInteger, ZRelayPing) {
    ZRelayDown,      // جوابی نیامد: پورت آزاد است، spawn مجاز
    ZRelayOurs,      // سرور خودمان: root همخوان
    ZRelayForeign,   // پورت دست دیگری است: spawn بی‌فایده، تعارض را گزارش کن
};

+ (ZRelayPing)ping:(NSString **)pidOut {
    __block ZRelayPing result = ZRelayDown;
    __block NSString *pid = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.timeoutIntervalForRequest = 1;
    NSURLSession *s = [NSURLSession sessionWithConfiguration:cfg];
    [[s dataTaskWithURL:[NSURL URLWithString:[kRelayBase stringByAppendingString:@"/alive"]]
      completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        if ([resp isKindOfClass:NSHTTPURLResponse.class]) {
            NSDictionary *obj = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
            NSString *root = [obj isKindOfClass:NSDictionary.class] &&
                             [obj[@"root"] isKindOfClass:NSString.class] ? obj[@"root"] : nil;
            id p = [obj isKindOfClass:NSDictionary.class] ? obj[@"pid"] : nil;
            if ([p isKindOfClass:NSNumber.class] || [p isKindOfClass:NSString.class]) pid = [p description];
            BOOL ours = ((NSHTTPURLResponse *)resp).statusCode == 200 && root &&
                        ([root isEqualToString:ZRes().path] ||
                         [root isEqualToString:ZRes().URLByResolvingSymlinksInPath.path]);
            result = ours ? ZRelayOurs : ZRelayForeign;
            if (!ours) ZLog(@"relay: 17635 answered but not ours (status=%ld root=%@ pid=%@)",
                            (long)((NSHTTPURLResponse *)resp).statusCode, root, pid);
        }
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)));
    [s invalidateAndCancel];
    if (pidOut) *pidOut = pid;
    return result;
}

+ (void)spawnServer {
    NSTask *p = [NSTask new];
    p.executableURL = [NSURL fileURLWithPath:@"/usr/bin/env"];
    p.arguments = @[@"python3", [ZRes() URLByAppendingPathComponent:@"serve.py"].path];
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[@"ZEMZEME_DATA"] = ZSupport().path;   // صفحه از بسته می‌آید، داده بیرون می‌نشیند
    p.environment = env;
    p.currentDirectoryURL = ZSupport();
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
    // فقط وقتی پورت واقعا آزاد است spawn کن؛ روی پورت اشغال، بچه فقط می‌میرد
    if ([self ping:NULL] == ZRelayDown) [self spawnServer];
    NSTask *p = [NSTask new];
    p.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"];
    p.arguments = @[@"-g", @"-na", @"Google Chrome", @"--args",
                    [NSString stringWithFormat:@"--app=%@/?relay=1", kRelayBase]];
    [p launchAndReturnError:nil];
}

- (void)ensureServer:(NSInteger)attempt {
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *pid = nil;
        ZRelayPing st = [ZChromeRelayEngine ping:&pid];
        if (st == ZRelayOurs) {
            dispatch_async(dispatch_get_main_queue(), ^{ [ws serverReady]; });
            return;
        }
        if (st == ZRelayForeign) {
            // پورت دست پروسه دیگری است (معمولا سرور جامانده از نسخه قبل).
            // spawn تازه bind نمی‌شود و بی‌صدا می‌میرد؛ به جای دور باطل، رک بگو.
            NSString *msg = pid.length
                ? [NSString stringWithFormat:@"پورت ۱۷۶۳۵ دست یک سرور دیگر است؛ در ترمینال ببندش: kill %@", pid]
                : @"پورت ۱۷۶۳۵ دست پروسه دیگری است؛ در ترمینال: lsof -i :17635";
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(ws) s = ws;
                if (!s || !s->_running) return;
                [s.delegate engineState:ZEngineGaveUp message:msg];
            });
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
            if (listening && !listening.boolValue && !s->_paused) {
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
