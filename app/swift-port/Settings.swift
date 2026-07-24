import Foundation

// شیوه درج متن در اپ مقصد
enum InsertMode: String, CaseIterable {
    case type      // تایپ مستقیم با رویداد یونیکد
    case paste     // پیست تکه‌ای (برای ریموت دسکتاپ امن‌تر)
    case collect   // فقط جمع کن؛ درج نکن (کپی آخر کار)

    var label: String {
        switch self {
        case .type: return "تایپ مستقیم"
        case .paste: return "پیست تکه‌ای"
        case .collect: return "فقط جمع کن"
        }
    }
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    var lang: String {
        get { d.string(forKey: "lang") ?? "fa-IR" }
        set { d.set(newValue, forKey: "lang") }
    }

    var engineName: String {
        get { d.string(forKey: "engine") ?? "google" }
        set { d.set(newValue, forKey: "engine") }
    }

    var insertMode: InsertMode {
        get { InsertMode(rawValue: d.string(forKey: "insertMode") ?? "") ?? .type }
        set { d.set(newValue.rawValue, forKey: "insertMode") }
    }

    // استثنای هر اپ: شناسه باندل به شیوه درج.
    // Windows App پیش‌فرض پیست می‌گیرد چون فوروارد یونیکد مصنوعی در RDP نامطمئن است.
    var perApp: [String: String] {
        get { d.dictionary(forKey: "perApp") as? [String: String] ?? ["com.microsoft.rdc.macos": "paste"] }
        set { d.set(newValue, forKey: "perApp") }
    }

    func insertMode(for bundleId: String?) -> InsertMode {
        if let b = bundleId, let raw = perApp[b], let m = InsertMode(rawValue: raw) { return m }
        return insertMode
    }

    // تشخیص دابل‌تپ داخل خود اپ (آزمایشی). پیش‌فرض خاموش: Karabiner کار را می‌کند.
    var internalHotkey: Bool {
        get { d.bool(forKey: "internalHotkey") }
        set { d.set(newValue, forKey: "internalHotkey") }
    }

    // مکث بین رویدادهای تایپ (میکروثانیه)
    var typeDelayMicros: UInt32 {
        let ms = d.object(forKey: "typeDelayMs") == nil ? 1.0 : d.double(forKey: "typeDelayMs")
        return UInt32(max(0, ms) * 1000)
    }

    // تاخیر بین کپی و Cmd+V در حالت پیست؛ برای همگام شدن کلیپ‌بورد ریموت دسکتاپ
    var pasteDelayMicros: UInt32 {
        let ms = d.object(forKey: "pasteDelayMs") == nil ? 350.0 : d.double(forKey: "pasteDelayMs")
        return UInt32(max(0, ms) * 1000)
    }
}
