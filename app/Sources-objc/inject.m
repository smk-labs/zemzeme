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
        // مرزِ تکه هیچ‌وقت وسط یک جفتِ جانشین نیفتد: نیمه‌ی تنها یا دور ریخته می‌شود
        // یا به U+FFFD تبدیل، در حالی که دفتر هر دو واحد را «تحویل‌شده» می‌شمارد.
        if (n > 1 && units[i + n - 1] >= 0xD800 && units[i + n - 1] <= 0xDBFF) n--;
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
// مرزِ «بلندتر از یک رویداد» (kZEventUnits) و خودِ انتخابِ مسیر، در هدر نشسته‌اند:
// آنجا کنارِ قراردادشان‌اند و بی هیچ لینکی آزمودنی. متنِ کوتاه‌تر ذاتا نمی‌تواند نصفه
// بیفتد و مسیرِ تایپِ اندازه‌گیری‌شده دست‌نخورده می‌ماند.

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
        // کشِ عنصرِ فوکوس‌دار را همین‌جا باطل کن. کش فقط می‌پرسد «این عنصر هنوز
        // زنده است؟»، نه «هنوز همان فوکوس‌دار است؟»، پس عنصری که یک بار اشتباه
        // resolve شده باشد (درختِ AX سرد بوده) تا آخر سشن زنده و غلط می‌ماند و
        // متن جای عوضی می‌نشیند. درج یک بار در پایان اتفاق می‌افتد، پس یک پرس‌وجوی
        // اضافه هیچ هزینه‌ای ندارد و همان یک بار است که باید درست باشد.
        ZInvalidateFocusCache();
        // اپی که صریحا پیست می‌خواهد، **همیشه** پیست می‌گیرد؛ نه فقط وقتی متن بلند
        // باشد و نه فقط وقتی اکسسبیلیتی رد کند.
        //
        // این یک رگرسیون بود که برگشت و باید یک بار برای همیشه بسته شود. ریموت
        // دسکتاپ تنها مسیرِ درستش پیست است: کلاینت، کلیپ‌بوردِ مک را فقط سرِ عوض شدنِ
        // پنجره‌ی کلید به سمت ویندوز سینک می‌کند، و `pasteNow` دقیقا همان فلیک را
        // می‌زند. تایپِ رویدادی آنجا به یک تنظیم در خودِ آن اپ بند است و نامطمئن،
        // و نوشتنِ اکسسبیلیتی اصلا جواب نمی‌دهد.
        //
        // چرا برگشت: شرطِ `atomic` (متنِ کوتاه‌تر از ۱۸ واحد) پیش از این شرط می‌نشست،
        // و در نسخه دو که هر مکث یک تکه‌ی کوتاه درج می‌کند، تکه‌های کوتاه از کنارِ
        // پیست رد می‌شدند و تایپ می‌رفتند. نتیجه‌اش برای کاربر این بود که داخل ریموت
        // «پیستِ خودِ ویندوز» اجرا می‌شد، یعنی هرچه از قبل در کلیپ‌بوردِ ویندوز بود.
        // نوشتنِ AX را فقط یک بار به ازای هر اپ امتحان می‌کنیم؛ رد که کرد، دیگر نه.
        BOOL axAvailable = !pasteIfRefused && text.length >= kZEventUnits
                        && ![ZNoAXWritePids() containsObject:@(pid)];
        BOOL viaAX = NO;
        if (axAvailable) {
            viaAX = [self axInsert:text pid:pid];
            if (!viaAX) {
                ZLog(@"inject: ax write refused by pid=%d", pid);
                [ZNoAXWritePids() addObject:@(pid)];
            }
        }
        // و از اینجا به بعد تصمیم **یک جا** گرفته می‌شود، همان تابعِ خالصِ هدر. تا امروز
        // این تصمیم پخش بود و سه خط توضیحِ بالای سرش وعده‌ی پیست می‌داد در حالی که کد
        // تایپ می‌کرد. هزینه‌اش را کاربر داد: در یک درجِ واقعی دقیقا ۱۸ واحد UTF-16 از
        // وسط متن افتاد (`\n* **بولت سوم:** ا`) و یک بولتِ کامل غیب شد، در حالی که متنِ
        // مدل روی دیسک سالم بود؛ یک `*` و یک `س` هم جابه‌جا ته متن ظاهر شدند، یعنی
        // رویدادها هم افتادند هم بی‌ترتیب رسیدند.
        //
        // و کلیپ‌بورد چیزی نمی‌بازد، برخلاف آنچه اول گمان می‌رفت: هر مسیرِ تحویل پیش از
        // درج `copyFinal:` را صدا زده (session.m)، پس همین متن از قبل رویش هست.
        switch (ZChooseWritePath(pasteIfRefused, viaAX, text.length)) {
            case ZWriteAX:
                break;    // نشست، تمام
            case ZWritePaste:
                ZLog(@"inject: pasting %lu chars into pid=%d (%@)", (unsigned long)text.length, pid,
                     pasteIfRefused ? @"اپ پیست می‌خواهد" : @"نوشتنِ اتمیک رد شد؛ رگبار متن را می‌خورد");
                [self pasteNow:text delayMicros:ZSettings.shared.pasteDelayMicros];
                break;
            case ZWriteType:
                // کوتاه‌تر از یک رویداد: تایپ ذاتا امن است و کلیپ‌بورد دست‌نخورده می‌ماند.
                ZLog(@"inject: typing %lu chars into pid=%d", (unsigned long)text.length, pid);
                [self typeNow:text delayMicros:d leadIn:YES];
                break;
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
    if (after.location == before.location) {
        // **نوشتن موفق بود، پس متن نشسته.** این تنها جایی بود که با وجودِ
        // kAXErrorSuccess «نه» برمی‌گرداند، و نتیجه‌اش درجِ دوباره‌ی همان متن بود:
        // در لاگ کاربر `ax write refused` و بلافاصله `pasting 338 chars`، یعنی
        // ۳۳۸ نویسه دو بار روی صفحه. اپ‌های مبتنی بر Chromium نشانگر را از راه IPC
        // می‌دهند و خیلی‌هایشان همیشه {0,0} می‌گویند؛ آن سکوت دلیلِ ننشستن نیست.
        // یازده خط پایین‌تر همین فایل برای نشانگرِ غیرمنتظره دقیقا همین را می‌گوید
        // («نوشتنِ AX تجزیه‌ناپذیر است، دوباره نمی‌نویسیم») و آنجا درست بود.
        ZLog(@"inject: ax write ok but caret did not move on pid=%d, trusting the write", pid);
        [ZNoAXWritePids() addObject:@(pid)];
        return YES;
    }
    if (after.location != before.location + (CFIndex)text.length) {
        // نه سر جایش، نه آنجا که انتظار داشتیم. متن تقریبا حتما نشسته (نوشتنِ AX
        // تجزیه‌ناپذیر است)، پس دوباره نمی‌نویسیم؛ ولی این اپ دیگر قابل اعتماد نیست.
        ZLog(@"inject: ax write landed at an unexpected caret on pid=%d, distrusting it", pid);
        [ZNoAXWritePids() addObject:@(pid)];
    }
    return YES;
}

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

