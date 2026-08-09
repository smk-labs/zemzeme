// نشانگر کنار کرسر: حالت «کرسر»، همان کاری که دیکته‌ی خود مک می‌کند. نه پنلی،
// نه نواری؛ فقط همان نشانِ کوچکِ وضعیت، زیر کرسرِ اپی که فوکس دارد. کرسر پیدا نشود،
// مثل نشانِ Grammarly گوشه‌ی باکس تایپ می‌ایستد. متن از همان مسیر درجِ زنده سر
// کرسر می‌نشیند.
#import "zemzeme.h"
#import <stdatomic.h>
#import <os/lock.h>
#import <ApplicationServices/ApplicationServices.h>

static const CGFloat kDotSize = 14;   // بلندی نشان؛ عرضش از ZMarkAspect درمی‌آید
// پنجره از خود نشان بزرگ‌تر است: نشان با بلندی صدا تا ۱٫۵ برابر باد می‌کند و
// بیرون از پنجره بریده می‌شد. نشان پهن‌تر از بلند است، پس پنجره دو ثابت جدا دارد
// و وسط‌چین کردن روی عرض انجام می‌شود، نه با یک ثابت مربع.
static const CGFloat kWinH = 22;
static const CGFloat kWinW = 24;
static const CGFloat kPadY = (kWinH - kDotSize) / 2;
static const CGFloat kGapY = 4;         // فاصله‌ی عمودی نقطه از خط متن
static const CGFloat kWinInset = 12;    // فروکاست پنجره: چقدر تو رفته از گوشه‌ی بالا-چپ
static const CGFloat kParkInset = 24;   // فروکاست آخر: فاصله از گوشه‌ی صفحه
static const CGFloat kBadgeInset = 6;   // فرورفتگی نشان از لبه‌های باکس تایپ، پله‌ی فیلد
static const CGFloat kBadgeRoom = 40;   // باکس کوتاه‌تر از این یعنی تک‌خطی: نشان بیرون بنشیند
static const NSTimeInterval kPoll = 1.0 / 6.0;   // ۶ هرتز: چشم روان می‌بیند، AX هم له نمی‌شود
static const CGFloat kMoveEps = 2.0;    // جابه‌جایی کمتر از این نادیده، وگرنه نقطه می‌لرزد
static const float kAXTimeout = 0.15f;

// ---------- پیدا کردن کرسر با اکسسبیلیتی ----------
// شکست اینجا استثنا نیست، قاعده است: اپ‌های Electron و وب‌ویو معمولا رنج متن را
// نمی‌دهند و ریموت دسکتاپ هیچ‌چیز نمی‌دهد. پس نردبان داریم و هر پله فقط یعنی
// «پله‌ی بعد»؛ هیچ فراخوانی نه می‌اندازد نه معطل می‌کند.
//
// چرا دیکته‌ی خود مک همیشه دقیق است و ما باید نردبان بسازیم: آن از اکسسبیلیتی
// استفاده نمی‌کند، داخل خودِ پشته‌ی ورودی متن (TSM/IMKit) نشسته و هر اپی که ورودی
// فارسی و ژاپنی را پشتیبانی می‌کند، از راه NSTextInputClient قاب دقیق کرسر را به
// سیستم می‌دهد؛ همان کانالی که پنجره‌ی کاندیدای IME را جا می‌اندازد. یک پروسه‌ی
// بیرونی نمی‌تواند NSTextInputClient اپ دیگر را صدا بزند، پس نزدیک‌ترین معادلِ
// از بیرون در دسترس را می‌سازیم و اپ به اپ اندازه می‌گیریم.
typedef NS_ENUM(NSInteger, ZCaretSource) {
    ZCaretNone = 0,     // هیچ: نقطه گوشه‌ی صفحه پارک می‌شود
    ZCaretWindow,       // فقط پنجره‌ی فوکس‌دار: پایین-چپِ داخل همان پنجره
    ZCaretField,        // قاب خود المنت فوکس‌دار (باکس تایپ)، بی‌مختصات کرسر داخلش
    ZCaretExact,        // خود نقطه‌ی درج
};

// مستطیل خام اکسسبیلیتی (مبدأ بالا-چپ)؛ برگرداندنش به مختصات AppKit روی نخ اصلی
// انجام می‌شود، چون NSScreen را نباید از نخ پس‌زمینه خواند. محور x برنمی‌گردد، پس
// `x` در همان مختصات AppKit هم معتبر است.
typedef struct {
    ZCaretSource src;
    CGRect rect;        // خطِ متن (پله‌ی دقیق) یا قاب باکس تایپ (پله‌ی فیلد)
    CGFloat x;          // خودِ ایکسِ کرسر؛ NAN یعنی «نمی‌دانم»، وسطِ rect
    int rtl;            // جهتِ خودِ متنِ همان فیلد: -۱ نمی‌دانم، ۰ چپ‌به‌راست، ۱ راست‌به‌چپ
    const char *how;    // کدام پله زد؛ فقط برای لاگ و probe، رشته‌ی ثابت
} ZCaretHit;

// کرسر باریک است. قابِ پهن‌تر از این یک خط یا یک انتخاب است، نه نقطه‌ی درج.
static const CGFloat kCaretWide = 8;

// probe روشن یعنی همین نردبان با صدای بلند اجرا می‌شود. یک پیاده‌سازی، دو مصرف:
// اگر ابزار اندازه‌گیری نردبان دومی می‌داشت، اندازه‌هایش هیچ‌چیز را ثابت نمی‌کرد.
static BOOL gProbe;

// خروجی هم روی stdout می‌رود هم ته یک فایل، چون اجازه‌ی اکسسبیلیتی به دو شکل به این
// باینری می‌رسد و فقط یکی‌شان ترمینال دارد: TCC درخواست را به پروسه‌ی «مسئول» نسبت
// می‌دهد، پس باینریِ اجراشده از ترمینال تا وقتی خودِ ترمینال اجازه نداشته باشد
// untrusted است، ولی همان باینری با `open -n` اجازه‌ی خودِ اپ را دارد و آنجا stdout
// جایی نمی‌رود. یک نوشتن بیشتر، در برابر یک ابزار که همیشه کار می‌کند.
static void ZProbeSay(NSString *s) {
    printf("%s\n", s.UTF8String);
    fflush(stdout);
    NSString *path = [ZSupport() URLByAppendingPathComponent:@"caretprobe.log"].path;
    NSData *d = [[s stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!h) {
        [NSFileManager.defaultManager createFileAtPath:path contents:d attributes:nil];
        return;
    }
    @try {
        [h seekToEndOfFile];
        [h writeData:d];
    } @catch (NSException *e) {}
    [h closeFile];
}

static void ZProbe(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void ZProbe(NSString *fmt, ...) {
    if (!gProbe) return;
    va_list ap;
    va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    ZProbeSay(s);
}

static AXUIElementRef ZSystemElement(void) {
    static AXUIElementRef sys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sys = AXUIElementCreateSystemWide();
        // مهلت روی عنصر system-wide یعنی مهلت پیش‌فرض همه‌ی عنصرهای این پروسه:
        // اپی که جواب نمی‌دهد (ریموت دسکتاپ، اپ گیرکرده) نباید صف ما را نگه دارد.
        if (sys) AXUIElementSetMessagingTimeout(sys, kAXTimeout);
    });
    return sys;
}

static CFTypeRef ZCopyAttr(AXUIElementRef el, CFStringRef attr) {
    if (!el) return NULL;
    CFTypeRef v = NULL;
    if (AXUIElementCopyAttributeValue(el, attr, &v) != kAXErrorSuccess) return NULL;
    return v;
}

