// تستِ طلاییِ «هیچ انتظاری روی صف اصلی». یک قاعده را می‌سنجد و همان قاعده یک بار اپ
// را کامل قفل کرد:
//
//   بلاکی که روی صف اصلی در حال اجراست، حق ندارد منتظر بلاکِ بعدیِ همان صف بماند.
//
// صف اصلی سریال است و **بازگشتی نیست**: چرخاندنِ دستیِ ران‌لوپ از داخل یک بلاکِ صف
// اصلی، بلاکِ بعدیِ آن صف را اجرا نمی‌کند. پس `while (!landed) { runMode… }` که منتظرِ
// یک `dispatch_async(main)` باشد، تا ابد می‌چرخد.
//
// این دقیقا آنچه افتاد: ذخیره‌ی کلید Gemini یک شیت «در حال بررسی…» می‌گذاشت و منتظرِ
// جوابی می‌ماند که با dispatch_async روی صف اصلی برمی‌گشت. از منو (رویداد عادی) کار
// می‌کرد، ولی از مسیرِ toggleAIPass → dispatch_after → offerKey → menuSetKey، خودش
// **داخلِ** یک بلاکِ صف اصلی بود و اپ روی همان پنجره خشک شد. لاگ هم هیچ نگفت، چون
// هیچ خطایی رخ نداده بود.
//
// دو ادعا: انتظار قفل می‌کند (تا مکانیزم اثبات شود، نه فرض)، و شکلِ درست قفل نمی‌کند.
#import <Foundation/Foundation.h>

static int failures = 0;

static void ok(BOOL cond, const char *what) {
    printf("%s %s\n", cond ? "ok  " : "FAIL", what);
    if (!cond) failures++;
}

// ادعای یک: الگوی قدیمی. از داخل یک بلاکِ صف اصلی، منتظرِ یک بلاکِ دیگرِ صف اصلی
// می‌مانیم و ران‌لوپ را دستی می‌چرخانیم. نباید هیچ‌وقت برسد.
//
// سقفِ خودِ تست یک ثانیه است: تستی که برای اثباتِ «قفل می‌کند» خودش قفل کند، تست نیست.
static void testWaitingDeadlocks(void) {
    __block BOOL landed = NO;
    __block BOOL timedOut = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        // همان کاری که saveKeyTested: قدیمی می‌کرد
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            dispatch_async(dispatch_get_main_queue(), ^{ landed = YES; });
        });
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
        while (!landed && [NSDate.date compare:deadline] == NSOrderedAscending) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                                   beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        timedOut = !landed;
        CFRunLoopStop(CFRunLoopGetMain());
    });
    CFRunLoopRun();
    ok(timedOut, "انتظار روی صف اصلی واقعا قفل می‌کند (پس باگ واقعی بود، نه حدس)");
}

// ادعای دو: شکلِ درست. بلاکِ صف اصلی **برمی‌گردد** و جواب در نوبتِ تازه‌ی خودش
// می‌آید. همین است که saveKeyTested: حالا می‌کند.
static void testReturningLands(void) {
    __block BOOL landed = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                landed = YES;
                CFRunLoopStop(CFRunLoopGetMain());
            });
        });
        // و بس. هیچ انتظاری، هیچ چرخاندنِ ران‌لوپی.
    });
    // سقف، که شکستِ تست هم قفل نشود بلکه FAIL بدهد
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ CFRunLoopStop(CFRunLoopGetMain()); });
    CFRunLoopRun();
    ok(landed, "برگشتن به‌جای انتظار: جواب در نوبت تازه می‌رسد");
}

int main(void) {
    @autoreleasepool {
        testWaitingDeadlocks();
        testReturningLands();
        printf(failures ? "\nmainq: %d ادعا شکست\n" : "\nmainq: همه‌ی ادعاها درست\n", failures);
        return failures ? 1 : 0;
    }
}
