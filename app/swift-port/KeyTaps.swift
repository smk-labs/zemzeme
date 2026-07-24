import AppKit

// تپ سبک Esc: فقط در طول سشن فعال است؛ Esc خالی را می‌بلعد و سشن را می‌بندد
final class EscTap {
    var onEsc: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func enable() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let cb: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<EscTap>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                me.reenable()
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown,
               event.getIntegerValueField(.keyboardEventKeycode) == 53,
               event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty {
                DispatchQueue.main.async { me.onEsc?() }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: cb,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            zlog("esc tap: create failed (accessibility?)")
            return
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func reenable() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
    }

    func disable() {
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            CFMachPortInvalidate(t)
        }
        source = nil
        tap = nil
    }
}

// تشخیص دابل‌تپ Command راست داخل خود اپ (آزمایشی؛ پیش‌فرض خاموش).
// همان ترفند lazy کارابینر: تپ تنها هیچ‌چیز به اپ‌ها نمی‌رساند (توی RDP کلید ویندوز نمی‌خورد)،
// ولی وقتی با کلید دیگری ترکیب شود، رویداد نگه‌داشته‌شده دوباره تزریق می‌شود تا ترکیب‌ها سالم بمانند.
// اگر اپ بمیرد، سیستم تپ را خودش برمی‌دارد و کیبورد به حالت عادی برمی‌گردد.
final class RCmdTap {
    var onDoubleTap: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var physDown = false
    private var emitted = false
    private var savedDown: CGEvent?
    private var lastTapAt: Double = 0
    private static let rightCmdBit: UInt64 = 0x10   // NX_DEVICERCMDKEYMASK

    func enable() {
        guard tap == nil else { return }
        let mask = CGEventMask((1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue))
        let cb: CGEventTapCallBack = { proxy, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<RCmdTap>.fromOpaque(info).takeUnretainedValue()
            return me.handle(proxy: proxy, type: type, event: event)
        }
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: cb,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            zlog("rcmd tap: create failed (accessibility?)")
            return
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        zlog("rcmd tap: enabled")
    }

    func disable() {
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            CFMachPortInvalidate(t)
        }
        source = nil
        tap = nil
        physDown = false
        emitted = false
        savedDown = nil
        zlog("rcmd tap: disabled")
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged, event.getIntegerValueField(.keyboardEventKeycode) == 54 {
            let isDown = event.flags.rawValue & Self.rightCmdBit != 0
            if isDown {
                physDown = true
                emitted = false
                savedDown = event.copy()
                return nil    // فعلا از همه پنهان؛ اگر ترکیب شد دوباره تزریق می‌شود
            }
            // رها شدن کلید
            let wasEmitted = emitted
            physDown = false
            emitted = false
            savedDown = nil
            if wasEmitted { return Unmanaged.passUnretained(event) }
            // تپِ تنها: بلعیده؛ شمارش دابل‌تپ
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastTapAt < 0.4 {
                lastTapAt = 0
                DispatchQueue.main.async { [weak self] in self?.onDoubleTap?() }
            } else {
                lastTapAt = now
            }
            return nil
        }
        if type == .keyDown, physDown, !emitted {
            // کلید دیگری آمد: right command واقعا مودیفایر بود؛ اول رویداد نگه‌داشته را بفرست
            if let saved = savedDown {
                saved.tapPostEvent(proxy)
            }
            emitted = true
            return Unmanaged.passUnretained(event)
        }
        return Unmanaged.passUnretained(event)
    }
}