// نوعِ برگشتی هم چک می‌شود، نه فقط موفق بودن فراخوان: اپ بدرفتار می‌تواند به جای
// عنصر هر چیزی بدهد و کست کور یعنی کرش.
static AXUIElementRef ZCopyElement(AXUIElementRef el, CFStringRef attr) {
    CFTypeRef v = ZCopyAttr(el, attr);
    if (!v) return NULL;
    if (CFGetTypeID(v) != AXUIElementGetTypeID()) {
        CFRelease(v);
        return NULL;
    }
    return (AXUIElementRef)v;
}

// به درد می‌خورد؟ خیلی از اپ‌ها به جای شکست، صفر یا عدد بی‌معنی برمی‌گردانند.
static BOOL ZRectUsable(CGRect r) {
    if (!isfinite(r.origin.x) || !isfinite(r.origin.y)
        || !isfinite(r.size.width) || !isfinite(r.size.height)) return NO;
    if (r.size.height < 1 || r.size.height > 400) return NO;   // یک خط متن است، نه کل صفحه
    // (۰,۰) همان «نمی‌دانم»ِ رایج است. کرسر واقعی آنجا نمی‌نشیند: در مختصات
    // اکسسبیلیتی آن گوشه زیر نوار منو است.
    if (r.origin.x == 0 && r.origin.y == 0) return NO;
    return YES;
}

// صفت پارامتری، با همان وسواسِ نوع. پارامترِ نال یعنی پرسش بی‌معنی، پس زود برگرد.
static CFTypeRef ZCopyParam(AXUIElementRef el, CFStringRef attr, CFTypeRef param) {
    if (!el || !param) return NULL;
    CFTypeRef v = NULL;
    AXError err = AXUIElementCopyParameterizedAttributeValue(el, attr, param, &v);
    if (err != kAXErrorSuccess || !v) {
        ZProbe(@"    %@ -> err %d", attr, err);
        if (v) CFRelease(v);
        return NULL;
    }
    return v;
}

static BOOL ZRectFromValue(CFTypeRef v, CGRect *out) {
    if (!v || CFGetTypeID(v) != AXValueGetTypeID()) return NO;
    CGRect r = CGRectZero;
    if (!AXValueGetValue((AXValueRef)v, kAXValueCGRectType, &r)) return NO;
    if (!ZRectUsable(r)) {
        ZProbe(@"    rect %.0f,%.0f %.0fx%.0f -> unusable", r.origin.x, r.origin.y,
               r.size.width, r.size.height);
        return NO;
    }
    *out = r;
    return YES;
}

static BOOL ZBoundsForRange(AXUIElementRef el, CFRange range, CGRect *out) {
    AXValueRef rv = AXValueCreate(kAXValueCFRangeType, &range);
    if (!rv) return NO;
    CFTypeRef bounds = ZCopyParam(el, kAXBoundsForRangeParameterizedAttribute, rv);
    CFRelease(rv);
    if (!bounds) return NO;
    BOOL ok = ZRectFromValue(bounds, out);
    CFRelease(bounds);
    if (ok) ZProbe(@"    bounds{%ld,%ld} -> %.0f,%.0f %.0fx%.0f", (long)range.location,
                   (long)range.length, out->origin.x, out->origin.y, out->size.width,
                   out->size.height);
    return ok;
}

// ---------- TextMarker: همان چیزی که VoiceOver روی وب می‌خواند ----------
// Chromium و WebKit درخت متنشان را با اندیس نمی‌دهند (رنجِ طول‌صفر آنجا پیاده نشده)،
// ولی «تِکست مارکر» را کامل می‌دهند، چون هر اسکرین‌ریدری روی همین بند است. مارکر
// یک CFType مبهم است و اسم صفت‌ها رسمی نیست؛ رشته‌ای صداشان می‌زنیم. سود جانبی:
// قابی که برمی‌گرداند از خود موتور چیدمان می‌آید، پس راست‌به‌چپ هم درست است.
static BOOL ZBoundsForMarkers(AXUIElementRef el, CFTypeRef range, CGRect *out) {
    CFTypeRef bounds = ZCopyParam(el, CFSTR("AXBoundsForTextMarkerRange"), range);
    if (!bounds) return NO;
    BOOL ok = ZRectFromValue(bounds, out);
    CFRelease(bounds);
    return ok;
}

static BOOL ZCaretFromMarkers(AXUIElementRef el, CGRect *out) {
    CFTypeRef sel = ZCopyAttr(el, CFSTR("AXSelectedTextMarkerRange"));
    if (!sel) {
        ZProbe(@"    AXSelectedTextMarkerRange -> none");
        return NO;
    }
    // رنج را روی نقطه‌ی شروعش جمع می‌کنیم: با متنِ انتخاب‌شده، قابِ کلِ انتخاب
    // برمی‌گردد و نشان می‌پرد وسط صفحه. همان کاری که VoiceOver برای «کرسر» می‌کند.
    CFTypeRef start = ZCopyParam(el, CFSTR("AXStartTextMarkerForTextMarkerRange"), sel);
    CFTypeRef collapsed = NULL;
    if (start) {
        const void *pair[2] = {start, start};
        CFArrayRef arr = CFArrayCreate(NULL, pair, 2, &kCFTypeArrayCallBacks);
        if (arr) {
            collapsed = ZCopyParam(el, CFSTR("AXTextMarkerRangeForUnorderedTextMarkers"), arr);
            CFRelease(arr);
        }
        CFRelease(start);
    }
    // اول رنجِ جمع‌شده، بعد خودِ رنجِ انتخاب: وقتی چیزی انتخاب نشده این دو یکی‌اند و
    // دومی هم همان کرسر است، پس اپی که مارکرِ جمع‌شده نمی‌سازد هم از دست نمی‌رود.
    BOOL ok = collapsed && ZBoundsForMarkers(el, collapsed, out);
    if (ok) ZProbe(@"    marker collapsed -> %.0f,%.0f %.0fx%.0f", out->origin.x,
                   out->origin.y, out->size.width, out->size.height);
    if (!ok && (ok = ZBoundsForMarkers(el, sel, out))) {
        ZProbe(@"    marker selection -> %.0f,%.0f %.0fx%.0f", out->origin.x, out->origin.y,
               out->size.width, out->size.height);
    }
    if (collapsed) CFRelease(collapsed);
    CFRelease(sel);
    return ok;
}

// قاب خام هر عنصر، بی‌قضاوت درباره‌ی این‌که فیلد است یا نه. هم برای پله‌ی فیلد لازم
// است هم برای عقل‌سنجیِ قابِ کرسر.
static BOOL ZElementFrame(AXUIElementRef el, CGRect *out) {
    CFTypeRef pos = ZCopyAttr(el, kAXPositionAttribute);
    CFTypeRef size = ZCopyAttr(el, kAXSizeAttribute);
    CGPoint p = CGPointZero;
    CGSize s = CGSizeZero;
    BOOL ok = pos && size
        && CFGetTypeID(pos) == AXValueGetTypeID() && CFGetTypeID(size) == AXValueGetTypeID()
        && AXValueGetValue((AXValueRef)pos, kAXValueCGPointType, &p)
        && AXValueGetValue((AXValueRef)size, kAXValueCGSizeType, &s)
        && isfinite(p.x) && isfinite(p.y) && s.width > 0 && s.height > 0
        && !(p.x == 0 && p.y == 0);
    if (pos) CFRelease(pos);
    if (size) CFRelease(size);
    if (ok) *out = CGRectMake(p.x, p.y, s.width, s.height);
    return ok;
}

// شبیه فیلد ورودی است یا سندِ تمام‌قد؟ سقف بلندی همان منطق ZRectUsable: یک باکس
// تایپ است، نه کل صفحه. اپ‌های Electron مثل دسکتاپ Claude رنج متن نمی‌دهند ولی
// بعد از بیدارباش همین قاب را می‌دهند.
static BOOL ZLooksLikeField(CGRect f) {
    return f.size.width >= 40 && f.size.height >= 12 && f.size.height <= 400;
}

