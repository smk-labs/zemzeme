// درج متن (تایپ یونیکد / پیست تکه‌ای) و تپ‌های کیبورد (Esc و دابل‌تپ Command راست).
#import "zemzeme.h"
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>

// ---------- ورودیِ غیرِ خودمان ----------
// رویدادهای ساختگیِ ما این برچسب را می‌گیرند. بی آن، تپِ سراسری تایپِ خودمان را هم
// «کاربر دست زد» می‌دید و مدرکِ سطح دو هیچ‌وقت معتبر نمی‌ماند.
static const int64_t kZOurEventTag = 0x7A656D32;    // "zem2"

static CFAbsoluteTime gLastForeignInputAt;

void ZNoteForeignInput(void) { gLastForeignInputAt = CFAbsoluteTimeGetCurrent(); }
CFAbsoluteTime ZLastForeignInputAt(void) { return gLastForeignInputAt; }

// ---------- ZInjector ----------

@implementation ZInjector {
    dispatch_queue_t _q;
    CFAbsoluteTime _lastWriteAt;   // مرجعِ مدرکِ سطح دو: از این لحظه به بعد کسی دست زد؟
}

- (instancetype)init {
    if ((self = [super init])) {
        _q = dispatch_queue_create("zemzeme.inject", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

+ (BOOL)accessibilityOK {
    return AXIsProcessTrusted();
}

+ (void)promptAccessibility {
    NSDictionary *opts = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);
}

+ (BOOL)secureInputActive {
    return IsSecureEventInputEnabled();
}

// سقف پاک‌کن. دُم یک پاره است، نه یک سند؛ عددی بزرگ‌تر از این یعنی دفترداریِ دُم به هم
// ریخته، و آن‌وقت هر Backspace اضافه می‌رود سراغ متن خود کاربر. جلوی فرار را می‌گیرد.
static const NSUInteger kZMaxErase = 256;

// کف فاصله‌ی بین Backspace ها. تایپ ۱۸ نویسه در یک رویداد می‌رود ولی پاک‌کن یک رویداد
// به ازای هر نویسه می‌فرستد؛ با ۱ میلی‌ثانیه، اپ‌های سنگین (کروم، الکترون) رویداد
// می‌انداختند و شمارشِ دُم از واقعیت جدا می‌شد. افتادنِ یک تایپ فقط زشت است، افتادنِ
// یک Backspace متنِ کاربر را می‌خورد؛ پس این سمت گران‌تر ولی محکم‌تر بسته می‌شود.
static const useconds_t kZEraseMinDelay = 2500;

// مهلت پیش از اولین رویدادِ یک رگبار تایپ، و کف فاصله‌ی بین رویدادها.
// اندازه‌گیری، نه حدس: در یک درجِ حالت زنده دقیقا ۱۸ واحد UTF-16 از اول تکه نرسید
// («انگار قاطی می‌کنه » که سر سوزن ۱۸ واحد است)، یعنی درست یک رویداد کامل، و بقیه
// سالم نشست. متن در فایل خام `sessions/` بود، پس نه تشخیص کم گذاشته بود نه پاس
// ویرایش؛ اپ مقصد اولین رویداد رگبار را انداخت. با ۱ میلی‌ثانیه فاصله، کل یک جمله
// در ~۶ میلی‌ثانیه شلیک می‌شد و اپ‌های سنگین (الکترون، مرورگر) فرصت نداشتند.
// حالت کرسر همیشه سالم بود چون آنجا چند نویسه‌ای و مدام تایپ می‌شود، پس اپ گرم است؛
// حالت زنده یک جمله را یک‌جا و پس از سکوت می‌فرستد، یعنی دقیقا حالت سرد.
static const useconds_t kZTypeLeadIn = 25000;
static const useconds_t kZTypeMinDelay = 6000;

// چرا پرچم صفر: رویدادِ ساخته‌شده با منبع NULL پرچم مودیفایرِ همان لحظه را برمی‌دارد.
// اگر موقع درج، Command یا Option فیزیکی پایین باشد، کیکد ۰ (که همان A است) می‌شود
// «همه را انتخاب کن» و kVK_Delete می‌شود «کل خط را پاک کن» یا «کلمه‌ی قبل را پاک کن».
// مسیر sendCmdV پرچمش را عمدا و صریح می‌گذارد؛ این دو مسیر باید صریحا صفرش کنند.
static void zPostPlain(CGEventRef e) {
    if (!e) return;
    CGEventSetFlags(e, 0);
    CGEventSetIntegerValueField(e, kCGEventSourceUserData, kZOurEventTag);
    CGEventPost(kCGSessionEventTap, e);
    CFRelease(e);
}

static void zPostUnicode(const UniChar *units, NSUInteger n) {
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, 0, true);
    if (down) {
        CGEventKeyboardSetUnicodeString(down, (UniCharCount)n, units);
        zPostPlain(down);
    }
    zPostPlain(CGEventCreateKeyboardEvent(NULL, 0, false));
}

// تایپ مستقیم: تکه‌های حداکثر ۱۸ واحد UTF-16 در هر رویداد؛
// چون پنل فوکس نمی‌گیرد، متن دقیقا سر کرسرِ اپ مقصد می‌نشیند.
- (void)type:(NSString *)text delayMicros:(useconds_t)d {
    [self type:text delayMicros:d done:nil];
}

- (void)type:(NSString *)text delayMicros:(useconds_t)d done:(void (^)(void))done {
    dispatch_async(_q, ^{
        [self typeNow:text delayMicros:d leadIn:YES];
        self->_lastWriteAt = CFAbsoluteTimeGetCurrent();
        if (done) dispatch_async(dispatch_get_main_queue(), done);
    });
}

// روی صف درج. lead-in فقط وقتی لازم است که اپ سرد باشد؛ بعد از پاک‌کن گرم است.
- (void)typeNow:(NSString *)text delayMicros:(useconds_t)d leadIn:(BOOL)leadIn {
    NSData *utf16 = [text dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    const UniChar *units = utf16.bytes;
    NSUInteger count = utf16.length / 2, i = 0;
    useconds_t td = MAX(d, kZTypeMinDelay);
    if (leadIn) usleep(kZTypeLeadIn);    // اپ مقصد سرد است؛ اولین رویداد نباید قربانی شود
    while (i < count) {
        NSUInteger n = MIN((NSUInteger)18, count - i);
        zPostUnicode(units + i, n);
        usleep(td);
        i += n;
    }
}

// ---------- درجِ اتمیک ----------
// یک رویدادِ کیبورد ۱۸ واحد UTF-16 می‌برد و اپ مقصد می‌تواند کلِ یک رویداد را
// بیندازد. اندازه‌گیری، دو بار، روی دو سشن جدا: «انگار قاطی می‌کنه » و
// « نظرم کافیه خدانگه»، هر دو سر سوزن ۱۸ واحد، هر دو در فایل خام sessions/ سالم و
// روی صفحه غایب. مهلتِ شروع و کفِ فاصله فقط احتمالش را کم می‌کنند، صفرش نمی‌کنند.
// یک نوشتنِ اکسسبیلیتی اما تجزیه‌ناپذیر است: یا همه‌اش می‌نشیند یا خطا برمی‌گرداند.
//
// فقط برای متنِ بلندتر از یک رویداد. متنِ کوتاه‌تر ذاتا نمی‌تواند نصفه بیفتد، و آنجا
// مسیر تایپِ اندازه‌گیری‌شده دست‌نخورده می‌ماند (دُمِ زنده‌ی حالت کرسر از همان می‌رود).
static const NSUInteger kZAtomicMinUnits = 18;

// اپ‌هایی که نوشتنِ AX را قبول نکردند. یک بار امتحان، بعد دیگر هزینه‌اش را نمی‌دهیم.
static NSMutableSet<NSNumber *> *ZNoAXWritePids(void) {
    static NSMutableSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSMutableSet set]; });
    return s;    // فقط روی صف درج دست می‌خورد، پس قفل لازم ندارد
}

