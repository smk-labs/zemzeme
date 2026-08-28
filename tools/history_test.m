// تست طلایی تاریخچه: می‌نویسد، پروسه را می‌بندد، سرد باز می‌کند و می‌خواهد که
// **هر** رکورد سر جایش باشد ــ با ترتیب درست و متنِ بایت‌به‌بایت همان.
//
// چرا چندفازی و نه یک main: ادعای اصلی این است که متن از کرش جان سالم به در
// می‌برد، و آن را فقط پروسه‌ی **دوم** می‌تواند ثابت کند. یک پروسه‌ی واحد در بهترین
// حالت کش خودش را می‌خواند و هیچ‌چیز ثابت نمی‌کند.
#import <Foundation/Foundation.h>
#import "zemzeme.h"
#include <unistd.h>

static int gFail = 0;

static void ok(BOOL cond, NSString *what) {
    if (cond) return;
    gFail++;
    fprintf(stderr, "  ✗ %s\n", what.UTF8String);
}

// core.m این را از audio.m می‌خواهد و تست میکروفن ندارد
void ZMicSetHighSensitivity(BOOL on) { (void)on; }

// ---------- متنِ نمونه ----------
// عمدا بدقلق: خط جدید (همان چیزی که هر فرمتِ خط‌محورِ ساده را می‌شکند)، گیومه و
// بک‌اسلش (که JSON باید فرار بدهد)، تب، نیم‌فاصله و نشانه‌ی راست‌به‌چپ، و گاهی متنِ
// خیلی بلند یا متنی که **خودش شبیه یک رکورد است**.
static NSString *bodyFor(NSInteger i) {
    NSMutableString *s = [NSMutableString stringWithFormat:@"رکورد شماره %ld", (long)i];
    [s appendString:@"\nخط دوم، با \"گیومه\" و \\ بک‌اسلش و\tتب"];
    [s appendString:@"\nنیم‌فاصله: می‌شود و می‌رود‏و یک نشانه‌ی راست‌به‌چپ"];
    if (i % 5 == 0) [s appendString:@"\n{\"text\": \"شبیهِ یک رکورد، ولی داخلِ متن\"}"];
    if (i % 7 == 0) for (int k = 0; k < 300; k++) [s appendFormat:@" واژه‌ی%d", k];
    return s;
}

// خامِ همان رکورد. هر سه‌تا یکی با `text` است (حالتِ معمول: نه ویرایشی، نه پاسی) تا
// هر دو مسیرِ نوشتن در همین یک دور آزموده شود: رشته‌ی خالی که یعنی «همان تحویل»، و
// خامِ کاملِ جدا که یعنی تحویل دستکاری شده.
static NSString *rawFor(NSInteger i) {
    if (i % 3 == 0) return bodyFor(i);
    return [bodyFor(i) stringByAppendingString:@"\nدُمِ خام که به تحویل نرسید"];
}

static NSString *sidFor(NSInteger i) { return [NSString stringWithFormat:@"s-%05ld", (long)i]; }

static NSURL *storeIn(NSString *dir) {
    return [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"history.jsonl"]];
}

// ---------- فازها ----------

static void phaseWrite(NSURL *store, NSInteger n) {
    for (NSInteger i = 0; i < n; i++) {
        ZHistoryAppendTo(store, bodyFor(i), rawFor(i), sidFor(i), ZHistoryViaAuto, @"TestApp");
    }
}

// همان نوشتن، ولی از چند نخ هم‌زمان. اگر قفل نباشد یا نوشتنِ ناقص حساب نشده باشد،
// اینجاست که رکوردها در هم می‌روند.
static void phaseHammer(NSURL *store, NSInteger n) {
    dispatch_apply((size_t)n, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) {
        ZHistoryAppendTo(store, bodyFor((NSInteger)i), rawFor((NSInteger)i), sidFor((NSInteger)i),
                         ZHistoryViaAuto, @"TestApp");
    });
}

