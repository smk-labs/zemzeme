// نوبتِ پاس: یک کارِ کامل در هر لحظه، روی انتقالی که دو مصرف‌کننده دارد.
//
// چرا این فایل هست (باگ واقعی، نه احتیاط): نگهبانِ «یک کار در هر لحظه» تا امروز دستِ
// خودِ فراخوان‌ها بود، و آن پرچم‌ها هر کدام مالِ یک پنل بودند: سشن با `_working` و
// `_enhancing`، پنل فایل با `_polishing`. پرچمِ پنل‌به‌پنل با هم جمع نمی‌شود، پس پاس
// نهاییِ سشن و کارِ پنل فایل واقعا روی هم می‌افتادند و دو چیز خراب می‌شد:
//   · تسکِ در پرواز یک خانه بیشتر نداشت، پس دومی روی اولی می‌نوشت و `cancel` فقط
//     همانی را می‌کشت که آن لحظه ثبت بود. دیگری بی‌صاحب می‌ماند و تا آخر می‌رفت.
//   · `resetCancel` یک بولینِ مشترک را صفر می‌کرد، پس کاربری که همین حالا «لغو» زده
//     بود جوابش را باز هم می‌گرفت.
//
// دو تصمیمِ اصلی این فایل:
//
//   · نوبت مالِ **کل پاس** است نه یک تماس. قفلِ تماس‌به‌تماس غلط بود: پاس نهایی دو تا
//     سه تماس دارد و بین «مو‌به‌مو» و «تمیزکاری» یک کارِ دیگر جا می‌شد.
//   · آزاد کردن کارِ فراخوان **نیست**. `ZPassLease` یک شی است و `dealloc` آزاد می‌کند،
//     پس متغیرِ محلیِ ARC خودش کار را تمام می‌کند. دلیلش شمردنی است: دو متد `work:`
//     روی هم هفده نقطه‌ی بازگشت دارند (کلید نبود، پرامپت نبود، لغو، شکست HTTP، تسلیمِ
//     دروازه). یک آزادسازیِ فراموش‌شده یعنی فیچر تا ری‌استارتِ بعدی قفل، که از خودِ
//     رقابتی که داریم درستش می‌کنیم بدتر است. شکلی که نشود فراموش کرد، بهتر از شکلی
//     است که باید نُه جا یادت بماند.
//
// عمدا فقط به Foundation وابسته است تا تنهایی کامپایل شود: `bash tools/passlock_test.sh`.
#import "zemzeme.h"

NSString *const ZPassOwnerFinal = @"پاس نهایی";
NSString *const ZPassOwnerEnhance = @"بهبود پرامپت";

// متدهای داخلی: فقط `ZPassLease` صدایشان می‌زند و هر دو در همین فایل‌اند.
@interface ZPassLock (ZLeasePrivate)
- (void)give:(uint64_t)gen;
- (BOOL)cancelledGen:(uint64_t)gen;
@end

@implementation ZPassLease {
    ZPassLock *_lock;
    uint64_t _gen;
}

// قفل را نگه می‌دارد و قفل او را نه: چرخه‌ای در کار نیست. قفل فقط یک عدد (نسل) از
// نوبت می‌داند، نه خودِ شی را.
- (instancetype)initWithLock:(ZPassLock *)lock owner:(NSString *)owner gen:(uint64_t)gen {
    if ((self = [super init])) {
        _lock = lock;
        _owner = [owner copy];
        _gen = gen;
    }
    return self;
}

- (BOOL)cancelled { return [_lock cancelledGen:_gen]; }

// تنها راهِ آزاد شدن. هیچ متدِ عمومیِ «آزاد کن» وجود ندارد، و این عمدی است: تا وقتی
// یک راه باشد، نمی‌شود در نُه نقطه‌ی بازگشت هشت جایش را یادت بماند.
- (void)dealloc { [_lock give:_gen]; }

@end

@implementation ZPassLock {
    NSLock *_mx;
    BOOL _busy;
    NSString *_who;
    // نسل: هر نوبت یک شماره‌ی تازه می‌گیرد، و لغو روی همان شماره می‌نشیند نه روی یک
    // بولینِ مشترک. همین یک عدد `resetCancel` را حذف کرد: لغوِ نوبتِ قبلی هیچ‌وقت به
    // نوبتِ بعدی نمی‌رسد، چون شماره‌اش دیگر آن نیست.
    uint64_t _gen;             // نوبتِ جاری؛ از ۱ شروع می‌شود، پس صفر یعنی «هیچ‌وقت»
    uint64_t _cancelledGen;    // نسلی که لغو شد؛ صفرِ اولیه با هیچ نوبتی برابر نمی‌افتد
    NSURLSessionTask *_task;
    NSURLSession *_session;
}

