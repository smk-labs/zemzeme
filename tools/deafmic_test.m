// تستِ طلاییِ «میکروفن کر». دو نسل از یک باگ، و هر دو نسل از یک شکایتِ واقعی آمده‌اند:
// کاربر دابل‌تپ می‌زد، پنل باز می‌شد، تا آخر حرف می‌زد، و هیچ متنی نمی‌آمد و هیچ خطایی
// هم نه.
//
// نسلِ اول، صفر بایت. ریشه: `ZMic` یک AVAudioEngine می‌ساخت و تمام عمر اپ نگه
// می‌داشت، ولی ناظرِ AVAudioEngineConfigurationChangeNotification را فقط داخل
// `startWithError:` می‌بست و در `stop` برمی‌داشت. یعنی هر عوض شدنِ دستگاه صدا **در
// فاصله‌ی دو سشن** به هیچ‌کس گفته نمی‌شد: هدست وصل یا قطع، درِ لپ‌تاپ، داک، و مهم‌تر
// از همه خواب و بیداری مک. سشنِ بعدی تپ را روی گره‌ی ورودیِ کهنه می‌بست،
// `startAndReturnError` هم موفق برمی‌گشت، و یک بایت صدا نمی‌آمد.
//
// نسلِ دوم (B9)، بایت می‌آید ولی هیچ حرفی در آن نیست. سشنِ ۲۰۲۶-۰۸-۱۸ ساعت ۰۵:۴۱:۰۸
// از تورِ نسلِ اول رد شد: پنج دقیقه صدا رسید، ۴۷ تکه رفت، هر ۴۷ تا «حرفی نبود»
// برگشت، و کاربر صفر نویسه و صفر خطا دید. تصمیمش حالا در warn.m است.
//
// چرا ادعاهای نسلِ اول روی سورس‌اند و نه روی خودِ ZMic: بازکردنِ میکروفن واقعی به
// اجازه‌ی مک و سخت‌افزارِ حاضر بند است، پس تستی که آن را لازم داشته باشد روی یک مکِ
// بی‌اجازه قرمز می‌شود و دیگر کسی جدی‌اش نمی‌گیرد. به‌جایش شکلِ تورِ ایمنی مستقل مدل
// می‌شود (همان کاری که injectq_test با صفِ درج می‌کند) و قاعده‌ی ریشه روی متنِ سورس
// سنجیده می‌شود.
//
// ولی ادعاهای نسلِ دوم روی کدِ واقعی‌اند، چون آستانه دارند: pipe.m و queue.m و warn.m
// کامپایل می‌شوند و فقط `ZGoogleStream` بدل است.
#import "zemzeme.h"
#import "warn.h"
#import <stdatomic.h>

static int failures = 0;

static void ok(BOOL cond, const char *what) {
    printf("%s %s\n", cond ? "ok  " : "FAIL", what);
    if (!cond) failures++;
}

// ---------- مدلِ تورِ ایمنیِ نسلِ اول ----------
// همان شکلی که در audio.m هست: شماره‌ی سشن، بیتِ «صدا رسید»، و بیتِ «یک بار از نو
// ساختم». `dispatch_after` لغو نمی‌شود، پس تنها راهِ از کار انداختنش شماره است.
typedef struct {
    dispatch_queue_t q;        // جای نخ اصلی
    NSUInteger gen;
    BOOL started;
    BOOL rebuilt;
    atomic_bool gotAudio;
    _Atomic int rebuilds;      // چند بار موتور از نو ساخته شد
    _Atomic int deafReports;   // چند بار به کاربر گفته شد
    dispatch_group_t g;
} Watch;

static const NSTimeInterval kCeiling = 0.02;   // سقفِ تست؛ در محصول ۱٫۲ ثانیه است