- (void)insert:(NSString *)text pid:(pid_t)pid delayMicros:(useconds_t)d
 pasteIfRefused:(BOOL)pasteIfRefused done:(void (^)(BOOL viaAX))done {
    dispatch_async(_q, ^{
        BOOL viaAX = NO;
        BOOL atomic = text.length >= kZAtomicMinUnits;
        if (atomic && ![ZNoAXWritePids() containsObject:@(pid)]) {
            viaAX = [self axInsert:text pid:pid];
            if (!viaAX) {
                ZLog(@"inject: ax write refused by pid=%d", pid);
                [ZNoAXWritePids() addObject:@(pid)];
            }
        }
        if (!viaAX) {
            // اپ همین حالا گفت نوشتنِ اتمیک را نمی‌پذیرد. رگبار رویدادِ ساختگی روی
            // متنِ بلند، در همان اپ، همان چیزی است که این مسیر برای فرارش ساخته شد:
            // اپ رویداد می‌اندازد و رویداد تکرار می‌کند و متن قیچی می‌شود. پیست تنها
            // مسیرِ اتمیکِ باقی‌مانده است، پس متنِ یکجا از آنجا می‌رود.
            BOOL viaPaste = atomic && pasteIfRefused;
            ZLog(@"inject: %@ %lu chars into pid=%d",
                 viaPaste ? @"pasting" : @"typing", (unsigned long)text.length, pid);
            if (viaPaste) [self pasteNow:text delayMicros:ZSettings.shared.pasteDelayMicros];
            else [self typeNow:text delayMicros:d leadIn:YES];
        }
        self->_lastWriteAt = CFAbsoluteTimeGetCurrent();
        if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(viaAX); });
    });
}

// روی صف درج صدا زده می‌شود. NO یعنی هیچ‌چیز ننشست و فراخوان باید تایپ کند.
- (BOOL)axInsert:(NSString *)text pid:(pid_t)pid {
    AXUIElementRef el = ZCopyFocusedElement(pid);
    if (!el) return NO;
    BOOL haveSel = NO;
    CFRange before = zSelectedRange(el, &haveSel);
    if (!haveSel) {
        CFRelease(el);
        return NO;
    }
    AXError w = AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute,
                                             (__bridge CFStringRef)text);
    if (w != kAXErrorSuccess) {
        CFRelease(el);
        return NO;
    }
    // «موفق» گفتن و کاری نکردن هم پیش می‌آید. کرسر باید دقیقا به اندازه‌ی متن جلو
    // رفته باشد؛ اگر تکان نخورده، چیزی ننشسته و تایپ می‌کنیم.
    BOOL haveAfter = NO;
    CFRange after = zSelectedRange(el, &haveAfter);
    CFRelease(el);
    if (!haveAfter) return YES;    // نتوانستیم بخوانیم؛ نوشتن خطا نداد، پس نشسته
    if (after.location == before.location) return NO;
    if (after.location != before.location + (CFIndex)text.length) {
        // نه سر جایش، نه آنجا که انتظار داشتیم. متن تقریبا حتما نشسته (نوشتنِ AX
        // تجزیه‌ناپذیر است)، پس دوباره نمی‌نویسیم؛ ولی این اپ دیگر قابل اعتماد نیست.
        ZLog(@"inject: ax write landed at an unexpected caret on pid=%d, distrusting it", pid);
        [ZNoAXWritePids() addObject:@(pid)];
    }
    return YES;
}

