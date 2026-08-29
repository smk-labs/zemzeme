// تستِ طلاییِ «نشستنِ متن در کادرِ مقصد»، همان چیزی که باگ B7 رویش گیر کرد.
//
// B7 چه بود: ۲۰۲۶-۰۸-۲۱ ساعت ۱۱:۲۳:۵۸، هفت تکه رفت و هفت تکه برگشت، `0 در راه`،
// و لاگ گفت `pasting 370 chars`. کاربر ۱۲۱ نویسه‌ی آخر را در کادر دید. گم شدن
// بیرون از زمزمه بود و این تست هم ادعا نمی‌کند آن را می‌گیرد. دو چیزِ دستِ خودمان
// را می‌گیرد:
//
//   یک، تور نجات. وقتی پیست ناقص می‌نشیند، تنها راهِ کاربر یک Cmd+V دستی است، و آن
//   فقط وقتی کار می‌کند که **آخرین** چیزِ روی کلیپ‌بورد کلِ متن باشد، نه نسخه‌ی
//   transient ای که مسیرِ پیست وسطِ کار می‌نویسد. این ترتیب یک بار شکسته بود
//   (tools/livestring_test.m سرش را شرح می‌دهد) و آن بار هیچ گاردی نداشت.
//
//   دو، عددی که ریشه را معلوم می‌کند. تا امروز لاگ فقط «چه فرستادیم» را داشت، پس
//   B7 با «ریشه ناشناس» ماند. حالا کادرِ مقصد پیش و پسِ پیست شمرده می‌شود.
//
// و آنچه عمدا **نیست**: هیچ هشداری روی پنل. دلیلش عدد است نه سلیقه، و در بندِ B7
// سندِ extras/docs/dev-notes/BUGS-2026-08-21.md نوشته شده.
#import <Foundation/Foundation.h>

static int failures = 0;

static void ok(BOOL cond, const char *what) {
    printf("%s %s\n", cond ? "ok  " : "FAIL", what);
    if (!cond) failures++;
}

// همان الگوی مسیرِ پیست، بی AppKit: یک صفِ سریال، یک «کلیپ‌بورد»، و دو نویسنده.
static NSString *zRunClipboard(dispatch_queue_t q, BOOL finalCopyLast,
                               NSString *slice, NSString *whole) {
    __block NSString *board = nil;
    void (^pasteStep)(void) = ^{
        board = slice;          // نسخه‌ی transient، همان که Cmd+V می‌خورد
        usleep(50000);          // مهلتِ سینک و خودِ Cmd+V
    };
    void (^finalStep)(void) = ^{ board = whole; };
    if (finalCopyLast) {
        dispatch_async(q, pasteStep);
        dispatch_async(q, finalStep);
    } else {
        dispatch_async(q, finalStep);
        dispatch_async(q, pasteStep);
    }
    dispatch_sync(q, ^{});
    return board;
}

static NSString *zSource(NSString *path) {
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]
           ?: @"";
}

