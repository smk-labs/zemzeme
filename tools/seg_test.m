// تست طلایی برش‌زن: روی ضبط‌های واقعی، بی‌میکروفن و بی‌شبکه.
//
// سه ادعا سنجیده می‌شود، و هر سه همان‌هایی‌اند که کیفیت به آن‌ها بند است:
//   ۱. هر مرزی که برش‌زن انتخاب می‌کند واقعا داخل یک دوره‌ی ساکت است.
//   ۲. مسیر تحمیلی فقط وقتی گرفته می‌شود که پنجره واقعا مکثی نداشته باشد.
//   ۳. هیچ تکه‌ای از پنجره بیرون نمی‌زند و جمعِ تکه‌ها دقیقا کل فایل است.
#import <Foundation/Foundation.h>
#import "zemzeme.h"

static int gFail = 0;

static void ok(BOOL cond, NSString *what) {
    if (cond) return;
    gFail++;
    fprintf(stderr, "  ✗ %s\n", what.UTF8String);
}

// همان تابع توانِ داخل seg.m، اینجا مستقل نوشته شده: تست نباید از پیاده‌سازیِ
// زیرِ آزمون قرض بگیرد، وگرنه یک باگِ مشترک را هر دو با هم نمی‌بینند.
static float rmsAt(const int16_t *s, NSUInteger byteOff, NSUInteger frameBytes) {
    const int16_t *p = s + byteOff / 2;
    NSUInteger n = frameBytes / 2;
    float acc = 0;
    for (NSUInteger i = 0; i < n; i++) {
        float v = p[i] / 32768.0f;
        acc += v * v;
    }
    return sqrtf(acc / MAX(1u, (unsigned)n));
}

// آیا این نقطه وسط یک دوره‌ی ساکتِ واجد شرایط است؟ دور و برش را نگاه می‌کنیم، نه
// خودِ نقطه را: برش وسطِ مکث می‌نشیند، پس دو طرفش هم باید ساکت باشد.
static BOOL insideQuietRun(NSData *pcm, NSUInteger cut) {
    const NSUInteger frame = 640;
    const int16_t *s = pcm.bytes;
    NSUInteger half = (NSUInteger)(kZSegQuietMs / 20.0) / 2;   // فریم در هر طرف
    if (cut < half * frame || cut + half * frame > pcm.length) return NO;
    for (NSUInteger k = 0; k < half; k++) {
        if (rmsAt(s, cut - (k + 1) * frame, frame) > kZSegRMS) return NO;
        if (rmsAt(s, cut + k * frame, frame) > kZSegRMS) return NO;
    }
    return YES;
}

// آیا پنجره واقعا هیچ مکث واجد شرایطی نداشت؟ ادعای مسیر تحمیلی همین است و باید
// مستقل بررسی شود، وگرنه یک برش‌زنِ تنبل می‌توانست همیشه بگوید «مکثی نبود».
static BOOL windowHasNoPause(NSData *pcm, NSUInteger base) {
    const NSUInteger frame = 640;
    const NSUInteger lo = (NSUInteger)(kZSegMinSec * kZPcmBytesPerSec);
    const NSUInteger hi = (NSUInteger)(kZSegMaxSec * kZPcmBytesPerSec);
    const NSUInteger need = (NSUInteger)(kZSegQuietMs / 20.0);
    const int16_t *s = pcm.bytes;
    NSUInteger frames = MIN(pcm.length - base, hi) / frame;
    NSUInteger run = 0;
    for (NSUInteger f = 0; f <= frames; f++) {
        BOOL quiet = f < frames && rmsAt(s, base + f * frame, frame) <= kZSegRMS;
        if (quiet) { run++; continue; }
        if (run >= need) {
            NSUInteger mid = (f - run + run / 2) * frame;
            if (mid >= lo && mid <= hi) return NO;
        }
        run = 0;
    }
    return YES;
}

static NSData *readWav(NSString *path) {
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (d.length < 44) return nil;
    return [d subdataWithRange:NSMakeRange(44, d.length - 44)];   // هدر WAV، ۴۴ بایت
}

