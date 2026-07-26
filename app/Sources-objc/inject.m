// درج متن (تایپ یونیکد / پیست تکه‌ای) و تپ‌های کیبورد (Esc و دابل‌تپ Command راست).
#import "zemzeme.h"
#import <Carbon/Carbon.h>

// ---------- ZInjector ----------

@implementation ZInjector {
    dispatch_queue_t _q;
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

// تایپ مستقیم: تکه‌های حداکثر ۱۸ واحد UTF-16 در هر رویداد؛
// چون پنل فوکس نمی‌گیرد، متن دقیقا سر کرسرِ اپ مقصد می‌نشیند.
- (void)type:(NSString *)text delayMicros:(useconds_t)d {
    NSData *utf16 = [text dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    dispatch_async(_q, ^{
        const UniChar *units = utf16.bytes;
        NSUInteger count = utf16.length / 2;
        NSUInteger i = 0;
        while (i < count) {
            NSUInteger n = MIN((NSUInteger)18, count - i);
            CGEventRef down = CGEventCreateKeyboardEvent(NULL, 0, true);
            if (down) {
                CGEventKeyboardSetUnicodeString(down, n, units + i);
                CGEventPost(kCGSessionEventTap, down);
                CFRelease(down);
            }
            CGEventRef up = CGEventCreateKeyboardEvent(NULL, 0, false);
            if (up) {
                CGEventPost(kCGSessionEventTap, up);
                CFRelease(up);
            }
            if (d > 0) usleep(d);
            i += n;
        }
    });
}

// جای دُم موقت را عوض می‌کند: n نویسه‌ی آخر پاک و متن تازه تایپ می‌شود، هر دو در یک
// بلاک روی همان صف سریال. یکی نشدنشان یعنی کاربر یک لحظه متن نصفه ببیند، یا بدتر،
// تایپِ بعدی وسط پاک کردنِ قبلی بنشیند. فقط برای نویسه‌هایی به کار می‌رود که خودمان
// همین حالا تایپشان کرده‌ایم؛ متن خودِ کاربر هیچ‌وقت از اینجا پاک نمی‌شود.
- (void)replaceLast:(NSUInteger)n with:(NSString *)text delayMicros:(useconds_t)d {
    NSData *utf16 = [text dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    dispatch_async(_q, ^{
        for (NSUInteger i = 0; i < n; i++) {
            for (int down = 1; down >= 0; down--) {
                CGEventRef e = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)kVK_Delete, down != 0);
                if (!e) continue;
                CGEventPost(kCGSessionEventTap, e);
                CFRelease(e);
            }
            if (d > 0) usleep(d);
        }
        const UniChar *units = utf16.bytes;
        NSUInteger count = utf16.length / 2, i = 0;
        while (i < count) {
            NSUInteger k = MIN((NSUInteger)18, count - i);
            CGEventRef down = CGEventCreateKeyboardEvent(NULL, 0, true);
            if (down) {
                CGEventKeyboardSetUnicodeString(down, k, units + i);
                CGEventPost(kCGSessionEventTap, down);
                CFRelease(down);
            }
            CGEventRef up = CGEventCreateKeyboardEvent(NULL, 0, false);
            if (up) {
                CGEventPost(kCGSessionEventTap, up);
                CFRelease(up);
            }
            if (d > 0) usleep(d);
            i += k;
        }
    });
}

// پیست تکه‌ای: کپی با نشونه transient (تاریخچه‌گیرها رد می‌کنند) و Cmd+V.
// همه چیز روی یک صف سریال تا دو پیست پشت هم مسابقه کلیپ‌بورد نگیرند
// (باگ واقعی: برگرداندن کلیپ‌بورد قبلی وسط پیست بعدی می‌نشست و متن قدیمی پیست می‌شد؛
// برای همین «برگرداندن» حذف شد. کپی پایانی Esc به هر حال کلیپ‌بورد را پر می‌کند.)
- (void)paste:(NSString *)text delayMicros:(useconds_t)d {
    dispatch_async(_q, ^{
        dispatch_sync(dispatch_get_main_queue(), ^{
            NSPasteboard *pb = NSPasteboard.generalPasteboard;
            NSPasteboardType transient = @"org.nspasteboard.TransientType";
            [pb declareTypes:@[NSPasteboardTypeString, transient] owner:nil];
            [pb setString:text forType:NSPasteboardTypeString];
            [pb setString:@"" forType:transient];
        });
        [ZInjector wakeRemoteClipboard];    // اول بیدارش کن، بعد مهلت بده
        usleep(d);    // مهلت سینک کلیپ‌بورد ریموت دسکتاپ
        [ZInjector sendCmdV];
        usleep(150000);
    });
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

static const CGEventFlags kZLeftShiftBit = 0x2;  // NX_DEVICELSHIFTKEYMASK

static void zPostModifier(CGKeyCode key, CGEventFlags flags) {
    CGEventRef e = CGEventCreateKeyboardEvent(NULL, key, true);
    if (!e) return;
    CGEventSetType(e, kCGEventFlagsChanged);
    CGEventSetFlags(e, flags);
    CGEventPost(kCGSessionEventTap, e);
    CFRelease(e);
    usleep(kZChordGap);
}

// بیدارباش قبل از مهلت سینک: یک ضربه‌ی خالی روی Shift چپ.
// اندازه‌گیری: Windows App کلیپ‌بورد مک را مدام نمی‌پاید. سرویس pasteboard.xpc اش
// ساعت‌ها بالا بود و ۰٫۰۳ ثانیه CPU خورده بود، و با عوض شدن کلیپ‌بورد در پس‌زمینه
// یک ذره هم تکان نخورد. تا چیزی بیدارش نکند، به ویندوز خبر نمی‌دهد که کلیپ‌بورد عوض
// شده، و ویندوز همان متن قبلی خودش را پیست می‌کند. Shift تنها بی‌خطرترین چیزی است
// که می‌شود فرستاد: در ویندوز هیچ کاری نمی‌کند، روی صفحه دیده نمی‌شود، و متن را
// دست نمی‌زند. کیکد ۵۶ است، پس تپ خودمان (که فقط ۵۴ را می‌پاید) هم نمی‌بیندش.
+ (void)wakeRemoteClipboard {
    zPostModifier((CGKeyCode)kVK_Shift, kCGEventFlagMaskShift | kZLeftShiftBit);
    zPostModifier((CGKeyCode)kVK_Shift, 0);
}

+ (void)sendCmdV {
    CGEventFlags held = kCGEventFlagMaskCommand | kZLeftCmdBit;
    zPostModifier((CGKeyCode)kVK_Command, held);
    for (int down = 1; down >= 0; down--) {
        CGEventRef e = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)kVK_ANSI_V, down != 0);
        if (!e) continue;
        CGEventSetFlags(e, held);
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
// تنظیم «هاتکی داخلی» روشن/خاموش می‌شود. بقیه (Esc، ⌥Space/C/V، تک‌تپ Command راست،
// Command راست+C) فقط وقتی sessionActive=YES باشد؛ بیرون از سشن دست‌نخورده رد می‌شوند.
// تشخیص تپِ راست-Command همان ترفند lazy کارابینر است: رویداد نگه‌داشته می‌شود و فقط
// اگر با کلید دیگری ترکیب شد دوباره تزریق می‌شود، وگرنه هیچ‌وقت به اپ دیگری نمی‌رسد.

static const uint64_t kRightCmdBit = 0x10;    // NX_DEVICERCMDKEYMASK
static const CGEventFlags kZModMask = kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate
                                     | kCGEventFlagMaskControl | kCGEventFlagMaskShift;
static const CFTimeInterval kZTapWindow = 0.35;   // پنجره دابل/تک‌تپ

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
    CGEventMask mask = CGEventMaskBit(kCGEventFlagsChanged) | CGEventMaskBit(kCGEventKeyDown);
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
    if (_savedDown) {
        CFRelease(_savedDown);
        _savedDown = NULL;
    }
    _physDown = NO;
    _emitted = NO;
    _suppressUp = NO;
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
    BOOL wasEmitted = _emitted;
    BOOL suppressUp = _suppressUp;
    _physDown = NO;
    _emitted = NO;
    _suppressUp = NO;
    if (_savedDown) {
        CFRelease(_savedDown);
        _savedDown = NULL;
    }
    if (wasEmitted) return suppressUp ? NULL : event;
    [self loneTapUp];
    return NULL;
}

// نقشه‌ی واحد کلید به کار: هم Command راست + حرف از آن می‌خواند هم ⌥ + حرف، پس دو
// مسیر هیچ‌وقت از هم واگرا نمی‌شوند و هر دکمه‌ی پنل دقیقا یک حرف دارد.
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
        case 9:  return self.onInsertHere;    // V
        default: return nil;
    }
}

- (CGEventRef)handleKeyDown:(CGEventRef)event proxy:(CGEventTapProxy)proxy {
    int64_t code = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

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
    void (^cb)(void) = nil;
    // Esc: صاحبش خودش تصمیم می‌گیرد (کارت راهنما یا سشن) و می‌گوید مصرف شد یا نه.
    // هم‌زمان، چون همین‌جا باید بدانیم رویداد را برگردانیم یا ببلعیم؛ دیر بگوییم،
    // Esc هم به اپ زیرین رسیده و هم کار ما را کرده.
    if (code == 53 && flags == 0) {
        BOOL (^esc)(void) = self.onEscape;
        return (esc && esc()) ? NULL : event;
    }
    if (flags == kCGEventFlagMaskAlternate) cb = [self actionForCode:code];
    if (cb) {
        dispatch_async(dispatch_get_main_queue(), cb);
        return NULL;
    }
    return event;
}

- (CGEventRef)handleProxy:(CGEventTapProxy)proxy type:(CGEventType)type event:(CGEventRef)event {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (_tap) CGEventTapEnable(_tap, true);
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