// خواندنِ سرد و ادعای اصلی: `n` رکورد، از نو به کهنه، هر کدام دقیقا همان متن.
static void phaseRead(NSURL *store, NSInteger n) {
    NSArray<ZHistoryEntry *> *got = ZHistoryRecentIn(store, (NSUInteger)n + 50);
    ok(got.count == (NSUInteger)n,
       ([NSString stringWithFormat:@"شمار رکوردها: %lu، انتظار %ld", (unsigned long)got.count, (long)n]));
    NSUInteger checked = MIN(got.count, (NSUInteger)n);
    for (NSUInteger k = 0; k < checked; k++) {
        NSInteger want = n - 1 - (NSInteger)k;    // نو اول
        ZHistoryEntry *e = got[k];
        if (![e.sid isEqualToString:sidFor(want)]) {
            ok(NO, ([NSString stringWithFormat:@"ردیف %lu باید %@ باشد، %@ بود",
                     (unsigned long)k, sidFor(want), e.sid ?: @"(بی‌شناسه)"]));
            continue;
        }
        ok([e.text isEqualToString:bodyFor(want)],
           ([NSString stringWithFormat:@"متنِ %@ دست‌نخورده نماند", sidFor(want)]));
        ok([e.raw isEqualToString:rawFor(want)],
           ([NSString stringWithFormat:@"خامِ %@ دست‌نخورده نماند", sidFor(want)]));
        ok([e.via isEqualToString:ZHistoryViaAuto] && [e.app isEqualToString:@"TestApp"],
           ([NSString stringWithFormat:@"همراهانِ %@ نماندند", sidFor(want)]));
        ok(e.at && fabs(e.at.timeIntervalSinceNow) < 3600,
           ([NSString stringWithFormat:@"زمانِ %@ بی‌معنی است", sidFor(want)]));
    }
}

// همان خواندنِ سرد، ولی بی‌ادعا روی **ترتیب**: نوشتنِ هم‌زمان از چند نخ ترتیبی
// ندارد که بشود ادعایش کرد. ادعای اینجا این است که هیچ‌کدام گم نشده و هیچ‌کدام در
// دیگری نرفته ــ یعنی دقیقا همان چیزی که قفل باید تضمین کند.
static void phaseReadSet(NSURL *store, NSInteger n) {
    NSArray<ZHistoryEntry *> *got = ZHistoryRecentIn(store, (NSUInteger)n + 50);
    ok(got.count == (NSUInteger)n,
       ([NSString stringWithFormat:@"شمار رکوردها: %lu، انتظار %ld", (unsigned long)got.count, (long)n]));
    NSMutableDictionary<NSString *, ZHistoryEntry *> *bySid = [NSMutableDictionary dictionary];
    for (ZHistoryEntry *e in got) {
        if (e.sid && bySid[e.sid]) ok(NO, ([NSString stringWithFormat:@"%@ دو بار آمد", e.sid]));
        if (e.sid) bySid[e.sid] = e;
    }
    for (NSInteger i = 0; i < n; i++) {
        ZHistoryEntry *e = bySid[sidFor(i)];
        if (!e) { ok(NO, ([NSString stringWithFormat:@"%@ گم شد", sidFor(i)])); continue; }
        ok([e.text isEqualToString:bodyFor(i)],
           ([NSString stringWithFormat:@"متنِ %@ دست‌نخورده نماند", sidFor(i)]));
        ok([e.raw isEqualToString:rawFor(i)],
           ([NSString stringWithFormat:@"خامِ %@ دست‌نخورده نماند", sidFor(i)]));
    }
}

// کرشِ وسطِ نوشتن، دقیقا همان‌طور که روی دیسک دیده می‌شود: رکوردِ آخر از وسط بریده
// و بی‌`\n` رها شده.
static void phaseTear(NSURL *store) {
    NSData *all = [NSData dataWithContentsOfURL:store];
    const char *b = all.bytes;
    NSUInteger end = all.length;
    while (end > 0 && b[end - 1] != '\n') end--;          // ته آخرین رکوردِ کامل
    if (end == 0) { ok(NO, @"فایلی برای بریدن نیست"); return; }
    NSUInteger start = end - 1;
    while (start > 0 && b[start - 1] != '\n') start--;    // سر همان رکورد
    ok(end > start + 20, @"فایل برای بریدن به اندازه‌ی کافی بزرگ نیست");
    // وسطِ رکوردِ آخر، نه سرش و نه تهش
    ok(truncate(store.path.fileSystemRepresentation, (off_t)(start + (end - start) / 2)) == 0,
       @"فایل بریده نشد");
}