int main(int argc, const char **argv) { @autoreleasepool {
    NSString *dir = @"tools/fixtures/read-aloud";
    NSArray *takes = @[@"01-bi-vaghfe-normal", @"01-bi-vaghfe-fast", @"01-bi-vaghfe-mixed",
                       @"02-estelahat", @"03-maks", @"04-pechpech", @"05-adad",
                       @"06-mohavere", @"07-estelahat-sade"];
    NSUInteger totalSegs = 0, totalDeg = 0;
    printf("برش‌زن روی ضبط‌های واقعی:\n\n");
    printf("  %-22s %6s %6s %7s %7s %7s\n", "ضبط", "ثانیه", "تکه", "میانگین", "تحمیلی", "بلندترین");

    for (NSString *take in takes) {
        NSString *path = [NSString stringWithFormat:@"%@/%@.wav", dir, take];
        NSData *pcm = readWav(path);
        if (!pcm) { fprintf(stderr, "  ✗ خوانده نشد: %s\n", path.UTF8String); gFail++; continue; }

        NSUInteger base = 0, segs = 0, deg = 0;
        double longest = 0;
        while (base < pcm.length) {
            ZSegCut c = ZSegFind((const char *)pcm.bytes + base, pcm.length - base, YES);
            ok(c.cut > 0, ([NSString stringWithFormat:@"%@: برش صفر سر بایت %lu", take, (unsigned long)base]));
            if (!c.cut) break;
            double sec = c.cut / kZPcmBytesPerSec;
            longest = MAX(longest, sec);

            // ادعای ۳: هیچ تکه‌ای از سقف بیرون نمی‌زند، و فقط ته‌مانده حق دارد کوتاه باشد
            ok(sec <= kZSegMaxSec + 0.001,
               ([NSString stringWithFormat:@"%@: تکه‌ی %.2f ثانیه‌ای از سقف زد", take, sec]));
            if (!c.tail) {
                ok(sec >= kZSegMinSec - 0.001,
                   ([NSString stringWithFormat:@"%@: تکه‌ی %.2f ثانیه‌ای زیر کف", take, sec]));
            }

            if (!c.tail) {
                if (c.degraded) {
                    deg++;
                    // ادعای ۲: تحمیلی فقط وقتی مکثی نبود
                    ok(windowHasNoPause(pcm, base),
                       ([NSString stringWithFormat:@"%@: برش تحمیلی سر %.1fs ولی پنجره مکث داشت",
                                                   take, base / kZPcmBytesPerSec]));
                } else {
                    // ادعای ۱: مرز واقعا داخل سکوت است
                    ok(insideQuietRun(pcm, base + c.cut),
                       ([NSString stringWithFormat:@"%@: مرز سر %.2fs داخل سکوت نبود (امتیاز %.2f)",
                                                   take, (base + c.cut) / kZPcmBytesPerSec, c.score]));
                }
            }
            base += c.cut;
            segs++;
            if (segs > 500) { ok(NO, ([NSString stringWithFormat:@"%@: حلقه‌ی بی‌پایان", take])); break; }
        }
        // ادعای ۳ ادامه: جمع تکه‌ها دقیقا کل فایل
        ok(base == pcm.length - (pcm.length % 2) || base == pcm.length,
           ([NSString stringWithFormat:@"%@: جمع تکه‌ها %lu بود نه %lu",
                                       take, (unsigned long)base, (unsigned long)pcm.length]));

        double total = pcm.length / kZPcmBytesPerSec;
        printf("  %-22s %6.1f %6lu %7.1f %7lu %7.1f\n", take.UTF8String, total,
               (unsigned long)segs, segs ? total / segs : 0, (unsigned long)deg, longest);
        totalSegs += segs;
        totalDeg += deg;
    }

    printf("\n  جمع: %lu تکه، %lu تحمیلی (%.1f٪)\n",
           (unsigned long)totalSegs, (unsigned long)totalDeg,
           totalSegs ? 100.0 * totalDeg / totalSegs : 0);
    printf("%s\n", gFail ? "\nناموفق" : "\nهمه‌ی ادعاها درست");
    return gFail ? 1 : 0;
}}
