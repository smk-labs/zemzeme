import AppKit
import Carbon.HIToolbox

// درج متن در اپ مقصد: تایپ مستقیم با رویداد یونیکد، یا کپی و Cmd+V.
// چون پنل فوکس نمی‌گیرد، کرسر کاربر همان‌جاست که بود و متن همان‌جا می‌نشیند.
final class Injector {
    private let q = DispatchQueue(label: "zemzeme.inject")

    static var accessibilityOK: Bool { AXIsProcessTrusted() }

    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static var secureInputActive: Bool { IsSecureEventInputEnabled() }

    // تایپ مستقیم: تکه‌های حداکثر ۱۸ واحد UTF-16 در هر رویداد
    func type(_ text: String, delayMicros: UInt32) {
        q.async {
            let units = Array(text.utf16)
            var i = 0
            while i < units.count {
                let n = min(18, units.count - i)
                let slice = Array(units[i..<(i + n)])
                if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                    slice.withUnsafeBufferPointer { p in
                        down.keyboardSetUnicodeString(stringLength: n, unicodeString: p.baseAddress)
                    }
                    down.post(tap: .cgSessionEventTap)
                }
                if let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                    up.post(tap: .cgSessionEventTap)
                }
                if delayMicros > 0 { usleep(delayMicros) }
                i += n
            }
        }
    }

    // پیست تکه‌ای: کپی با نشونه transient (تاریخچه‌گیرها رد می‌کنند)، Cmd+V،
    // و برگرداندن کلیپ‌بورد قبلی کاربر. تاخیر برای همگام شدن کلیپ‌بورد RDP.
    func paste(_ text: String, delayMicros: UInt32) {
        DispatchQueue.main.async {
            let pb = NSPasteboard.general
            let savedString = pb.string(forType: .string)
            let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
            pb.declareTypes([.string, transient], owner: nil)
            pb.setString(text, forType: .string)
            pb.setString("", forType: transient)
            self.q.async {
                usleep(delayMicros)
                self.sendCmdV()
                usleep(500_000)
                DispatchQueue.main.async {
                    // فقط متن ساده قبلی برمی‌گردد؛ برای بیمه پایانی copyFinal جدا هست
                    if let s = savedString {
                        let pb2 = NSPasteboard.general
                        pb2.declareTypes([.string], owner: nil)
                        pb2.setString(s, forType: .string)
                    }
                }
            }
        }
    }

    private func sendCmdV() {
        if let d = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true) {
            d.flags = .maskCommand
            d.post(tap: .cgSessionEventTap)
        }
        if let u = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) {
            u.flags = .maskCommand
            u.post(tap: .cgSessionEventTap)
        }
    }

    // بیمه پایانی: کپی معمولی و ماندگار کل متن سشن
    static func copyFinal(_ text: String) {
        let pb = NSPasteboard.general
        pb.declareTypes([.string], owner: nil)
        pb.setString(text, forType: .string)
    }
}