// ---------- جایگزینیِ تاییدشده ----------
// قاعده‌ی سفت: هیچ Backspace ای بی مدرک نمی‌رود. مدرک یا خواندنِ متن واقعی است، یا
// (در اپی که خواندن نمی‌دهد) این‌که از آخرین نوشتنِ ما هیچ ورودیِ غیرِ خودمان نیامده.

static CFRange zSelectedRange(AXUIElementRef el, BOOL *ok) {
    *ok = NO;
    CFRange r = {0, 0};
    CFTypeRef v = NULL;
    if (AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute, &v) != kAXErrorSuccess
        || !v) return r;
    if (CFGetTypeID(v) == AXValueGetTypeID()
        && AXValueGetValue((AXValueRef)v, kAXValueCFRangeType, &r)) *ok = YES;
    CFRelease(v);
    return r;
}

static NSString *zStringForRange(AXUIElementRef el, CFRange range) {
    AXValueRef rv = AXValueCreate(kAXValueCFRangeType, &range);
    if (!rv) return nil;
    CFTypeRef out = NULL;
    AXError e = AXUIElementCopyParameterizedAttributeValue(
        el, kAXStringForRangeParameterizedAttribute, rv, &out);
    CFRelease(rv);
    if (e != kAXErrorSuccess || !out) return nil;
    NSString *s = CFGetTypeID(out) == CFStringGetTypeID() ? [(__bridge NSString *)out copy] : nil;
    CFRelease(out);
    return s;
}

static BOOL zSetSelectedRange(AXUIElementRef el, CFRange range) {
    AXValueRef rv = AXValueCreate(kAXValueCFRangeType, &range);
    if (!rv) return NO;
    AXError e = AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute, rv);
    CFRelease(rv);
    return e == kAXErrorSuccess;
}

- (void)replaceLast:(NSUInteger)n expecting:(NSString *)expected with:(NSString *)text
        delayMicros:(useconds_t)d pid:(pid_t)pid
               done:(void (^)(ZWriteProof proof, BOOL viaAX))done {
    // روی همان صف سریالِ درج، پس هرچه قبلا فرستاده‌ایم نشسته و خواندن با واقعیت
    // می‌خواند. خواندنِ AX پیش از خالی شدن این صف، متنِ یک لحظه قبل را می‌داد.
    dispatch_async(_q, ^{
        BOOL viaAX = NO;
        ZWriteProof proof = ZProofNone;
        AXUIElementRef el = ZCopyFocusedElement(pid);
        if (el) {
            BOOL haveSel = NO;
            CFRange sel = zSelectedRange(el, &haveSel);
            // انتخابِ باز یعنی کاربر چیزی را نشان کرده؛ دست زدن به آن کارِ ما نیست
            if (haveSel && sel.length == 0 && sel.location >= (CFIndex)n) {
                CFRange tail = {sel.location - (CFIndex)n, (CFIndex)n};
                NSString *actual = zStringForRange(el, tail);
                if (actual && [actual isEqualToString:expected]) {
                    proof = ZProofRead;
                    // یک عمل: رنجِ انتخاب را روی همان دم بگذار و متن تازه را بنویس.
                    // بی Backspace یعنی نه رویدادی می‌افتد، نه مودیفایرِ همان لحظه
                    // معنی‌اش را عوض می‌کند، نه شمارشِ دم از واقعیت جدا می‌شود.
                    if (zSetSelectedRange(el, tail)) {
                        AXError w = AXUIElementSetAttributeValue(
                            el, kAXSelectedTextAttribute, (__bridge CFStringRef)text);
                        if (w == kAXErrorSuccess) {
                            viaAX = YES;
                        } else {
                            // نوشتن نپذیرفت. کرسر را سر جایش برگردان، وگرنه انتخابِ
                            // باز می‌ماند و اولین Backspace فال‌بک کلِ آن را می‌خورد.
                            zSetSelectedRange(el, (CFRange){sel.location, 0});
                        }
                    }
                }
            }
            CFRelease(el);
        }
        if (proof == ZProofNone) {
            // مدرکِ سطح دو: از آخرین نوشتنِ ما هیچ کلید و کلیکی از کاربر نیامده.
            // ضعیف‌تر از خواندن است، ولی مدرک است نه حدس، و تنها چیزی است که در
            // ریموت دسکتاپ در دسترس است (آنجا اپ اصلا نمی‌داند چه متنی آن‌طرف است).
            if (self->_lastWriteAt > 0 && ZLastForeignInputAt() < self->_lastWriteAt) {
                proof = ZProofUntouched;
            }
        }
        if (proof == ZProofNone) {
            if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(ZProofNone, NO); });
            return;
        }
        if (!viaAX) [self eraseAndType:n text:text delayMicros:d];
        self->_lastWriteAt = CFAbsoluteTimeGetCurrent();
        ZWriteProof p = proof;
        if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(p, viaAX); });
    });
}

// فال‌بکِ کلیدی، فقط روی ناحیه‌ای که همین حالا تاییدش کرده‌ایم
- (void)eraseAndType:(NSUInteger)n text:(NSString *)text delayMicros:(useconds_t)d {
    useconds_t ed = MAX(d, kZEraseMinDelay);
    for (NSUInteger i = 0; i < n; i++) {
        for (int down = 1; down >= 0; down--) {
            zPostPlain(CGEventCreateKeyboardEvent(NULL, (CGKeyCode)kVK_Delete, down != 0));
        }
        usleep(ed);
    }
    // lead-in لازم نیست: پاک‌کن همین حالا رویداد فرستاده، پس اپ گرم است
    [self typeNow:text delayMicros:d leadIn:NO];
}

