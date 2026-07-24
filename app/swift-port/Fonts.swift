import AppKit

enum Fonts {
    // Vazirmatn از Resources اپ ثبت می‌شود؛ اگر نبود، فونت سیستم (فارسی را درست می‌کشد)
    static func registerBundled() {
        guard let res = Bundle.main.resourceURL else { return }
        for name in ["Vazirmatn-Regular.ttf", "Vazirmatn-Medium.ttf"] {
            let u = res.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: u.path) {
                CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil)
            }
        }
    }

    static func ui(_ size: CGFloat, medium: Bool = false) -> NSFont {
        NSFont(name: medium ? "Vazirmatn-Medium" : "Vazirmatn-Regular", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: medium ? .medium : .regular)
    }
}