static void arm(Watch *w, NSUInteger gen) {
    dispatch_group_enter(w->g);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCeiling * NSEC_PER_SEC)), w->q, ^{
        if (!w->started || w->gen != gen) { dispatch_group_leave(w->g); return; }
        if (atomic_load(&w->gotAudio)) { dispatch_group_leave(w->g); return; }
        if (!w->rebuilt) {
            w->rebuilt = YES;
            atomic_fetch_add(&w->rebuilds, 1);
            arm(w, gen);                      // یک دور دیگر، و همین یکی
            dispatch_group_leave(w->g);
            return;
        }
        atomic_fetch_add(&w->deafReports, 1);
        dispatch_group_leave(w->g);
    });
}

static Watch *newWatch(void) {
    Watch *w = calloc(1, sizeof(Watch));
    w->q = dispatch_queue_create("zemzeme.test.watch", DISPATCH_QUEUE_SERIAL);
    w->g = dispatch_group_create();
    w->started = YES;
    w->gen = 1;
    atomic_store(&w->gotAudio, false);
    return w;
}

static void settle(Watch *w) {
    dispatch_group_wait(w->g, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)));
    dispatch_sync(w->q, ^{});
}

// ---------- بدل‌ها ----------
// core.m این را از audio.m می‌خواهد و تست میکروفن ندارد
void ZMicSetHighSensitivity(BOOL on) { (void)on; }
// و warn.m این را از app.m می‌خواهد. کلیدش اینجاست تا هر دو جوابِ مک آزموده شود.
static BOOL gClash = NO;
BOOL ZMacDictationOnDoubleCommand(void) { return gClash; }

// بدلِ شبکه: یا متن می‌دهد یا «شنیدم و حرفی نبود». همان جفتِ (متن، دلیلِ بسته شدن)
// که queue_test هم دارد، چون تمامِ تصمیمِ صف روی همین دو تا سوار است.
static BOOL gEmpty = NO;
static NSLock *gLock;

@implementation ZGoogleStream {
    NSUInteger _fed;
    BOOL _closed;
}
- (instancetype)initWithLang:(NSString *)lang { (void)lang; return [super init]; }
- (void)connect { }
- (void)feed:(NSData *)pcm { _fed += pcm.length; }
- (void)finishUpload {
    _bytesFed = _fed;
    BOOL empty = gEmpty;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        if (!empty && self.onEvent) {
            ZSpeechEvent *ev = [ZSpeechEvent new];
            ev.hasResults = YES;
            ev.finals = [NSMutableArray arrayWithObject:@"یک جمله"];
            self.onEvent(ev);
        }
        [self close:@"ok"];      // بسته شدنِ تمیز: یعنی «گوش کردم»، نه «نرسیدم»
    });
}
- (void)cancel { [self close:@"cancelled"]; }
- (void)close:(NSString *)reason {
    [gLock lock];
    BOOL was = _closed;
    _closed = YES;
    [gLock unlock];
    if (was) return;
    if (self.onClose) self.onClose(reason);
}
@end

// ---------- صدای واقعی ----------
// آرام‌ترین ضبطِ ریپو: پچ‌پچ. اوجِ rms اش در قابِ هفت‌ثانیه‌ای ۰٫۰۰۸۱ است، یعنی فقط
// ۱٫۶ برابرِ kZVoiceRMS، و همین آن را بدترین حالتِ «حرفِ واقعیِ آرام» می‌کند. اگر
// نگهبان قرار باشد جایی الکی آژیر بکشد، اینجاست.
//
// و با `ZDecodePCMRange` خوانده می‌شود نه با خواندنِ خامِ فایل، چون همان دری است که
// خودِ صف برای تکه‌ی در انتظار از آن می‌خواند.
static NSData *whisper(double seconds) {
    NSURL *u = [NSURL fileURLWithPath:@"tools/fixtures/read-aloud/04-pechpech.wav"];
    NSError *err = nil;
    NSData *d = ZDecodePCMRange(u, 0, (unsigned long long)(seconds * 16000), &err);
    if (!d.length) fprintf(stderr, "  fixture خوانده نشد: %s\n",
                           err.localizedDescription.UTF8String ?: "?");
    return d;
}

static NSData *hush(double seconds) {
    NSMutableData *d = [NSMutableData data];
    [d increaseLengthBy:(NSUInteger)(seconds * 16000) * 2];
    return d;
}

