// تستِ طلاییِ «یک صفِ درج برای کلِ اپ». یک قاعده را می‌سنجد و همان قاعده کلیپ‌بورد را
// سنگین کرد و متنِ عوضی پیست کرد:
//
//   دو درج هیچ‌وقت نباید هم‌زمان اجرا شوند.
//
// کامنتِ خودِ inject.m از روز اول این را ادعا می‌کرد («همه چیز روی یک صف سریال تا دو
// پیست مسابقه‌ی کلیپ‌بورد نگیرند»)، ولی صف در `init` ساخته می‌شد و هر درج یک
// `[ZInjector new]` تازه بود. دو شیء یعنی دو صف، و دو صف یعنی هم‌زمان.
//
// هزینه‌اش سه‌تاست: پیستِ دوم وسطِ مهلتِ ۶۰۰ میلی‌ثانیه‌ایِ اولی کلیپ‌بورد را عوض می‌کند
// و Cmd+V اولی متنِ دومی را می‌گذارد؛ دو فلیکِ درهم رگبارِ عوض شدنِ پنجره‌ی کلید
// می‌سازد و کلاینت ریموت سرِ هر بار کلِ کلیپ‌بورد را دوباره می‌خواند؛ و
// `ZNoAXWritePids` که قفل ندارد چون «فقط روی صف درج دست می‌خورد»، از دو صف دستکاری
// می‌شود.
//
// سه ادعا: صفِ به‌ازای شیء واقعا هم‌پوشانی می‌دهد (مکانیزم اثبات شود، نه فرض)، صفِ
// مشترک نمی‌دهد، و خودِ inject.m امروز صفِ مشترک را صدا می‌زند.
#import <Foundation/Foundation.h>
#import <stdatomic.h>

static int failures = 0;

static void ok(BOOL cond, const char *what) {
    printf("%s %s\n", cond ? "ok  " : "FAIL", what);
    if (!cond) failures++;
}

// یک «درج» ساختگی: مثل پیستِ واقعی، مدتی طول می‌کشد و در آن مدت روی یک منبعِ مشترک
// (اینجا شمارنده، آنجا کلیپ‌بورد) دست دارد. اگر دو تا هم‌زمان بروند، شمارنده از یک
// بالاتر می‌رود و همان لحظه‌ی مسابقه است.
static void fakeInject(dispatch_queue_t q, _Atomic int *live, _Atomic int *peak, dispatch_group_t g) {
    dispatch_group_async(g, q, ^{
        int now = atomic_fetch_add(live, 1) + 1;
        int seen = atomic_load(peak);
        while (now > seen && !atomic_compare_exchange_weak(peak, &seen, now)) {}
        usleep(60000);    // جای مهلتِ سینکِ کلیپ‌بورد
        atomic_fetch_sub(live, 1);
    });
}

int main(void) { @autoreleasepool {
    // ادعای یک: الگوی قدیمی. هر «شیء» صفِ خودش را می‌سازد.
    {
        _Atomic int live = 0, peak = 0;
        dispatch_group_t g = dispatch_group_create();
        for (int i = 0; i < 4; i++) {
            dispatch_queue_t own = dispatch_queue_create("per.object", DISPATCH_QUEUE_SERIAL);
            fakeInject(own, &live, &peak, g);
        }
        dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
        ok(atomic_load(&peak) > 1, "صفِ به‌ازای شیء واقعا هم‌زمان می‌شود (پس باگ واقعی بود)");
    }

    // ادعای دو: صفِ مشترک. همان چهار درج، همان کد، فقط یک صف.
    {
        _Atomic int live = 0, peak = 0;
        dispatch_group_t g = dispatch_group_create();
        dispatch_queue_t shared = dispatch_queue_create("zemzeme.inject", DISPATCH_QUEUE_SERIAL);
        for (int i = 0; i < 4; i++) fakeInject(shared, &live, &peak, g);
        dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
        ok(atomic_load(&peak) == 1, "صفِ مشترک هیچ‌وقت دو درج را هم‌زمان نمی‌کند");
    }

    // ادعای سه: خودِ سورس. تستِ رفتاری بالا inject.m را لینک نمی‌کند (به کارِبن و
    // اکسسبیلیتی و پنجره وصل است و پیستِ واقعی رویدادِ واقعی می‌فرستد)، پس قاعده را
    // همین‌جا روی متن می‌سنجیم: کسی که فردا صف را به شیء برگرداند باید اینجا قرمز
    // ببیند، نه در کلیپ‌بوردِ کاربر.
    NSString *src = [NSString stringWithContentsOfFile:@"app/Sources-objc/inject.m"
                                              encoding:NSUTF8StringEncoding error:nil];
    ok(src.length > 0, "inject.m خوانده شد");
    ok([src containsString:@"static dispatch_queue_t ZInjectQueue(void)"],
       "صفِ درج یک تابعِ ثابتِ سطحِ فایل است، نه فیلدِ شیء");
    ok(![src containsString:@"dispatch_async(_q"],
       "هیچ درجی روی صفِ شیء نمی‌رود");

    printf(failures ? "\ninjectq: %d ادعا افتاد\n" : "\ninjectq: همه‌ی ادعاها درست\n", failures);
    return failures ? 1 : 0;
} }
