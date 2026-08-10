// استریم نمایشی: متن، هم‌گام با حرف زدن، سریع و خام.
//
// **این مسیر کیفیت نیست و هیچ‌وقت نمی‌شود.** یک قاعده دارد و همه‌چیزش از همان
// می‌آید: خروجی این فایل فقط به دُم خاکستری پنل می‌رود. نه وارد متن سشن می‌شود، نه
// درج، نه کپی، نه روی دیسک. یک‌طرفه. تا این قاعده سر جایش باشد، این استریم نمی‌تواند
// کیفیت را خراب کند؛ حداکثر می‌تواند پهنای باند بخورد، و برای همان هم پایین‌تر تدبیر
// شده.
//
// چرا اصلا سشن جدا، در حالی که نسخه دو دقیقا برای نداشتنِ مسیر دوم نوشته شد: چون از
// خودِ خط لوله نمی‌شود متنِ سریع بیرون کشید. برش‌زن تا بافر به دوازده ثانیه نرسد
// تصمیم نمی‌گیرد (seg.m:93)، و نقطه‌ای که می‌بُرد پنج ثانیه عقب‌تر از «الان» است. پس
// سشنی که زنده تغذیه شود، تا وقتی مرز معلوم شود صدای تکه‌ی بعدی را هم بلعیده، یعنی
// هم‌پوشانی، یعنی همان درزی که کل نسخه دو برای نداشتنش نوشته شد. آن دوازده ثانیه
// عمدی و اندازه‌گیری‌شده است و برای متنِ سریع دست نمی‌خورد.
//
// و کیفیتش عمدا خام است. سشن پیوسته در همان ناحیه‌ای کار می‌کند که جدول RESULTS.md
// می‌گوید کیفیت در آن فرو می‌ریزد. این معامله آگاهانه است: **سریع و خام، بعد درست
// و سفید.** رنگ همین را می‌گوید و سرنویس پنل هم.
#import "zemzeme.h"

// چرخش هر ~۸ ثانیه. دو کار می‌کند و هر دو لازم‌اند، نه تزئینی:
//
//   ۱. اندپوینت بعد از ~۲۵ تا ۳۰ ثانیه‌ی پیوسته از تشخیص می‌افتد. بی چرخش، پیش‌نمایش
//      وسط یک دیکته‌ی پنج دقیقه‌ای برای همیشه یخ می‌زد. آن دیگر «کم‌کیفیت» نیست، خراب است.
//   ۲. هشت ثانیه نزدیک قله‌ی همان منحنی است، پس خامی‌اش هم بی‌جهت بدتر از لازم نمی‌شود.
//
// و چرخش اینجا **ارزان** است، برخلاف نسخه یک: آنجا متنِ چرخش نتیجه بود و مرزش باید
// دوخته می‌شد؛ اینجا دور ریختنی است. یک کلمه سر مرز بپرد، چند ثانیه بعد سفید می‌شود.
#define kZPreviewRotateSec 8.0

// سقفِ صدای معطل، عمدا خیلی کوچک‌تر از مسیر کیفیت (۶۰ ثانیه). روی شبکه‌ی ضعیف هر دو
// استریم عقب می‌افتند و هر کدام قدیمی‌ترین صدایش را دور می‌ریزد؛ با این عدد، **این
// یکی اول عقب می‌کشد**. یعنی پیش‌نمایش هیچ‌وقت سر پهنای باند با متنِ واقعی دعوا
// نمی‌کند. صدای نمایشیِ سه ثانیه پیش هم که دیگر به درد نمایش نمی‌خورد.
#define kZPreviewBacklogBytes ((NSUInteger)(32000 * 3))

// بس کن و دیگر برنگرد. اندپوینت که پشت سر هم رد کند، تلاش دوباره فقط فشار بیشتر روی
// همان کلیدی است که مسیر کیفیت هم از آن می‌خواند.
#define kZPreviewMaxFails 3

@implementation ZPreviewStream {
    NSString *_lang;
    ZGoogleStream *_cur;
    NSLock *_lock;
    // متنِ هر دورِ چرخش، به ترتیب. هر سشن سطلِ خودش را دارد و همان‌جا پرش می‌کند، پس
    // فاینال‌های دیررسِ سشنِ بازنشسته هم سر جای درست خودشان می‌نشینند نه ته متن.
    NSMutableArray<NSMutableString *> *_buckets;
    NSString *_interim;      // فقط مالِ سشنِ فعلی؛ سشن بازنشسته فاینال دارد، حدس نه
    NSUInteger _gen;         // شماره‌ی سشن فعلی، برای اینکه بلاکِ سشنِ کهنه interim ننویسد
    NSString *_sent;         // آخرین چیزی که به رابط دادیم؛ تکرارِ بی‌تغییر نفرست
    double _sec;             // ثانیه‌ی صدای دورِ فعلی، از بایت‌ها
    NSInteger _fails;
    BOOL _stopped;
}

- (instancetype)initWithLang:(NSString *)lang {
    if ((self = [super init])) {
        _lang = [lang copy];
        _lock = [NSLock new];
        _buckets = [NSMutableArray array];
        _interim = @"";
        _sent = @"";
    }
    return self;
}

- (void)start {
    if (_stopped || _cur) return;
    [self open];
}

// ---------- سشن ----------