// قاب یک پنجره، اگر همان‌طور که باید موقعیت و اندازه بدهد
static BOOL ZWindowFrame(AXUIElementRef win, CGRect *out) {
    if (!win) return NO;
    CFTypeRef pos = ZCopyAttr(win, kAXPositionAttribute);
    CFTypeRef size = ZCopyAttr(win, kAXSizeAttribute);
    CGPoint p = CGPointZero;
    CGSize s = CGSizeZero;
    BOOL ok = pos && size
        && CFGetTypeID(pos) == AXValueGetTypeID() && CFGetTypeID(size) == AXValueGetTypeID()
        && AXValueGetValue((AXValueRef)pos, kAXValueCGPointType, &p)
        && AXValueGetValue((AXValueRef)size, kAXValueCGSizeType, &s)
        && isfinite(p.x) && isfinite(p.y) && s.width > 40 && s.height > 40;
    if (pos) CFRelease(pos);
    if (size) CFRelease(size);
    if (ok) *out = CGRectMake(p.x, p.y, s.width, s.height);
    return ok;
}

// اپ‌های Chromium (و هر Electron) درخت اکسسبیلیتی را تنبل می‌سازند: تا وقتی یک ابزار
// کمکی سراغشان نرود، نه عنصر فوکس‌دار می‌دهند نه رنج متن، و نقطه محکوم است به گوشه‌ی
// پنجره. دو کلید برای بیدار کردنشان هست و هر دو یک بار به ازای هر pid زده می‌شوند:
// `AXManualAccessibility` که Electron خودش مستندش کرده ولی روی خیلی از نسخه‌ها
// advertise نشده و kAXErrorAttributeUnsupported (-25205) می‌دهد
// (electron/electron#37465)، و `AXEnhancedUserInterface` که همان چیزی است که
// VoiceOver می‌گذارد و Chromium را وادار به ساختن کل درخت می‌کند.
// چون این دومی روی اپ اثر می‌گذارد و تا ری‌استارت اپ می‌ماند، سر بستن سشن پس گرفته
// می‌شود: بیدار نگه داشتن اپ‌های کاربر بعد از پایان دیکته کار ما نیست.
static NSMutableSet<NSNumber *> *ZPokedPids(void) {
    static NSMutableSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSMutableSet set]; });
    return s;
}

// کامنت قبلی می‌گفت «فقط روی صف caret دست می‌خورد، پس قفل لازم ندارد». غلط بود:
// مسیر inject هم از راه ZResolveFocused به همین‌جا می‌رسد و آن صف دیگری است. نتیجه‌اش
// می‌توانست «collection was mutated while being enumerated» وسط بستن سشن باشد.
static os_unfair_lock gPokeLock = OS_UNFAIR_LOCK_INIT;

static void ZWakeAccessibility(AXUIElementRef app, pid_t pid) {
    os_unfair_lock_lock(&gPokeLock);
    BOOL already = [ZPokedPids() containsObject:@(pid)];
    os_unfair_lock_unlock(&gPokeLock);
    if (already) return;
    AXError m = AXUIElementSetAttributeValue(app, CFSTR("AXManualAccessibility"), kCFBooleanTrue);
    AXError e = AXUIElementSetAttributeValue(app, CFSTR("AXEnhancedUserInterface"), kCFBooleanTrue);
    // **فقط موفقیت ثبت می‌شود.** قبلا pid پیش از هر دو نوشتن اضافه می‌شد، پس اپی که
    // همان لحظه مشغول بالا آمدن بود و تایم‌اوت می‌داد، تا آخر سشن دیگر بیدار نمی‌شد
    // و کرسرش هیچ‌وقت پیدا نمی‌شد. حالا شکستِ گذرا دفعه‌ی بعد دوباره امتحان می‌شود.
    if (m != kAXErrorSuccess && e != kAXErrorSuccess) {
        ZLog(@"caret: بیدارباش pid=%d نگرفت (manual=%d enhanced=%d)؛ دوباره امتحان می‌شود", pid, m, e);
        return;
    }
    os_unfair_lock_lock(&gPokeLock);
    [ZPokedPids() addObject:@(pid)];
    os_unfair_lock_unlock(&gPokeLock);
    ZLog(@"caret: woke ax for pid=%d manual=%d enhanced=%d", pid, m, e);
}

static void ZCaretSleepAll(void) {
    os_unfair_lock_lock(&gPokeLock);
    NSArray *pids = ZPokedPids().allObjects;    // عکس، نه خودِ مجموعه
    [ZPokedPids() removeAllObjects];
    os_unfair_lock_unlock(&gPokeLock);
    for (NSNumber *pid in pids) {
        AXUIElementRef app = AXUIElementCreateApplication(pid.intValue);
        if (!app) continue;
        AXUIElementSetMessagingTimeout(app, kAXTimeout);
        AXUIElementSetAttributeValue(app, CFSTR("AXEnhancedUserInterface"), kCFBooleanFalse);
        AXUIElementSetAttributeValue(app, CFSTR("AXManualAccessibility"), kCFBooleanFalse);
        CFRelease(app);
    }
}

// جهتِ متنِ خودِ فیلد، از روی محتوایش نه از روی زبانِ سشن. هر جا اپ خودش راست‌به‌چپ را
// درست هندل می‌کند، ما هم باید همان سمت را بگیریم؛ حدس زدن از روی زبانِ دیکته یعنی
// نشان می‌افتد آن‌سوی متن، همان‌جا که کاربر گفت اشتباه است. اولین حرفِ جهت‌دار تصمیم
// می‌گیرد، همان قاعده‌ی یونیکد. فقط ۴۰ نویسه‌ی اول خوانده می‌شود: AXValue روی یک سند
// بزرگ می‌تواند مگابایت باشد و این مسیر ۶ بار در ثانیه اجرا می‌شود.
static int ZTextDirection(AXUIElementRef el) {
    // طولِ متن اول پرسیده می‌شود، چون رنجِ بیرون از متن را خیلی از ویوهای AppKit رد
    // می‌کنند و آن‌وقت درست در حالتِ رایج (فیلدِ کوتاه) جهت را از دست می‌دادیم.
    CFTypeRef n = ZCopyAttr(el, kAXNumberOfCharactersAttribute);
    CFIndex len = 0;
    if (n) {
        int count = 0;
        if (CFGetTypeID(n) == CFNumberGetTypeID()
            && CFNumberGetValue((CFNumberRef)n, kCFNumberIntType, &count)) len = MIN(count, 40);
        CFRelease(n);
    }
    if (len <= 0) return -1;
    CFRange head = {0, len};
    AXValueRef rv = AXValueCreate(kAXValueCFRangeType, &head);
    if (!rv) return -1;
    CFTypeRef s = ZCopyParam(el, kAXStringForRangeParameterizedAttribute, rv);
    CFRelease(rv);
    if (!s) return -1;
    NSString *text = CFGetTypeID(s) == CFStringGetTypeID() ? (__bridge NSString *)s : nil;
    int dir = -1;
    for (NSUInteger i = 0; i < text.length && dir < 0; i++) {
        unichar c = [text characterAtIndex:i];
        if ((c >= 0x0590 && c <= 0x08FF) || (c >= 0xFB1D && c <= 0xFDFF)
            || (c >= 0xFE70 && c <= 0xFEFF)) dir = 1;                 // عربی، عبری، فارسی
        else if ([NSCharacterSet.letterCharacterSet characterIsMember:c]) dir = 0;
    }
    CFRelease(s);
    ZProbe(@"    direction from text -> %d", dir);
    return dir;
}

// ---------- پله‌های «خودِ نقطه‌ی درج» ----------
// همه روی عنصر فوکس‌دار کار می‌کنند و به ترتیبِ دقت مرتب‌اند. هیچ‌کدام معطل نمی‌کند:
// صفتی که اپ پیاده نکرده باشد همان لحظه با kAXErrorAttributeUnsupported برمی‌گردد،
// نه بعد از مهلت ۱۵۰ میلی‌ثانیه؛ مهلت فقط برای اپِ گیرکرده است. پس نردبانِ بلند
// برای اپ سالم چند رفت‌وبرگشتِ ارزان است، نه یک تیکِ ازدست‌رفته.

