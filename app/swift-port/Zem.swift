import Foundation

// مسیرها و لاگ مشترک اپ
enum Zem {
    // ریشه پروژه: Zemzeme.app کنار serve.py زندگی می‌کند
    // exe: dictate/Zemzeme.app/Contents/MacOS/zemzeme یا dictate/app/.build/release/zemzeme
    static let root: URL = {
        var u = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        for _ in 0..<4 { u.deleteLastPathComponent() }
        if FileManager.default.fileExists(atPath: u.appendingPathComponent("serve.py").path) { return u }
        return URL(fileURLWithPath: NSHomeDirectory() + "/Projects/hobby/mem/dictate")
    }()
    static let sessionsDir = root.appendingPathComponent("sessions")
    static let logFile = root.appendingPathComponent("app.log")

    static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    static let idFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return f
    }()
}

private let zlogLock = NSLock()

func zlog(_ message: String) {
    let line = Zem.timeFmt.string(from: Date()) + " " + message + "\n"
    guard let d = line.data(using: .utf8) else { return }
    zlogLock.lock()
    defer { zlogLock.unlock() }
    if let h = try? FileHandle(forWritingTo: Zem.logFile) {
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: d)
    } else {
        try? d.write(to: Zem.logFile)
    }
    FileHandle.standardError.write(d)
}

// اعداد فارسی برای همه متن‌های رابط
func faDigits(_ s: String) -> String {
    let map: [Character: Character] = [
        "0": "۰", "1": "۱", "2": "۲", "3": "۳", "4": "۴",
        "5": "۵", "6": "۶", "7": "۷", "8": "۸", "9": "۹",
    ]
    return String(s.map { map[$0] ?? $0 })
}
