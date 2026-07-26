// تست دفتر متن. بی‌میکروفن، بی‌شبکه، قطعی.
//
// ادعای مرکزی یکی است و بقیه شاخ و برگش‌اند: **هیچ‌وقت متنی که مال ما نیست پاک
// نمی‌شود، و متنِ قطعی‌شده هیچ‌وقت کوتاه نمی‌شود.**
//
// اجرا: bash tools/ledger_test.sh
#import <Foundation/Foundation.h>
#import "zemzeme.h"

static int gFail;

// ledger.m لاگ می‌زند؛ اینجا فقط چاپش می‌کنیم تا تست به core.m و پوشه‌ی داده وصل نشود
void ZLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    printf("      log: %s\n", s.UTF8String);
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

static ZTextLedger *fresh(ZMemorySink **sinkOut, BOOL rendersPending) {
    ZMemorySink *sink = [ZMemorySink new];
    sink.rendersPendingFlag = rendersPending;
    ZTextLedger *l = [[ZTextLedger alloc] initWithSink:sink];
    l.pendingThrottle = 0;    // قطعی و بدترین‌حالت: بیشترین تعداد عملیات ممکن
    if (sinkOut) *sinkOut = sink;
    return l;
}

// ---------- گفتار عادی ----------

static void testNormalSpeech(void) {
    ZMemorySink *sink;
    ZTextLedger *l = fresh(&sink, YES);
    [l applyCommitted:@"" pending:@"سلام"];
    [l applyCommitted:@"" pending:@"سلام چطور"];
    [l applyCommitted:@"سلام چطوری" pending:@""];
    eq(@"normal speech lands exactly", sink.text, @"سلام چطوری");
    ok(@"normal speech never erases", l.stats.replaces == 0,
       [NSString stringWithFormat:@"replaces=%lu", (unsigned long)l.stats.replaces]);
}

// حالت زنده: دُم اصلا نوشته نمی‌شود، پس عملیات مخرب ذاتا ممکن نیست
static void testLiveModeIsAppendOnly(void) {
    ZMemorySink *sink;
    ZTextLedger *l = fresh(&sink, NO);
    for (int i = 0; i < 20; i++) {
        [l applyCommitted:@"" pending:[NSString stringWithFormat:@"دم ناپایدار شماره %d", i]];
    }
    [l applyCommitted:@"جمله‌ی اول" pending:@"دم تازه"];
    [l applyCommitted:@"جمله‌ی اول جمله‌ی دوم" pending:@""];
    eq(@"live mode renders only committed", sink.text, @"جمله‌ی اول جمله‌ی دوم");
    ok(@"live mode is append-only by construction", l.stats.replaces == 0,
       [NSString stringWithFormat:@"replaces=%lu", (unsigned long)l.stats.replaces]);
}

// پاس ویرایش: خام می‌نشیند، نسخه‌ی ویرایش‌شده جایش را می‌گیرد، و دیف باید کوچک باشد
static void testPolishIsALocalDiff(void) {
    ZMemorySink *sink;
    ZTextLedger *l = fresh(&sink, YES);
    [l applyCommitted:@"" pending:@"سلام چطوری"];
    [l applyCommitted:@"سلام، چطوری؟" pending:@""];
    eq(@"polish replaces the raw tail", sink.text, @"سلام، چطوری؟");
    NSString *last = sink.ops.lastObject;
    ok(@"polish diff is local, not a whole-sentence rewrite",
       [last hasPrefix:@"-6+"], [NSString stringWithFormat:@"last op: %@", last]);
}