// اندیس‌ها: رنج با طول صفر پرسیده می‌شود، چون وقتی متنی انتخاب شده باشد مستطیلِ
// کلِ انتخاب برمی‌گردد و نشان می‌پرد وسط صفحه.
static BOOL ZCaretFromIndex(AXUIElementRef el, CFRange sel, ZCaretHit *hit) {
    CGRect box = CGRectZero;
    if (ZBoundsForRange(el, CFRangeMake(sel.location, 0), &box)) {
        hit->rect = box;
        hit->x = NAN;               // رنجِ طول‌صفر عرض ندارد، وسطش خودِ کرسر است
        hit->how = "index";
        return YES;
    }
    // نویسه‌ی همسایه: اپی که رنجِ طول‌صفر را پیاده نکرده، رنجِ طول‌یک را می‌دهد. قابِ
    // نویسه‌ی بعد و قبل، کرسر را بین خودشان می‌گیرند؛ همان‌جا که دو قاب به هم
    // می‌رسند خودِ کرسر است و جهت متن هم از همین مقایسه درمی‌آید، بی‌آنکه بپرسیم.
    CGRect next = CGRectZero, prev = CGRectZero;
    BOOL haveNext = ZBoundsForRange(el, CFRangeMake(sel.location, 1), &next);
    BOOL havePrev = sel.location > 0
        && ZBoundsForRange(el, CFRangeMake(sel.location - 1, 1), &prev);
    if (haveNext && havePrev && fabs(CGRectGetMidY(next) - CGRectGetMidY(prev)) < 2) {
        hit->rect = next;
        hit->x = CGRectGetMinX(next) >= CGRectGetMaxX(prev) - 1
            ? (CGRectGetMinX(next) + CGRectGetMaxX(prev)) / 2      // چپ‌به‌راست
            : (CGRectGetMaxX(next) + CGRectGetMinX(prev)) / 2;     // راست‌به‌چپ
        hit->how = "char pair";
        return YES;
    }
    // فقط یکی از دو همسایه. وسطِ آن نویسه نشستن یعنی نیم‌نویسه خطا، و در متن فارسی
    // این نیم‌نویسه می‌افتد آن‌سوی کرسر: کرسر لبه‌ی «آغازِ» نویسه‌ی بعدی است و لبه‌ی
    // «پایانِ» نویسه‌ی قبلی، و کدام لبه، به جهت متن بستگی دارد. جهت را از خود متن
    // می‌پرسیم، نه از زبان سشن.
    if (haveNext || havePrev) {
        hit->rect = haveNext ? next : prev;
        hit->rtl = ZTextDirection(el);
        hit->x = NAN;
        if (hit->rtl == 1) hit->x = haveNext ? CGRectGetMaxX(next) : CGRectGetMinX(prev);
        if (hit->rtl == 0) hit->x = haveNext ? CGRectGetMinX(next) : CGRectGetMaxX(prev);
        hit->how = haveNext ? "char next" : "char prev";
        return YES;
    }
    return NO;
}

// خطِ کرسر: بعضی ویوهای AppKit رنجِ طول‌صفر را رد می‌کنند ولی شماره‌ی خط و رنجِ خط
// را می‌دهند. قابِ «متنِ قبل از کرسر روی همین خط» لبه‌اش دقیقا خودِ کرسر است، و
// این‌که کدام لبه، از مقایسه با قابِ کلِ خط درمی‌آید نه از حدس زبان.
static BOOL ZCaretFromLine(AXUIElementRef el, CFRange sel, ZCaretHit *hit) {
    CFTypeRef lineNo = ZCopyAttr(el, kAXInsertionPointLineNumberAttribute);
    if (!lineNo) return NO;
    CFTypeRef lineRangeV = ZCopyParam(el, kAXRangeForLineParameterizedAttribute, lineNo);
    CFRelease(lineNo);
    if (!lineRangeV) return NO;
    CFRange line = {0, 0};
    BOOL got = CFGetTypeID(lineRangeV) == AXValueGetTypeID()
        && AXValueGetValue((AXValueRef)lineRangeV, kAXValueCFRangeType, &line);
    CFRelease(lineRangeV);
    CGRect lineBox = CGRectZero;
    if (!got || !ZBoundsForRange(el, line, &lineBox)) return NO;
    hit->rect = lineBox;
    hit->x = NAN;
    hit->how = "line";
    CGRect head = CGRectZero;
    if (sel.location > (CFIndex)line.location
        && ZBoundsForRange(el, CFRangeMake(line.location, sel.location - line.location), &head)) {
        hit->x = CGRectGetMinX(head) <= CGRectGetMinX(lineBox) + 2
            ? CGRectGetMaxX(head)      // متن از چپ شروع شده، پس کرسر لبه‌ی راستِ آن است
            : CGRectGetMinX(head);     // از راست شروع شده: فارسی
        hit->how = "line head";
    }
    return YES;
}

// قابی که برگشته اصلا داخل همان عنصر است؟ اپ بدرفتار یا مختصاتِ با قرارداد دیگر،
// عددِ به‌ظاهر سالم می‌دهد که جای دیگری از صفحه است؛ آن‌وقت نشان می‌رود جایی که هیچ
// ربطی به تایپ ندارد. پله‌ی بعد از این بهتر است، نه بدتر.
static BOOL ZInsideElement(CGRect caret, CGRect frame) {
    CGPoint c = CGPointMake(CGRectGetMidX(caret), CGRectGetMidY(caret));
    return CGRectContainsPoint(CGRectInset(frame, -16, -16), c);
}

static NSString *ZStringAttr(AXUIElementRef el, CFStringRef attr) {
    CFTypeRef v = ZCopyAttr(el, attr);
    if (!v) return nil;
    NSString *s = CFGetTypeID(v) == CFStringGetTypeID() ? [(__bridge NSString *)v copy] : nil;
    CFRelease(v);
    return s;
}

// «کدام پله، روی چه عنصری، در کدام اپ». بی این، هر گزارشِ «نشان جای بدی می‌نشیند»
// حدس می‌ماند. یک بار به ازای هر تغییرِ وضعیت لاگ می‌شود نه ۶ بار در ثانیه: لاگی که
// پر شود کسی نمی‌خواندش. صفت‌های اضافه فقط همان لحظه‌ی لاگ خوانده می‌شوند.
static void ZCaretNote(AXUIElementRef el, pid_t pid, ZCaretHit hit) {
    static NSString *last;
    NSString *sig = [NSString stringWithFormat:@"%d|%ld|%s", pid, (long)hit.src, hit.how];
    if (!gProbe && [sig isEqualToString:last]) return;
    last = sig;
    NSString *bundle = [NSRunningApplication runningApplicationWithProcessIdentifier:pid]
        .bundleIdentifier;
    ZLog(@"caret: %@ pid=%d step=%s role=%@/%@ rect=%.0f,%.0f %.0fx%.0f x=%.0f rtl=%d",
         bundle ?: @"?", pid, hit.how,
         ZStringAttr(el, kAXRoleAttribute) ?: @"?",
         ZStringAttr(el, kAXSubroleAttribute) ?: @"-",
         hit.rect.origin.x, hit.rect.origin.y, hit.rect.size.width, hit.rect.size.height,
         hit.x, hit.rtl);
}

