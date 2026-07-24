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

+ (void)sendCmdV {
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)kVK_ANSI_V, true);
    if (down) {
        CGEventSetFlags(down, kCGEventFlagMaskCommand);
        CGEventPost(kCGSessionEventTap, down);
        CFRelease(down);
    }
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)kVK_ANSI_V, false);
    if (up) {
        CGEventSetFlags(up, kCGEventFlagMaskCommand);
        CGEventPost(kCGSessionEventTap, up);
        CFRelease(up);
    }
}

// بیمه پایانی: کپی معمولی و ماندگار کل متن سشن
+ (void)copyFinal:(NSString *)text {
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb declareTypes:@[NSPasteboardTypeString] owner:nil];
    [pb setString:text forType:NSPasteboardTypeString];
}

@end

// ---------- ZSessionKeys ----------
// فقط در طول سشن فعال است. Esc خالی سشن را می‌بندد؛ شورتکات‌های ⌥ هم اینجا:
// ⌥Space مکث/ادامه، ⌥C کپی تا اینجا، ⌥V درج همینجا. بیرون از سشن هیچ‌کدام گرفته نمی‌شود.

@interface ZSessionKeys ()
- (CGEventRef)handleType:(CGEventType)type event:(CGEventRef)event;
@end

static CGEventRef zKeysCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    ZSessionKeys *me = (__bridge ZSessionKeys *)info;
    return [me handleType:type event:event];
}

@implementation ZSessionKeys {
    CFMachPortRef _tap;
    CFRunLoopSourceRef _source;
}

- (void)enable {
    if (_tap) return;
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown);
    _tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                            mask, zKeysCallback, (__bridge void *)self);
    if (!_tap) {
        ZLog(@"session keys tap: create failed (accessibility?)");
        return;
    }
    _source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _tap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
    CGEventTapEnable(_tap, true);
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
}

- (CGEventRef)handleType:(CGEventType)type event:(CGEventRef)event {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (_tap) CGEventTapEnable(_tap, true);
        return event;
    }
    if (type != kCGEventKeyDown) return event;
    int64_t code = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    CGEventFlags flags = CGEventGetFlags(event)
        & (kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate
           | kCGEventFlagMaskControl | kCGEventFlagMaskShift);

    void (^cb)(void) = nil;
    if (code == 53 && flags == 0) cb = self.onEsc;
    else if (flags == kCGEventFlagMaskAlternate) {
        if (code == 49) cb = self.onAltSpace;       // Space
        else if (code == 8) cb = self.onAltC;       // C
        else if (code == 9) cb = self.onAltV;       // V
    }
    if (cb) {
        dispatch_async(dispatch_get_main_queue(), cb);
        return NULL;
    }
    return event;
}

@end

// ---------- ZRCmdTap ----------
// تشخیص دابل‌تپ Command راست داخل خود اپ (آزمایشی؛ پیش‌فرض خاموش).
// همان ترفند lazy کارابینر: تپ تنها هیچ‌چیز به اپ‌ها نمی‌رساند (توی RDP کلید
// ویندوز نمی‌خورد)، ولی اگر با کلید دیگری ترکیب شد، رویداد نگه‌داشته دوباره
// تزریق می‌شود تا ترکیب‌ها سالم بمانند. اگر اپ بمیرد، سیستم تپ را برمی‌دارد.

static const uint64_t kRightCmdBit = 0x10;    // NX_DEVICERCMDKEYMASK

@interface ZRCmdTap ()
- (CGEventRef)handleProxy:(CGEventTapProxy)proxy type:(CGEventType)type event:(CGEventRef)event;
@end

static CGEventRef zRCmdCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    ZRCmdTap *me = (__bridge ZRCmdTap *)info;
    return [me handleProxy:proxy type:type event:event];
}

@implementation ZRCmdTap {
    CFMachPortRef _tap;
    CFRunLoopSourceRef _source;
    BOOL _physDown;
    BOOL _emitted;
    CGEventRef _savedDown;
    CFAbsoluteTime _lastTapAt;
}

- (void)enable {
    if (_tap) return;
    CGEventMask mask = CGEventMaskBit(kCGEventFlagsChanged) | CGEventMaskBit(kCGEventKeyDown);
    _tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                            mask, zRCmdCallback, (__bridge void *)self);
    if (!_tap) {
        ZLog(@"rcmd tap: create failed (accessibility?)");
        return;
    }
    _source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _tap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
    CGEventTapEnable(_tap, true);
    ZLog(@"rcmd tap: enabled");
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
    ZLog(@"rcmd tap: disabled");
}

- (CGEventRef)handleProxy:(CGEventTapProxy)proxy type:(CGEventType)type event:(CGEventRef)event {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (_tap) CGEventTapEnable(_tap, true);
        return event;
    }
    if (type == kCGEventFlagsChanged
        && CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) == 54) {
        BOOL isDown = (CGEventGetFlags(event) & kRightCmdBit) != 0;
        if (isDown) {
            _physDown = YES;
            _emitted = NO;
            if (_savedDown) CFRelease(_savedDown);
            _savedDown = CGEventCreateCopy(event);
            return NULL;    // فعلا از همه پنهان؛ اگر ترکیب شد دوباره تزریق می‌شود
        }
        BOOL wasEmitted = _emitted;
        _physDown = NO;
        _emitted = NO;
        if (_savedDown) {
            CFRelease(_savedDown);
            _savedDown = NULL;
        }
        if (wasEmitted) return event;
        // تپِ تنها: بلعیده؛ شمارش دابل‌تپ
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - _lastTapAt < 0.4) {
            _lastTapAt = 0;
            void (^cb)(void) = self.onDoubleTap;
            if (cb) dispatch_async(dispatch_get_main_queue(), cb);
        } else {
            _lastTapAt = now;
        }
        return NULL;
    }
    if (type == kCGEventKeyDown && _physDown && !_emitted) {
        // کلید دیگری آمد: right command واقعا مودیفایر بود؛ اول رویداد نگه‌داشته را بفرست
        if (_savedDown) CGEventTapPostEvent(proxy, _savedDown);
        _emitted = YES;
        return event;
    }
    return event;
}

@end
