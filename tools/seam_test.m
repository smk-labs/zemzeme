// تست طلاییِ جوش درز. بی‌میکروفن، بی‌شبکه، در کمتر از یک ثانیه.
//
// هر مورد از یک درزِ واقعیِ همین دستگاه آمده (فایل‌های خام sessions/، یعنی پیش از
// پاس ویرایش و پیش از هر درجی). سه تای اولش باگ‌های ثبت‌شده‌اند: همان چند کلمه سر
// درزِ چرخش دو بار نوشته می‌شد.
//
// اجرا: bash tools/seam_test.sh
#import <Foundation/Foundation.h>
#import "zemzeme.h"

static int gFail;

// دقیقا همان کاری که موتور سر درز می‌کند: جوش بزن، بعد فقط تکه‌ی تازه را بردار.
// اگر تست مستقیم روی رشته‌ی جوش‌خورده ادعا می‌کرد، مسیر واقعی را نمی‌سنجید.
static NSString *ZSeamRest(NSString *prev, NSString *cur, double overlapSec) {
    NSString *joined = ZStitchOverlapMax(prev, cur, ZStitchWords(overlapSec));
    if (joined.length <= prev.length) return nil;    // «کل تکه تکراری بود»: موتور خام نگه می‌دارد
    return [[joined substringFromIndex:prev.length]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static void expect(NSString *name, NSString *got, NSString *want) {
    BOOL ok = want ? [got isEqualToString:want] : (got == nil);
    if (!ok) gFail++;
    printf("%s %s\n", ok ? "ok  " : "FAIL", name.UTF8String);
    if (!ok) {
        printf("      want: %s\n", want ? want.UTF8String : "(raw, fully redundant)");
        printf("      got:  %s\n", got ? got.UTF8String : "(raw, fully redundant)");
    }
}

int main(void) {
    @autoreleasepool {
        // ---------- درزهای واقعی که تکرار می‌نوشتند ----------

        // sessions/app-2026-07-25-21-27-40.txt، خط ۱ و ۲
        expect(@"seam: نور خورشید (repeat at seam)",
               ZSeamRest(@"امروز می‌خوام درباره یک مطلب علمی نسبتا طولانی با شما صحبت کنم که حداقل "
                         @"بیشتر از ۳۰ ثانیه بشه و مثلاً راجع به درختان باشه می‌دونید درختان فتوسنتز "
                         @"رو با کمک نور خورشید انجام",
                         @"نور خورشید انجام می‌دهند که آفتاب که به برگ‌ها می‌تابه", 2.0),
               @"می‌دهند که آفتاب که به برگ‌ها می‌تابه");

        // sessions/app-2026-07-25-21-29-38.txt، خط ۱ و ۲
        expect(@"seam: متفاوتی دارند (repeat at seam)",
               ZSeamRest(@"خوبه مود حالت درج زنده رو هم تست کنم بنابراین یک بار دیگه این بار راجع به "
                         @"عطر و بوی گل‌ها می‌خوام صحبت کنم گل‌ها رنگ‌ها و بوهای متفاوتی دارند",
                         @"متفاوتی دارند معمولاً گل‌هایی که زیباتر هستند", 2.0),
               @"معمولاً گل‌هایی که زیباتر هستند");

        // sessions/app-2026-07-26-00-01-33.txt، خط ۱ و ۲. اینجاست که قاعده‌ی قبلی
        // می‌شکست: گوگل در ناحیه‌ی هم‌پوشانی «مرغابی» را «خوابی» شنید، تطبیقِ دقیق
        // ۵۰٪ شد و از آستانه‌ی ۷۰٪ رد نشد.
        expect(@"seam: مرغابی/خوابی (misheard inside the overlap)",
               ZSeamRest(@"خب الان داریم تست می‌کنیم برای یه متن طولانی راجع به انواع مرغابی مثلاً "
                         @"مرغابی سفید مرغابی سرخ مرغابی قرمز",
                         @"خوابی قرمز نارنجی زرد سبز آبی نیلی بنفش", 2.0),
               @"نارنجی زرد سبز آبی نیلی بنفش");

        // sessions/app-2026-07-25-20-37-43.txt: «جمع» وسط درز نصف شده بود. با
        // هم‌پوشانی، استریم تازه کلمه را از اولش می‌شنود و درز جوش می‌خورد.
        expect(@"seam: جمع (word halved at the cut, now whole)",
               ZSeamRest(@"نه حالتی که جمع", @"جمع می‌کنه در پنل در حالت جمع کن", 2.0),
               @"می‌کنه در پنل در حالت جمع کن");

        // ---------- چیزهایی که نباید جوش بخورند ----------

        expect(@"no-seam: two unrelated sentences stay whole",
               ZSeamRest(@"سلام حال شما چطور است", @"امروز هوا خیلی خوب است", 2.0),
               @"امروز هوا خیلی خوب است");

        // گفتار تکراری: باید کمترین چیز برداشته شود، نه بیشترین. با جهتِ حلقه‌ی
        // قبلی (از بزرگ‌ترین k) یک تطبیقِ الکیِ بزرگ زودتر جواب می‌داد و جمله را
        // می‌خورد؛ حالا بهترین امتیاز برنده است و سر تساوی k کوچک‌تر.
        expect(@"no-seam: repeated phrase loses only the real overlap",
               ZSeamRest(@"گفتم برو گفتم برو", @"گفتم برو دیگه", 2.0),
               @"دیگه");

        // پنجره هرگز از هم‌پوشانیِ صوتی گشادتر نمی‌شود. با هم‌پوشانی صفر، هیچ‌چیز
        // برداشته نمی‌شود حتی اگر متن تکراری به نظر برسد.
        expect(@"no-seam: a zero-second overlap removes nothing but an exact word",
               ZSeamRest(@"یک دو سه چهار پنج", @"شش هفت هشت", 0.0),
               @"شش هفت هشت");

        // «کل تکه تکراری بود» یعنی تردید، و در تردید متن خام می‌ماند
        expect(@"seam: fully redundant chunk keeps raw",
               ZSeamRest(@"الف ب ج د", @"ج د", 2.0), nil);

        // نیم‌فاصله و یای عربی نباید تفاوت حساب شوند: یک صدا، دو املا
        expect(@"seam: zwnj and arabic yeh fold before comparing",
               ZSeamRest(@"دارد می‌شود همين", @"داردمی شود همین کار", 2.0),
               @"کار");

        printf("\n%s  (%d failed)\n", gFail ? "FAILED" : "all seam tests passed", gFail);
        return gFail ? 1 : 0;
    }
}
