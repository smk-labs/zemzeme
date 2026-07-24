import Foundation

enum EngineStatus: Equatable {
    case idle
    case connecting
    case listening
    case reconnecting(attempt: Int)
    case gaveUp(String)     // پیام فارسی روشن برای پنل
    case pageNeeded         // موتور کروم: صفحه باز نیست
}

// موتورها همه کال‌بک‌ها را روی نخ اصلی تحویل می‌دهند
protocol EngineDelegate: AnyObject {
    func engineInterim(_ text: String)   // کل متن خاکستری لحظه‌ای فعلی
    func engineFinal(_ text: String)     // یک تکه قطعی‌شده
    func engineStatus(_ s: EngineStatus)
    func engineLevel(_ rms: Float)       // سطح صدا ۰ تا ۱ برای ضربان
}

// موتور pluggable: امروز گوگل مستقیم و صفحه کروم؛ فردا موتور آفلاین (Qwen3-ASR یا ویسپر فارسی)
protocol Engine: AnyObject {
    var delegate: EngineDelegate? { get set }
    func start(lang: String)
    func setLang(_ lang: String)
    func stop()
}

// نقطه اتصال آینده: پاس اصلاح متن (LLM لوکال یا ابزار گرامر).
// متن کامل سشن می‌رود تو، متن اصلاح‌شده می‌آید بیرون؛ خروجی به کلیپ‌بورد پایانی می‌رود.
protocol TextRefiner {
    func refine(_ text: String) -> String
}

struct IdentityRefiner: TextRefiner {
    func refine(_ text: String) -> String { text }
}

enum TextRefiners {
    static var active: TextRefiner = IdentityRefiner()
}