// جای دُم موقت را عوض می‌کند: n نویسه‌ی آخر پاک و متن تازه تایپ می‌شود، هر دو در یک
// بلاک روی همان صف سریال. یکی نشدنشان یعنی کاربر یک لحظه متن نصفه ببیند، یا بدتر،
// تایپِ بعدی وسط پاک کردنِ قبلی بنشیند. فقط برای نویسه‌هایی به کار می‌رود که خودمان
// همین حالا تایپشان کرده‌ایم؛ متن خودِ کاربر هیچ‌وقت از اینجا پاک نمی‌شود.
- (void)replaceLast:(NSUInteger)n with:(NSString *)text delayMicros:(useconds_t)d {
    NSData *utf16 = [text dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    if (n > kZMaxErase) {
        ZLog(@"inject: erase %lu clamped to %lu (tail bookkeeping suspect)",
             (unsigned long)n, (unsigned long)kZMaxErase);
        n = kZMaxErase;
    }
    useconds_t ed = MAX(d, kZEraseMinDelay);
    dispatch_async(_q, ^{
        for (NSUInteger i = 0; i < n; i++) {
            for (int down = 1; down >= 0; down--) {
                zPostPlain(CGEventCreateKeyboardEvent(NULL, (CGKeyCode)kVK_Delete, down != 0));
            }
            usleep(ed);
        }
        const UniChar *units = utf16.bytes;
        NSUInteger count = utf16.length / 2, i = 0;
        // اینجا lead-in لازم نیست: پاک‌کن همین حالا رویداد فرستاده، پس اپ گرم است
        while (i < count) {
            NSUInteger k = MIN((NSUInteger)18, count - i);
            zPostUnicode(units + i, k);
            usleep(MAX(d, kZTypeMinDelay));
            i += k;
        }
    });
}

// فلیکِ پنجره‌ی کلید فقط مالِ کلاینتِ ریموت است. در یک اپ مک گرفتنِ لحظه‌ایِ کلید
// بی‌دلیل است و می‌تواند پاپ‌اوورِ باز را ببندد، پس آنجا دست نمی‌زنیم. مقصدِ Cmd+V
// همان اپِ جلو است، پس همین‌جا و همین حالا پرسیدنش دقیقا همان چیزی است که لازم داریم.
static BOOL zFrontIsRemoteClient(void) {
    __block NSString *b = nil;
    if (NSThread.isMainThread) {
        b = NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier;
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            b = NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier;
        });
    }
    return [b isEqualToString:kZRDPBundleId];
}

// پیست تکه‌ای: کپی با نشونه transient (تاریخچه‌گیرها رد می‌کنند) و Cmd+V.
// همه چیز روی یک صف سریال تا دو پیست پشت هم مسابقه کلیپ‌بورد نگیرند
// (باگ واقعی: برگرداندن کلیپ‌بورد قبلی وسط پیست بعدی می‌نشست و متن قدیمی پیست می‌شد؛
// برای همین «برگرداندن» حذف شد. کپی پایانی Esc به هر حال کلیپ‌بورد را پر می‌کند.)
- (void)paste:(NSString *)text delayMicros:(useconds_t)d {
    dispatch_async(_q, ^{ [self pasteNow:text delayMicros:d]; });
}

// روی صف درج. مسیرِ درجِ اتمیک از همین‌جا صدایش می‌زند، چون همان‌جا روی صف است و
// یک dispatch دیگر فقط پیست را پشتِ کارهای بعدی می‌انداخت.
- (void)pasteNow:(NSString *)text delayMicros:(useconds_t)d {
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSPasteboard *pb = NSPasteboard.generalPasteboard;
        NSPasteboardType transient = @"org.nspasteboard.TransientType";
        [pb declareTypes:@[NSPasteboardTypeString, transient] owner:nil];
        [pb setString:text forType:NSPasteboardTypeString];
        [pb setString:@"" forType:transient];
    });
    if (zFrontIsRemoteClient()) [ZKeyFlick flick];   // «برو مک و برگرد»، خودکار
    usleep(d);    // مهلت سینک کلیپ‌بورد ریموت دسکتاپ
    [ZInjector sendCmdV];
    usleep(150000);
}

// کپی پایانی پشت صف درج: هر پیست/تایپ معلق اول تمام می‌شود، بعد کلیپ‌بورد پر می‌شود
- (void)copyFinalAfterPending:(NSString *)text {
    dispatch_async(_q, ^{
        dispatch_sync(dispatch_get_main_queue(), ^{
            [ZInjector copyFinal:text];
        });
    });
}

// یک Cmd+V دقیقا به شکل فیزیکی‌اش، نه یک V با پرچم Command.
// چرا: اپ مک از modifierFlags همان keyDown می‌خواند، پس پرچم تنها هم کافی بود. ولی
// ریموت دسکتاپ باید کلید را اسکن‌کد به اسکن‌کد به ویندوز بفرستد؛ مودیفایر برایش یک
// رویداد جداست (flagsChanged) و چپ و راست را از بیت دستگاه می‌شناسد. Windows App
// دو طرف را دو کار می‌کند: Command چپ یعنی میان‌بر مک (پیست، که خودش Ctrl+V ویندوز
// می‌شود) و Command راست یعنی کلید ویندوز. رویداد قبلی نه flagsChanged داشت نه بیت
// چپ/راست، پس در هیچ‌کدام از دو سطل ننشست و پیست خودکار در ریموت هیچ‌وقت نیفتاد.
static const CGEventFlags kZLeftCmdBit = 0x8;    // NX_DEVICELCMDKEYMASK
static const useconds_t kZChordGap = 25000;      // مهلت رسیدن مودیفایر، قبل از حرف

