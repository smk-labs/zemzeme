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

static void ok(NSString *name, BOOL cond, NSString *detail) {
    if (!cond) gFail++;
    printf("%s %s\n", cond ? "ok  " : "FAIL", name.UTF8String);
    if (!cond && detail.length) printf("      %s\n", detail.UTF8String);
}

static void eq(NSString *name, NSString *got, NSString *want) {
    ok(name, [got isEqualToString:want],
       [NSString stringWithFormat:@"want: «%@»\n      got:  «%@»", want, got]);
}

static void expect(NSString *name, NSString *got, NSString *want) {
    BOOL pass = want ? [got isEqualToString:want] : (got == nil);
    ok(name, pass, [NSString stringWithFormat:@"want: %@\n      got:  %@",
                    want ?: @"(raw, fully redundant)", got ?: @"(raw, fully redundant)"]);
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

        // ---------- درزهای سشن سه‌دقیقه‌ای 2026-07-26 ----------
        // اینها را بازپخشِ یک سشن واقعی پیدا کرد، نه چشم.

        // سشن قدیمی یک کلمه‌ی اضافه وسط ناحیه‌ی هم‌پوشانی ساخت («جستجرهای»). مقایسه‌ی
        // خانه‌به‌خانه از آنجا به بعد همه‌چیز را یک خانه جابه‌جا می‌دید و درز تکرار نوشت.
        expect(@"seam: an extra word inside the overlap still aligns",
               ZSeamRest(@"نزدیکی به کیبورد هست که با سه انگشت چهار انگشت جستجرهای مختلفی که",
                         @"چهار انگشت مختلفی که داره و کلاً اصلاً او اسش", 2.0),
               @"داره و کلاً اصلاً او اسش");

        // و وقتی کل تکه واقعا دوباره شنیده شده و تطبیق تقریبا دقیق است، باید دور برود.
        // اینجا ZStitchOverlapMax همان `a` را می‌دهد (یعنی «چیزی برای اضافه کردن نیست»)
        // و ZTranscript از روی همین امتیاز تصمیم می‌گیرد دورش بریزد.
        ZSeamMatch m = ZSeamFind(@"تو هم لاگ رو بخونی خوبه و بعدش میرم سراغ تست با دو مدل دیگه",
                                 @"مدل دیگه", ZStitchWords(2.0));
        ok(@"seam: a fully re-heard chunk is recognised with certainty",
           m.dropWords == 2 && m.score >= 0.90,
           [NSString stringWithFormat:@"drop=%lu score=%.2f", (unsigned long)m.dropWords, m.score]);

        // ولی تطبیقِ لب‌مرزی نباید «قطعی» حساب شود؛ آنجا خام می‌ماند
        ZSeamMatch weak = ZSeamFind(@"یک دو سه چهار", @"پنج شش", ZStitchWords(2.0));
        ok(@"seam: an unrelated chunk is not a match at all", weak.dropWords == 0,
           [NSString stringWithFormat:@"drop=%lu score=%.2f", (unsigned long)weak.dropWords, weak.score]);


        // ---------- نجاتِ سر چرخش: نیم‌فاصله نباید کلِ جمله را دو بار بنویسد ----------
        // سشن واقعی 2026-07-26-03-09-19: نجات‌گرفته به «شونه‌تون» تمام می‌شد و آخرین
        // interim به «شونه» عقب نشسته بود. تطبیقِ پیش‌فرض سرِ نیم‌فاصله می‌ایستاد، پس
        // «شونه» را داخل «شونه‌تون» ندید و carry دو برابر شد: همان ۵۶ کلمه دو بار.
        {
            NSString *saved = @"پیشنهاد می‌کنم شما هم شونه‌تون";
            NSString *rolledBack = @"پیشنهاد می‌کنم شما هم شونه";
            eq(@"merge: a rollback across a half-space keeps the longer",
               ZMergeInterim(saved, rolledBack), saved);
        }

        // ---------- راچتِ دُم: عقب‌گردِ interim نمایش را پاک نکند ----------
        // رشته‌ها از سشن واقعی 03-09-19 همین دستگاه‌اند (رویدادهای ۱۰۵ تا ۱۰۸).

        NSString *longI = @"خیلی خیلی ظاهر آراسته‌تر و زیباتری پیدا می‌کنه و بقیه بهش رغبت "
            @"بیشتری پیدا می‌کنند و در جمع‌ها پذیرفته می‌شه و نهایتاً خیلی خیلی اتفاقات خوبی "
            @"براش می‌افته اما فقط محدود به این نیست شونه کار پزشکی خیلی مهم";
        NSString *rolled = @"خیلی خیلی ظاهر آراسته‌تر و زیباتری پیدا می‌کنه و بقیه بهش رغبت "
            @"بیشتری پیدا می‌کنند و در جمع‌ها پذیرفته می‌شه و نهایتاً خیلی خیلی";
        eq(@"ratchet: a rollback to a prefix keeps the long text",
           ZInterimRatchet(longI, rolled), longI);
        eq(@"ratchet: plain growth follows",
           ZInterimRatchet(@"سلام حال", @"سلام حال شما"), @"سلام حال شما");
        eq(@"ratchet: same-origin rewrite adopts the longer",
           ZInterimRatchet(@"سلام حال شما چطوره", @"سلام حال شما چطور است امروز"),
           @"سلام حال شما چطور است امروز");
        eq(@"ratchet: sliding window joins at the tail",
           ZInterimRatchet(@"یک دو سه چهار پنج", @"چهار پنج شش هفت"),
           @"یک دو سه چهار پنج شش هفت");
        // نیم‌فاصله سر رشدِ کلمه. دو باگِ واقعیِ سشن 2026-08-01-00-16-14 و ریشه‌ی هر
        // دو یکی بود: containsString: پیش‌فرض سرِ خوشه‌ی نویسه می‌ایستد و U+200C در
        // یونیکد ادامه‌ی حرف قبلی است، پس «نکته» را داخل «نکته‌اش» پیدا نمی‌کرد و
        // راچت به جای جایگزینی می‌چسباند. از همان‌جا به بعد دُم مسموم بود و کل جمله
        // سه بار در متن نشست.
        eq(@"ratchet: a word growing across a half-space is the same word",
           ZInterimRatchet(@"نکته", @"نکته‌اش"), @"نکته‌اش");
        eq(@"ratchet: and inside a sentence too",
           ZInterimRatchet(@"هست یعنی لایه", @"هست یعنی لایه‌های"),
           @"هست یعنی لایه‌های");
        eq(@"ratchet: a sliding window whose last word is still half-typed",
           ZInterimRatchet(@"ت ی‌ا", @"ی‌اسی"), @"ت ی‌اسی");
        eq(@"ratchet: a sliding window with a partial tail word",
           ZInterimRatchet(@"یک دو سه چهار پن", @"سه چهار پنج شش"),
           @"یک دو سه چهار پنج شش");
        {
            // هم‌پوشانیِ درازتر از پنجره‌ی قدیمیِ ۱۶ کلمه‌ای. سرِ cur هم بازنویسی شده،
            // پس فقط هم‌ترازیِ فازی جوابش را دارد. با سقفِ ۱۶، DP یک هم‌ترازیِ قلابیِ
            // کوتاه‌تر پیدا می‌کرد و باقی‌مانده را می‌چسباند: یک جمله دو بار.
            NSString *best = @"ت ی‌اسی و تک سونامی کامل کلی که اون یک کار اساسی اولی "
                @"در هر موضوعی هست یعنی لایه";
            NSString *cur = @"‌اسی و تک سونامی کامل کلی که اون یک کار اساسی اولی "
                @"در هر موضوعی هست یعنی لایه‌های";
            NSString *got = ZInterimRatchet(best, cur);
            ok(@"ratchet: an overlap longer than sixteen words still joins once",
               [got componentsSeparatedByString:@"سونامی"].count == 2, got);
        }
        {
            // روی دنباله‌ی واقعی، نمایش هیچ‌وقت کوتاه نمی‌شود
            NSArray *seq = @[rolled, longI, rolled,
                             [longI stringByAppendingString:@" هم هست"], rolled];
            NSString *best = @"";
            BOOL monotone = YES;
            for (NSString *cur in seq) {
                NSString *next = ZInterimRatchet(best, cur);
                if (next.length < best.length) monotone = NO;
                best = next;
            }
            ok(@"ratchet: the real rollback sequence never shrinks on screen", monotone,
               [NSString stringWithFormat:@"ended at: %@", best]);
            ok(@"ratchet: and the medical words survive the whole sequence",
               [best containsString:@"پزشکی"], best);
        }

        // ---------- دمِ پوشش‌داده‌نشده: متنِ قطعیِ کوتاه‌تر از دُمِ در دست ----------
        eq(@"uncovered: a final covering a prefix leaves the tail",
           ZUncoveredTail(longI, rolled),
           @"اتفاقات خوبی براش می‌افته اما فقط محدود به این نیست شونه کار پزشکی خیلی مهم");
        eq(@"uncovered: a final covering everything leaves nothing",
           ZUncoveredTail(rolled, longI), @"");
        eq(@"uncovered: an unrelated final claims nothing",
           ZUncoveredTail(@"یک دو سه چهار پنج شش هفت هشت", @"باران برف آفتاب ابر مه رعد طوفان"),
           @"");
        // «چطوره» در برابر «چطور است»: هم‌ترازی یک توکنِ لبِ مرز را نگه می‌دارد.
        // عمدی است: خطای این تابع باید به سمتِ تکرار بیفتد نه گم شدن، و «است»ِ
        // اضافه همان سمتِ امن است.
        eq(@"uncovered: wording drift keeps the boundary token (dup side, by rule)",
           ZUncoveredTail(@"سلام حال شما چطور است امروز هوا خوب است",
                          @"سلام حال شما چطوره"),
           @"است امروز هوا خوب است");

        printf("\n%s  (%d failed)\n", gFail ? "FAILED" : "all seam tests passed", gFail);
        return gFail ? 1 : 0;
    }
}