- (instancetype)init {
    if ((self = [super init])) _mx = [NSLock new];
    return self;
}

// مشغول بود یعنی **همان لحظه نه**، نه «در صف بمان». صف زدن اینجا غلط است: پاس نهایی
// دقیقه‌ها طول می‌کشد و کاربری که دکمه را زده منتظرِ یک جواب است، نه منتظرِ نوبت. پیامِ
// رد کردن هم زیر همین قفل ساخته می‌شود تا اسمِ کاری که واقعا در جریان است درست باشد.
- (ZPassLease *)claim:(NSString *)owner busy:(NSString **)busy {
    [_mx lock];
    if (_busy) {
        NSString *who = _who;
        [_mx unlock];
        if (busy) {
            *busy = [NSString stringWithFormat:
                @"%@ همین حالا در جریان است؛ یک کار در هر لحظه. کمی بعد دوباره بزن.", who];
        }
        return nil;
    }
    _busy = YES;
    _who = [owner copy];
    uint64_t g = ++_gen;
    [_mx unlock];
    return [[ZPassLease alloc] initWithLock:self owner:owner gen:g];
}

- (void)give:(uint64_t)gen {
    NSURLSessionTask *t = nil;
    NSURLSession *s = nil;
    [_mx lock];
    if (_busy && _gen == gen) {
        _busy = NO;
        _who = nil;
        // تسکِ جامانده نباید باشد (`disarm` بعد از هر تماس پاکش می‌کند)، ولی اگر بود
        // باید با همین نوبت برود. وگرنه نوبتِ بعدی صاحبِ تسکی می‌شد که مالِ او نیست و
        // اولین «لغو»ش کارِ خودش را نمی‌کشت، کارِ مرده‌ی قبلی را.
        t = _task;
        s = _session;
        _task = nil;
        _session = nil;
    }
    [_mx unlock];
    [t cancel];
    [s invalidateAndCancel];
}

- (BOOL)cancelledGen:(uint64_t)gen {
    [_mx lock];
    BOOL c = (gen != 0 && _cancelledGen == gen);
    [_mx unlock];
    return c;
}

// لغو **به نامِ صاحب**. قبلا یک بولینِ مشترک بود، پس Esc در سشن می‌توانست کارِ پنل فایل
// را بکشد و برعکس. حالا اگر کاری که در جریان است مالِ این صاحب نباشد، اینجا هیچ اتفاقی
// نمی‌افتد: نه پرچمی، نه تسکی.
- (BOOL)cancelOwner:(NSString *)owner {
    NSURLSessionTask *t = nil;
    NSURLSession *s = nil;
    BOOL mine = NO;
    [_mx lock];
    if (_busy && [_who isEqualToString:owner]) {
        mine = YES;
        _cancelledGen = _gen;
        t = _task;
        s = _session;
        _task = nil;
        _session = nil;
    }
    [_mx unlock];
    // بیرون از قفل: `invalidateAndCancel` کال‌بک می‌اندازد و زیر قفل نگهش داشتن یعنی
    // قفلِ درهم. بدنه‌ی درخواست چند مگابایت صداست و قطعش واقعا لازم است.
    [t cancel];
    [s invalidateAndCancel];
    return mine;
}

// تسکِ در پرواز، فقط برای نوبتِ جاری. `NO` یعنی همین حالا لغو شده و درخواست اصلا
// فرستاده نشود: کسی که «لغو» زده منتظرِ تمام شدنِ یک آپلود نیست.
- (BOOL)armTask:(NSURLSessionTask *)task session:(NSURLSession *)session {
    [_mx lock];
    BOOL live = _busy && _cancelledGen != _gen;
    if (live) {
        _task = task;
        _session = session;
    }
    [_mx unlock];
    return live;
}

- (void)disarm {
    [_mx lock];
    _task = nil;
    _session = nil;
    [_mx unlock];
}

- (NSString *)busyOwner {
    [_mx lock];
    NSString *o = _busy ? _who : nil;
    [_mx unlock];
    return o;
}

@end
