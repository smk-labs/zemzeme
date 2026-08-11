// تاریخچه‌ی متن‌های تحویل‌شده: انبار، خواندن از ته فایل، و جاروی روزانه
#import "zemzeme.h"
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

// ---------- چرا یک فایل، و چرا این شکل ----------
//
// تا امروز تنها نسخه‌ی ماندگارِ یک دیکته‌ی تمام‌شده `sessions/<تاریخ>/text.txt` بود،
// و آن هم فقط اگر پوشه‌ی سشن ساخته شده باشد و جاروی هفت‌روزه هنوز نبرده باشدش.
// کلیپ‌بورد و درج هر دو بیرون از دستِ ما هستند: مدیر کلیپ‌بورد ممکن است نگیرد، درج
// ممکن است جای عوضی بنشیند. پس متن باید یک خانه‌ی خودش داشته باشد که همان لحظه‌ی
// تحویل نوشته شود.
//
// **یک فایل JSONL، فقط افزودنی**: هر رکورد دقیقا یک خط.
//
//   چرا نه متنِ ساده با جداکننده: خودِ متنِ دیکته خط جدید دارد، پس هیچ جداکننده‌ای
//   امن نیست. JSON خطِ جدید را `\n` می‌نویسد، پس «یک رکورد = یک خط» یک قاعده‌ی
//   واقعی می‌شود نه یک آرزو.
//
//   چرا نه SQLite: همان دوامِ افزودنی را می‌دهد ولی یک فایل باینری با دو فایل
//   کناری (WAL و shm) و یک اسکیما به ارث می‌آورد. اینجا حداکثر چند هزار ردیف است
//   و مهم‌ترین ویژگی‌اش این است که با `tail` و هر ویرایشگری خوانده شود. وابستگیِ
//   تازه هم لازم ندارد: NSJSONSerialization داخل Foundation است.
//
// **کرشِ وسطِ نوشتن**: تنها بایت‌هایی رکوردند که تا آخرین `\n` آمده‌اند. هرچه بعد
// از آخرین `\n` مانده نصفه است و خواننده دورش می‌اندازد. پس بدترین حالتِ کرش،
// از دست رفتنِ همان رکوردی است که داشت نوشته می‌شد، و نه یک بایت بیشتر.
//
// **هر تحویل یک عکسِ کامل**: سشن سرِ هر مکث تحویل می‌دهد، و هر بار کلِ متنِ تا آن
// لحظه نوشته می‌شود. خواننده رکوردها را با `sid` جمع می‌کند و آخری را نگه می‌دارد.
// فایده‌اش این است که فایل افزودنیِ خالص می‌ماند (هیچ‌وقت بازنویسی نمی‌شود) و از
// همان اولین تحویل یک نسخه روی دیسک هست.

// ---------- شکل رکورد ----------
// {"app":"Safari","at":1770826923,"sid":"2026-08-11-14-22-03","t":"2026-08-11 14:22:03","text":"…","via":"auto"}
//
// دو تا زمان عمدی است: `at` برای حسابِ جارو (بی‌پارس کردنِ تاریخ) و `t` برای چشمِ
// آدم وقتی فایل را با tail باز می‌کند.

NSString *const ZHistoryViaAuto = @"auto";       // پایان یا مکثِ سشن
NSString *const ZHistoryViaCopy = @"copy";       // دکمه‌ی کپی
NSString *const ZHistoryViaInsert = @"insert";   // دکمه‌ی درج
NSString *const ZHistoryDidChangeNotification = @"ZHistoryDidChange";

// پنجره‌ی اولِ خواندن از ته فایل. بیست رکوردِ معمولی خیلی کمتر از این است، پس
// معمولا یک خواندن کافی است؛ کم که بیاید خودش هشت‌برابر می‌شود.
static const unsigned long long kZHistoryTailBytes = 256 * 1024;

@implementation ZHistoryEntry
@end

NSURL *ZHistoryFile(void) {
    return [ZSupport() URLByAppendingPathComponent:@"history.jsonl"];
}

// یک قفل برای همه‌ی نوشتن‌ها. کارش جلوگیری از درهم رفتنِ دو رکورد است وقتی نوشتنِ
// اول ناقص برگردد؛ جاروی روزانه هم همین را می‌گیرد تا وسطِ جابه‌جاییِ فایل، رکوردی
// روی نسخه‌ی قدیمی ننشیند و گم شود.
static NSLock *zHistoryLock(void) {
    static NSLock *l;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ l = [NSLock new]; });
    return l;
}

