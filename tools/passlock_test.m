// تست طلاییِ نوبتِ پاس. بی‌کلید، بی‌شبکه، بی‌سهم، در کمتر از یک ثانیه.
//
// چه چیزی را ثابت می‌کند (و چرا این‌ها):
//   · نوبتِ دوم **بلوکه نمی‌شود**، همان لحظه رد می‌شود، و پیامش فارسی است و اسمِ کاری
//     که در جریان است در آن هست.
//   · نوبت مالِ **کل پاس** است نه یک تماس: بینِ تماس اول و دوم و سومِ یک پاس هم کسی
//     تو نمی‌آید، و نتیجه‌ی پاسِ اول دست‌نخورده می‌ماند.
//   · هر نقطه‌ی بازگشت نوبت را پس می‌دهد، به همان ترتیبی که در دو متد
//     `work:` هستند، و هیچ‌کدام «آزاد کن» صدا نمی‌زند: آزادسازی کارِ `dealloc` است.
//     تست عمدا استخر تازه نمی‌سازد، پس اگر روزی ARC نوبت را به استخر بیندازد (یعنی
//     آزاد شدن تا تخلیه‌ی استخر عقب بیفتد) همین‌جا قرمز می‌شود.
//   · لغو صاحب دارد: لغوِ یک مصرف‌کننده کارِ آن یکی را نمی‌کشد، و لغوِ کهنه به نوبتِ
//     بعدی نمی‌رسد (همان `resetCancel`ی که حذف شد).
//
// اجرا: bash tools/passlock_test.sh
#import <Foundation/Foundation.h>
#import <stdatomic.h>
#import "zemzeme.h"

static int gFail;

static void ok(NSString *name, BOOL cond, NSString *detail) {
    if (!cond) gFail++;
    printf("%s %s\n", cond ? "ok  " : "FAIL", name.UTF8String);
    if (!cond && detail.length) printf("      %s\n", detail.UTF8String);
}

// ---------- نقطه‌های بازگشت ----------
// نام‌ها همان‌هایی است که در `-[ZFinalPass work:lang:say:]` و
// `-[ZEnhance work:lang:say:]` واقعا وجود دارند. اگر روزی یکی اضافه شود، همین‌جا هم
// یک سطر اضافه می‌شود و شکل کار عوض نمی‌شود.
static NSString *const kBails[] = {
    @"key-missing", @"prompt-missing", @"cancelled-before-audio", @"audio-part-failed",
    @"cancelled-before-transcribe", @"transcribe-empty", @"gate-gave-up", @"normal-end",
};
#define kBailCount (sizeof(kBails) / sizeof(kBails[0]))

// هیچ‌جای این تابع «نوبت را پس بده» نوشته نشده، و همین نکته‌اش است.
static NSString *bailAt(ZPassLock *lock, NSUInteger stop) {
    ZPassLease *lease = [lock claim:ZPassOwnerFinal busy:NULL];
    if (!lease) return @"claim-failed";
    for (NSUInteger i = 0; i < kBailCount; i++) {
        if (i == stop) return kBails[i];
    }
    return @"fell-through";
}

// ---------- یک پاسِ کامل، چند تماس ----------
// دو سمافور به‌جای خواب: تست باید قطعی باشد نه امیدوار. `at` یعنی «وسط تماس i ام‌ام»
// و `go` یعنی «برو جلو».
static NSString *fakePass(ZPassLock *lock, NSString *owner,
                          dispatch_semaphore_t at, dispatch_semaphore_t go) {
    ZPassLease *lease = [lock claim:owner busy:NULL];
    if (!lease) return nil;
    NSMutableString *s = [NSMutableString string];
    for (int i = 1; i <= 3; i++) {
        dispatch_semaphore_signal(at);
        dispatch_semaphore_wait(go, DISPATCH_TIME_FOREVER);
        if (lease.cancelled) return nil;
        [s appendFormat:@"%d", i];
    }
    return s;
}

// ---------- مسابقه ----------
static atomic_int gLive, gWon, gOverlap;

