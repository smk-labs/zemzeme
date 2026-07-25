// نشانگر کنار کرسر: حالت «کرسر»، همان کاری که دیکته‌ی خود مک می‌کند. نه پنلی،
// نه نواری؛ فقط یک نقطه‌ی کوچک بالای کرسرِ اپی که فوکس دارد، با همان رنگ‌های
// وضعیتِ نقطه‌ی روی پنل. متن از همان مسیر درجِ زنده سر کرسر می‌نشیند.
#import "zemzeme.h"
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
static const NSTimeInterval kPoll = 1.0 / 6.0;   // ۶ هرتز: چشم روان می‌بیند، AX هم له نمی‌شود
static const CGFloat kMoveEps = 2.0;    // جابه‌جایی کمتر از این نادیده، وگرنه نقطه می‌لرزد
static const float kAXTimeout = 0.15f;

// ---------- پیدا کردن کرسر با اکسسبیلیتی ----------
// شکست اینجا استثنا نیست، قاعده است: اپ‌های Electron و وب‌ویو معمولا رنج متن را
// نمی‌دهند و ریموت دسکتاپ هیچ‌چیز نمی‌دهد. پس چهار پله داریم و هر پله فقط یعنی
// «پله‌ی بعد»؛ هیچ فراخوانی نه می‌اندازد نه معطل می‌کند.
typedef NS_ENUM(NSInteger, ZCaretSource) {
    ZCaretNone = 0,     // هیچ: نقطه گوشه‌ی صفحه پارک می‌شود
    ZCaretWindow,       // فقط پنجره‌ی فوکس‌دار: پایین-چپِ داخل همان پنجره
    ZCaretField,        // قاب خود المنت فوکس‌دار (باکس تایپ)، بی‌مختصات کرسر داخلش
    ZCaretExact,        // خود نقطه‌ی درج
};

// مستطیل خام اکسسبیلیتی (مبدأ بالا-چپ)؛ برگرداندنش به مختصات AppKit روی نخ اصلی
// انجام می‌شود، چون NSScreen را نباید از نخ پس‌زمینه خواند.
typedef struct {
    ZCaretSource src;
    CGRect rect;
} ZCaretHit;

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

static BOOL ZBoundsForRange(AXUIElementRef el, CFRange range, CGRect *out) {
    AXValueRef rv = AXValueCreate(kAXValueCFRangeType, &range);
    if (!rv) return NO;
    CFTypeRef bounds = NULL;
    AXError err = AXUIElementCopyParameterizedAttributeValue(
        el, kAXBoundsForRangeParameterizedAttribute, rv, &bounds);
    CFRelease(rv);
    if (err != kAXErrorSuccess || !bounds) return NO;
    CGRect r = CGRectZero;
    BOOL ok = CFGetTypeID(bounds) == AXValueGetTypeID()
        && AXValueGetValue((AXValueRef)bounds, kAXValueCGRectType, &r)
        && ZRectUsable(r);
    CFRelease(bounds);
    if (ok) *out = r;
    return ok;
}

// قاب خود المنتِ فوکس‌دار، فقط اگر شبیه فیلد ورودی باشد نه سند تمام‌قد (سقف بلندی
// همان منطق ZRectUsable: یک باکس تایپ است، نه کل صفحه). اپ‌های Electron مثل
// دسکتاپ Claude رنج متن نمی‌دهند ولی بعد از بیدارباش قاب باکس تایپشان را می‌دهند،
// و «زیر همان باکس» خیلی به کرسر واقعی نزدیک‌تر است تا «گوشه‌ی پنجره».
static BOOL ZFieldFrame(AXUIElementRef el, CGRect *out) {
    CFTypeRef pos = ZCopyAttr(el, kAXPositionAttribute);
    CFTypeRef size = ZCopyAttr(el, kAXSizeAttribute);
    CGPoint p = CGPointZero;
    CGSize s = CGSizeZero;
    BOOL ok = pos && size
        && CFGetTypeID(pos) == AXValueGetTypeID() && CFGetTypeID(size) == AXValueGetTypeID()
        && AXValueGetValue((AXValueRef)pos, kAXValueCGPointType, &p)
        && AXValueGetValue((AXValueRef)size, kAXValueCGSizeType, &s)
        && isfinite(p.x) && isfinite(p.y)
        && s.width >= 40 && s.height >= 12 && s.height <= 400
        && !(p.x == 0 && p.y == 0);
    if (pos) CFRelease(pos);
    if (size) CFRelease(size);
    if (ok) *out = CGRectMake(p.x, p.y, s.width, s.height);
    return ok;
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
    return s;    // فقط روی صف caret دست می‌خورد، پس قفل لازم ندارد
}