static void zPostModifier(CGKeyCode key, CGEventFlags flags) {
    CGEventRef e = CGEventCreateKeyboardEvent(NULL, key, true);
    if (!e) return;
    CGEventSetType(e, kCGEventFlagsChanged);
    CGEventSetFlags(e, flags);
    CGEventSetIntegerValueField(e, kCGEventSourceUserData, kZOurEventTag);
    CGEventPost(kCGSessionEventTap, e);
    CFRelease(e);
    usleep(kZChordGap);
}

// چرا پیش از پیست، پنجره‌ی کلید فلیک می‌شود (بالا، در pasteNow):
//
// اندازه‌گیری روی Windows App 11.3.0.2814، از دیس‌اسمبلیِ خودِ کلاینت: فرستادنِ
// کلیپ‌بوردِ مک به سرور تنها از دو جا صدا زده می‌شود، onNSWindowDidBecomeKey و
// onNSWindowDidResignKey (هر دو به updateClipboardHandler و getAvailableFormats
// می‌روند). نه تایمری کلیپ‌بورد را می‌پاید، نه ناظری روی NSPasteboard هست. یعنی تا
// پنجره‌ی کلاینت کلید را از دست ندهد و پس نگیرد، سرور اصلا خبر ندارد کلیپ‌بورد عوض
// شده و Ctrl+V همان متنِ قبلیِ خودِ ویندوز را می‌گذارد. کاربر دستی همین را می‌کرد:
// «برو روی مک و برگرد». حالا ZKeyFlick همان کار را در ۸۰ میلی‌ثانیه می‌کند.
//
// اینجا قبلا یک ضربه‌ی خالی روی Shift چپ می‌رفت، با این حدس که هر ورودی‌ای کلاینت را
// بیدار می‌کند. حدس غلط بود: ورودی کلید را عوض نمی‌کند، پس آن راه از اول هم نمی‌توانست
// کار کند. پاک شد، چون کدی که کاری نمی‌کند بدتر از نبودن است: جای فیکس واقعی می‌نشیند.

+ (void)sendCmdV {
    CGEventFlags held = kCGEventFlagMaskCommand | kZLeftCmdBit;
    zPostModifier((CGKeyCode)kVK_Command, held);
    for (int down = 1; down >= 0; down--) {
        CGEventRef e = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)kVK_ANSI_V, down != 0);
        if (!e) continue;
        CGEventSetFlags(e, held);
        CGEventSetIntegerValueField(e, kCGEventSourceUserData, kZOurEventTag);
        CGEventPost(kCGSessionEventTap, e);
        CFRelease(e);
        usleep(kZChordGap);
    }
    zPostModifier((CGKeyCode)kVK_Command, 0);
}

// بیمه پایانی: کپی معمولی و ماندگار کل متن سشن
+ (void)copyFinal:(NSString *)text {
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb declareTypes:@[NSPasteboardTypeString] owner:nil];
    [pb setString:text forType:NSPasteboardTypeString];
}

@end

// ---------- ZCaretSink ----------
// مقصدِ سر کرسر. حالت «درج زنده» و حالت «کنار کرسر» هر دو از این می‌خورند و تنها
// فرقشان renderPending است. همان یک بولین است که حالت زنده را ذاتا بدون هیچ عملیات
// مخربی نگه می‌دارد: دُمِ ناپایدار آنجا اصلا نوشته نمی‌شود، پس چیزی برای پاک کردن نیست.

@implementation ZCaretSink {
    ZInjector *_injector;
    ZLedgerStats *_stats;
}

- (instancetype)initWithInjector:(ZInjector *)injector {
    if ((self = [super init])) _injector = injector;
    return self;
}

- (void)useStats:(ZLedgerStats *)stats { _stats = stats; }

- (BOOL)targetIsFront {
    NSRunningApplication *f = NSWorkspace.sharedWorkspace.frontmostApplication;
    return _target && f && _target.processIdentifier == f.processIdentifier;
}

// می‌شود همین حالا نوشت؟ اپ باید جلو باشد و اجازه‌ها سر جایشان.
- (BOOL)writable {
    return [self targetIsFront] && [ZInjector accessibilityOK] && ![ZInjector secureInputActive];
}

- (BOOL)typing {
    return [ZSettings.shared insertModeForBundleId:_target.bundleIdentifier] == ZInsertType;
}

// دُم فقط جایی نوشته می‌شود که هم بی‌خطر باشد هم برگشت‌پذیر: مسیر پیست هیچ‌کدام نیست
// (هر رفت‌وبرگشتش کند و نامطمئن است و بازنویسی‌اش راهی ندارد).
- (BOOL)rendersPending { return _renderPending && [self typing]; }
- (BOOL)canRewrite { return [self typing] && [self writable]; }

- (void)appendText:(NSString *)text done:(void (^)(ZSinkResult))done {
    if (![self writable]) {
        done(ZSinkUnavailable);
        return;
    }
    if (![self typing]) {
        [_injector paste:text delayMicros:ZSettings.shared.pasteDelayMicros];
        done(ZSinkOK);    // پیست خبرِ نشستن ندارد؛ آنجا بازنویسی هم در کار نیست
        return;
    }
    // دُمِ زنده پیست نمی‌شود: هر تکه یک رفت‌وبرگشتِ کند به کلیپ‌بورد است و دفتر باید
    // بتواند بازنویسی‌اش کند. اینجا تکه‌ها کوچک‌اند و دفتر حسابشان را دارد.
    [_injector insert:text pid:_target.processIdentifier
          delayMicros:ZSettings.shared.typeDelayMicros
       pasteIfRefused:NO
                 done:^(BOOL viaAX) { done(ZSinkOK); }];
}