// عنصر فوکس‌دارِ اپِ جلویی. دو مصرف دارد و عمدا یک پیاده‌سازی: نشانگر کنار کرسر
// (۶ بار در ثانیه) و تاییدِ درج پیش از هر پاک کردن. نردبانِ دومی یعنی دو رفتار واگرا.
//
// کش، چون مسیر تایید روی صف درج می‌دود و نباید هر بار کل درخت را بالا بیاورد.
// باطل می‌شود با: عوض شدن اپ جلویی، خبرِ NSWorkspace، و یک انقضای کوتاه (فوکس داخل
// همان اپ هم عوض می‌شود و خبری نمی‌دهد). عنصرِ کهنه خطرناک نیست: متنِ خوانده‌شده با
// آنچه انتظار داریم نمی‌خواند و تایید رد می‌شود، یعنی خطا به سمتِ امن می‌افتد.
static const NSTimeInterval kZFocusCacheSec = 0.5;
static AXUIElementRef gFocusCache;
static pid_t gFocusPid;
static CFAbsoluteTime gFocusAt;

// **کشِ فوکوس فقط روی یک صف دست‌کاری می‌شود.** قبلا دو نخ به همین اشاره‌گر دست
// می‌زدند: باطل‌سازی روی نخ اصلی (خبرِ عوض شدن اپ) و خواندن روی صف inject. سه
// مسابقه‌ی جدا داشت و هر سه بد: تستِ غیرِنال و بعد CFRetain (یعنی CFRetain(NULL) یا
// روی شیءِ آزادشده)، دو CFRelease هم‌زمان، و ذخیره‌ی اشاره‌گر روی متغیری که نخ اصلی
// همان لحظه نال کرده (نشتِ یک عنصر به ازای هر بار عوض شدن اپ).
// حالا نخ اصلی فقط یک شمارنده را جلو می‌برد و تمام کار CF روی همان یک صف می‌ماند.
static atomic_uint gFocusGen;
static unsigned gFocusCachedGen;

void ZInvalidateFocusCache(void) {
    atomic_fetch_add(&gFocusGen, 1);
}

// فقط از صفی صدا زده می‌شود که کش را می‌سازد و می‌خواند.
static void ZDropFocusCacheLocal(void) {
    if (gFocusCache) {
        CFRelease(gFocusCache);
        gFocusCache = NULL;
    }
    gFocusPid = 0;
}

static AXUIElementRef ZResolveFocused(pid_t frontPid) {
    AXUIElementRef focused = ZCopyElement(ZSystemElement(), kAXFocusedUIElementAttribute);
    if (!focused && frontPid > 0) {
        // عنصر فوکس‌دار را از خودِ اپ هم می‌پرسیم. system-wide گاهی خالی برمی‌گردد
        // در حالی که همان اپ مستقیم جواب می‌دهد؛ اندازه‌گیری شد که در پروسه‌ای بی
        // NSApplication (همان --caretprobe) همیشه خالی است.
        AXUIElementRef app = AXUIElementCreateApplication(frontPid);
        if (app) {
            AXUIElementSetMessagingTimeout(app, kAXTimeout);
            ZWakeAccessibility(app, frontPid);
            focused = ZCopyElement(app, kAXFocusedUIElementAttribute);
            CFRelease(app);
        }
    }
    if (focused) AXUIElementSetMessagingTimeout(focused, kAXTimeout);
    return focused;
}

AXUIElementRef ZCopyFocusedElement(pid_t frontPid) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSWorkspace.sharedWorkspace.notificationCenter
            addObserverForName:NSWorkspaceDidActivateApplicationNotification
                        object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *n) { ZInvalidateFocusCache(); }];
    });
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    unsigned gen = atomic_load(&gFocusGen);
    if (gen != gFocusCachedGen) {       // اپ جلویی عوض شده بود
        ZDropFocusCacheLocal();
        gFocusCachedGen = gen;
    }
    if (gFocusCache && gFocusPid == frontPid && now - gFocusAt < kZFocusCacheSec) {
        // عنصرِ کهنه بی‌خطر نیست: مسیر درجِ مستقیم متن را با انتظار مقایسه نمی‌کند و
        // فقط جابه‌جا شدنِ نشانگر را می‌بیند، پس یک عنصرِ مرده (اپ‌های Electron سرِ
        // ارسال، کلِ گره را از نو می‌سازند) یعنی نوشتن در جای عوضی. یک پرسشِ ارزان
        // قبل از تحویل: هنوز زنده است؟
        CFTypeRef role = NULL;
        AXError st = AXUIElementCopyAttributeValue(gFocusCache, kAXRoleAttribute, &role);
        if (role) CFRelease(role);
        if (st == kAXErrorSuccess) return (AXUIElementRef)CFRetain(gFocusCache);
        ZDropFocusCacheLocal();
    }
    ZDropFocusCacheLocal();
    AXUIElementRef el = ZResolveFocused(frontPid);
    if (el) {
        gFocusCache = (AXUIElementRef)CFRetain(el);
        gFocusPid = frontPid;
        gFocusAt = now;
    }
    return el;
}

// pid از نخ اصلی می‌آید (NSWorkspace را از نخ پس‌زمینه نمی‌خوانیم)
static ZCaretHit ZFindCaret(pid_t frontPid) {
    ZCaretHit hit = {ZCaretNone, CGRectZero, NAN, -1, "none"};
    AXUIElementRef focused = ZResolveFocused(frontPid);
    if (!focused) {
        // پله ۳: پنجره‌ی فوکس‌دارِ خودِ اپ. اپی که عنصر فوکس‌دار نمی‌دهد معمولا این را
        // می‌دهد. سر راه، اگر Chromium خوابیده باشد بیدارش می‌کنیم: تیک بعدی ممکن است
        // کرسر واقعی داشته باشد و اصلا به این پله نرسد.
        if (frontPid > 0) {
            AXUIElementRef app = AXUIElementCreateApplication(frontPid);
            if (app) {
                AXUIElementSetMessagingTimeout(app, kAXTimeout);
                ZWakeAccessibility(app, frontPid);
                AXUIElementRef win = ZCopyElement(app, kAXFocusedWindowAttribute);
                CGRect f;
                if (win && ZWindowFrame(win, &f)) {
                    hit.src = ZCaretWindow;
                    hit.rect = f;
                }
                if (win) CFRelease(win);
                CFRelease(app);
            }
        }
        hit.how = "app window";
        ZCaretNote(NULL, frontPid, hit);
        return hit;
    }
    CGRect elFrame = CGRectZero;
    BOOL haveFrame = ZElementFrame(focused, &elFrame);

    // پله ۱: خودِ نقطه‌ی درج، به ترتیبِ دقت. مارکر اول می‌آید چون Chromium و WebKit
    // فقط همان را کامل داده‌اند؛ اندیس‌ها اول بودند و روی نوار آدرس Chrome، اسپات‌لایت
    // و اپ‌های Electron هیچ‌وقت نمی‌زدند.
    // هر قابی که برمی‌گردد کرسر نیست: اندازه‌گیری روی اپ دسکتاپ Claude نشان داد رنجِ
    // مارکرِ همان باکس تایپ گاهی ۰ نقطه پهنا دارد (کرسر) و گاهی ۷۱۶ (کلِ خط، وقتی
    // چیزی تایپ نشده). پهن یعنی «خط»، نه «کرسر»: وسطش نشستن همان اشتباهِ وسطِ باکس
    // است. پس نگهش می‌داریم برای نشانِ گوشه‌ای و اول پله‌های بعدی را می‌آزماییم.
    ZCaretHit line = {ZCaretNone, CGRectZero, NAN, -1, "none"};
    CGRect box = CGRectZero;
    if (ZCaretFromMarkers(focused, &box)) {
        if (box.size.width <= kCaretWide) {
            hit.src = ZCaretExact;
            hit.rect = box;
            hit.how = "marker";
        } else {
            line.src = ZCaretField;
            line.rect = box;
            line.how = "marker line";
        }
    }
    if (hit.src == ZCaretNone) {
        CFTypeRef sel = ZCopyAttr(focused, kAXSelectedTextRangeAttribute);
        CFRange r = {0, 0};
        BOOL haveSel = sel && CFGetTypeID(sel) == AXValueGetTypeID()
            && AXValueGetValue((AXValueRef)sel, kAXValueCFRangeType, &r);
        ZCaretHit c = {ZCaretNone, CGRectZero, NAN, -1, "none"};
        if (haveSel && (ZCaretFromIndex(focused, r, &c) || ZCaretFromLine(focused, r, &c))) {
            // ایکس که معلوم باشد، پهنای قاب مهم نیست: خطش را داریم و جای دقیق روی خط را هم.
            if (!isnan(c.x) || c.rect.size.width <= kCaretWide) {
                c.src = ZCaretExact;
                hit = c;
            } else if (line.src == ZCaretNone) {
                c.src = ZCaretField;
                line = c;
            }
        }
        if (sel) CFRelease(sel);
    }
    if (hit.src == ZCaretNone) hit = line;
    // قابِ کرسر باید داخل خودِ عنصر بیفتد، وگرنه پله‌ی بعد صادق‌تر است.
    if (hit.src == ZCaretExact && haveFrame && !ZInsideElement(hit.rect, elFrame)) {
        ZProbe(@"    %s rect is outside the element frame, dropped", hit.how);
        hit.src = ZCaretNone;
        hit.x = NAN;
    }

    // پله ۲: قاب خود المنت، بعد پنجره‌ی همان عنصر. اپی که رنج نمی‌دهد معمولا یکی
    // از این دو را می‌دهد، پس دست‌کم نشان نزدیک تایپ می‌ماند نه گوشه‌ی صفحه. اینجا
    // هم یک بار بیدارباش می‌فرستیم: Chromium نیمه‌بیدار عنصر فوکس‌دار می‌دهد ولی
    // رنج متن نه.
    if (hit.src == ZCaretNone) {
        if (frontPid > 0) {
            AXUIElementRef app = AXUIElementCreateApplication(frontPid);
            if (app) {
                AXUIElementSetMessagingTimeout(app, kAXTimeout);
                ZWakeAccessibility(app, frontPid);
                CFRelease(app);
            }
        }
        if (haveFrame && ZLooksLikeField(elFrame)) {
            hit.src = ZCaretField;
            hit.rect = elFrame;
            hit.how = "field frame";
        } else {
            AXUIElementRef win = ZCopyElement(focused, kAXWindowAttribute);
            CGRect f;
            if (win && ZWindowFrame(win, &f)) {
                hit.src = ZCaretWindow;
                hit.rect = f;
                hit.how = "element window";
            }
            if (win) CFRelease(win);
        }
    }
    // نشانِ گوشه‌ای سمتِ دنباله‌ی متن می‌نشیند، پس جهت لازم است. اول از خودِ متنِ فیلد
    // پرسیده می‌شود؛ فیلدِ خالی جهت ندارد و آنجا زبانِ سشن تصمیم می‌گیرد.
    if (hit.src == ZCaretField && hit.rtl < 0) hit.rtl = ZTextDirection(focused);
    ZCaretNote(focused, frontPid, hit);
    CFRelease(focused);
    return hit;
}