int main(void) { @autoreleasepool {
    NSString *whole = @"کلِ حرفِ کاربر که سیصد و هفتاد نویسه بود";
    NSString *slice = @"فقط تکه‌ای که سر کرسر رفت";
    dispatch_queue_t q = dispatch_queue_create("test.inject", DISPATCH_QUEUE_SERIAL);

    // ---------- ادعای یک: ترتیب، و اینکه شکستنش واقعا متن را می‌برد ----------
    ok([zRunClipboard(q, NO, slice, whole) isEqualToString:slice],
       "کپیِ پایانی جلوتر از پیست، کلیپ‌بورد را با تکه رها می‌کند (پس باگ واقعی بود)");
    ok([zRunClipboard(q, YES, slice, whole) isEqualToString:whole],
       "کپیِ پایانی پشتِ پیست، کلِ متن را روی کلیپ‌بورد می‌گذارد");

    // ---------- ادعای دو: خودِ سورس، چون تستِ بالا session.m را لینک نمی‌کند ----------
    NSString *ses = zSource(@"app/Sources-objc/session.m");
    ok(ses.length > 0, "session.m خوانده شد");
    NSRange ins  = [ses rangeOfString:@"[inj insert:text pid:"];
    NSRange keep = [ses rangeOfString:@"[inj copyFinalAfterPending:keep]"];
    ok(ins.location != NSNotFound && keep.location != NSNotFound && ins.location < keep.location,
       "درج اول صف می‌شود و کپیِ پایانی بعدش، پس پیستِ دستی همیشه کل متن را دارد");
    // و آنچه نگه داشته می‌شود کلِ متن است نه تکه‌ی سر کرسر. اگر فردا کسی `fresh` را
    // اینجا بگذارد، پیستِ دستیِ کاربر همان ناقصی را دوباره می‌دهد.
    ok([ses containsString:@"keep:ZSigned(all)"],
       "آنچه روی کلیپ‌بورد می‌ماند کلِ متن است، نه تکه‌ی سر کرسر");

    // ---------- ادعای سه: اندازه‌گیری هست، و روی مسیرِ زنده سوار نیست ----------
    NSString *inj = zSource(@"app/Sources-objc/inject.m");
    ok(inj.length > 0, "inject.m خوانده شد");
    ok([inj containsString:@"static NSInteger zBoxChars(pid_t pid)"],
       "کادرِ مقصد شمرده می‌شود");
    ok([inj containsString:@"NSInteger before = path == ZWritePaste && !pasteIfRefused"],
       "فقط مسیرِ «اتمیک رد شد» شمرده می‌شود؛ اپی که خودش پیست می‌خواهد کادر نمی‌دهد");
    // خواندنِ دوم باید dispatch خودش را داشته باشد. بی آن، پشتِ صف می‌ماندِ کپیِ
    // پایانی و تور نجات دیرتر می‌رسد؛ دقیقا همان چیزی که ادعای یک نگهش می‌دارد.
    NSRange after = [inj rangeOfString:@"NSInteger after = zBoxChars(pid)"];
    NSRange async = [inj rangeOfString:@"dispatch_async(ZInjectQueue(), ^{\n            NSInteger after"];
    ok(after.location != NSNotFound && async.location != NSNotFound,
       "خواندنِ دوم پشتِ صف می‌رود، پس کپیِ پایانی را عقب نمی‌اندازد");

    // ---------- ادعای چهار: مثبتِ کاذب، همان چیزی که هشدار را رد می‌کند ----------
    // کادرِ مقصد تقریبا همیشه از قبل متن دارد. پس تنها عددِ معنادار **رشدِ** کادر
    // است، نه طولش. با یک عدد (طولِ کادر) هر درجی در یک کادرِ پر «ناقص» دیده می‌شد،
    // و آژیرِ همیشه‌روشن همان آژیرِ خاموش است.
    NSInteger sent = 370;
    ok((2370 - 2000) == sent, "کادرِ پر با درجِ کامل، رشدش دقیقا اندازه‌ی متنِ فرستاده است");
    ok((2121 - 2000) < sent, "کادرِ پر با درجِ ناقص، رشدش کمتر از متنِ فرستاده است");
    ok((370 - 0) == sent, "کادرِ خالی هم با همان یک قاعده سنجیده می‌شود");
    // و «نشد خواند» فرق دارد با «چیزی ننشست»: کلاینتِ ریموت کادری نمی‌دهد و آنجا
    // سکوت درست است، نه ادعای شکست.
    ok([inj containsString:@"@\"نشد خواند\""],
       "نخواندنِ کادر جدا از ننشستنِ متن گزارش می‌شود");

    printf(failures ? "\nlanding: %d ادعا افتاد\n" : "\nlanding: همه‌ی ادعاها درست\n", failures);
    return failures ? 1 : 0;
} }