- (void)replaceLast:(NSUInteger)n expecting:(NSString *)expected with:(NSString *)text
               done:(void (^)(ZSinkResult))done {
    if (![self canRewrite]) {
        done(ZSinkUnavailable);
        return;
    }
    ZLedgerStats *stats = _stats;
    [_injector replaceLast:n expecting:expected with:text
               delayMicros:ZSettings.shared.typeDelayMicros
                       pid:_target.processIdentifier
                      done:^(ZWriteProof proof, BOOL viaAX) {
        stats.axReads = stats.axReads + 1;
        if (proof == ZProofRead) stats.verifiedByRead = stats.verifiedByRead + 1;
        if (proof == ZProofUntouched) stats.verifiedByEpoch = stats.verifiedByEpoch + 1;
        done(proof == ZProofNone ? ZSinkDisowned : ZSinkOK);
    }];
}

@end

// ---------- ZHotkeyTap ----------
// یک CGEventTap واحد برای کل اپ (نه یک تپ جدا به ازای هر سشن): از launch تا quit
// زنده می‌ماند. دابل‌تپ Command راست (شروع/پایان سشن) در هر حالتی کار می‌کند و با
// تنظیم «هاتکی داخلی» روشن/خاموش می‌شود. بقیه (Esc، تک‌تپ Command راست،
// Command راست+C) فقط وقتی sessionActive=YES باشد؛ بیرون از سشن دست‌نخورده رد می‌شوند.
// تشخیص تپِ راست-Command همان ترفند lazy کارابینر است: رویداد نگه‌داشته می‌شود و فقط
// اگر با کلید دیگری ترکیب شد دوباره تزریق می‌شود، وگرنه هیچ‌وقت به اپ دیگری نمی‌رسد.

static const uint64_t kRightCmdBit = 0x10;    // NX_DEVICERCMDKEYMASK
static const CGEventFlags kZModMask = kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate
                                     | kCGEventFlagMaskControl | kCGEventFlagMaskShift;
static const CFTimeInterval kZTapWindow = 0.35;   // پنجره دابل/تک‌تپ

// دو مدرکِ بی‌واسطه درباره‌ی Command راست، هر دو ارزان و هیچ‌کدام از حالتِ خودمان:
// یکی این‌که کلید *واقعا* پایین است (از HID، یعنی خودِ سخت‌افزار)، و دیگری این‌که
// *سیستم* پایین می‌داندش (حالتِ ترکیبی، که رویدادِ تزریق‌شده هم در آن حساب می‌شود).
// حالتِ نگه‌داشته‌ی ما می‌تواند کهنه شود؛ این دو هیچ‌وقت نمی‌شوند. همان قاعده‌ی دفتر:
// هیچ چیزی بی مدرک تزریق یا بلعیده نمی‌شود.
static BOOL zRightCmdHeldForReal(void) {
    return CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, (CGKeyCode)kVK_RightCommand);
}

static BOOL zSystemThinksRightCmdHeld(void) {
    return (CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & kRightCmdBit) != 0;
}

@interface ZHotkeyTap ()
- (CGEventRef)handleProxy:(CGEventTapProxy)proxy type:(CGEventType)type event:(CGEventRef)event;
@end

static CGEventRef zHotkeyCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    ZHotkeyTap *me = (__bridge ZHotkeyTap *)info;
    return [me handleProxy:proxy type:type event:event];
}

@implementation ZHotkeyTap {
    CFMachPortRef _tap;
    CFRunLoopSourceRef _source;
    BOOL _physDown;      // Command راست همین الان فیزیکی پایین است
    BOOL _emitted;       // این نگه‌داشتن قبلا برای یک ترکیب دوباره تزریق/مصرف شد
    BOOL _suppressUp;    // ترکیب میان‌بر خودمان بود؛ بالاآمدن راست-Command هم بلعیده شود
    CGEventRef _savedDown;
    CFAbsoluteTime _lastTapAt;
    NSInteger _tapGen;   // نسل تپِ تنها؛ رسیدن تپ دوم تایمر تک‌تپِ قبلی را لغو می‌کند
}

- (BOOL)enabled { return _tap != NULL; }

- (void)enable {
    if (_tap) return;
    // کلیکِ ماوس هم پاییده می‌شود، فقط برای مدرکِ «کسی دست نزده». کلیک کرسر را
    // جابه‌جا می‌کند و بی این، اپی که خواندنِ AX ندارد بعد از یک کلیک هنوز خودش را
    // مالکِ دُم می‌دانست.
    CGEventMask mask = CGEventMaskBit(kCGEventFlagsChanged) | CGEventMaskBit(kCGEventKeyDown)
                     | CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventRightMouseDown);
    _tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                            mask, zHotkeyCallback, (__bridge void *)self);
    if (!_tap) {
        ZLog(@"hotkey tap: create failed (accessibility?)");
        return;
    }
    _source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _tap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
    CGEventTapEnable(_tap, true);
    ZLog(@"hotkey tap: enabled");
}

- (void)disable {
    if (_source) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
        CFRelease(_source);
        _source = NULL;
    }
    if (_tap) {
        CGEventTapEnable(_tap, false);
        CFMachPortInvalidate(_tap);
        CFRelease(_tap);
        _tap = NULL;
    }
    [self forgetHeld];
}

