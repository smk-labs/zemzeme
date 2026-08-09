// تست طلاییِ ساعتِ گیر کردن. بی‌میکروفن، بی‌شبکه، در کمتر از یک ثانیه.
//
// «گیر کردن» یعنی سرور زنده است و فریم می‌فرستد ولی دیگر متنی نمی‌دهد. تشخیصش دو
// طرفِ خرابی دارد و هر دو بد است: دیر بفهمد، کاربر چند ثانیه به متنِ یخ‌زده نگاه
// می‌کند؛ زود بفهمد، استریمِ سالمی را می‌کشد که داشت صدای بازپخش را می‌جوید، و چون
// جایگزینش بازپخشِ درازتری می‌گیرد همان اشتباه بزرگ‌تر تکرار می‌شود.
//
// باگی که این تست نگهبانش است: مهلتِ جویدنِ بازپخش فقط **سنجش** را معلق می‌کرد و از
// ساعت کم نمی‌شد. سشن ۲۰۲۶-۰۸-۰۸ ساعت ۰۹:۲۲ همین دستگاه: «stalled 6s»، ده ثانیه بعد
// «stalled 10s»، و بعد بازپخش روی سقفِ ۱۲ ثانیه میخ شد. ۲۷ ثانیه حرف زدن، ۸۱ نویسه.
//
// اجرا: bash tools/stall_test.sh
#import <Foundation/Foundation.h>
#import "zemzeme.h"

static int gFail;

static void ok(BOOL cond, NSString *what) {
    if (cond) {
        printf("ok   %s\n", what.UTF8String);
        return;
    }
    gFail++;
    printf("FAIL %s\n", what.UTF8String);
}

// یک استریم را همان‌طور که موتور می‌سازدش وصف می‌کند: لحظه‌ی باز شدن، ثانیه‌های صدای
// کهنه‌ای که با آن شروع کرده، و اینکه از آن به بعد نتیجه‌ای گرفته یا نه.
typedef struct {
    NSDate *lastResultAt;
    NSDate *graceUntil;
} ZStreamClock;

static ZStreamClock opened(NSDate *at, NSTimeInterval prerollSec) {
    // آینه‌ی openStream: هر دو از لحظه‌ی باز شدن ست می‌شوند و مهلت به اندازه‌ی
    // بازپخش به‌علاوه‌ی دو ثانیه است.
    return (ZStreamClock){ .lastResultAt = at,
                           .graceUntil = [at dateByAddingTimeInterval:prerollSec + 2.0] };
}

static BOOL due(ZStreamClock c, NSDate *now, NSTimeInterval voiced) {
    return voiced > kZStallVoiceSec && ZStallSeconds(c.lastResultAt, c.graceUntil, now) > kZStallSec;
}

