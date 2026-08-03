// موتور اصلی گوگل (میکروفن + استریم + سوپروایزر) و موتور فال‌بک صفحه کروم.
#import "zemzeme.h"
#import <stdatomic.h>

// مهر زمانیِ آخرین تکه‌ی صدا، بی‌قفل و بی‌شیء. bit-cast می‌شود چون atomic_double
// روی همه‌ی نسخه‌ها موجود نیست و دقتِ لازم اینجا در حد ثانیه است.
static inline void ZSetChunkStamp(atomic_llong *slot) {
    double now = CFAbsoluteTimeGetCurrent();
    long long bits;
    memcpy(&bits, &now, sizeof(bits));
    atomic_store(slot, bits);
}

static inline double ZChunkStamp(atomic_llong *slot) {
    long long bits = atomic_load(slot);
    double v;
    memcpy(&v, &bits, sizeof(v));
    return v;
}

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
    // حلقه‌ی دم: همیشه آخرین kZRotateOverlapSec ثانیه صدا، مستقل از اینکه نتیجه آمده یا نه.
    // چرا جدا از _replay: آن یکی سر *هر* فریمِ نتیجه خالی می‌شود و فریم interim چند بار
    // در ثانیه می‌آید، پس در گفتار عادی همیشه حدود ۰٫۱ تا ۰٫۵ ثانیه است، نه ۱۲ ثانیه.
    // سقف ۱۲ ثانیه‌اش فقط وقتی پر می‌شود که گوگل لال شده باشد. اندازه‌گیری روی لاگ
    // واقعی: از ۵ چرخش، هم‌پوشانی ۰٫۰۰ و ۰٫۱۰ و ۰٫۳۱ و ۰٫۵۰ و ۲٫۰۰ ثانیه شد، و همان
    // چرخش‌های کوتاه دوباره حرف اول کلمه را خوردند («برای» شد «رای»، «که» شد «ه»).
    NSMutableData *_tailAudio;
    BOOL _voiceInCycle;

    NSDate *_lastEventAt;
    NSDate *_lastResultAt;       // آخرین فریمِ نتیجه‌دار، نه هر فریمی
    NSTimeInterval _voiceSinceResult;   // جمع ثانیه‌های صدای واقعی از آخرین نتیجه
    NSDate *_prevLevelAt;        // برای اندازه‌گیری همان جمع
    NSDate *_stallGraceUntil;    // تا این لحظه استریمِ تازه متهم به گیر کردن نمی‌شود

    // رونوشت. کلِ منطقِ «متن چه شکلی درمی‌آید» آنجاست، نه اینجا: موتور فقط می‌گوید
    // چه شنید و کِی چرخید. همین جدایی است که بازپخشِ بی‌میکروفن را ممکن می‌کند.
    ZTranscript *_tx;
    BOOL _drainGotFinal;
    NSDate *_lastVoiceAt;        // آخرین لحظه‌ای که واقعا صدا بود؛ برای بریدن در سکوت
    // جوش به خودِ استریم بسته است، نه به «استریمِ فعلی». باگ واقعی: استریمی که با
    // هم‌پوشانی شروع شده بود، تا متن قطعی‌اش برسد معمولا خودش چرخیده و در حال تخلیه
    // بود، و مسیر تخلیه جوش نمی‌زد؛ پس همان چند کلمه دو بار می‌نشستند.
    __weak ZGoogleStream *_overlapStream;   // با هم‌پوشانی باز شد و هنوز متن قطعی نداده
    NSTimeInterval _streamPrerollSec;       // صدای کهنه‌ای که این استریم با آن شروع شد
    BOOL _rotating;                         // openStream بعدی از مسیر چرخش می‌آید، نه ری‌استارت
    NSInteger _endsSinceResult;
    BOOL _gotResultThisCycle;
    NSString *_lastInterim;
    NSString *_salvageBest;      // بلندترین interim از آخرین final؛ بیمه پنجره لغزان گوگل
    NSTimer *_restartTimer;
    NSTimer *_watchdog;
    NSDate *_streamStartedAt;
    ZEngineState _lastState;
    NSDate *_lastLevelAt;
    // زمانِ آخرین تکه، به‌صورت عدد نه شیء: روی نخ صدا نوشته می‌شود و روی نخ اصلی
    // خوانده. با NSDate* هر نوشتن یک release روی شیءِ قبلی است و آن دو نخ با هم
    // یعنی over-release. عدد اتمیک نه پاره خوانده می‌شود نه چیزی آزاد می‌کند.
    atomic_llong _lastChunkAtBits;
    NSInteger _micRetries;
    BOOL _paused;

    NSDate *_lastRateLogAt;              // برای لاگ دوره‌ای نرخ آپلود
    unsigned long long _lastRateLogBytes;
}