// «سیستم همین حالا Command راست را پایین می‌داند؟» تنها جایی به کار می‌آید که جوابِ
// آری معنی‌اش این است که یک پایین‌رفتنِ *تزریق‌شده* رها نشده، چون پایین‌رفتنِ عادی را
// خودمان بلعیده‌ایم و در این حالت اصلا نمی‌نشیند.
//
// جای دیگری از این خانواده نپرسیم: یک بار از HID پرسیده شد «کلید واقعا پایین است؟»
// و همیشه «نه» گفت، چون پایین‌رفتن را همین تپ بلعیده بود. یعنی آن سوال با این طراحی
// ذاتا جوابش نه بود، و نتیجه‌اش این شد که Command راست دیگر مالِ زمزمه نبود و مثل
// Command چپ رد می‌شد. مدرکی که خودت نگذاشته‌ای باشد، مدرک نیست.
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
// فراموش کردنِ نگه‌داشتن. رویدادِ بلعیده‌شده پس داده می‌شود، نه دور ریخته: کاربر
// Command راست را واقعا پایین آورده و اگر ما آن را نه پخش کنیم نه پس بدهیم، اپِ
// زیرین بعدا یک بالاآمدنِ بی‌صاحب می‌گیرد و مودیفایرش گیر می‌کند.
- (void)forgetHeld {
    _physDown = NO;
    _emitted = NO;
    _suppressUp = NO;
    if (_savedDown) {
        CGEventPost(kCGSessionEventTap, _savedDown);
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
    // همین‌جا خودش را درمان می‌کند، پس اگر یک روز مودیفایر گیر کرد، اولین تپِ تنها آزادش
    // می‌کند و این خط در لاگ می‌گوید که چنین چیزی افتاده بود.
    if (zSystemThinksRightCmdHeld()) {
        ZLog(@"hotkey tap: Command راستِ رهانشده آزاد شد");
        return event;
    }
    return NULL;
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
    if (code == 0) return self.onAIPass;      // A، همیشه: تاگل است نه کارِ سشن
    if (code == 11) return self.onSecondPass; // B، همیشه: تاگل است (bilingual)
    if (code == 35) return self.onPreview;    // P، همیشه: تاگل است (preview/پیش‌نمایش)
    if (!self.sessionActive) return nil;      // بقیه فقط در حین سشن
    switch (code) {
        case 49: return self.onPause;         // Space: مکث. تک‌تپ دیگر مکث نیست، پایان است
        case 8:  return self.onCopyNow;       // C
        case 2:  return self.onTrash;         // D
        case 37: return self.onLangSwitch;    // L
        case 14: return self.onModeToggle;    // E
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

    // **بیت واقعیِ Command راست، هر بار از نو.** تشخیصِ چپ از راست تماما روی
    // `_physDown` بود، و آن فقط وقتی پاک می‌شد که بالاآمدنِ کلید را ببینیم. یک
    // بالاآمدنِ گم‌شده (خواب صفحه، عوض شدن Space، تپِ دیگری جلوتر از ما مثل
    // Karabiner) یعنی `_physDown` برای همیشه روشن می‌ماند. از آن لحظه هر
    // ⌘+حرفِ عادیِ کاربر با **Command چپ** میان‌بر ما حساب می‌شد و بلعیده:
    // ⌘L زبان دیکته را عوض می‌کرد، ⌘E حالت را، ⌘D کل متن را دور می‌ریخت، و اپِ
    // مقصد هیچ‌کدام را نمی‌دید. حالا خودِ رویداد پرسیده می‌شود، پس حالتِ کهنه در
    // همان اولین کلید خودش را درمان می‌کند.
    if (_physDown && !(CGEventGetFlags(event) & kRightCmdBit)) [self forgetHeld];
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
    } else {
        // رویدادِ خودمان است (تایپ، یا Cmd+V). تا امروز مثل ورودی کاربر از همین
        // ماشین حالت رد می‌شد: تایپِ خود اپ به شاخه‌ی «کلید دیگری آمد» می‌افتاد،
        // رویدادِ نگه‌داشته‌ی Command راست را دوباره تزریق می‌کرد و تپِ در جریانِ
        // کاربر را می‌خورد. صدای خودمان را ورودی حساب نکنیم.
        return event;
    }
    // ماوس هم «کلید دیگری» است: با Command راست + کلیک، رها کردنِ کلید تپِ تنها
    // حساب می‌شد و ۰.۳۵ ثانیه بعد سشن بی‌دلیل مکث می‌کرد.
    if (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown) {
        if (_physDown) _emitted = YES;
        return event;
    }
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