// و نکته‌ی واقعی: بعد از آن کرش، اپ دوباره بالا می‌آید و می‌نویسد. رکوردِ تازه هم
// باید سالم بنشیند، نه اینکه به دُمِ نصفه بچسبد و با آن بسوزد.
static void phaseAppendAfterTear(NSURL *store, NSInteger i) {
    ZHistoryAppendTo(store, bodyFor(i), rawFor(i), sidFor(i), ZHistoryViaAuto, @"TestApp");
}

// جارو: رکوردهای کهنه می‌روند، تازه‌ها با همان ترتیب می‌مانند. رکوردهای کهنه را
// دستی و خام می‌نویسیم ــ که هم بشود زمان دلخواه گذاشت، هم ثابت شود فایل با هر
// ابزار دیگری هم نوشتنی است، نه فقط با خودِ اپ.
static void phaseSweep(NSURL *store) {
    NSMutableString *raw = [NSMutableString string];
    long long now = (long long)NSDate.date.timeIntervalSince1970;
    // نیم‌روز جلوتر از سرِ هر روز، که رکوردِ روزِ شصتم درست **روی** مرز نیفتد: مرز
    // چند میکروثانیه بعد از این حلقه حساب می‌شود و تستی که به آن چند میکروثانیه بند
    // باشد، تست نیست.
    for (NSInteger d = 100; d >= 1; d--) {
        [raw appendFormat:@"{\"at\":%lld,\"sid\":\"day-%03ld\",\"text\":\"روز %ld\",\"via\":\"auto\"}\n",
                          now - (long long)d * 86400 + 43200, (long)d, (long)d];
    }
    [raw writeToURL:store atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-60 * 86400.0];
    NSUInteger dropped = ZHistorySweepFile(store, cutoff);
    ok(dropped == 40, ([NSString stringWithFormat:@"جارو باید ۴۰ رکورد ببرد، %lu برد",
                        (unsigned long)dropped]));
    NSArray<ZHistoryEntry *> *left = ZHistoryRecentIn(store, 500);
    ok(left.count == 60, ([NSString stringWithFormat:@"باید ۶۰ رکورد بماند، %lu ماند",
                           (unsigned long)left.count]));
    // نو اول: روز ۱ تازه‌ترین است
    if (left.count == 60) {
        ok([left.firstObject.sid isEqualToString:@"day-001"], @"تازه‌ترینِ بازمانده جابه‌جا شد");
        ok([left.lastObject.sid isEqualToString:@"day-060"], @"کهنه‌ترینِ بازمانده جابه‌جا شد");
    }
    // و جاروی دوباره روی فایلِ جاروشده نباید چیزی ببرد
    ok(ZHistorySweepFile(store, cutoff) == 0, @"جاروی دوم هم چیزی برد");
}

// یک سشن، چند تحویل: هر مکث یک عکسِ کامل می‌نویسد و باید **یک** ردیف بماند، آخری.
static void phaseDedupe(NSURL *store) {
    ZHistoryAppendTo(store, @"سلام", @"سلام", @"same-session", ZHistoryViaAuto, @"TestApp");
    ZHistoryAppendTo(store, @"سلام، حالت چطور است", @"سلام، حالت چطور است",
                     @"same-session", ZHistoryViaAuto, @"TestApp");
    ZHistoryAppendTo(store, @"سلام، حالت چطور است؟ خوبم", @"سلام، حالت چطور است؟ خوبم",
                     @"same-session", ZHistoryViaCopy, @"TestApp");
    NSArray<ZHistoryEntry *> *got = ZHistoryRecentIn(store, 50);
    ok(got.count == 1, ([NSString stringWithFormat:@"یک سشن باید یک ردیف بدهد، %lu داد",
                         (unsigned long)got.count]));
    ok([got.firstObject.text isEqualToString:@"سلام، حالت چطور است؟ خوبم"], @"آخرین عکسِ سشن نماند");
    ok([got.firstObject.raw isEqualToString:@"سلام، حالت چطور است؟ خوبم"], @"خامِ آخرین عکسِ سشن نماند");
}