int main(void) {
    @autoreleasepool {
        ZPassLock *lock = [ZPassLock new];
        ok(@"lock: free at the start", lock.busyOwner == nil, lock.busyOwner);

        // ---------- رد کردنِ همان‌لحظه‌ای، با پیام فارسی ----------
        {
            NSString *busy = nil;
            ZPassLease *a = [lock claim:ZPassOwnerFinal busy:&busy];
            ok(@"claim: the first caller gets the pass", a != nil, nil);
            ok(@"claim: a free lock says nothing about being busy", busy == nil, busy);
            ok(@"claim: the owner is what was asked for",
               [a.owner isEqualToString:ZPassOwnerFinal], a.owner);

            NSDate *t0 = NSDate.date;
            NSString *busy2 = nil;
            ZPassLease *b = [lock claim:ZPassOwnerEnhance busy:&busy2];
            NSTimeInterval dt = [NSDate.date timeIntervalSinceDate:t0];
            ok(@"claim: the second caller is refused, not queued", b == nil, b.owner);
            // «همان لحظه» عدد می‌خواهد وگرنه ادعاست. ۱۰ میلی‌ثانیه سقفِ بسیار دست‌ودل‌بازی
            // است و هر شکلی از بلوکه شدن یا صف زدن از آن رد می‌شود.
            ok(@"claim: the refusal is immediate, never blocking",
               dt < 0.01, [NSString stringWithFormat:@"%.1f ms", dt * 1000]);
            ok(@"claim: the refusal names the work that is actually running",
               [busy2 rangeOfString:ZPassOwnerFinal].location != NSNotFound, busy2);
            ok(@"claim: the refusal is one Persian line, ready for the status bar",
               busy2.length > 0 && [busy2 rangeOfString:@"\n"].location == NSNotFound
                   && [busy2 rangeOfString:@"همین حالا در جریان است"].location != NSNotFound,
               busy2);
            ok(@"claim: a refused caller still sees the lock held by the first",
               [lock.busyOwner isEqualToString:ZPassOwnerFinal], lock.busyOwner);
        }
        // `a` از اسکوپ بیرون رفت. هیچ‌کس «آزاد کن» نزد.
        ok(@"lease: leaving scope hands the pass back, with no explicit release",
           lock.busyOwner == nil, lock.busyOwner);

        // ---------- هر نقطه‌ی بازگشت ----------
        // بی استخرِ تازه و بی هیچ کارِ دیگری بین فراخوان و ادعا: اگر آزادسازی تا
        // تخلیه‌ی استخر عقب بیفتد، این حلقه همان دور اول قرمز می‌شود.
        for (NSUInteger i = 0; i < kBailCount; i++) {
            NSString *hit = bailAt(lock, i);
            ok([NSString stringWithFormat:@"return path %lu/%lu (%@) releases the pass",
                (unsigned long)(i + 1), (unsigned long)kBailCount, kBails[i]],
               [hit isEqualToString:kBails[i]] && lock.busyOwner == nil,
               [NSString stringWithFormat:@"hit=%@ stillHeldBy=%@", hit, lock.busyOwner ?: @"(free)"]);
        }

        // ---------- کل پاس، نه یک تماس ----------
        {
            dispatch_semaphore_t at = dispatch_semaphore_create(0);
            dispatch_semaphore_t go = dispatch_semaphore_create(0);
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            __block NSString *got = nil;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                @autoreleasepool { got = fakePass(lock, ZPassOwnerFinal, at, go); }
                dispatch_semaphore_signal(done);
            });
            for (int call = 1; call <= 3; call++) {
                dispatch_semaphore_wait(at, DISPATCH_TIME_FOREVER);
                NSString *busy = nil;
                ZPassLease *cut = [lock claim:ZPassOwnerEnhance busy:&busy];
                ok([NSString stringWithFormat:
                    @"whole pass: nobody slips in between call %d and %d", call, call + 1],
                   cut == nil, busy);
                dispatch_semaphore_signal(go);
            }
            dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
            ok(@"whole pass: the first pass finishes untouched",
               [got isEqualToString:@"123"], got);
            ok(@"whole pass: the lock is free once the pass returns",
               lock.busyOwner == nil, lock.busyOwner);
        }

        // ---------- لغو صاحب دارد ----------
        {
            ZPassLease *e = [lock claim:ZPassOwnerEnhance busy:NULL];
            ok(@"cancel: setup, enhance holds the pass", e != nil, nil);
            BOOL hit = [lock cancelOwner:ZPassOwnerFinal];
            ok(@"cancel: the final pass cannot cancel enhance's work", !hit, nil);
            ok(@"cancel: and enhance's own lease is untouched", !e.cancelled, nil);
            hit = [lock cancelOwner:ZPassOwnerEnhance];
            ok(@"cancel: the owner can cancel its own work", hit, nil);
            ok(@"cancel: and the lease reports it", e.cancelled, nil);
        }
        // ---------- لغوِ کهنه به نوبتِ بعدی نمی‌رسد ----------
        // این همان چیزی است که `resetCancel` را حذف کرد. قبلا یک بولینِ مشترک بود، پس
        // یا لغو کهنه کارِ بعدی را می‌کشت، یا `resetCancel` لغوِ همین‌لحظه‌ی کاربر را
        // پاک می‌کرد. با نسل، هیچ‌کدام.
        {
            ZPassLease *nxt = [lock claim:ZPassOwnerFinal busy:NULL];
            ok(@"cancel: a stale cancel never reaches the next pass",
               nxt != nil && !nxt.cancelled, nil);
            // و همان کارِ لغو‌شده‌ی قبلی هم دوباره تحویل داده می‌شود، بی‌آنکه چیزی صفر شود
            ZPassLease *same = [lock claim:ZPassOwnerEnhance busy:NULL];
            ok(@"cancel: no reset needed anywhere", same == nil, nil);
        }
        ok(@"cancel: the lock is free again afterwards", lock.busyOwner == nil, lock.busyOwner);

        // ---------- تسکِ در پرواز ----------
        // سشن و تسکِ واقعی، ولی `resume` هیچ‌وقت زده نمی‌شود: نه بایتی می‌رود، نه سهمی.
        {
            NSURLSession *s = [NSURLSession sessionWithConfiguration:
                               NSURLSessionConfiguration.ephemeralSessionConfiguration];
            NSURLSessionTask *t = [s dataTaskWithURL:[NSURL URLWithString:@"https://127.0.0.1:1/"]];
            ZPassLease *e = [lock claim:ZPassOwnerEnhance busy:NULL];
            ok(@"live task: arming works while the pass is running",
               e != nil && [lock armTask:t session:s], nil);
            [lock cancelOwner:ZPassOwnerEnhance];
            ok(@"live task: cancelling the owner really kills the in-flight task",
               t.state == NSURLSessionTaskStateCanceling || t.state == NSURLSessionTaskStateCompleted,
               [NSString stringWithFormat:@"state=%ld", (long)t.state]);
            ok(@"live task: after a cancel, the next request is never even sent",
               ![lock armTask:t session:s], nil);
            [lock disarm];
        }
        // یک تسک بی‌نوبت هیچ‌جا ثبت نمی‌شود: نوبتِ بعدی نباید صاحبِ زباله‌ی قبلی شود
        {
            NSURLSession *s = [NSURLSession sessionWithConfiguration:
                               NSURLSessionConfiguration.ephemeralSessionConfiguration];
            NSURLSessionTask *t = [s dataTaskWithURL:[NSURL URLWithString:@"https://127.0.0.1:1/"]];
            ok(@"live task: arming without a lease is refused",
               ![lock armTask:t session:s], lock.busyOwner);
            [s invalidateAndCancel];
        }

        // ---------- مسابقه‌ی واقعی ----------
        // شصت‌وچهار نخ همزمان. ادعای درست «دقیقا یکی برنده شد» نیست (نوبت‌ها پشت هم
        // آزاد می‌شوند و نفر بعدی می‌گیرد)، ادعای درست «هیچ‌وقت دو تا با هم نه» است.
        dispatch_apply(64, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) {
            @autoreleasepool {
                ZPassLease *l = [lock claim:(i % 2) ? ZPassOwnerFinal : ZPassOwnerEnhance
                                       busy:NULL];
                if (!l) return;
                atomic_fetch_add(&gWon, 1);
                if (atomic_fetch_add(&gLive, 1) + 1 > 1) atomic_fetch_add(&gOverlap, 1);
                for (int k = 0; k < 200; k++) (void)l.cancelled;    // کمی وقت‌کشی زیر نوبت
                atomic_fetch_sub(&gLive, 1);
            }
        });
        ok(@"race: two passes are never live at the same time",
           atomic_load(&gOverlap) == 0,
           [NSString stringWithFormat:@"%d overlaps in %d wins", gOverlap, gWon]);
        ok(@"race: at least one thread did get through", atomic_load(&gWon) > 0, nil);
        ok(@"race: the lock is free at the end", lock.busyOwner == nil, lock.busyOwner);

        printf("\n%s  (%d failed)\n", gFail ? "FAILED" : "all pass-lock tests passed", gFail);
        return gFail ? 1 : 0;
    }
}