// مختصات اکسسبیلیتی از بالا-چپِ صفحه‌ی اصلی می‌شمارد و AppKit از پایین-چپِ همان
// صفحه. بدون این برگردان، نقطه روی نیمه‌ی وارونه‌ی صفحه می‌نشیند و روی مانیتور دوم
// اصلا جای دیگری. صفحه‌ی مرجع screens[0] است (همان که نوار منو دارد و مبدأ صفر
// است)، نه mainScreen که «صفحه‌ی پنجره‌ی فعال» است و جابه‌جا می‌شود.
static NSRect ZFromAX(CGRect r) {
    NSScreen *primary = NSScreen.screens.firstObject;
    CGFloat top = primary ? NSMaxY(primary.frame) : 0;
    return NSMakeRect(r.origin.x, top - r.origin.y - r.size.height, r.size.width, r.size.height);
}

// ---------- ZCaretDot ----------

@interface ZCaretDot ()
- (void)moveTo:(ZCaretHit)hit;
@end

@implementation ZCaretDot {
    NSPanel *_win;
    ZMarkView *_dot;
    NSTimer *_timer;
    dispatch_queue_t _q;
    BOOL _busy;        // پرس‌وجوی قبلی هنوز برنگشته؛ اپ کند نباید صف بسازد
    BOOL _pulsing;
    NSPoint _at;
    BOOL _haveAt;
    BOOL _rtl;         // زبان سشن فارسی است: نشانِ گوشه‌ای سمت چپ می‌نشیند نه راست
}

- (instancetype)init {
    if ((self = [super init])) {
        _q = dispatch_queue_create("zemzeme.caret", DISPATCH_QUEUE_SERIAL);
        // همان تنظیمات پنل شناور، چون همان‌ها درست‌اند: نه فوکس می‌گیرد، نه اپ را
        // فعال می‌کند، روی همه‌ی Space ها و روی فول‌اسکرین می‌ماند و با رفتن اپ به
        // پس‌زمینه پنهان نمی‌شود.
        _win = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, kWinW, kWinH)
                                          styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                            backing:NSBackingStoreBuffered defer:NO];
        _win.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                                | NSWindowCollectionBehaviorFullScreenAuxiliary
                                | NSWindowCollectionBehaviorIgnoresCycle;
        // ترتیب مهم است: floatingPanel خودش سطح پنجره را روی floating (۳) می‌گذارد و
        // اگر بعد از level بیاید، بی‌صدا پایینش می‌آورد. اندازه‌گیری شد: نقطه روی سطح ۳
        // می‌نشست نه ۲۵.
        _win.floatingPanel = YES;
        _win.level = NSStatusWindowLevel;
        _win.hidesOnDeactivate = NO;
        _win.opaque = NO;
        _win.backgroundColor = NSColor.clearColor;
        _win.hasShadow = NO;
        _win.becomesKeyOnlyIfNeeded = YES;
        _win.releasedWhenClosed = NO;
        // نقطه درست جایی می‌نشیند که کاربر دارد تایپ می‌کند، پس باید کلیک از رویش رد
        // شود و به اپ زیرین برسد؛ وگرنه یک سوراخ کور روی متن ساخته بودیم.
        _win.ignoresMouseEvents = YES;

        NSView *host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kWinW, kWinH)];
        _dot = [[ZMarkView alloc] initWithFrame:
            NSMakeRect((kWinW - kDotSize * ZMarkAspect) / 2, kPadY,
                       kDotSize * ZMarkAspect, kDotSize)];
        // سایه‌ی نرم: نشان روی هر پس‌زمینه‌ای ممکن است بنشیند و بی این، روی رنگ
        // نزدیک به خودش گم می‌شود.
        _dot.layer.shadowColor = NSColor.blackColor.CGColor;
        _dot.layer.shadowOpacity = 0.35f;
        _dot.layer.shadowRadius = 2;
        _dot.layer.shadowOffset = CGSizeZero;
        [host addSubview:_dot];
        _win.contentView = host;
    }
    return self;
}

- (void)show {
    if (_timer) return;
    _haveAt = NO;    // اولین تیک بی‌قید جابه‌جا کند، وگرنه نقطه سر جای سشن قبلی می‌ماند
    // کشِ عنصرِ فوکوس‌دار از سشن قبلی می‌تواند کهنه باشد و همان بود که نقطه را سرِ
    // شروع یک گوشه می‌نشاند: کاربر تا یک اسپیس نمی‌زد (که درختِ AX را تازه می‌کرد)
    // نشان سر جای درست نمی‌رفت. یک بار اینجا باطلش می‌کنیم تا نردبان از صفر بپرسد.
    ZInvalidateFocusCache();
    [_win orderFrontRegardless];
    [self tick];
    // و چند تیکِ تندِ اولیه: درختِ اکسسبیلیتی بعضی اپ‌ها (Chromium و Electron) تا
    // اولین پرس‌وجو ساخته نمی‌شود، پس اولین تیک تقریبا همیشه به پله‌ی فال‌بک می‌افتد.
    // با ۶ هرتزِ عادی آن گوشه تا ثانیه‌ها روی صفحه می‌ماند و کاربر فکر می‌کند خراب است.
    for (int i = 1; i <= 6; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.08 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (self->_timer) [self tick];
        });
    }
    _timer = [NSTimer timerWithTimeInterval:kPoll target:self selector:@selector(tick)
                                   userInfo:nil repeats:YES];
    // common modes: وقتی منویی باز است یا کاربر دارد چیزی می‌کشد هم دنبال کرسر بماند
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)hide {
    [_timer invalidate];
    _timer = nil;
    [self stopPulse];
    [_win orderOut:nil];
    // بیدارباشی که به اپ‌های Chromium داده‌ایم پس گرفته می‌شود، روی همان صفی که
    // ست شده بود. روشن ماندنش بعد از پایان دیکته یعنی هزینه‌ی درخت اکسسبیلیتی را
    // تا ری‌استارت اپ به کاربر تحمیل کرده‌ایم، بی‌آنکه دیگر لازممان باشد.
    dispatch_async(_q, ^{ ZCaretSleepAll(); });
}

