// تستِ طلاییِ فلیکِ پنجره‌ی کلید. رفتار واقعی سیستم‌عامل را می‌سنجد، نه ادای آن را:
// پنجره باید کلید بگیرد، اپ نباید فعال شود، و کلید باید پس داده شود.
//
// چرا این سه تا: پیستِ ریموت روی هر سه بند است. اگر پنجره کلید نگیرد، کلاینت ریموت
// کلیپ‌بورد تازه را به سرور نمی‌فرستد و متن قبلی پیست می‌شود. اگر اپ فعال شود، فوکس
// از اپ مقصد کنده می‌شود و متن جای دیگری می‌رود. و اگر کلید پس داده نشود، Cmd+V بعدی
// (و هر چه کاربر بعدش تایپ کند) به پنجره‌ی ما می‌رسد نه به اپ مقصد.
#import "zemzeme.h"

static int failures = 0;

static void ok(BOOL cond, const char *what) {
    printf("%s %s\n", cond ? "ok  " : "FAIL", what);
    if (!cond) failures++;
}

// حلقه‌ی اصلی را برای مدت کوتاهی بچرخان: رویدادهای سرورِ پنجره در همین حلقه پردازش
// می‌شوند، پس بی این هیچ‌کدام از این حالت‌ها به‌روز نمی‌شود.
static void spin(NSTimeInterval sec) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:sec]];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        // اکسسوری، دقیقا مثل خودِ زمزمه (LSUIElement): بی این، اپِ تست خودش می‌آید جلو
        // و تست چیزی را می‌سنجد که در محصول اتفاق نمی‌افتد.
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        spin(0.3);

        NSRunningApplication *before = NSWorkspace.sharedWorkspace.frontmostApplication;
        printf("front before: %s\n", before.bundleIdentifier.UTF8String ?: "?");
        ok(!NSApp.isActive, "اپِ تست از اول فعال نیست");
        ok(NSApp.keyWindow == nil, "از اول هیچ پنجره‌ی کلیدی نداریم");

        // فلیک روی صف جداست، همان‌جور که در محصول از صف درج صدا زده می‌شود: بین گرفتن
        // و پس دادنِ کلید، حلقه‌ی اصلی باید آزاد باشد.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [ZKeyFlick flick];
        });

        spin(0.04);    // وسطِ نگه‌داشتن (فلیک ۸۰ میلی‌ثانیه نگه می‌دارد)
        ok(NSApp.keyWindow != nil, "وسط فلیک، پنجره‌ی ما کلید است");
        // «اپِ جلو» همان می‌ماند و این مهم‌ترین بند است: رول‌های کارابینر که به
        // frontmost_application_if بسته‌اند (Cmd+A داخل ریموت و بقیه) از همین می‌خوانند،
        // پس فلیک آن‌ها را نمی‌شکند. NSApp.isActive اما وسط فلیک YES می‌شود، چون پنجره‌ی
        // کلید دستِ ماست. اندازه‌گیری‌شده، و بی‌اهمیت: اپ اکسسوری است و منوباری ندارد
        // که عوض شود، و ۸۰ میلی‌ثانیه بعد پس داده می‌شود.
        printf("     (وسط فلیک NSApp.isActive=%d، انتظارِ همین است)\n", NSApp.isActive);
        ok(NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier
               == before.processIdentifier, "وسط فلیک، اپِ جلو عوض نشده");

        spin(0.4);     // بعد از پس دادن
        ok(NSApp.keyWindow == nil, "بعد از فلیک، کلید پس داده شد");
        ok(!NSApp.isActive, "بعد از فلیک، اپ فعال نشده");
        ok(NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier
               == before.processIdentifier, "بعد از فلیک، اپِ جلو عوض نشده");

        // دو بار پشت هم: پنجره یک‌بار ساخته می‌شود و باید دوباره هم کار کند
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [ZKeyFlick flick];
        });
        spin(0.04);
        ok(NSApp.keyWindow != nil, "فلیکِ دوم هم کلید می‌گیرد");
        spin(0.4);
        ok(NSApp.keyWindow == nil, "فلیکِ دوم هم کلید را پس می‌دهد");

        printf("\n%s\n", failures == 0 ? "flick: all passed" : "flick: FAILED");
        return failures == 0 ? 0 : 1;
    }
}