// رکوردی که نسخه‌های پیش از «خام» نوشته‌اند. دو ادعا: خوانده می‌شود، و خامش **خالی**
// می‌ماند. جا زدنِ متنِ تحویل‌شده به‌جای خام همان دروغی است که C1 ساخت، این بار با
// مهرِ اپ رویش؛ پنجره هم روی همین nil کلیدِ خام را خاموش نگه می‌دارد.
static void phaseLegacy(NSURL *store) {
    long long now = (long long)NSDate.date.timeIntervalSince1970;
    NSString *line = [NSString stringWithFormat:
        @"{\"at\":%lld,\"sid\":\"old-one\",\"text\":\"متنِ رکوردِ کهنه\",\"via\":\"auto\"}\n", now];
    [line writeToURL:store atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSArray<ZHistoryEntry *> *got = ZHistoryRecentIn(store, 20);
    ok(got.count == 1, @"رکوردِ کهنه (بی کلیدِ خام) اصلا خوانده نشد");
    ok([got.firstObject.text isEqualToString:@"متنِ رکوردِ کهنه"], @"متنِ رکوردِ کهنه عوض شد");
    ok(got.firstObject.raw == nil, @"رکوردِ کهنه خام ندارد، ولی یکی برایش ساخته شد");
    // و رکوردِ تازه پشتِ همان فایل می‌نشیند. خامش عینا برابرِ تحویل است، یعنی مسیرِ
    // رشته‌ی خالی، و باید همان متن برگردد نه هیچ.
    ZHistoryAppendTo(store, @"متنِ تازه", @"متنِ تازه", @"new-one", ZHistoryViaAuto, @"TestApp");
    got = ZHistoryRecentIn(store, 20);
    ok(got.count == 2, @"بعد از رکوردِ کهنه، رکوردِ تازه ننشست");
    ok([got.firstObject.raw isEqualToString:@"متنِ تازه"], @"خامِ برابر با تحویل برنگشت");
}

// جمع شدن با sid، سختش: تحویل و خام باید از **یک** رکورد بیایند. بلندترین خام عمدا
// وسط است، پس خواننده‌ای که «بلندترینش را بردار» یا «آخرین خامی که دیدی را بردار»
// باشد همین‌جا قرمز می‌شود.
static void phasePair(NSURL *store) {
    ZHistoryAppendTo(store, @"عکس یک", @"خامِ یک", @"one-sid", ZHistoryViaAuto, @"TestApp");
    ZHistoryAppendTo(store, @"عکس دو", @"خامِ دو، که بلندترین خامِ این فایل است و نباید برنده شود",
                     @"one-sid", ZHistoryViaAuto, @"TestApp");
    ZHistoryAppendTo(store, @"عکس سه", @"خامِ سه", @"one-sid", ZHistoryViaCopy, @"TestApp");
    NSArray<ZHistoryEntry *> *got = ZHistoryRecentIn(store, 50);
    ok(got.count == 1, ([NSString stringWithFormat:@"یک سشن باید یک ردیف بدهد، %lu داد",
                         (unsigned long)got.count]));
    ok([got.firstObject.text isEqualToString:@"عکس سه"] &&
       [got.firstObject.raw isEqualToString:@"خامِ سه"], @"تحویل و خام از یک رکورد نیامدند");

    // و ردیفی که تازه‌ترین رکوردش خام ندارد، حق ندارد خامِ رکوردِ کهنه‌ترِ همان سشن را
    // قرض بگیرد: خامِ کهنه کنارِ متنِ تازه بدترین حالت است، چون شبیهِ درست است.
    NSString *had = [NSString stringWithContentsOfURL:store encoding:NSUTF8StringEncoding error:nil];
    long long now = (long long)NSDate.date.timeIntervalSince1970;
    NSString *line = [NSString stringWithFormat:
        @"{\"at\":%lld,\"sid\":\"one-sid\",\"text\":\"عکس چهار\",\"via\":\"auto\"}\n", now];
    [[had stringByAppendingString:line] writeToURL:store atomically:YES
                                          encoding:NSUTF8StringEncoding error:nil];
    got = ZHistoryRecentIn(store, 50);
    ok([got.firstObject.text isEqualToString:@"عکس چهار"] && got.firstObject.raw == nil,
       @"خامِ رکوردِ کهنه‌تر به رکوردِ تازه قرض داده شد");
}

// شکلِ خودِ باگ C1، سشن ۲۰۲۶-۰۸-۲۶-۰۳-۲۳-۵۷: تحویل، متنِ ویرایش‌شده‌ی بریده بود و
// نیمه‌ی دومِ حرف را نداشت. ادعا این است که همان ردیف حالا نیمه‌ی دوم را هم دارد، پس
// یک تکرارِ همان باگ دیگر متن را نمی‌برد.
static void phaseC1(NSURL *store) {
    NSString *half = @"نیمه‌ی اولِ حرف، همان که کاربر در پنل ویرایشش کرد";
    NSString *tail = @"و نیمه‌ی دوم، همان که از کلیپ‌بورد و از ردیف تاریخچه افتاده بود";
    NSString *delivered = [half stringByAppendingString:@" (ویرایش‌شده)"];
    NSString *whole = [NSString stringWithFormat:@"%@ %@", half, tail];
    ZHistoryAppendTo(store, delivered, whole, @"2026-08-26-03-23-57", ZHistoryViaAuto, @"Windows App");
    NSArray<ZHistoryEntry *> *got = ZHistoryRecentIn(store, 20);
    ok(got.count == 1, @"ردیفِ سشنِ C1 خوانده نشد");
    ok([got.firstObject.text isEqualToString:delivered], @"متنِ تحویل‌شده‌ی C1 عوض شد");
    ok(got.firstObject.raw.length > got.firstObject.text.length &&
       [got.firstObject.raw hasSuffix:tail],
       @"نیمه‌ی دومِ حرف از ردیفِ C1 برداشتنی نیست");
}

// چیزهایی که نباید بترکانند
static void phaseJunk(NSURL *store) {
    ok(ZHistoryRecentIn(store, 20).count == 0, @"فایلِ نبوده رکورد داد");
    [@"" writeToURL:store atomically:YES encoding:NSUTF8StringEncoding error:nil];
    ok(ZHistoryRecentIn(store, 20).count == 0, @"فایلِ خالی رکورد داد");
    [@"نه JSON است نه چیزی\nیک خطِ دیگر\n" writeToURL:store atomically:YES
                                            encoding:NSUTF8StringEncoding error:nil];
    ok(ZHistoryRecentIn(store, 20).count == 0, @"آشغال رکورد داد");
    // آشغال هم جلوی نوشتنِ بعدی را نگیرد
    ZHistoryAppendTo(store, @"بعدِ آشغال", @"بعدِ آشغال", @"after-junk", ZHistoryViaAuto, @"TestApp");
    NSArray<ZHistoryEntry *> *got = ZHistoryRecentIn(store, 20);
    ok(got.count == 1 && [got.firstObject.text isEqualToString:@"بعدِ آشغال"],
       @"بعد از آشغال، رکوردِ سالم خوانده نشد");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: history_test <phase> <dir> [n]\n");
            return 2;
        }
        NSString *phase = @(argv[1]);
        NSString *dir = @(argv[2]);
        NSInteger n = argc > 3 ? atol(argv[3]) : 0;
        NSURL *store = storeIn(dir);

        if ([phase isEqualToString:@"write"]) phaseWrite(store, n);
        else if ([phase isEqualToString:@"hammer"]) phaseHammer(store, n);
        else if ([phase isEqualToString:@"read"]) phaseRead(store, n);
        else if ([phase isEqualToString:@"readset"]) phaseReadSet(store, n);
        else if ([phase isEqualToString:@"tear"]) phaseTear(store);
        else if ([phase isEqualToString:@"append"]) phaseAppendAfterTear(store, n);
        else if ([phase isEqualToString:@"sweep"]) phaseSweep(store);
        else if ([phase isEqualToString:@"dedupe"]) phaseDedupe(store);
        else if ([phase isEqualToString:@"legacy"]) phaseLegacy(store);
        else if ([phase isEqualToString:@"pair"]) phasePair(store);
        else if ([phase isEqualToString:@"c1"]) phaseC1(store);
        else if ([phase isEqualToString:@"junk"]) phaseJunk(store);
        else { fprintf(stderr, "فاز ناشناخته: %s\n", argv[1]); return 2; }

        if (gFail) fprintf(stderr, "%d ادعا شکست (فاز %s)\n", gFail, argv[1]);
        return gFail ? 1 : 0;
    }
}