// fsync روی صف پس‌زمینه، نه روی نخِ فراخوان. دلیلش: `write` بایت‌ها را همان لحظه به
// هسته می‌دهد و از آن به بعد کرشِ اپ چیزی نمی‌برد، ولی fsync تا خودِ دیسک می‌رود و
// روی APFS گاهی دهها میلی‌ثانیه طول می‌کشد. آن انتظار جای نخِ اصلی نیست.
static dispatch_queue_t zHistoryFlushQ(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("zemzeme.history.flush", DISPATCH_QUEUE_SERIAL); });
    return q;
}

// نوشتنِ کاملِ یک بافر. `write` حق دارد کمتر از خواسته بنویسد و همان یک بار که این
// اتفاق بیفتد، بی این حلقه یک رکوردِ نصفه روی دیسک می‌ماند.
static BOOL zWriteAll(int fd, const void *buf, size_t len) {
    const char *p = buf;
    size_t off = 0;
    while (off < len) {
        ssize_t n = write(fd, p + off, len - off);
        if (n > 0) { off += (size_t)n; continue; }
        if (n < 0 && errno == EINTR) continue;
        return NO;
    }
    return YES;
}

static NSString *zHistoryStamp(NSDate *when) {
    static NSDateFormatter *df;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    return [df stringFromDate:when];
}

void ZHistoryAppendTo(NSURL *file, NSString *text, NSString *sid, NSString *via, NSString *app) {
    NSString *t = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!t.length || !file) return;

    NSMutableDictionary *rec = [NSMutableDictionary dictionary];
    NSDate *now = NSDate.date;
    rec[@"at"] = @((long long)llround(now.timeIntervalSince1970));
    rec[@"t"] = zHistoryStamp(now);
    rec[@"text"] = t;
    if (sid.length) rec[@"sid"] = sid;
    if (via.length) rec[@"via"] = via;
    if (app.length) rec[@"app"] = app;

    // کلیدهای مرتب: خروجی قابل پیش‌بینی می‌شود، پس هم diff فایل معنی دارد هم تست
    // می‌تواند رویش حساب کند. اسلش‌ها هم دست‌نخورده می‌مانند که نشانیِ داخل متن
    // در tail خوانا بماند.
    NSError *err = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:rec
                                                   options:NSJSONWritingSortedKeys |
                                                           NSJSONWritingWithoutEscapingSlashes
                                                     error:&err];
    if (!json.length) {
        ZLog(@"تاریخچه: رکورد ساخته نشد: %@", err.localizedDescription ?: @"?");
        return;
    }
    // شرطِ کلِ این طراحی همین است: یک رکورد، یک خط. اگر روزی خطِ جدیدی از لای
    // رشته رد شد، رکورد را ننویس؛ فایلِ نیمه‌درست بدتر از رکوردِ نیامده است.
    if (memchr(json.bytes, '\n', json.length)) {
        ZLog(@"تاریخچه: رکورد خطِ جدید داشت و نوشته نشد");
        return;
    }
    NSMutableData *line = [json mutableCopy];
    [line appendBytes:"\n" length:1];

    NSString *path = file.path;
    NSLock *lock = zHistoryLock();
    [lock lock];
    // O_RDWR و نه O_WRONLY، فقط برای همان یک بایتِ خواندن پایین‌تر. O_APPEND به هر
    // حال هر نوشتنی را ته فایل می‌برد.
    int fd = open(path.fileSystemRepresentation, O_RDWR | O_APPEND | O_CREAT, 0600);
    BOOL ok = fd >= 0;
    if (ok) {
        // **بستنِ دُمِ نصفه.** کرشِ وسطِ نوشتن یک خطِ بی‌`\n` ته فایل جا می‌گذارد.
        // خواننده خودش دورش می‌اندازد، ولی نوشتنِ بعدی بی این چند خط به همان دُم
        // **می‌چسبید** و یک خطِ ناخوانا می‌ساخت، یعنی کرشِ دیروز رکوردِ امروز را هم
        // می‌برد. یک `\n` پیش از رکورد، همان‌جا زخم را می‌بندد.
        off_t size = lseek(fd, 0, SEEK_END);
        char last = '\n';
        if (size > 0 && pread(fd, &last, 1, size - 1) == 1 && last != '\n') {
            NSMutableData *fixed = [NSMutableData dataWithBytes:"\n" length:1];
            [fixed appendData:line];
            line = fixed;
            ZLog(@"تاریخچه: دُمِ نصفه‌ی یک نوشتنِ ناتمام بسته شد");
        }
        ok = zWriteAll(fd, line.bytes, line.length);
    }
    [lock unlock];

    if (!ok) {
        ZLog(@"تاریخچه: نوشته نشد (%s)", strerror(errno));
        if (fd >= 0) close(fd);
        return;
    }
    dispatch_async(zHistoryFlushQ(), ^{
        fsync(fd);
        close(fd);
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:ZHistoryDidChangeNotification
                                                          object:nil];
    });
}