// یک سشن: صدا از همان دانه‌بندیِ ۱۰۰ میلی‌ثانیه‌ایِ موتور رد می‌شود، بعد ته‌مانده
// بریده می‌شود، بعد تا خالی شدنِ صف صبر می‌کنیم. سقفِ انتظار پایین‌تر آمده است.
static ZQueue *run(NSData *audio, BOOL emptyReplies) {
    gEmpty = emptyReplies;
    ZQueue *q = [ZQueue new];
    ZPipe *fa = [[ZPipe alloc] initWithLang:@"fa-IR"];
    fa.queue = q;
    const NSUInteger step = 3200;
    for (NSUInteger off = 0; off < audio.length; off += step)
        [fa feed:[audio subdataWithRange:NSMakeRange(off, MIN(step, audio.length - off))] at:off];
    [fa finish];
    [q waitForFirstPass];
    return q;
}

// انتظار با سقف، و ساعتش همین حلقه است: انتظارِ بی‌سقف در این ریپو ممنوع است. عدد
// عمدا بزرگ است چون کارش ممنوع‌کردن است نه اندازه‌گیریِ سرعت؛ روی دستگاهِ سالم هر
// انتظار با شرطِ خودش تمام می‌شود و این عدد دیده نمی‌شود.
static const double kWaitCeiling = 20.0;

static BOOL settleQueue(ZQueue *q) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:kWaitCeiling];
    while (q.waiting > 0 && [NSDate.date compare:end] == NSOrderedAscending) usleep(20000);
    return q.waiting == 0;
}

static NSInteger silentCount(ZQueue *q) {
    NSInteger n = 0;
    for (ZSlot *s in q.snapshot) if (!s.extra && s.state == ZSlotSilent) n++;
    return n;
}