- (void)open {
    NSMutableString *bucket = [NSMutableString string];
    [_lock lock];
    [_buckets addObject:bucket];
    NSUInteger gen = ++_gen;
    _sec = 0;
    [_lock unlock];

    ZGoogleStream *s = [[ZGoogleStream alloc] initWithLang:_lang];
    s.backlogCap = kZPreviewBacklogBytes;
    __weak typeof(self) weak = self;
    s.onEvent = ^(ZSpeechEvent *ev) {
        typeof(self) me = weak;
        if (!me) return;
        [me->_lock lock];
        for (NSString *f in ev.finals) {
            if (!f.length) continue;
            if (bucket.length) [bucket appendString:@" "];
            [bucket appendString:f];
        }
        // حدسِ سشنِ کهنه را ننویس: سشنِ تازه از همان صدا حدسِ خودش را دارد و آن یکی
        // فقط متن را عقب می‌کشد.
        if (gen == me->_gen && ev.hasResults) me->_interim = ev.interim ?: @"";
        [me->_lock unlock];
        [me push];
    };
    s.onClose = ^(NSString *reason) {
        typeof(self) me = weak;
        if (!me) return;
        [me closed:gen reason:reason];
    };
    [_lock lock];
    _cur = s;
    [_lock unlock];
    [s connect];
}

// سشنی بسته شد. اگر سشنِ فعلی بود یعنی برنامه‌ریزی‌نشده (قطعی شبکه، رد شدن اندپوینت):
// یک بار دیگر باز کن، ولی نه بی‌نهایت. سشنِ بازنشسته‌ی چرخش اینجا کاری ندارد.
- (void)closed:(NSUInteger)gen reason:(NSString *)reason {
    [_lock lock];
    BOOL wasCurrent = (gen == _gen) && !_stopped;
    if (wasCurrent) _cur = nil;
    NSInteger fails = wasCurrent ? ++_fails : _fails;
    [_lock unlock];
    if (!wasCurrent) return;
    if (fails >= kZPreviewMaxFails) {
        ZLog(@"preview: %ld بار پشت سر هم بسته شد (%@)؛ تا پایان سشن خاموش", (long)fails, reason);
        [self stop];
        return;
    }
    ZLog(@"preview: بسته شد (%@)، دوباره باز می‌شود", reason);
    [self open];
}

// ---------- صدا ----------
// از نخ صداست، مثل بقیه‌ی مسیر. هیچ‌وقت بلوکه نمی‌شود و هیچ‌وقت خطا بالا نمی‌دهد:
// پیش‌نمایشِ خراب باید بی‌سروصدا بمیرد، نه اینکه دیکته را بگیرد.
- (void)feed:(NSData *)pcm {
    [_lock lock];
    ZGoogleStream *s = _stopped ? nil : _cur;
    BOOL rotate = NO;
    if (s) {
        _sec += pcm.length / kZPcmBytesPerSec;
        rotate = _sec >= kZPreviewRotateSec;
    }
    [_lock unlock];
    if (!s) return;
    [s feed:pcm];
    if (!rotate) return;
    // پایانِ نرم، نه cancel: آخرین فاینال‌های همین دور هنوز در راه‌اند و سطلِ خودشان
    // سر جایش است، پس وقتی برسند دقیقا همان‌جا می‌نشینند. cancel آن‌ها را می‌خورد.
    [s finishUpload];
    [self open];
}

// ---------- متن ----------

- (NSString *)compose {
    NSMutableString *out = [NSMutableString string];
    for (NSMutableString *b in _buckets) {
        if (!b.length) continue;
        if (out.length) [out appendString:@" "];
        [out appendString:b];
    }
    if (_interim.length) {
        if (out.length) [out appendString:@" "];
        [out appendString:_interim];
    }
    return out;
}

- (void)push {
    [_lock lock];
    NSString *text = [self compose];
    BOOL same = [text isEqualToString:_sent];
    if (!same) _sent = text;
    BOOL dead = _stopped;
    [_lock unlock];
    if (same || dead) return;    // interim که عوض نشده، یک بازنویسیِ بی‌خود روی ادیتور است
    __weak typeof(self) weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) me = weak;
        if (!me || me->_stopped || !me.onText) return;
        me.onText(text);
    });
}

// سطل آشغال. سشنِ فعلی هم می‌رود و نه فقط سطل‌ها: فاینال‌هایش هنوز در راه‌اند و اگر
// بگذاریمش، همان حرف‌هایی که کاربر دور ریخت چند ثانیه بعد برمی‌گردند. بالا بردنِ
// `_gen` هر رویدادِ در پروازِ آن سشن را بی‌اثر می‌کند.
- (void)reset {
    [_lock lock];
    if (_stopped) {
        [_lock unlock];
        return;
    }
    ZGoogleStream *old = _cur;
    _cur = nil;
    _gen++;
    [_buckets removeAllObjects];
    _interim = @"";
    _sent = @"";
    _fails = 0;
    [_lock unlock];
    [old cancel];
    [self open];
    if (self.onText) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (self.onText) self.onText(@""); });
    }
}

- (void)stop {
    [_lock lock];
    if (_stopped) {
        [_lock unlock];
        return;
    }
    _stopped = YES;
    ZGoogleStream *s = _cur;
    _cur = nil;
    _gen++;    // هر رویدادِ در پروازِ سشنِ قبلی از این به بعد بی‌اثر است
    [_lock unlock];
    [s cancel];
}

@end