@synthesize delegate;
@synthesize paused = _paused;
// ضبط سشن. موتور گوگل صاحب میکروفن است، پس تنها جایی که می‌تواند صدا را به ضبط بدهد
// همین‌جاست. رله‌ی کروم میکروفن ندارد و همین ویژگی را دارد ولی هیچ‌وقت پرش نمی‌کند،
// یعنی آنجا فایل صدایی ساخته نمی‌شود و پاس نهایی همین را صریح می‌گوید.
@synthesize recorder;

// ZMergeInterim و ZStitchOverlapMax هر دو به seam.m رفتند: سه مصرف‌کننده داشتند
// (چرخشِ مسیر زنده، درزِ رونویسی فایل، نجاتِ interim) و تعریفشان لای موتور و لای
// مسیر دسته‌ای پخش بود. حالا یک فایلِ بی‌وابستگی دارند که تست تنهایی کامپایلش می‌کند.

- (instancetype)init {
    if ((self = [super init])) {
        _mic = [ZMic new];
        _feedLock = [NSLock new];
        _replay = [NSMutableData data];
        _tailAudio = [NSMutableData data];
        _tx = [ZTranscript new];
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
    [self salvageFrom:_stream];
    _endsSinceResult = 0;
    [_stream cancel];    // مسیر close با زبان جدید ری‌استارت می‌کند
}

// مکث: شنیدن می‌ایستد، میکروفن گرم می‌ماند که ادامه آنی باشد
- (void)pause {
    if (!_running || _paused) return;
    _paused = YES;
    [self salvageFrom:_stream];
    [_stream cancel];    // مسیر close با گارد paused ری‌استارت نمی‌کند
    [self state:ZEnginePaused msg:@""];
    ZLog(@"engine: paused");
}

- (void)resume {
    if (!_running || !_paused) return;
    _paused = NO;
    _endsSinceResult = 0;
    ZSetChunkStamp(&_lastChunkAtBits);
    // صدای پیش از مکث دیگر همسایه‌ی صدای تازه نیست؛ هم‌پوشانی از آن یعنی چسباندن دو
    // تکه‌ی بی‌ربط به هم
    [_feedLock lock];
    _tailAudio.length = 0;
    [_feedLock unlock];
    [self state:ZEngineConnecting msg:@""];
    [self openStream];
    ZLog(@"engine: resumed");
}

- (void)stop {
    BOOL was = _running;
    _running = NO;
    _paused = NO;
    // بستن وسط تخلیه: سشن قدیمی هنوز متن قطعی‌اش را نداده و چند خط پایین‌تر cancel
    // می‌شود؛ بعدش مسیر close آن را «غریبه» می‌بیند (چون _draining نال شده) و متنش
    // بی‌صدا دور ریخته می‌شود. همان بیمه‌ای که handleClose دارد، اینجا هم لازم است.
    // چرا حالا بیشتر پیش می‌آید: چرخش منتظر سکوت می‌ماند، و سکوت یعنی حرفت تمام شده،
    // یعنی دقیقا همان لحظه‌ای که دستت می‌رود سراغ Esc. آخرین چند کلمه قربانی می‌شد.
    // ترتیب مهم است: carry مال لحظه‌ی چرخش است، پس از salvage (که متن تازه‌تر
    // استریم فعلی است) قدیمی‌تر است و باید اول برود.
    // تخلیه دیگر در جریان نیست: متن معلقش و هرچه منتظر نوبت بود همین حالا قطعی
    // می‌شوند. بستن وسط تخلیه بی این، آخرین چند کلمه را می‌خورد، و از وقتی چرخش
    // منتظر سکوت می‌ماند دقیقا همان لحظه‌ای است که دست می‌رود سراغ Esc.
    _draining = nil;
    if (was) [_tx endDrain];
    if (was) [self salvageFrom:_stream];
    // هرچه بعد از نجات هنوز خاکستری مانده (دُمی که هیچ متنِ قطعی‌ای پوشش نداد)
    // همین‌جا قطعی می‌شود. در حالت زنده که دُم رندر نمی‌شود، بی این یک خط، آن متن
    // بی‌هیچ ردی گم می‌شد.
    if (was) [_tx sealPending];
    [_stream cancel];
    [_draining cancel];
    _stream = nil;
    _draining = nil;
    [_feedLock lock];
    _feedTarget = nil;
    _replay.length = 0;
    _tailAudio.length = 0;
    [_feedLock unlock];
    _overlapStream = nil;
    [self stopMicAndTimers];
    [self emit];
    [self state:ZEngineIdle msg:@""];
    if (was) ZLog(@"engine: stopped by user");
}

// انصراف. سه چیز باید همزمان برود، وگرنه حرف‌ها از یکی از راه‌ها برمی‌گردند:
// متن خاکستری، صدای بازپخش، و خودِ سشن‌های در جریان که همان صدا را دارند و متن
// قطعی‌شان را می‌فرستند. سشن تازه از همین لحظه شروع می‌کند، پس شنیدن قطع نمی‌شود.
- (void)dropPending {
    if (!_running) return;
    _lastInterim = @"";
    _salvageBest = @"";
    _drainGotFinal = YES;      // بیمه‌ی چرخش هم لازم نیست؛ کاربر همین را نمی‌خواهد
    // رونوشتِ قطعی دست نمی‌خورد. کوتاه کردنش کارِ مصرف‌کننده است و فقط تا جایی که
    // واقعا درج شده؛ موتور حق ندارد متنی را که تحویل داده پس بگیرد.
    [_tx dropPending];
    [self emit];
    [_feedLock lock];
    _feedTarget = nil;
    _replay.length = 0;
    _tailAudio.length = 0;     // «دور بریز» یعنی صدای هم‌پوشان هم نباید برگردد
    _voiceSinceResult = 0;
    [_feedLock unlock];
    _overlapStream = nil;      // صدای هم‌پوشان هم رفت، جوشی در کار نیست
    // نال کردن قبل از cancel: مسیر close این‌ها را «غریبه» می‌بیند، پس نه salvage
    // می‌کند نه ری‌استارت، و متن قطعیِ دیررسشان هم دور ریخته می‌شود.
    ZGoogleStream *old = _stream, *dr = _draining;
    _stream = nil;
    _draining = nil;
    [old cancel];
    [dr cancel];
    ZLog(@"engine: dropped pending text and audio");
    if (!_paused) [self openStream];
}

- (void)startMicAndStream {
    __weak typeof(self) ws = self;
    _mic.onChunk = ^(NSData *pcm) {
        __strong typeof(ws) s = ws;
        if (!s) return;
        ZSetChunkStamp(&s->_lastChunkAtBits);
        s->_micRetries = 0;
        // در مکث فقط **بالا نمی‌رود**. تا امروز اصلا دور ریخته می‌شد: نه روی دیسک
        // می‌نشست نه در بافر، پس یک مکثِ ناخواسته (یا یک تپِ اشتباهی) همان چند ثانیه
        // را برای همیشه می‌برد و پاس نهایی هم دیگر نمی‌توانست از صدا نجاتش دهد.
        // ضبط ادامه دارد، چون فایل سشن باید همان چیزی باشد که میکروفن شنید.
        if (s->_paused) {
            [s.recorder feed:pcm];
            return;
        }
        // ضبط روی دیسک، پیش از هر تصمیم دیگری: این تکه ممکن است در چرخش و بازپخش و
        // جوش هزار جا برود، ولی فایل سشن باید دقیقا همان چیزی باشد که میکروفن شنید.
        [s.recorder feed:pcm];
        // هر تکه هم به استریم می‌رود هم در بافر بازپخش می‌ماند تا اولین نتیجه برسد.
        // قبلا فقط صدای «هنوز روی سیم نرفته» نگه داشته می‌شد، که موقع گیر کردن سرور
        // همیشه خالی بود (سیم سالم بود، سرور جواب نمی‌داد)، پس همان حرف‌ها گم می‌شدند.
        [s->_feedLock lock];
        [s->_replay appendData:pcm];
        if (s->_replay.length > kZReplayCapBytes) {
            [s->_replay replaceBytesInRange:NSMakeRange(0, s->_replay.length - kZReplayCapBytes)
                                  withBytes:NULL length:0];
        }
        [s->_tailAudio appendData:pcm];
        if (s->_tailAudio.length > kZOverlapCapBytes) {
            [s->_tailAudio replaceBytesInRange:NSMakeRange(0, s->_tailAudio.length - kZOverlapCapBytes)
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
            s->_lastVoiceAt = n;    // چرخش می‌خواهد بداند همین حالا وسط کلمه‌ایم یا نه
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
    ZSetChunkStamp(&_lastChunkAtBits);
    _micRetries = 0;
    [self openStream];
    [_watchdog invalidate];
    _watchdog = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *t) {
        [ws tick];
    }];
}

- (void)openStream {
    // تایمرِ ری‌استارتِ معلق و استریمِ قبلی هر دو باید همین‌جا بمیرند. بی این، یک
    // ری‌استارتِ زمان‌بندی‌شده بعد از drop یا resume دوباره شلیک می‌شد و استریمِ
    // دومی می‌ساخت؛ اولی نه لغو می‌شد نه finishUpload می‌گرفت، سوکتش می‌ماند و هر
    // رویدادش هم دور ریخته می‌شد چون دیگر `_stream` نبود.
    [_restartTimer invalidate];
    _restartTimer = nil;
    if (_paused) return;
    if (_stream && _stream != _draining) [_stream cancel];
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
    _voiceInCycle = NO;
    // بازپخش: هرچه بعد از آخرین نتیجه گفته شده دوباره از اول به استریم تازه می‌رود.
    // پاک نمی‌شود، چون اگر این استریم هم بی‌نتیجه بمیرد باید باز هم دستمان باشد؛
    // پاک شدنش فقط سر رسیدن نتیجه است، پس نه چیزی گم می‌شود نه تکراری درج می‌شود.
    NSData *pre = _replay.length ? [_replay copy] : nil;
    // **اول بازپخش، بعد اعلامِ مقصد، و هر دو داخل همان قفل.** قبلا `_feedTarget`
    // پیش از فرستادنِ بازپخش ست می‌شد و قفل هم باز بود؛ یک تکه‌ی میکروفن که در همان
    // شکاف می‌رسید (از نخ صدا) زودتر از بازپخش روی سیم می‌نشست. یعنی استریم تازه
    // صدا را بی‌ترتیب می‌گرفت، و برای FLAC بی‌ترتیب یعنی خراب: چند ثانیه‌ی اولش
    // هیچ متنی نمی‌داد و همان‌جا بود که جمله گم می‌شد.
    if (pre) [s feed:pre];
    _feedTarget = s;
    [_feedLock unlock];
    // هر استریمی که با صدای کهنه شروع شود اولین متن قطعی‌اش تکرار دارد، چه چرخش باشد
    // چه ری‌استارتِ بعد از مرگ (آنجا هم متنِ همان صدا با salvage تحویل شده). پنجره از
    // روی طول واقعی همین بازپخش حساب می‌شود، پس هم ۲ ثانیه‌ی چرخش را می‌پوشاند هم
    // ۱۲ ثانیه‌ی یک گیرِ طولانی، بی‌آنکه هیچ‌کدام پنجره‌ی دیگری را گشاد کند.
    _streamPrerollSec = pre.length / 32000.0;
    // جوش فقط برای بازپخشِ چرخش. در مسیر ری‌استارت بعد از مرگ، صدای بازپخش‌شده اصلا
    // تشخیص داده *نشده* بود (کل دلیل نگه داشتنش همین است)، پس هم‌پوشانیِ متنی وجود
    // ندارد و پنجره‌ای به عرض همان بازپخش (۸ ثانیه یعنی ۳۲ کلمه) می‌توانست ۳۲ کلمه‌ی
    // کاملا تازه را با یک تطبیق الکی ببلعد. آنجا متنِ معلق را salvage جدا داده است.
    _overlapStream = (pre.length && _rotating) ? s : nil;
    _tx.weldWords = ZStitchWords(kZRotateOverlapSec);
    _rotating = NO;
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
        // متن قطعیِ سشنِ قدیمی جای متن معلقش را می‌گیرد. جوش لازم ندارد: این ادامه‌ی
        // همان تشخیص است، نه یک تشخیصِ دوم از همان صدا.
        for (NSString *f in ev.finals) {
            _drainGotFinal = YES;
            [_tx drainFinal:f];
        }
        if (ev.finals.count) [self emit];
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
        [self deliverFinal:f weld:[self takeWeldFor:s]];
    }
    // باگ‌فیکس حذف متن: فریم بدون result (endpointer/status) دیگر interim را پاک نمی‌کند؛
    // فقط فریم‌های نتیجه‌دار حق دست زدن به متن خاکستری دارند.
    if (ev.hasResults && (ev.finals.count || ![ev.interim isEqualToString:_lastInterim])) {
        _lastInterim = [ev.interim copy];
        if (_lastInterim.length > _salvageBest.length) _salvageBest = [_lastInterim copy];
        [_tx setInterim:_lastInterim];
        // اینجا یک بار «پل تخلیه» گذاشته شد (نمایش = معلقِ قدیمی + interim تازه) که
        // جمله‌ی خاکستری سر چرخش آب نشود. در پنل بی‌خطر بود، در حالت کرسر فاجعه:
        // آنجا «نمایش» یعنی تایپ واقعی، پس آن رشته‌ی بلند سر کرسر تایپ می‌شد و یک
        // ثانیه بعد که تخلیه تمام می‌شد با یک مشت Backspace پاک. متن گم نمی‌شد ولی
        // کاربر می‌دید جمله‌اش کوبیده می‌شود. برداشته شد: مصرف‌کننده‌ای که پاک کردنش
        // گران است نباید قربانی زیباییِ مصرف‌کننده‌ای شود که پاک کردنش مجانی است.
        [self emit];
    }
    // مرز یک متن قطعی بهترین جای چرخش است: هیچ متن معلقی در کار نیست. ولی «متن قطعی»
    // یعنی گوگل یک پاره را بست، نه اینکه کاربر ساکت شد؛ وسط جمله هم می‌آید. پس شرط
    // دوم لازم است: همین حالا صدایی نباشد. اگر پیوسته حرف می‌زند، سقف‌های tick می‌بُرند
    // و هم‌پوشانی درز را می‌پوشاند.
    if (ev.finals.count && [self audioAge] > kZRotateAtFinalSec && [self quietNow]) {
        [self rotate];
    }
}

// عمر استریم به «ثانیه‌ی صدایی که خورده» است، نه ساعت دیوار. بودجه‌ی سرور همان است:
// استریمی که با ۸ ثانیه بازپخش باز شود فقط ~۱۶ ثانیه حرف تازه جا دارد، و اگر ساعت
// دیوار بشماریم ۲۲ ثانیه بعد هنوز خودمان را زیر سقف می‌بینیم در حالی که ۳۰ ثانیه صدا
// داده‌ایم و سرور مرده. یک بار همین اتفاق افتاد و گیر کردن جای چرخش را گرفت.
- (NSTimeInterval)audioAge {
    return [NSDate.date timeIntervalSinceDate:_streamStartedAt] + _streamPrerollSec;
}

// همین حالا وسط کلمه‌ایم یا نه. تنها معیارِ در دسترسِ درست: آخرین باری که میکروفن
// صدای واقعی دید (همان آستانه‌ای که _voiceInCycle از آن می‌خواند).
- (BOOL)quietNow {
    [_feedLock lock];
    NSDate *v = _lastVoiceAt;
    [_feedLock unlock];
    return !v || [NSDate.date timeIntervalSinceDate:v] > kZRotateQuietSec;
}

- (void)handleClose:(NSString *)reason from:(ZGoogleStream *)s {
    if (s && s == _draining) {
        _draining = nil;
        [_tx endDrain];    // متن معلقِ بی‌جواب و هرچه منتظر نوبت بود، همین‌جا می‌نشیند
        [self emit];
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
    [self salvageFrom:s];
    if (!_running || _paused) return;
    if (hadVoice && !_gotResultThisCycle) _endsSinceResult++;
    [self scheduleRestart];
}

// متن خاکستری معلق را قبل از هر مرگ/ری‌استارت قطعی کن که هیچ‌وقت گم نشود.
// بلندترین interim این پاره هم با دم فعلی ادغام می‌شود (پنجره لغزان گوگل کلمه نخورد).
//
// با ZInterimRatchet و نه ZMergeInterim: این دو رشته دو snapshot از **یک** استریم‌اند و
// همین پرسشِ راچت است. ادغامِ چسبنده اینجا هر بازنویسیِ گوگل را به یک جمله‌ی تکراری
// ترجمه می‌کرد: در سشن 2026-08-01-02-19-17 نجات‌گرفته به «دیگه بشه مثلاً ۶ ماهه» تمام
// می‌شد و آخرین interim همان جمله را با «یادش نره» بازنویسی کرده بود، پس سرِ هر دو یکی
// بود ولی هیچ‌کدام زیررشته‌ی دیگری نبود و carry دو برابر شد.
//
// و ورودی‌ها ثبت می‌شوند، نه فقط نتیجه. تا امروز لاگ فقط رشته‌ی ادغام‌شده را داشت، پس
// بازپخش خودِ ادغام را هرگز نمی‌دواند و این باگ از کورپوسِ طلایی رد شد. رویدادِ salvage
// دقیقا پیش از رفتن به رونوشت نوشته می‌شود، پس بازپخش همان لحظه بازسازی‌اش می‌کند.
- (NSString *)mergedSalvage {
    ZEventLogWrite(@{@"k": @"salvage",
                     @"best": _salvageBest ?: @"", @"last": _lastInterim ?: @""});
    return ZInterimRatchet(_salvageBest, _lastInterim);
}

- (void)salvageFrom:(ZGoogleStream *)s {
    NSString *t = [self mergedSalvage];
    _lastInterim = @"";
    _salvageBest = @"";
    // «چیزی برای تحویل ندارم» یعنی همین، نه «هرچه روی صفحه است را پاک کن». این بند
    // حالا ساختاری است، نه یک احتیاط: نجات فقط می‌تواند رونوشت را رشد بدهد، و راهی
    // برای کوتاه کردنش ندارد. سر یک طوفان قطعیِ TLS (۱۲ بار بسته شدن در ۴ ثانیه)
    // نسخه‌ی قدیمی دوازده بار پشت هم «پاک کن» می‌فرستاد و جمله می‌رفت.
    // پاک کردنِ عمدی فقط کار dropPending است.
    if (!t.length) return;
    ZLog(@"engine: salvaged %lu chars", (unsigned long)t.length);
    [self deliverFinal:t weld:[self takeWeldFor:s]];
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
    NSTimeInterval sinceChunk = CFAbsoluteTimeGetCurrent() - ZChunkStamp(&_lastChunkAtBits);
    if (_micRunning && sinceChunk > 5) {
        if (_micRetries < 2) {
            _micRetries++;
            ZSetChunkStamp(&_lastChunkAtBits);
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
        [self salvageFrom:_stream];
        [_stream cancel];    // مسیر close ری‌استارت را می‌برد
        return;
    }
    // چرخش اجباری قبل از سقف ~۳۰ ثانیه‌ای صدای سرور. این مسیر عادی است، نه استثنا:
    // اگر همیشه قبل از سقف عوض کنیم، هیچ‌وقت به گیر کردن و بازپخش نمی‌رسیم.
    // اول در اولین سکوت بعد از kZRotateSec؛ اگر پیوسته حرف می‌زند، سر سقف سخت.
    NSTimeInterval audio = [self audioAge];
    if (audio > kZRotateSec && [self quietNow]) {
        [self rotate];
    } else if (audio > kZRotateHardSec) {
        ZLog(@"engine: hard rotate at %.0fs of audio, no silence found", audio);
        [self rotate];
    }
}

// چرخش نرم: برعکس مسیر گیر کردن، اینجا آپلود سالم تمام می‌شود، پس سرور همه‌ی صدای
// کاملی را که گرفته تشخیص می‌دهد. ولی «همه‌ی صدا» شامل نصفِ کلمه‌ی سر درز نیست: هجای
// ناقصِ آخر را دور می‌ریزد. برای همین به جای خالی کردن بازپخش، آخرین چند ثانیه‌اش را
// نگه می‌داریم تا استریم تازه همان کلمه را از اولش بشنود. تکرارِ حاصل مشکل نیست،
// جوشِ متنی (ZTranscript) برش می‌دارد؛ گم شدنِ کلمه مشکل بود.
- (void)rotate {
    if (!_running || !_stream) return;
    ZGoogleStream *old = _stream;
    ZLog(@"engine: rotate pair=%@ age=%.0fs audio=%.0fs", old.pair,
         [NSDate.date timeIntervalSinceDate:_streamStartedAt], [self audioAge]);
    _rotating = YES;
    // تخلیه‌ی قبلی هنوز تمام نشده؟ اول تسویه‌اش کن. صرفِ cancel یعنی مسیر close
    // آن استریم را غریبه ببیند و متن معلقش دور برود.
    if (_draining) {
        ZGoogleStream *prev = _draining;
        _draining = nil;
        [_tx endDrain];
        [prev cancel];
    }
    _draining = old;
    _drainGotFinal = NO;
    // متن معلقِ این لحظه می‌رود در carry، و carry جزئی از pending است، پس **روی صفحه
    // سر جایش می‌ماند**. قبلا اینجا از نمایش غیب می‌شد و اولین interim کوتاهِ سشن تازه
    // جایش می‌نشست: در گفتار بی‌وقفه یعنی دویست نویسه می‌رفت و پنج نویسه می‌آمد، همان
    // «یک‌دفعه نصف بیشتر متن پرید». دفترِ salvage پاک می‌شود که همان حرف‌ها دو بار نروند.
    // پرچمِ جوش مالِ همین استریم است. در گفتار بی‌وقفه سشن پیش از دادن متن قطعی
    // می‌چرخد، پس اولین متنش از مسیر تخلیه می‌رسد و بی این پرچم جوش نمی‌خورد.
    [_tx beginDrainWithCarry:[self mergedSalvage] weld:[self takeWeldFor:old]];
    _lastInterim = @"";
    _salvageBest = @"";
    [_feedLock lock];
    // هم‌پوشانی از حلقه‌ی دم می‌آید، نه از _replay: آن یکی سر هر فریمِ نتیجه خالی شده و
    // معمولا چند صدم ثانیه بیشتر ندارد. هرکدام بلندتر بود همان می‌ماند، پس صدای
    // بی‌جوابِ یک گیرِ طولانی هم قربانیِ سقفِ دو ثانیه‌ای نمی‌شود.
    if (_tailAudio.length > _replay.length) [_replay setData:_tailAudio];
    NSUInteger overlapBytes = _replay.length;
    _voiceSinceResult = 0;
    [_feedLock unlock];
    ZLog(@"engine: rotate overlap %.2fs", overlapBytes / 32000.0);
    [self emit];    // ترکیب pending عوض شد (interim به carry منتقل شد)، متن همان است
    [old finishUpload];
    __weak typeof(self) ws = self;
    __weak ZGoogleStream *wold = old;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(ws) s = ws;
        __strong ZGoogleStream *o = wold;
        if (s && o && s->_draining == o) {
            // فقط cancel. نال کردن _draining اینجا یعنی وقتی handleClose آسنکرون
            // برسد این استریم را «غریبه» ببیند و متن معلقش بی‌صدا دور
            // ریخته شود. مسیر close خودش نال می‌کند و carry را هم می‌نشاند.
            ZLog(@"engine: drain timed out, cancelling pair=%@", o.pair);
            [o cancel];
        }
    });
    [self openStream];
}

// ---------- پل به رونوشت ----------

- (void)emit {
    [self.delegate engineDidUpdateCommitted:_tx.committed pending:_tx.pending];
}

// آیا این استریم همان است که با هم‌پوشانی باز شد و هنوز اولین متن قطعی‌اش نیامده؟
// فقط همان یک تکه تکرار دارد.
- (BOOL)takeWeldFor:(ZGoogleStream *)s {
    if (!s || s != _overlapStream) return NO;
    _overlapStream = nil;
    return YES;
}

- (void)deliverFinal:(NSString *)text weld:(BOOL)weld {
    [_tx addFinal:text weld:weld];
    [self emit];
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
    NSMutableString *_committed;   // همان قرارداد رونوشت، برای موتور فال‌بک
    NSString *_pending;
    NSURLSessionDataTask *_sseTask;
    NSMutableData *_sseBuf;
    NSTimer *_hbTimer;
    NSDate *_lastPageSeen;
}

@synthesize delegate;
@synthesize paused = _paused;
// ضبط سشن. موتور گوگل صاحب میکروفن است، پس تنها جایی که می‌تواند صدا را به ضبط بدهد
// همین‌جاست. رله‌ی کروم میکروفن ندارد و همین ویژگی را دارد ولی هیچ‌وقت پرش نمی‌کند،
// یعنی آنجا فایل صدایی ساخته نمی‌شود و پاس نهایی همین را صریح می‌گوید.
@synthesize recorder;

- (instancetype)init {
    if ((self = [super init])) {
        _sseBuf = [NSMutableData data];
        _committed = [NSMutableString string];
        _pending = @"";
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

// انصراف در موتور فال‌بک: خودِ صفحه کروم متن معلق را نگه داشته، پس تشخیصش stop و
// start می‌شود که آن متن آنجا هم دور برود، نه فقط روی پنل.
- (void)dropPending {
    if (!_running) return;
    _pending = @"";
    [self emit];
    [self cmd:@{@"kind": @"cmd", @"cmd": @"stop"}];
    if (!_paused) [self cmd:@{@"kind": @"cmd", @"cmd": @"start"}];
    ZLog(@"relay: dropped pending text");
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
            // همان راچتِ موتور اصلی: عقب‌گردِ interim نمایش را پاک نکند
            s->_pending = ZInterimRatchet(s->_pending, t);
            [s emit];
            [s.delegate engineLevel:0.4f];
        } else if ([kind isEqualToString:@"final"]) {
            NSString *t = [obj[@"text"] isKindOfClass:NSString.class] ? obj[@"text"] : @"";
            if (t.length) {
                [s->_committed setString:ZJoinText(s->_committed, t)];
                s->_pending = @"";
                [s emit];
            }
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

- (void)emit {
    [self.delegate engineDidUpdateCommitted:_committed pending:_pending];
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
