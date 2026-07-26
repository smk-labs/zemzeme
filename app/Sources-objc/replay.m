// ثبت رویداد و بازپخش.
//
// چرا این فایل مهم‌ترین بخش این بازنویسی است: پنج دور وصله شکست خورد چون هیچ تستی
// مسیر زنده را نمی‌دوید. هر باگ فقط با میکروفن و شبکه و شانس دیده می‌شد، و «درست
// شد» یعنی «این بار ندیدمش». حالا ورودیِ خامِ رونوشت روی دیسک ثبت می‌شود و همان
// ورودی، بی‌میکروفن و بی‌شبکه و قطعی، از همان خط لوله رد می‌شود.
//
//   zemzeme --replay <events.jsonl> [--live]
//
// پیش‌فرض، دُمِ ناپایدار هم نوشته می‌شود (حالت کنار کرسر). با --live مثل حالت درج
// زنده فقط متنِ قطعی می‌رود، پس همان مسیر هم سنجیده می‌شود.
#import "zemzeme.h"

// ---------- ثبت ----------
// عمدا داخل ZTranscript صدا زده می‌شود، نه لای موتور: چیزی که ثبت می‌شود دقیقا
// ورودیِ همان کلاسی است که بازپخش می‌دواندش، پس سشنِ ضبط‌شده مو‌به‌مو دوباره پخش
// می‌شود. لاگی که یک لایه بالاتر یا پایین‌تر گرفته شود، همین خاصیت را ندارد.

static NSFileHandle *gEventLog;
static NSLock *gEventLock;

void ZEventLogStart(NSURL *path) {
    if (!gEventLock) gEventLock = [NSLock new];
    [gEventLock lock];
    [gEventLog closeFile];
    [NSFileManager.defaultManager createFileAtPath:path.path contents:nil attributes:nil];
    gEventLog = [NSFileHandle fileHandleForWritingAtPath:path.path];
    [gEventLock unlock];
}

void ZEventLogStop(void) {
    if (!gEventLock) return;
    [gEventLock lock];
    [gEventLog closeFile];
    gEventLog = nil;
    [gEventLock unlock];
}