// حالتِ «Command راست پایین است» را دور بریز، بی تزریق و بی بلعیدن. هرجا که مدرک
// می‌گوید این حالت کهنه است از همین‌جا رد می‌شود، یک نقطه و نه چند جای پراکنده.
- (void)forgetHeld {
    _physDown = NO;
    _emitted = NO;
    _suppressUp = NO;
    if (_savedDown) {
        CFRelease(_savedDown);
        _savedDown = NULL;
    }
}

// تپِ تنها راست-Command: یا نیمه‌ی دوم یک دابل‌تپ (فوری: toggle) یا اگر پنجره سپری
// شد و کسی نیامد، تک‌تپ (مکث/ادامه، فقط در حین سشن).
- (void)loneTapUp {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime last = _lastTapAt;
    _lastTapAt = now;
    _tapGen++;
    if (last > 0 && now - last < kZTapWindow) {
        _lastTapAt = 0;    // سه‌تایی پشت هم را دوتا-دوتا نخوان
        if (ZSettings.shared.internalHotkey) {
            void (^cb)(void) = self.onToggle;
            if (cb) dispatch_async(dispatch_get_main_queue(), cb);
        }
        return;
    }
    NSInteger gen = _tapGen;
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kZTapWindow * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(ws) me = ws;
        if (!me || me->_tapGen != gen || !me.sessionActive) return;    // تپ دومی رسید یا سشنی نیست
        void (^cb)(void) = me.onPauseToggle;
        if (cb) cb();
    });
}

- (CGEventRef)handleFlagsChanged:(CGEventRef)event {
    BOOL isDown = (CGEventGetFlags(event) & kRightCmdBit) != 0;
    if (isDown) {
        _physDown = YES;
        _emitted = NO;
        if (_savedDown) CFRelease(_savedDown);
        _savedDown = CGEventCreateCopy(event);
        return NULL;    // فعلا از همه پنهان؛ اگر ترکیب شد دوباره تزریق می‌شود
    }
    // بالاآمدنی که پایین‌رفتنش را ندیده‌ایم مالِ ما نیست: یعنی تپ وسطِ نگه‌داشتنِ کلید
    // بالا آمده، یا با تایم‌اوت خاموش بوده و رویدادها بی ما رد شده‌اند. بلعیدنش یعنی
    // سیستم هیچ‌وقت نمی‌فهمد مودیفایر رها شد، و از آن لحظه هر کلیدی در هر اپی با
    // Command راست خوانده می‌شود؛ داخل ریموت دسکتاپ آن هم کلیدِ ویندوز است، پس
    // میان‌برهای خودِ کاربر (Cmd+A و بقیه) یکجا از کار می‌افتند.
    if (!_physDown) return event;
    BOOL wasEmitted = _emitted;
    BOOL suppressUp = _suppressUp;
    [self forgetHeld];
    if (wasEmitted) return suppressUp ? NULL : event;
    [self loneTapUp];
    // تپِ تنها باید برای بقیه نامرئی باشد، پس بالاآمدنش هم بلعیده می‌شود. یک استثنا:
    // اگر سیستم همین حالا Command راست را پایین می‌داند، یعنی یک پایین‌رفتنِ تزریق‌شده
    // جایی رها نشده؛ بلعیدنِ این رویداد آن مودیفایر را برای همیشه گیر می‌اندازد.
    // آنجا رد می‌شود: یک ⌘ اضافه‌ی دیده‌نشده بهتر از کیبوردی است که تا ریبوت خراب است.
    return zSystemThinksRightCmdHeld() ? event : NULL;
}

// نقشه‌ی کلید به کار. یک ورودی دارد و بس: Command راست + حرف. هر دکمه‌ی پنل دقیقا
// یک حرف دارد و همان حرف تنها راهش است.
// F و H استثنا هستند و بیرون از سشن هم کار می‌کنند: پنل رونویسی فایل به سشن ربطی
// ندارد، و راهنما را کسی می‌خواهد که هنوز میان‌برها را نمی‌داند، یعنی هنوز سشنی هم
// ندارد. هزینه‌اش را می‌دانیم: Command راست + F و + H دیگر به اپ زیرین نمی‌رسند
// (Find و Hide با Command چپ سر جایشان هستند).
- (void (^)(void))actionForCode:(int64_t)code {
    if (code == 3) return self.onFilePanel;   // F، همیشه، حتی بی‌سشن
    if (code == 4) return self.onHelp;        // H، همیشه، حتی بی‌سشن
    if (!self.sessionActive) return nil;      // بقیه فقط در حین سشن
    switch (code) {
        case 49: return self.onPauseToggle;   // Space
        case 8:  return self.onCopyNow;       // C
        case 2:  return self.onTrash;         // D
        case 37: return self.onLangSwitch;    // L
        case 14: return self.onModeToggle;    // E
        case 35: return self.onPolishNow;     // P
        // N و R تازه‌اند و مثل بقیه فقط در حین سشن: N پایان و پاس نهایی، R چرخش بین
        // نسخه‌های متن. عمدا بیرون از سشن کار نمی‌کنند، چون Command راست + N و + R در
        // اپ‌های دیگر معنی دارند (پنجره‌ی نو، بازخوانی) و یک تپ سراسری هر ترکیبی را که
        // همیشه بگیرد، همیشه از همه می‌دزدد.
        case 45: return self.onFinalPass;     // N
        case 15: return self.onRotateText;    // R
        // B مثل «بهبود». بتاست، ولی کلیدش مثل بقیه فقط در حین سشن کار می‌کند: Command
        // راست + B در اپ‌های دیگر «بولد» است و یک تپ سراسری هر ترکیبی را که همیشه
        // بگیرد، همیشه از همه می‌دزدد.
        case 11: return self.onEnhance;       // B
        // I نه V: روی ⌥V سه چیز نشسته بود. مککی (تاریخچه‌ی کلیپ‌بورد مک) و، داخل
        // ریموت، رول کارابینر که ⌥V را به Win+V می‌برد (تاریخچه‌ی کلیپ‌بورد ویندوز).
        // آن دو یک معنی‌اند در دو دنیا و کلیدشان مال خودشان است؛ درجِ زمزمه راه‌های
        // دیگری هم دارد (دکمه‌ی پنل و Esc)، پس همین یکی کنار کشید. I هم مثل insert.
        // S مثل sensitivity و مثل «حساسیت». مثل بقیه فقط در حین سشن، چون بیرون از
        // سشن میکروفنی باز نیست که حساسیتش معنا داشته باشد.
        case 1:  return self.onSensToggle;    // S
        case 34: return self.onInsertHere;    // I
        default: return nil;
    }
}

