// تستِ طلاییِ «میکروفن کر». دو قاعده را می‌سنجد، و هر دو از یک باگِ واقعی آمده‌اند:
// کاربر دابل‌تپ می‌زد، پنل باز می‌شد، تا آخر حرف می‌زد، و هیچ متنی نمی‌آمد. در لاگ هم
// هیچ نشانه‌ای نبود: خطِ `mic:` سالم نشسته بود.
//
// ریشه: `ZMic` یک AVAudioEngine می‌ساخت و تمام عمر اپ نگه می‌داشت، ولی ناظرِ
// AVAudioEngineConfigurationChangeNotification را فقط داخل `startWithError:` می‌بست
// و در `stop` برمی‌داشت. یعنی هر عوض شدنِ دستگاه صدا **در فاصله‌ی دو سشن** به هیچ‌کس
// گفته نمی‌شد: هدست وصل یا قطع، درِ لپ‌تاپ، داک، و مهم‌تر از همه خواب و بیداری مک.
// سشنِ بعدی تپ را روی گره‌ی ورودیِ کهنه می‌بست، `startAndReturnError` هم موفق
// برمی‌گشت، و یک بایت صدا نمی‌آمد.
//
// چرا ادعاها روی سورس‌اند و نه روی خودِ ZMic: بازکردنِ میکروفن واقعی به اجازه‌ی مک و
// سخت‌افزارِ حاضر بند است، پس تستی که آن را لازم داشته باشد روی یک مکِ بی‌اجازه قرمز
// می‌شود و دیگر کسی جدی‌اش نمی‌گیرد. به‌جایش شکلِ تورِ ایمنی مستقل مدل می‌شود (همان
// کاری که injectq_test با صفِ درج می‌کند) و قاعده‌ی ریشه روی متنِ سورس سنجیده می‌شود.
#import <Foundation/Foundation.h>
#import <stdatomic.h>

static int failures = 0;

static void ok(BOOL cond, const char *what) {
    printf("%s %s\n", cond ? "ok  " : "FAIL", what);
    if (!cond) failures++;
}

// ---------- مدلِ تورِ ایمنی ----------
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

int main(void) {
    @autoreleasepool {

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

    printf(failures ? "\ndeafmic: %d ادعا افتاد\n" : "\ndeafmic: همه‌ی ادعاها درست\n", failures);
    return failures ? 1 : 0;
} }