- (void)tick {
    if (_busy) return;
    _busy = YES;
    pid_t front = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    __weak typeof(self) ws = self;
    dispatch_async(_q, ^{
        // اکسسبیلیتی روی نخ پس‌زمینه: هر فراخوان می‌تواند تا مهلتش طول بکشد و نخ
        // اصلی، که تایپ و رندر روی آن است، نباید پشتش بماند.
        ZCaretHit hit = ZFindCaret(front);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) s = ws;
            if (!s) return;
            s->_busy = NO;
            if (s->_timer) [s moveTo:hit];    // سشن همین وسط تمام شده باشد، دیگر تکان نده
        });
    });
}

- (void)moveTo:(ZCaretHit)hit {
    NSPoint p = [self originFor:hit];
    if (_haveAt && fabs(p.x - _at.x) <= kMoveEps && fabs(p.y - _at.y) <= kMoveEps) return;
    _at = p;
    _haveAt = YES;
    [_win setFrameOrigin:p];
}

// سه پله‌ی فروکاست، به همین ترتیب. هیچ پله‌ای پنجره را پنهان نمی‌کند: تا سشن زنده
// است کاربر باید بتواند ببیند که دیکته روشن است.
- (NSPoint)originFor:(ZCaretHit)hit {
    if (hit.src == ZCaretExact) {
        // درست زیر کرسر و وسط‌چین با آن، همان کاری که دیکته‌ی خود مک می‌کند. بالای
        // کرسر جای بدی بود: روی خط قبلی می‌افتاد و سر خط اولِ سند می‌رفت روی نوار
        // عنوان. زیرِ کرسر همیشه یک خط پایین‌تر است، یعنی جایی که هنوز چیزی ننوشته‌ای.
        // ایکس از خودِ نردبان می‌آید اگر داده باشد؛ نداده باشد وسطِ قاب، که برای رنجِ
        // طول‌صفر همان نقطه است.
        NSRect c = ZFromAX(hit.rect);
        CGFloat cx = isnan(hit.x) ? NSMidX(c) : hit.x;   // محور x برنمی‌گردد
        NSPoint ref = NSMakePoint(cx, NSMidY(c));
        CGFloat below = NSMinY(c) - kGapY - kPadY - kDotSize;
        // ته صفحه جا نیست: همان‌جا برمی‌گردد بالای کرسر، باز هم مثل خود مک
        CGFloat y = below >= NSMinY([self screenNear:ref].frame)
            ? below : NSMaxY(c) + kGapY - kPadY;
        return [self clamp:NSMakePoint(cx - kWinW / 2, y) near:ref];
    }
    if (hit.src == ZCaretField) {
        return [self badgeOrigin:ZFromAX(hit.rect) rtl:hit.rtl < 0 ? _rtl : hit.rtl == 1];
    }
    if (hit.src == ZCaretWindow) {
        // پایین-چپِ داخل پنجره، نه بالا-چپ. بالا-چپ روی پنجره‌ی تمام‌صفحه یعنی
        // گوشه‌ی بالای مانیتور، که کاربر گفت اصلا دیده نمی‌شود؛ و اپ‌هایی که به این
        // پله می‌افتند (چت و پیام‌رسان و Electron) اینپوتشان پایین صفحه است، پس
        // پایین حدسِ نزدیک‌تری به کرسر واقعی است.
        NSRect w = ZFromAX(hit.rect);
        return [self clamp:NSMakePoint(NSMinX(w) + kWinInset, NSMinY(w) + kWinInset)
                      near:NSMakePoint(NSMidX(w), NSMinY(w) + 1)];
    }
    NSRect vf = [self activeScreen].visibleFrame;
    return NSMakePoint(NSMinX(vf) + kParkInset, NSMinY(vf) + kParkInset);
}

// پله‌ی فیلد: کرسر واقعی در کار نیست، فقط قاب باکس تایپ یا خط. وسطِ آن قاب نشستن
// یعنی دروغ گفتن (و همان چیزی بود که کاربر می‌دید: نشان وسط باکس یا زیرش)، پس مثل
// نشانِ Grammarly گوشه می‌نشیند: داخل باکس، پایینِ سمتِ دنباله، کمی تو رفته. سمت
// دنباله یعنی راست برای متن انگلیسی و چپ برای فارسی، تا جلوی متنی که همین حالا
// تایپ می‌شود نایستد. باکسِ تک‌خطی جا ندارد و نشان می‌افتد روی خودِ متن، پس آنجا همان
// گوشه ولی بیرونِ باکس؛ ته صفحه جا نباشد، بالای باکس.
- (NSPoint)badgeOrigin:(NSRect)f rtl:(BOOL)rtl {
    CGFloat markW = kDotSize * ZMarkAspect;
    CGFloat padX = (kWinW - markW) / 2;
    CGFloat markX = rtl ? NSMinX(f) + kBadgeInset : NSMaxX(f) - kBadgeInset - markW;
    NSPoint ref = NSMakePoint(rtl ? NSMinX(f) + 1 : NSMaxX(f) - 1, NSMinY(f) + 1);
    CGFloat y;
    if (NSHeight(f) >= kBadgeRoom) {
        y = NSMinY(f) + kBadgeInset - kPadY;
    } else {
        CGFloat below = NSMinY(f) - kGapY - kPadY - kDotSize;
        y = below >= NSMinY([self screenNear:ref].frame) ? below : NSMaxY(f) + kGapY - kPadY;
    }
    return [self clamp:NSMakePoint(markX - padX, y) near:ref];
}

// صفحه‌ی زیر موس؛ وقتی هیچ اپی جایی برای نشان دادن نداده، همان‌جا که کاربر نگاه می‌کند
- (NSScreen *)activeScreen {
    NSPoint mouse = NSEvent.mouseLocation;
    for (NSScreen *sc in NSScreen.screens) {
        if (NSMouseInRect(mouse, sc.frame, NO)) return sc;
    }
    return NSScreen.mainScreen ?: NSScreen.screens.firstObject;
}

// نقطه را داخل همان صفحه‌ای نگه می‌دارد که هدف رویش است. معیار frame است نه
// visibleFrame: کرسری که بالای پنجره‌ی فول‌اسکرین است با visibleFrame به اندازه‌ی
// نوار منو پایین کشیده می‌شد و درست می‌افتاد روی همان متن.
- (NSScreen *)screenNear:(NSPoint)p {
    for (NSScreen *sc in NSScreen.screens) {
        if (NSPointInRect(p, sc.frame)) return sc;
    }
    return [self activeScreen];
}

- (NSPoint)clamp:(NSPoint)p near:(NSPoint)ref {
    NSRect f = [self screenNear:ref].frame;
    return NSMakePoint(MIN(MAX(p.x, NSMinX(f)), NSMaxX(f) - kWinW),
                       MIN(MAX(p.y, NSMinY(f)), NSMaxY(f) - kWinH));
}