static void ZWakeAccessibility(AXUIElementRef app, pid_t pid) {
    if ([ZPokedPids() containsObject:@(pid)]) return;
    [ZPokedPids() addObject:@(pid)];
    AXError m = AXUIElementSetAttributeValue(app, CFSTR("AXManualAccessibility"), kCFBooleanTrue);
    AXError e = AXUIElementSetAttributeValue(app, CFSTR("AXEnhancedUserInterface"), kCFBooleanTrue);
    ZLog(@"caret: woke ax for pid=%d manual=%d enhanced=%d", pid, m, e);
}

static void ZCaretSleepAll(void) {
    for (NSNumber *pid in ZPokedPids()) {
        AXUIElementRef app = AXUIElementCreateApplication(pid.intValue);
        if (!app) continue;
        AXUIElementSetMessagingTimeout(app, kAXTimeout);
        AXUIElementSetAttributeValue(app, CFSTR("AXEnhancedUserInterface"), kCFBooleanFalse);
        AXUIElementSetAttributeValue(app, CFSTR("AXManualAccessibility"), kCFBooleanFalse);
        CFRelease(app);
    }
    [ZPokedPids() removeAllObjects];
}

// pid از نخ اصلی می‌آید (NSWorkspace را از نخ پس‌زمینه نمی‌خوانیم)
static ZCaretHit ZFindCaret(pid_t frontPid) {
    ZCaretHit hit = {ZCaretNone, CGRectZero};
    AXUIElementRef focused = ZCopyElement(ZSystemElement(), kAXFocusedUIElementAttribute);
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
        return hit;
    }
    AXUIElementSetMessagingTimeout(focused, kAXTimeout);

    // پله ۱: خودِ نقطه‌ی درج. رنج با طول صفر پرسیده می‌شود، چون وقتی متنی انتخاب
    // شده باشد مستطیلِ کلِ انتخاب برمی‌گردد و نقطه می‌پرد وسط صفحه.
    CFTypeRef sel = ZCopyAttr(focused, kAXSelectedTextRangeAttribute);
    if (sel) {
        CFRange r = {0, 0};
        if (CFGetTypeID(sel) == AXValueGetTypeID()
            && AXValueGetValue((AXValueRef)sel, kAXValueCFRangeType, &r)) {
            CGRect box = CGRectZero;
            // بعضی اپ‌ها برای رنج صفر چیزی نمی‌دهند؛ آنجا خودِ رنج انتخاب‌شده را
            // می‌پرسیم که دست‌کم روی همان خط بنشیند.
            if (ZBoundsForRange(focused, CFRangeMake(r.location, 0), &box)
                || (r.length > 0 && ZBoundsForRange(focused, r, &box))) {
                hit.src = ZCaretExact;
                hit.rect = box;
            }
        }
        CFRelease(sel);
    }

    // پله ۲: قاب خود المنت، بعد پنجره‌ی همان عنصر. اپی که رنج نمی‌دهد معمولا یکی
    // از این دو را می‌دهد، پس دست‌کم نقطه نزدیک تایپ می‌ماند نه گوشه‌ی صفحه. اینجا
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
        CGRect ff;
        if (ZFieldFrame(focused, &ff)) {
            hit.src = ZCaretField;
            hit.rect = ff;
        } else {
            AXUIElementRef win = ZCopyElement(focused, kAXWindowAttribute);
            CGRect f;
            if (win && ZWindowFrame(win, &f)) {
                hit.src = ZCaretWindow;
                hit.rect = f;
            }
            if (win) CFRelease(win);
        }
    }
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
    [_win orderFrontRegardless];
    [self tick];
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
    if (hit.src == ZCaretExact || hit.src == ZCaretField) {
        // درست زیر کرسر و وسط‌چین با آن، همان کاری که دیکته‌ی خود مک می‌کند. برای
        // پله‌ی فیلد همان حساب روی قاب باکس تایپ می‌نشیند: زیر لبه‌ی پایین، وسط‌چین. بالای
        // کرسر جای بدی بود: روی خط قبلی می‌افتاد و سر خط اولِ سند می‌رفت روی نوار
        // عنوان. زیرِ کرسر همیشه یک خط پایین‌تر است، یعنی جایی که هنوز چیزی ننوشته‌ای.
        // مرکز افقی از NSMidX می‌آید نه NSMinX: رنجِ طول‌صفر عرض ندارد و این دو یکی‌اند،
        // ولی اگر اپی رنج واقعی برگرداند باز هم وسطِ همان می‌نشیند نه کنارش.
        NSRect c = ZFromAX(hit.rect);
        NSPoint ref = NSMakePoint(NSMidX(c), NSMidY(c));
        CGFloat below = NSMinY(c) - kGapY - kPadY - kDotSize;
        // ته صفحه جا نیست: همان‌جا برمی‌گردد بالای کرسر، باز هم مثل خود مک
        CGFloat y = below >= NSMinY([self screenNear:ref].frame)
            ? below : NSMaxY(c) + kGapY - kPadY;
        return [self clamp:NSMakePoint(NSMidX(c) - kWinW / 2, y) near:ref];
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
