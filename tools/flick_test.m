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

        // ---------- فوکوسِ ادیتورِ پنل ----------
        // ادیتورِ حالت «جمع در پنل» فوکوس نمی‌گرفت و ویرایش کار نمی‌کرد، در حالی که
        // NSTextView از اول editable بود. علت یک پیش‌فرضِ AppKit بود، و همین‌جا روی
        // خودِ سیستم‌عامل سنجیده می‌شود نه با حدس: پنجره‌ی borderless پیش‌فرض
        // canBecomeKeyWindow=NO می‌دهد، پس becomesKeyOnlyIfNeeded هیچ‌وقت شانسی نداشت.
        // اگر روزی اپل این پیش‌فرض را عوض کند، این ادعا قرمز می‌شود و می‌فهمیم که
        // زیرکلاسِ ZPanelWindow دیگر لازم نیست.
        NSPanel *plain = [[NSPanel alloc]
            initWithContentRect:NSMakeRect(0, 0, 100, 40)
                      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                        backing:NSBackingStoreBuffered defer:NO];
        ok(!plain.canBecomeKeyWindow,
           "پنلِ borderless خودش کلید نمی‌شود؛ همین بود که ویرایش را کشته بود");

        NSString *pan = [NSString stringWithContentsOfFile:@"app/Sources-objc/panel.m"
                                                 encoding:NSUTF8StringEncoding error:nil];
        ok(pan.length > 0, "panel.m خوانده شد");
        ok([pan containsString:@"@implementation ZPanelWindow"] &&
           [pan containsString:@"- (BOOL)canBecomeKeyWindow { return YES; }"],
           "ZPanelWindow پیش‌فرض را برمی‌گرداند تا ادیتور فوکوس بگیرد");
        ok([pan containsString:@"[[ZPanelWindow alloc] initWithContentRect:"],
           "خودِ پنل از همان زیرکلاس ساخته می‌شود، نه NSPanel خام");
        // و becomesKeyOnlyIfNeeded باید بماند: بی آن، پنل با آمدنش کلید می‌شود و
        // فوکوسِ کاربر را وسط کار از اپ مقصد می‌کند.
        ok([pan containsString:@"becomesKeyOnlyIfNeeded = YES"],
           "پنل فقط با کلیک روی ادیتور کلید می‌شود، نه با آمدنش");

        // **بندِ حیاتی.** پیست با CGEventPost به هر که فوکوس دارد می‌رود نه به یک pid،
        // پس پنلِ کلید یعنی متن در خودِ پنل پیست می‌شود و اپ مقصد دست خالی می‌ماند.
        // کسی که فردا این خط را بردارد باید اینجا قرمز ببیند، نه در متنِ کاربر.
        NSString *ses = [NSString stringWithContentsOfFile:@"app/Sources-objc/session.m"
                                                 encoding:NSUTF8StringEncoding error:nil];
        NSRange inj = [ses rangeOfString:@"- (void)injectAtCaret:"];
        NSRange yld = [ses rangeOfString:@"[_panel yieldKey];"];
        ok(inj.location != NSNotFound && yld.location != NSNotFound && yld.location > inj.location
           && yld.location - inj.location < 500,
           "هر درجی اول کلید را پس می‌دهد، وگرنه پیست در خودِ پنل می‌نشیند");

        printf("\n%s\n", failures == 0 ? "flick: all passed" : "flick: FAILED");
        return failures == 0 ? 0 : 1;
    }
}