- (void)render:(ZPanelModel *)m {
    _dot.color = ZStatusColor(m);
    _rtl = [m.lang hasPrefix:@"fa"];
    BOOL live = m.listening && !m.paused;
    if (live && !_pulsing) [self startPulse];
    if (!live && _pulsing) [self stopPulse];
}

- (void)pulseLevel:(float)level {
    CGFloat s = 1 + MIN(MAX(level, 0.0f), 1.0f) * 0.5;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _dot.layer.affineTransform = CGAffineTransformMakeScale(s, s);
    [CATransaction commit];
}

- (void)startPulse {
    _pulsing = YES;
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
    a.fromValue = @1.0;
    a.toValue = @0.35;
    a.duration = 0.6;
    a.autoreverses = YES;
    a.repeatCount = HUGE_VALF;
    [_dot.layer addAnimation:a forKey:@"pulse"];
}

- (void)stopPulse {
    _pulsing = NO;
    [_dot.layer removeAnimationForKey:@"pulse"];
    _dot.layer.opacity = 1;
}

@end

// ---------- zemzeme --caretprobe ----------
// نردبان یک بار روی اپی که همین حالا فوکس دارد اجرا می‌شود و می‌گوید چه دید و کدام
// پله زد. بی این، هر جمله‌ای درباره‌ی «فلان اپ کرسر می‌دهد» حرف است نه اندازه.
// باید با باینریِ نصب‌شده اجرا شود (`/Applications/Zemzeme.app/Contents/MacOS/zemzeme`)
// چون اجازه‌ی اکسسبیلیتی روی همان شناسه و همان امضا ذخیره شده، نه روی باینری تست.
// اجرا: --caretprobe [ثانیه‌ی صبر] [--watch]. صبر لازم است چون اپِ فوکس‌دار در لحظه‌ی
// اجرا خودِ ترمینال است؛ در این فرصت روی اپِ هدف کلیک می‌کنی.
static void ZProbeNames(AXUIElementRef el) {
    CFArrayRef names = NULL;
    if (AXUIElementCopyAttributeNames(el, &names) == kAXErrorSuccess && names) {
        ZProbe(@"  attrs: %@", [(__bridge NSArray *)names componentsJoinedByString:@", "]);
        CFRelease(names);
    }
    CFArrayRef pnames = NULL;
    if (AXUIElementCopyParameterizedAttributeNames(el, &pnames) == kAXErrorSuccess && pnames) {
        ZProbe(@"  param attrs: %@", [(__bridge NSArray *)pnames componentsJoinedByString:@", "]);
        CFRelease(pnames);
    }
}

// امضای ارزانِ «چه چیزی فوکس دارد»: در حالت دیده‌بانی فقط با عوض شدن این، اندازه‌گیری
// تازه چاپ می‌شود.
static AXUIElementRef ZProbeFocused(void) {
    AXUIElementRef el = ZCopyElement(ZSystemElement(), kAXFocusedUIElementAttribute);
    if (el) return el;
    pid_t pid = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    AXUIElementRef app = pid > 0 ? AXUIElementCreateApplication(pid) : NULL;
    if (!app) return NULL;
    AXUIElementSetMessagingTimeout(app, kAXTimeout);
    el = ZCopyElement(app, kAXFocusedUIElementAttribute);
    CFRelease(app);
    return el;
}

static NSString *ZProbeSignature(void) {
    AXUIElementRef el = ZProbeFocused();
    if (!el) return @"none";
    CGRect f = CGRectZero;
    ZElementFrame(el, &f);
    NSString *s = [NSString stringWithFormat:@"%@|%.0f,%.0f %.0fx%.0f",
                   ZStringAttr(el, kAXRoleAttribute) ?: @"?", f.origin.x, f.origin.y,
                   f.size.width, f.size.height];
    CFRelease(el);
    return s;
}

static void ZProbeOnce(void) {
    // pid از همان جایی که نردبانِ زنده می‌گیردش: NSWorkspace. عنصر system-wide هم
    // پرسیده می‌شود ولی فقط برای گزارش، چون در پروسه‌ای که NSApplication ندارد
    // اندازه‌گیری شد که kAXFocusedApplication چیزی برنمی‌گرداند.
    NSRunningApplication *ra = NSWorkspace.sharedWorkspace.frontmostApplication;
    pid_t pid = ra.processIdentifier;
    AXUIElementRef app = ZCopyElement(ZSystemElement(), kAXFocusedApplicationAttribute);
    pid_t axPid = 0;
    if (app) {
        AXUIElementGetPid(app, &axPid);
        CFRelease(app);
    }
    ZProbe(@"\napp: %@ (%@) pid=%d ax-focused-pid=%d trusted=%d", ra.localizedName ?: @"?",
           ra.bundleIdentifier ?: @"?", pid, axPid, AXIsProcessTrusted());
    AXUIElementRef focused = ZProbeFocused();
    if (focused) {
        CGRect f = CGRectZero;
        BOOL haveFrame = ZElementFrame(focused, &f);
        ZProbe(@"  focused: role=%@/%@ desc=%@ frame=%@", ZStringAttr(focused, kAXRoleAttribute)
               ?: @"?", ZStringAttr(focused, kAXSubroleAttribute) ?: @"-",
               ZStringAttr(focused, kAXRoleDescriptionAttribute) ?: @"-",
               haveFrame ? [NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f", f.origin.x,
                            f.origin.y, f.size.width, f.size.height] : @"none");
        ZProbeNames(focused);
        CFRelease(focused);
    } else {
        ZProbe(@"  focused: none");
    }
    ZProbe(@"  ladder:");
    ZCaretHit hit = ZFindCaret(pid);
    NSRect flipped = ZFromAX(hit.rect);
    ZProbe(@"  => step=%s src=%ld rect(ax)=%.0f,%.0f %.0fx%.0f rect(appkit)=%.0f,%.0f x=%.0f",
           hit.how, (long)hit.src, hit.rect.origin.x, hit.rect.origin.y, hit.rect.size.width,
           hit.rect.size.height, flipped.origin.x, flipped.origin.y, hit.x);
}

int ZCaretProbeMain(NSArray<NSString *> *args) {
    @autoreleasepool {
        gProbe = YES;
        BOOL watch = [args containsObject:@"--watch"];
        NSUInteger i = [args indexOfObject:@"--caretprobe"];
        double delay = i + 1 < args.count ? args[i + 1].doubleValue : 0;
        if (delay <= 0) delay = 3;
        if (!AXIsProcessTrusted()) {
            ZProbeSay(@"warn: no accessibility permission for this process. either grant it to "
                      @"your terminal, or run: open -n /Applications/Zemzeme.app --args "
                      @"--caretprobe 5 --watch");
        }
        ZProbeSay([NSString stringWithFormat:@"\n--- caretprobe, focus the app to measure, %.0fs"
                   @"%@", delay, watch ? @", then keep switching apps" : @""]);
        usleep((useconds_t)(delay * 1e6));
        NSString *sig = ZProbeSignature();
        ZProbeOnce();
        // حالت دیده‌بانی: یک بار اجرا کن، بعد در اپ‌های مختلف کلیک کن. فقط وقتی عنصر
        // فوکس‌دار عوض شود یک اندازه‌گیری تازه چاپ می‌شود، پس کل جدول README با یک
        // اجرا درمی‌آید و خروجی تکراری هم نمی‌سازد.
        // سقف ده دقیقه: با `open -n` هیچ ترمینالی نیست که ctrl-c بزند و پروسه‌ی
        // یتیم نباید تا ری‌استارت دستگاه بماند.
        for (int left = watch ? 1200 : 0; left > 0; left--) {
            usleep(500000);
            NSString *now = ZProbeSignature();
            if ([now isEqualToString:sig]) continue;
            sig = now;
            ZProbeOnce();
        }
        if (watch) ZProbeSay(@"--- caretprobe: 10 minutes up, stopping");
    }
    return 0;
}