void ZHistoryAppend(NSString *text, NSString *sid, NSString *via, NSString *app) {
    ZHistoryAppendTo(ZHistoryFile(), text, sid, via, app);
}

// ---------- خواندن ----------

// خطوطِ **کاملِ** داخل یک تکه بایت، از نو به کهنه. «کامل» یعنی هر دو سرش `\n` دیده
// باشد: خطِ اولِ پنجره وقتی از وسط فایل بریده شده نصفه است، و هرچه بعد از آخرین
// `\n` مانده هم نصفه است (همان دُمِ کرش). هر دو می‌افتند.
static NSArray<NSData *> *zNewestFirstLines(NSData *chunk, BOOL fromStart) {
    const char *b = chunk.bytes;
    NSUInteger n = chunk.length;
    NSUInteger end = n;
    while (end > 0 && b[end - 1] != '\n') end--;    // دُمِ نصفه را ببر
    NSUInteger begin = 0;
    if (!fromStart) {
        while (begin < end && b[begin] != '\n') begin++;
        if (begin < end) begin++;                   // سرِ نصفه را هم
    }
    NSMutableArray<NSData *> *out = [NSMutableArray array];
    NSUInteger lineEnd = end;
    while (lineEnd > begin) {
        NSUInteger i = lineEnd - 1;                 // این یکی خودِ `\n` است
        NSUInteger lineStart = begin;
        for (NSUInteger j = i; j > begin; j--) {
            if (b[j - 1] == '\n') { lineStart = j; break; }
        }
        if (i > lineStart) [out addObject:[chunk subdataWithRange:NSMakeRange(lineStart, i - lineStart)]];
        lineEnd = lineStart;
    }
    return out;
}

static ZHistoryEntry *zParseLine(NSData *line) {
    NSDictionary *d = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
    if (![d isKindOfClass:NSDictionary.class]) return nil;
    NSString *text = d[@"text"];
    if (![text isKindOfClass:NSString.class] || !text.length) return nil;
    ZHistoryEntry *e = [ZHistoryEntry new];
    e.text = text;
    e.sid = [d[@"sid"] isKindOfClass:NSString.class] ? d[@"sid"] : nil;
    e.via = [d[@"via"] isKindOfClass:NSString.class] ? d[@"via"] : nil;
    e.app = [d[@"app"] isKindOfClass:NSString.class] ? d[@"app"] : nil;
    NSNumber *at = [d[@"at"] isKindOfClass:NSNumber.class] ? d[@"at"] : nil;
    e.at = at ? [NSDate dateWithTimeIntervalSince1970:at.doubleValue] : nil;
    return e;
}

NSArray<ZHistoryEntry *> *ZHistoryRecentIn(NSURL *file, NSUInteger max) {
    if (!file || max == 0) return @[];
    NSFileHandle *h = [NSFileHandle fileHandleForReadingAtPath:file.path];
    if (!h) return @[];
    unsigned long long size = 0;
    @try { size = [h seekToEndOfFile]; }
    @catch (NSException *e) { [h closeFile]; return @[]; }

    NSMutableArray<ZHistoryEntry *> *out = [NSMutableArray array];
    // پنجره از ته بزرگ می‌شود تا یا به اندازه رکورد جمع شود یا به سرِ فایل برسیم.
    // فایلِ شصت‌روزه‌ی یک کاربر سنگین چند مگابایت است، ولی خواندنِ کلش برای نشان
    // دادنِ بیست ردیف اسراف است و روزی که فایل بزرگ شود همان‌جا دیده می‌شود.
    for (unsigned long long window = kZHistoryTailBytes; ; window *= 8) {
        BOOL fromStart = window >= size;
        // یک بایت عقب‌تر از پنجره عمدی است: بی آن، پنجره‌ای که تصادفا دقیقا سرِ یک
        // خط بیفتد آن خط را «نصفه» می‌بیند و یک رکوردِ سالم را می‌اندازد. با این
        // بایتِ اضافه، همیشه پایانِ خطِ قبلی جلوی چشم است و مرز درست پیدا می‌شود.
        unsigned long long start = fromStart ? 0 : (size - window) - 1;
        NSData *chunk = nil;
        @try {
            [h seekToFileOffset:start];
            chunk = [h readDataOfLength:(NSUInteger)(size - start)];
        } @catch (NSException *e) { break; }

        [out removeAllObjects];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        NSUInteger broken = 0;
        for (NSData *line in zNewestFirstLines(chunk, fromStart)) {
            ZHistoryEntry *e = zParseLine(line);
            if (!e) { broken++; continue; }
            // یک ردیف برای هر سشن، و تازه‌ترین عکسش. رکوردِ بی‌sid تکی است.
            NSString *key = e.sid.length ? e.sid : [NSString stringWithFormat:@"#%lu", (unsigned long)out.count];
            if ([seen containsObject:key]) continue;
            [seen addObject:key];
            [out addObject:e];
            if (out.count >= max) break;
        }
        if (broken) ZLog(@"تاریخچه: %lu خطِ ناخوانا رد شد", (unsigned long)broken);
        if (out.count >= max || fromStart) break;
    }
    [h closeFile];
    return out;
}