void ZEventLogWrite(NSDictionary *ev) {
    if (!gEventLog) return;
    NSData *d = [NSJSONSerialization dataWithJSONObject:ev options:0 error:nil];
    if (!d) return;
    [gEventLock lock];
    @try {
        [gEventLog writeData:d];
        [gEventLog writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    } @catch (NSException *e) {}
    [gEventLock unlock];
}

// ---------- بازپخش ----------

static NSString *ZEvStr(NSDictionary *e, NSString *k) {
    id v = e[k];
    return [v isKindOfClass:NSString.class] ? v : @"";
}

// «کلمه‌های گم‌شده» و «کلمه‌های تکراری» را می‌شمارد. معیار پذیرش همین دو عدد است و
// نه چشمِ آدم: صفر و صفر، وگرنه تست قرمز است.
static NSString *ZDiffWords(NSString *got, NSString *want) {
    NSArray *g = [got componentsSeparatedByString:@" "];
    NSArray *w = [want componentsSeparatedByString:@" "];
    NSCountedSet *gs = [NSCountedSet setWithArray:g];
    NSCountedSet *ws = [NSCountedSet setWithArray:w];
    NSUInteger missing = 0, extra = 0;
    for (NSString *t in ws) {
        NSUInteger have = [gs countForObject:t], need = [ws countForObject:t];
        if (need > have) missing += need - have;
    }
    for (NSString *t in gs) {
        NSUInteger have = [gs countForObject:t], need = [ws countForObject:t];
        if (have > need) extra += have - need;
    }
    if (!missing && !extra) return nil;
    return [NSString stringWithFormat:@"%lu missing, %lu duplicated",
            (unsigned long)missing, (unsigned long)extra];
}

int ZReplayMain(NSArray<NSString *> *args) {
    @autoreleasepool {
        NSUInteger at = [args indexOfObject:@"--replay"];
        if (at == NSNotFound || at + 1 >= args.count) {
            fprintf(stderr, "usage: zemzeme --replay <events.jsonl> [--live]\n");
            return 2;
        }
        NSString *path = args[at + 1];
        NSString *body = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding error:nil];
        if (!body) {
            fprintf(stderr, "replay: cannot read %s\n", path.UTF8String);
            return 2;
        }
        BOOL live = [args containsObject:@"--live"];

        ZTranscript *tx = [ZTranscript new];
        ZMemorySink *sink = [ZMemorySink new];
        sink.rendersPendingFlag = !live;
        ZTextLedger *ledger = [[ZTextLedger alloc] initWithSink:sink];
        // سقفِ زمانی خاموش: هم قطعی می‌شود، هم بدترین حالت را می‌سنجد. در اپ واقعی
        // سقف ۱۲۰ms چند بروزرسانی را در یک عملیات ادغام می‌کند، پس تعداد عملیات
        // آنجا کمتر است نه بیشتر.
        ledger.pendingThrottle = 0;

        NSString *note = nil, *expect = nil;
        NSUInteger lineNo = 0;
        for (NSString *raw in [body componentsSeparatedByString:@"\n"]) {
            lineNo++;
            NSString *line = [raw stringByTrimmingCharactersInSet:
                              NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!line.length || [line hasPrefix:@"//"]) continue;
            NSDictionary *e = [NSJSONSerialization
                JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding]
                           options:0 error:nil];
            if (![e isKindOfClass:NSDictionary.class]) {
                fprintf(stderr, "replay: bad json on line %lu\n", (unsigned long)lineNo);
                return 2;
            }
            NSString *k = ZEvStr(e, @"k");
            if ([k isEqualToString:@"note"]) { note = ZEvStr(e, @"text"); continue; }
            if ([k isEqualToString:@"expect"]) { expect = ZEvStr(e, @"text"); continue; }
            if ([k isEqualToString:@"overlap"]) {
                tx.weldWords = ZStitchWords([e[@"sec"] doubleValue]);
                continue;
            }
            if ([k isEqualToString:@"interim"]) [tx setInterim:ZEvStr(e, @"text")];
            else if ([k isEqualToString:@"final"]) {
                [tx addFinal:ZEvStr(e, @"text") weld:[e[@"weld"] boolValue]];
            }
            else if ([k isEqualToString:@"rotate"]) {
                [tx beginDrainWithCarry:ZEvStr(e, @"carry") weld:[e[@"weld"] boolValue]];
            }
            else if ([k isEqualToString:@"drainfinal"]) [tx drainFinal:ZEvStr(e, @"text")];
            else if ([k isEqualToString:@"drainend"]) [tx endDrain];
            else if ([k isEqualToString:@"drop"]) [tx dropPending];
            else if ([k isEqualToString:@"away"]) sink.available = NO;
            else if ([k isEqualToString:@"back"]) { sink.available = YES; [ledger flushNow]; }
            else if ([k isEqualToString:@"usertyped"]) [sink userTyped:ZEvStr(e, @"text")];
            else {
                fprintf(stderr, "replay: unknown event '%s' on line %lu\n",
                        k.UTF8String, (unsigned long)lineNo);
                return 2;
            }
            [ledger applyCommitted:tx.committed pending:tx.pending];
        }
        // پایان سشن: هرچه مانده تحویل می‌شود، مثل مسیر واقعی
        [ledger applyCommitted:tx.committed pending:@""];
        [ledger flushNow];

        printf("--- %s%s ---\n", note.length ? note.UTF8String : path.UTF8String,
               live ? " [live mode]" : "");
        printf("%s\n", sink.text.UTF8String);
        printf("    %s\n", ledger.stats.summary.UTF8String);
        if (ledger.stats.replaces != ledger.stats.verifiedByRead + ledger.stats.verifiedByEpoch) {
            printf("FAIL an erase ran without proof\n");
            return 1;
        }
        if (expect) {
            NSString *got = [sink.text stringByTrimmingCharactersInSet:
                             NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSString *diff = ZDiffWords(got, expect);
            if (diff || ![got isEqualToString:expect]) {
                printf("FAIL %s\n", diff ? diff.UTF8String : "text differs");
                printf("    want: %s\n", expect.UTF8String);
                printf("    got:  %s\n", got.UTF8String);
                return 1;
            }
            printf("    ok: no word lost, none duplicated\n");
        }
        return 0;
    }
}