int main(void) {
    @autoreleasepool {
    gLock = [NSLock new];

    // ---------- نسلِ اول: صفر بایت ----------

    // ادعای یک: میکروفنِ کر **یک بار** موتور را از نو می‌سازد و **یک بار** به کاربر
    // می‌گوید. حلقه نمی‌زند. اگر این بشکند، اپ تا آخر سشن هر ۱٫۲ ثانیه یک موتور صدا
    // می‌سازد، که از خودِ کر بودن بدتر است.
    {
        Watch *w = newWatch();
        arm(w, w->gen);
        settle(w);
        ok(atomic_load(&w->rebuilds) == 1, "صدا که نیامد، موتور دقیقا یک بار از نو ساخته می‌شود");
        ok(atomic_load(&w->deafReports) == 1, "و دقیقا یک بار به کاربر گفته می‌شود");
    }

    // ادعای دو: صدا که می‌آید، تورِ ایمنی هیچ کاری نمی‌کند. آژیرِ الکی روی سشنِ سالم
    // یعنی کاربر یاد می‌گیرد نادیده‌اش بگیرد.
    {
        Watch *w = newWatch();
        atomic_store(&w->gotAudio, true);
        arm(w, w->gen);
        settle(w);
        ok(atomic_load(&w->rebuilds) == 0 && atomic_load(&w->deafReports) == 0,
           "سشنِ سالم هیچ آژیری نمی‌زند");
    }

    // ادعای سه: سشن که تمام شد، تورِ ایمنیِ در پرواز باید بی‌اثر شود. بی این، کاربر
    // یک ثانیه بعد از Esc پیامِ خطای سشنِ تمام‌شده را می‌بیند.
    {
        Watch *w = newWatch();
        arm(w, w->gen);
        dispatch_sync(w->q, ^{ w->started = NO; w->gen++; });   // همان کاری که stop می‌کند
        settle(w);
        ok(atomic_load(&w->rebuilds) == 0 && atomic_load(&w->deafReports) == 0,
           "سشنِ تمام‌شده آژیر نمی‌زند، چون شماره عوض شده");
    }

    // ---------- نسلِ دوم: بایت می‌آید و حرفی در آن نیست ----------

    NSData *quiet = whisper(29.0);
    ok(quiet.length > 16000 * 20 * 2, "پچ‌پچِ واقعی از ZDecodePCMRange خوانده شد");

    // مثبتِ کاذبِ یک، و مهم‌ترینشان: کاربری که فکر می‌کند. سکوتِ محض اصلا وارد صف
    // نمی‌شود (خط لوله همان‌جا می‌اندازدش)، پس هیچ‌وقت «حرفی نبود» نمی‌سازد.
    {
        ZQueue *q = run(hush(40.0), YES);
        ok(settleQueue(q), "صفِ سکوت ته کشید");
        ok(q.snapshot.count == 0, "سکوتِ محض هیچ جایی در صف نمی‌گیرد");
        ok(ZDeafWarning(q.snapshot) == nil, "کاربری که چهل ثانیه فکر می‌کند هشدار نمی‌گیرد");
    }

    // مثبتِ کاذبِ دو: حرفِ واقعیِ آرام که متن هم می‌گیرد. اولین متن که برسد، میکروفن
    // خودش را ثابت کرده و پرونده بسته است.
    {
        ZQueue *q = run(quiet, NO);
        ok(settleQueue(q), "صفِ پچ‌پچ ته کشید");
        ok(q.snapshot.count > 0, "پچ‌پچ از دروازه‌ی حرف‌داشتن رد می‌شود");
        ok(ZDeafWarning(q.snapshot) == nil, "حرفِ آرامی که متن می‌گیرد هشدار نمی‌گیرد");
    }

    // و حالا خودِ باگ: همان صدای واقعی، ولی سرور هر بار می‌گوید حرفی نبود.
    {
        NSMutableData *long_ = [NSMutableData data];
        for (int i = 0; i < 3; i++) [long_ appendData:quiet];    // ~۸۷ ثانیه، بیش از پنج تکه
        ZQueue *q = run(long_, YES);
        ok(settleQueue(q), "صفِ کر ته کشید");
        NSInteger n = silentCount(q);
        ok(n >= 5, "سشنِ کر بیش از پنج تکه‌ی بی‌حرف ساخت");
        NSString *w = ZDeafWarning(q.snapshot);
        ok(w.length > 0, "میکروفنِ کر به کاربر گفته می‌شود");
        ok([w containsString:@"Sound"], "و متنش می‌گوید کجا را باید عوض کرد");
        printf("     %ld تکه‌ی بی‌حرف، آستانه ۵\n", (long)n);
    }

    // آستانه واقعا آستانه است: چهار تا هنوز ساکت است. بی این ادعا، عدد پنج فقط یک
    // حرف است و کسی نمی‌فهمد کِی عوض شده.
    {
        NSMutableArray<ZSlot *> *slots = [NSMutableArray array];
        for (int i = 0; i < 4; i++) {
            ZSlot *s = [ZSlot new];
            s.seq = i;
            s.state = ZSlotSilent;
            [slots addObject:s];
        }
        ok(ZDeafWarning(slots) == nil, "چهار تکه‌ی بی‌حرف هنوز هشدار نیست");
        ZSlot *fifth = [ZSlot new];
        fifth.seq = 4;
        fifth.state = ZSlotSilent;
        [slots addObject:fifth];
        ok(ZDeafWarning(slots).length > 0, "پنجمی هشدار است");
        // پاس دومِ انگلیسی شمرده نمی‌شود: هر جور شکستش ZSlotSilent است، پس اگر
        // شمرده می‌شد آژیر روی سشنِ سالم هم زودتر می‌رفت.
        NSMutableArray<ZSlot *> *withExtra = [NSMutableArray array];
        for (int i = 0; i < 5; i++) {
            ZSlot *s = [ZSlot new];
            s.seq = i;
            s.state = ZSlotSilent;
            s.extra = (i % 2 == 1);
            [withExtra addObject:s];
        }
        ok(ZDeafWarning(withExtra) == nil, "جای پاس دوم در این شمار نمی‌آید");
        // و یک متن که برسد، پرونده بسته است حتی اگر بعدش باز هم ساکت بیاید.
        ZSlot *done = [ZSlot new];
        done.seq = 0;
        done.state = ZSlotDone;
        done.text = @"یک جمله";
        [slots insertObject:done atIndex:0];
        ok(ZDeafWarning(slots) == nil, "یک متن که آمد، دیگر هشداری نیست");
    }

    // ---------- B8: برخوردِ میان‌بر ----------
    // نه خودش را تکرار می‌کند و نه وقتی برخوردی نیست حرفی می‌زند.
    {
        gClash = NO;
        ok(ZClashWarning() == nil, "بی برخورد، هیچ هشداری نیست");
        gClash = YES;
        NSString *first = ZClashWarning();
        ok(first.length > 0, "با برخورد، یک بار گفته می‌شود");
        ok([first containsString:@"Dictation"], "و متنش می‌گوید کجا باید خاموش شود");
        ok(ZClashWarning() == nil, "و بارِ دوم دیگر تکرار نمی‌شود");
    }

    // ---------- قاعده‌ی ریشه، روی سورس ----------
    NSString *src = [NSString stringWithContentsOfFile:@"app/Sources-objc/audio.m"
                                              encoding:NSUTF8StringEncoding error:nil];
    ok(src.length > 0, "audio.m خوانده شد");

    // **موتور در init ساخته نمی‌شود.** این خطِ اصلیِ باگ بود: یک موتور برای تمام عمر اپ.
    ok(![src containsString:@"_engine = [AVAudioEngine new];\n        //"] &&
       [src containsString:@"- (BOOL)buildEngineWithError:"],
       "ساختنِ موتور تابعِ خودش را دارد، نه یک خط در init");
    ok([src containsString:@"_engine = [AVAudioEngine new]"],
       "موتور همان‌جا از نو ساخته می‌شود");
    ok([src containsString:@"if (![self buildEngineWithError:err]) { _started = NO; return NO; }"],
       "هر سشن با موتورِ تازه شروع می‌شود");
    // ناظرِ تغییرِ پیکربندی باید داخل همان ساختن باشد، نه جای دیگر: هر موتورِ تازه
    // ناظرِ خودش را لازم دارد، چون ناظر به شیءِ موتور بسته می‌شود.
    NSRange build = [src rangeOfString:@"- (BOOL)buildEngineWithError:"];
    NSRange watch = [src rangeOfString:@"- (void)armDeafWatchdog"];
    NSRange obs   = [src rangeOfString:@"AVAudioEngineConfigurationChangeNotification"];
    ok(build.location != NSNotFound && watch.location != NSNotFound &&
       obs.location != NSNotFound && obs.location > build.location && obs.location < watch.location,
       "ناظرِ تغییرِ پیکربندی با هر موتورِ تازه از نو بسته می‌شود");
    ok([src containsString:@"_gen++;     // تورِ ایمنیِ در پرواز از کار می‌افتد"],
       "stop شماره‌ی سشن را بالا می‌برد");

    // و سرِ دیگرِ سیم: کر بودن باید به کاربر برسد، وگرنه فقط در لاگ می‌ماند و لاگ را
    // کسی وسط کار نمی‌خواند.
    NSString *eng = [NSString stringWithContentsOfFile:@"app/Sources-objc/engine.m"
                                              encoding:NSUTF8StringEncoding error:nil];
    ok([eng containsString:@"_mic.onDeaf = ^{"] &&
       [eng containsString:@"ZEngineGaveUp"],
       "onDeaf به مسیرِ خطای دیدنیِ کاربر وصل است");

    // و نسلِ دوم هم باید سیم داشته باشد، نه فقط تابع: بی این خط، warn.m یک کتابخانه‌ی
    // بی‌مشتری است و باگ سرِ جایش می‌ماند.
    NSString *ses = [NSString stringWithContentsOfFile:@"app/Sources-objc/session.m"
                                              encoding:NSUTF8StringEncoding error:nil];
    ok([ses containsString:@"ZDeafWarning(_queue.snapshot)"] &&
       [ses containsString:@"ZClashWarning()"],
       "هر دو هشدار از session.m به پنل می‌روند");

    printf(failures ? "\ndeafmic: %d ادعا افتاد\n" : "\ndeafmic: همه‌ی ادعاها درست\n", failures);
    return failures ? 1 : 0;
} }