- (CGEventRef)handleKeyDown:(CGEventRef)event proxy:(CGEventTapProxy)proxy {
    int64_t code = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

    // مدرک، پیش از اعتماد به حالتِ خودمان: «نگه‌داشته» می‌تواند کهنه باشد و کلید همین
    // حالا بالا باشد. بی این پرسش، رویدادِ کهنه‌ی پایین‌رفتن تزریق می‌شد و چون هیچ
    // بالاآمدنی پشتش نمی‌آمد، Command راست تا ابد پایین می‌ماند.
    if (_physDown && !zRightCmdHeldForReal()) {
        ZLog(@"hotkey tap: حالت کهنه دور ریخته شد (Command راست دیگر پایین نیست)");
        [self forgetHeld];
    }

    if (_physDown && !_emitted) {
        CGEventFlags mods = CGEventGetFlags(event) & kZModMask;
        // گارد سشن داخل خود نقشه است، چون یک کار (F) عمدا بی‌سشن هم کار می‌کند
        void (^cb)(void) = mods == kCGEventFlagMaskCommand ? [self actionForCode:code] : nil;
        if (cb) {
            // میان‌بر ماست؛ نه پایین‌رفتن نه بالاآمدنش به اپ زیرین نرسد
            _emitted = YES;
            _suppressUp = YES;
            dispatch_async(dispatch_get_main_queue(), cb);
            return NULL;
        }
        // کلید دیگری آمد: Command راست واقعا مودیفایر بود؛ اول رویداد نگه‌داشته را بفرست
        if (_savedDown) CGEventTapPostEvent(proxy, _savedDown);
        _emitted = YES;
        return event;
    }

    CGEventFlags flags = CGEventGetFlags(event) & kZModMask;
    // Esc: صاحبش خودش تصمیم می‌گیرد (کارت راهنما یا سشن) و می‌گوید مصرف شد یا نه.
    // هم‌زمان، چون همین‌جا باید بدانیم رویداد را برگردانیم یا ببلعیم؛ دیر بگوییم،
    // Esc هم به اپ زیرین رسیده و هم کار ما را کرده.
    if (code == 53 && flags == 0) {
        BOOL (^esc)(void) = self.onEscape;
        return (esc && esc()) ? NULL : event;
    }
    // ⌥ + حرف عمدا دیگر خوانده نمی‌شود. یک تپ سراسری هر ترکیبی را که بگیرد از همه‌ی
    // اپ‌های دیگر می‌دزدد، و ⌥ شلوغ‌ترین جای ممکن بود: ⌥V مال مککی است، ⌥P مال پین
    // کردن همان، و داخل ریموت ⌥V به Win+V می‌رود. مسیر دوم هیچ کار تازه‌ای هم نمی‌کرد،
    // فقط همان نقشه را از راه دیگری صدا می‌زد. حالا یک راه هست: Command راست + حرف.
    return event;
}

- (CGEventRef)handleProxy:(CGEventTapProxy)proxy type:(CGEventType)type event:(CGEventRef)event {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        // در فاصله‌ی خاموشی هر تعداد رویداد بی ما رد شده. هرچه نگه داشته‌ایم دیگر
        // مدرک نیست، حدس است، پس دور ریخته می‌شود. لاگ هم لازم است: خاموش شدن با
        // تایم‌اوت یعنی نخ اصلی سر وقت جواب نداده، و آن خودش یک باگ است نه یک اتفاق.
        ZLog(@"hotkey tap: %@، دوباره روشن شد",
             type == kCGEventTapDisabledByTimeout ? @"با تایم‌اوت خاموش شد (نخ اصلی دیر جواب داد)"
                                                 : @"با ورودی کاربر خاموش شد");
        [self forgetHeld];
        if (_tap) CGEventTapEnable(_tap, true);
        return event;
    }
    // هر ورودی‌ای که برچسبِ ما را ندارد یعنی کاربر (یا اپ دیگری) دست زده. تنها
    // مدرکی است که در اپِ بی‌خواندن (ریموت دسکتاپ) در دسترس است، پس اول از همه.
    if (CGEventGetIntegerValueField(event, kCGEventSourceUserData) != kZOurEventTag) {
        ZNoteForeignInput();
    }
    if (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown) return event;
    if (type == kCGEventFlagsChanged
        && CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) == 54) {
        return [self handleFlagsChanged:event];
    }
    if (type == kCGEventKeyDown) {
        return [self handleKeyDown:event proxy:proxy];
    }
    return event;
}

@end