int main(void) {
    @autoreleasepool {
        NSDate *t0 = [NSDate dateWithTimeIntervalSince1970:1000000];
        NSTimeInterval talking = kZStallVoiceSec + 1.0;    // دارد حرف می‌زند

        // ---------- استریمِ تازه بی‌بازپخش ----------
        ZStreamClock fresh = opened(t0, 0);
        ok(!due(fresh, [t0 dateByAddingTimeInterval:1], talking),
           @"استریمِ تازه در ثانیه‌ی اول متهم نمی‌شود");
        ok(!due(fresh, [t0 dateByAddingTimeInterval:5], talking),
           @"دو ثانیه مهلت به‌علاوه‌ی پنج ثانیه سقف: در ثانیه‌ی پنجم هنوز نه");
        ok(due(fresh, [t0 dateByAddingTimeInterval:8], talking),
           @"ولی در ثانیه‌ی هشتم بله");

        // ---------- استریمی که با بازپخش باز شده: قلبِ باگ ----------
        // این همان استریمِ دومِ سشن ۰۹:۲۲ است: ۶٫۴ ثانیه صدای کهنه، پس مهلتش تا
        // ثانیه‌ی ۸٫۴ است. اگر ساعت از لحظه‌ی باز شدن برود، همان‌جا شمارنده ۸٫۴ است
        // و سقفِ ۵ از قبل رد شده: در اولین tickِ بعد از مهلت کشته می‌شود.
        ZStreamClock replayed = opened(t0, 6.4);
        ok(!due(replayed, [t0 dateByAddingTimeInterval:8.0], talking),
           @"وسط مهلت متهم نمی‌شود");
        ok(!due(replayed, [t0 dateByAddingTimeInterval:8.5], talking),
           @"و درست بعد از مهلت هم نه: تازه اول فرصتش است");
        ok(!due(replayed, [t0 dateByAddingTimeInterval:10.0], talking),
           @"ده ثانیه بعد از باز شدن هنوز نه (باگِ قدیمی اینجا می‌کشتش)");
        ok(!due(replayed, [t0 dateByAddingTimeInterval:13.0], talking),
           @"در ثانیه‌ی سیزدهم هم نه: ۸٫۴ مهلت به‌علاوه‌ی ۵ سقف یعنی ۱۳٫۴");
        ok(due(replayed, [t0 dateByAddingTimeInterval:14.0], talking),
           @"ولی بعد از مهلت به‌علاوه‌ی پنج ثانیه‌ی کامل، بله");

        // ---------- بازپخشِ درازتر، مهلتِ درازتر ----------
        // بی این، هر کشتن بازپخشِ درازتری به بعدی می‌داد و کشتنِ بعدی حتمی‌تر می‌شد.
        ZStreamClock capped = opened(t0, 12.0);
        ok(!due(capped, [t0 dateByAddingTimeInterval:14.0], talking),
           @"با بازپخشِ سقف، تا پایان مهلت (۱۴ ثانیه) هیچ اتهامی نیست");
        ok(!due(capped, [t0 dateByAddingTimeInterval:18.0], talking),
           @"و پنج ثانیه‌ی فرصتش هنوز تمام نشده");
        ok(due(capped, [t0 dateByAddingTimeInterval:20.0], talking),
           @"بعدش بله");

        // ---------- نتیجه‌ای که وسط مهلت رسید ----------
        // مهلت هنوز جلوتر است، پس ساعت از پایانِ مهلت می‌رود نه از خودِ نتیجه.
        ZStreamClock c = opened(t0, 6.4);
        c.lastResultAt = [t0 dateByAddingTimeInterval:3.0];
        ok(!due(c, [t0 dateByAddingTimeInterval:12.0], talking),
           @"نتیجه‌ی وسطِ مهلت پنجره را کوتاه نمی‌کند");
        ok(due(c, [t0 dateByAddingTimeInterval:14.0], talking),
           @"و بعد از مهلت به‌علاوه‌ی سقف، بله");

        // ---------- نتیجه‌ای که بعد از مهلت رسید ----------
        // حالا مهلت گذشته است و ساعت باید از خودِ نتیجه برود، وگرنه تشخیصِ گیر کردن
        // روی یک استریمِ طولانی هیچ‌وقت تازه نمی‌شد.
        ZStreamClock d = opened(t0, 6.4);
        d.lastResultAt = [t0 dateByAddingTimeInterval:20.0];
        ok(!due(d, [t0 dateByAddingTimeInterval:24.0], talking),
           @"بعد از نتیجه‌ی تازه، شمارنده صفر می‌شود");
        ok(due(d, [t0 dateByAddingTimeInterval:26.0], talking),
           @"و پنج ثانیه بعدش دوباره می‌شمارد");

        // ---------- شرطِ صدا ----------
        ok(!due(fresh, [t0 dateByAddingTimeInterval:60], 0),
           @"سکوت هرچقدر هم طول بکشد گیر کردن نیست");
        ok(!due(fresh, [t0 dateByAddingTimeInterval:60], kZStallVoiceSec),
           @"و یک مکثِ فکر کردن هم نه");

        printf(gFail ? "\nstall: %d FAIL\n" : "\nstall: all passed  (0 failed)\n", gFail);
    }
    return gFail ? 1 : 0;
}