NSArray<ZHistoryEntry *> *ZHistoryRecent(NSUInteger max) {
    return ZHistoryRecentIn(ZHistoryFile(), max);
}

// ---------- جارو ----------

// بازنویسیِ فایل با همان رکوردهایی که از مرز جوان‌ترند. تنها جایی است که این فایل
// افزودنی نیست، پس زیر همان قفلِ نوشتن می‌رود و آخرش با rename جا عوض می‌کند: یا
// نسخه‌ی قدیم سر جایش است یا نسخه‌ی نو، هیچ‌وقت نیمه‌ی یکی.
NSUInteger ZHistorySweepFile(NSURL *file, NSDate *cutoff) {
    if (!file || !cutoff) return 0;
    NSLock *lock = zHistoryLock();
    [lock lock];
    NSUInteger dropped = 0;
    @try {
        NSData *all = [NSData dataWithContentsOfURL:file];
        if (!all.length) return 0;
        NSArray<NSData *> *lines = zNewestFirstLines(all, YES);
        NSMutableData *keep = [NSMutableData data];
        // از نو به کهنه آمده‌اند؛ برای نوشتن باید برگردند به ترتیب اصلی
        for (NSData *line in lines.reverseObjectEnumerator) {
            ZHistoryEntry *e = zParseLine(line);
            // خطِ ناخوانا هم می‌رود: نگه داشتنش فقط زباله را جاودانه می‌کند
            if (!e || (e.at && [e.at compare:cutoff] == NSOrderedAscending)) { dropped++; continue; }
            [keep appendData:line];
            [keep appendBytes:"\n" length:1];
        }
        if (!dropped) return 0;

        NSString *tmp = [file.path stringByAppendingString:@".tmp"];
        int fd = open(tmp.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd < 0) { ZLog(@"تاریخچه: جارو نشد (%s)", strerror(errno)); return 0; }
        BOOL ok = zWriteAll(fd, keep.bytes, keep.length);
        if (ok) ok = fsync(fd) == 0;
        close(fd);
        if (!ok || rename(tmp.fileSystemRepresentation, file.path.fileSystemRepresentation) != 0) {
            ZLog(@"تاریخچه: جارو نشد (%s)", strerror(errno));
            unlink(tmp.fileSystemRepresentation);
            return 0;
        }
    } @finally {
        [lock unlock];
    }
    return dropped;
}

// روزی یک بار، و بی‌صدا. «روز» از روی شماره‌ی روزِ ذخیره‌شده حساب می‌شود نه از روی
// تایمر، پس اپی که هفته‌ای یک بار باز می‌شود هم جارویش را می‌کند و اپی که یک ماه باز
// می‌ماند روزی یک بار (تایمر روزانه‌ی app.m همین را دوباره صدا می‌زند).
void ZHistorySweepIfDue(void) {
    NSInteger days = ZSettings.shared.historyKeepDays;
    if (days <= 0) return;      // صفر یعنی هرگز
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        NSInteger today = (NSInteger)floor(NSDate.date.timeIntervalSince1970 / 86400.0);
        if ([d objectForKey:@"historySweptDay"] && [d integerForKey:@"historySweptDay"] == today) return;
        [d setInteger:today forKey:@"historySweptDay"];

        NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-(double)days * 86400.0];
        NSUInteger recs = ZHistorySweepFile(ZHistoryFile(), cutoff);
        NSUInteger logLines = ZLogTrimBefore(cutoff);
        if (recs || logLines) {
            ZLog(@"جارو: %lu رکورد تاریخچه و %lu خط لاگ قدیمی‌تر از %ld روز پاک شد",
                 (unsigned long)recs, (unsigned long)logLines, (long)days);
        }
    });
}