// ---------- باگی که کاربر همین امروز دید ----------
// حالت جمع، گفتار بی‌وقفه: سر چرخش دُم خاکستری کوتاه می‌شد و «نصف بیشتر متن می‌پرید».
// اینجا ادعا این است که متنِ قطعی‌شده هرگز لمس نمی‌شود، هرچقدر هم دُم بالا و پایین برود.
static void testCommittedNeverShrinks(void) {
    ZMemorySink *sink;
    ZTextLedger *l = fresh(&sink, YES);
    NSString *committed = @"این متن قطعی شده و باید تا آخر سر جایش بماند";
    [l applyCommitted:committed pending:@"و این یک دم خاکستری خیلی خیلی طولانی است که "
                                        @"سر چرخش سشن یک‌دفعه کوتاه می‌شد"];
    NSUInteger peak = sink.text.length;
    // چرخش: استریم تازه اولین interim کوتاهش را می‌دهد
    [l applyCommitted:committed pending:@"خب"];
    ok(@"committed survives a pending collapse", [sink.text hasPrefix:committed],
       [NSString stringWithFormat:@"text: «%@»", sink.text]);
    eq(@"collapse touches only the pending tail", sink.text,
       [committed stringByAppendingString:@" خب"]);
    ok(@"the collapse was real (the test is not vacuous)", sink.text.length < peak, nil);
    // تخلیه‌ی سشن قدیمی می‌رسد و همه‌چیز سر جایش برمی‌گردد
    NSString *full = [committed stringByAppendingString:
                      @" و این یک دم خاکستری خیلی خیلی طولانی است که سر چرخش سشن یک‌دفعه کوتاه می‌شد"];
    [l applyCommitted:full pending:@"خب"];
    eq(@"drain restores the carried text", sink.text, [full stringByAppendingString:@" خب"]);
}

// ---------- دخالت بیرونی ----------

static void testNeverErasesForeignText(void) {
    ZMemorySink *sink;
    ZTextLedger *l = fresh(&sink, YES);
    [l applyCommitted:@"" pending:@"سلام"];
    [sink userTyped:@"XYZ"];               // کاربر خودش تایپ کرد
    NSString *before = [sink.text copy];
    [l applyCommitted:@"" pending:@"سلا"];  // دُم کوتاه شد: عملیات مخرب لازم است
    eq(@"foreign text is never erased", sink.text, before);
    ok(@"the refusal is counted as a disown", l.stats.disowns == 1,
       [NSString stringWithFormat:@"disowns=%lu", (unsigned long)l.stats.disowns]);
    // و از این به بعد فقط اضافه می‌کند، بی‌آنکه به تکه‌ی جامانده بچسبد
    [l applyCommitted:@"سلام علیکم" pending:@""];
    ok(@"after a disown it appends with a separator",
       [sink.text isEqualToString:@"سلامXYZ سلام علیکم"],
       [NSString stringWithFormat:@"got: «%@»", sink.text]);
}

// مقصدی که خواندنِ تاییدی ندارد (ریموت دسکتاپ): تاییدِ سطح دو، «دستِ نخورده»
static void testUnreadableSinkUsesEpochProof(void) {
    ZMemorySink *sink;
    ZTextLedger *l = fresh(&sink, YES);
    sink.readable = NO;
    [l applyCommitted:@"" pending:@"سلام"];
    [l applyCommitted:@"" pending:@"سلا"];
    eq(@"untouched target may still be rewritten", sink.text, @"سلا");
    ok(@"and that erase was proved by the untouched epoch",
       l.stats.verifiedByEpoch == 1 && l.stats.verifiedByRead == 0,
       [NSString stringWithFormat:@"epoch=%lu read=%lu",
        (unsigned long)l.stats.verifiedByEpoch, (unsigned long)l.stats.verifiedByRead]);

    ZMemorySink *sink2;
    ZTextLedger *l2 = fresh(&sink2, YES);
    sink2.readable = NO;
    [l2 applyCommitted:@"" pending:@"سلام"];
    [sink2 userTyped:@"!"];
    NSString *before = [sink2.text copy];
    [l2 applyCommitted:@"" pending:@"سلا"];
    eq(@"a touched unreadable target is never erased", sink2.text, before);
}

// مقصد جلو نیست: متن در دفتر می‌ماند و بعدا یکجا می‌رود. همین «صف» است.
static void testUnavailableTargetHoldsText(void) {
    ZMemorySink *sink;
    ZTextLedger *l = fresh(&sink, NO);
    sink.available = NO;
    [l applyCommitted:@"جمله یک" pending:@""];
    [l applyCommitted:@"جمله یک جمله دو" pending:@""];
    eq(@"nothing is written while the target is away", sink.text, @"");
    ok(@"the ledger knows how much is waiting", l.undelivered > 0,
       [NSString stringWithFormat:@"undelivered=%lu", (unsigned long)l.undelivered]);
    sink.available = YES;
    [l flushNow];
    eq(@"it all lands at once when the target returns", sink.text, @"جمله یک جمله دو");
    ok(@"and nothing is left waiting", l.undelivered == 0, nil);
}

// سطل آشغال: دُم از روی صفحه هم برداشته می‌شود، ولی متنِ قطعی دست نمی‌خورد
static void testDropOwned(void) {
    ZMemorySink *sink;
    ZTextLedger *l = fresh(&sink, YES);
    [l applyCommitted:@"متن قطعی" pending:@"این دم دور ریخته می‌شود"];
    [l dropOwned];
    eq(@"trash removes only the pending tail", sink.text, @"متن قطعی");
}

// ---------- هزار عملیات، در برابر مدل مرجع ----------
// دیکته‌ی شبیه‌سازی‌شده: کلمه‌ها یکی‌یکی وارد دُم می‌شوند، هر چند کلمه یک بار قطعی
// می‌شوند، و گاهی پاس ویرایش چند نویسه‌ی آخر را عوض می‌کند.
static void testThousandOpsAgainstReference(void) {
    ZMemorySink *sink;
    ZTextLedger *l = fresh(&sink, YES);
    uint32_t seed = 20260726;
    NSArray *vocab = @[@"سلام", @"دنیا", @"این", @"یک", @"تست", @"طولانی", @"است",
                       @"و", @"باید", @"درست", @"کار", @"کند", @"همیشه"];
    NSMutableString *committed = [NSMutableString string];
    NSMutableArray *pendingWords = [NSMutableArray array];
    for (int step = 0; step < 1000; step++) {
        seed = seed * 1103515245u + 12345u;
        uint32_t r = (seed >> 16) & 0x7fff;
        if (r % 5 == 0 && pendingWords.count) {
            // قطعی شدن، گاهی با یک ویرایشِ کوچک (همان کاری که پاس ویرایش می‌کند)
            NSString *chunk = [pendingWords componentsJoinedByString:@" "];
            if (r % 3 == 0) chunk = [chunk stringByAppendingString:@"."];
            [committed setString:ZJoinText(committed, chunk)];
            [pendingWords removeAllObjects];
        } else {
            [pendingWords addObject:vocab[r % vocab.count]];
            if (pendingWords.count > 12) [pendingWords removeObjectAtIndex:0];
        }
        [l applyCommitted:committed pending:[pendingWords componentsJoinedByString:@" "]];
    }
    NSString *want = ZJoinText(committed, [pendingWords componentsJoinedByString:@" "]);
    eq(@"1000 ops match the reference model exactly", sink.text, want);
    NSUInteger ops = l.stats.appends + l.stats.replaces;
    double ratio = ops ? (double)l.stats.appends * 100.0 / (double)ops : 100;
    printf("      %s\n", l.stats.summary.UTF8String);
    // بدونِ throttle، یعنی بدترین حالت. در اپ واقعی سقف ۱۲۰ms چند بروزرسانی را
    // در یک عملیات ادغام می‌کند، پس نسبت واقعی از این بهتر است.
    ok([NSString stringWithFormat:@"append ratio stays above 90%% (got %.1f%%)", ratio],
       ratio >= 90.0, nil);
    ok(@"every erase was verified before it ran",
       l.stats.replaces == l.stats.verifiedByRead + l.stats.verifiedByEpoch,
       [NSString stringWithFormat:@"replaces=%lu verified=%lu",
        (unsigned long)l.stats.replaces,
        (unsigned long)(l.stats.verifiedByRead + l.stats.verifiedByEpoch)]);
}

int main(void) {
    @autoreleasepool {
        testNormalSpeech();
        testLiveModeIsAppendOnly();
        testPolishIsALocalDiff();
        testCommittedNeverShrinks();
        testNeverErasesForeignText();
        testUnreadableSinkUsesEpochProof();
        testUnavailableTargetHoldsText();
        testDropOwned();
        testThousandOpsAgainstReference();
        printf("\n%s  (%d failed)\n", gFail ? "FAILED" : "all ledger tests passed", gFail);
        return gFail ? 1 : 0;
    }
}
