import AppKit

// مدل تسمه‌نقاله: پنل فقط بافر خاکستری است؛ هر تکه قطعی همان لحظه سر کرسرِ
// اپ مقصد درج می‌شود. اگر اپ جلویی عوض شود درج می‌ایستد و صف جمع می‌شود.
final class DictationSession: NSObject, EngineDelegate {
    let engine: Engine
    private let panel: PanelController
    private let injector = Injector()

    private(set) var target: NSRunningApplication?
    private var queue: [String] = []        // تکه‌های قطعیِ هنوز درج‌نشده
    private var transcript: [String] = []   // همه قطعی‌ها برای کپی پایانی
    private var interim = ""
    private var statusText = ""
    private var errorState = false
    private var listening = false
    var locked = false

    private var pasteBuf: [String] = []
    private var pasteTimer: Timer?

    private let sessionFile: URL
    private var finished = false
    var onFinish: (() -> Void)?

    init(engine: Engine, panel: PanelController) {
        self.engine = engine
        self.panel = panel
        self.sessionFile = Zem.sessionsDir
            .appendingPathComponent("app-" + Zem.idFmt.string(from: Date()) + ".txt")
        super.init()
    }

    func start() {
        target = NSWorkspace.shared.frontmostApplication
        zlog("session: start target=\(target?.bundleIdentifier ?? "?") engine=\(Settings.shared.engineName) lang=\(Settings.shared.lang)")
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(frontChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        panel.onClose = { [weak self] in self?.finish() }
        panel.onToggleLock = { [weak self] in
            guard let self else { return }
            self.locked.toggle()
            self.pump()
        }
        panel.onRetarget = { [weak self] in self?.retarget() }
        panel.onToggleLang = { [weak self] in self?.toggleLang() }
        panel.show()
        if !Injector.accessibilityOK {
            statusText = "دسترسی Accessibility نیست؛ درج کار نمی‌کند، متن آخر کار کپی می‌شود"
        }
        engine.delegate = self
        engine.start(lang: Settings.shared.lang)
        render()
    }

    // MARK: EngineDelegate (روی نخ اصلی)

    func engineInterim(_ text: String) {
        interim = text
        render()
    }

    func engineFinal(_ text: String) {
        transcript.append(text)
        appendToSessionFile(text)
        queue.append(text)
        pump()
    }

    func engineStatus(_ s: EngineStatus) {
        errorState = false
        listening = false
        switch s {
        case .idle:
            statusText = ""
        case .connecting:
            statusText = "در حال اتصال…"
        case .listening:
            listening = true
            statusText = "دارم گوش می‌دم"
        case .reconnecting:
            statusText = "اتصال ناپایدار، دوباره وصل می‌شم…"
        case .gaveUp(let msg):
            errorState = true
            statusText = msg
        case .pageNeeded:
            errorState = true
            statusText = "صفحه کروم باز نیست؛ از منوی زمزمه بازش کن"
        }
        render()
    }

    func engineLevel(_ rms: Float) {
        panel.pulse(level: rms)
    }

    // MARK: تسمه‌نقاله

    private var targetIsFront: Bool {
        guard let t = target, let f = NSWorkspace.shared.frontmostApplication else { return false }
        return t.processIdentifier == f.processIdentifier
    }

    private func pump() {
        defer { render() }
        guard !queue.isEmpty else { return }
        let mode = Settings.shared.insertMode(for: target?.bundleIdentifier)
        guard mode != .collect, !locked else { return }
        guard Injector.accessibilityOK, targetIsFront, !Injector.secureInputActive else { return }
        let chunk = queue.joined(separator: " ") + " "
        queue.removeAll()
        switch mode {
        case .type:
            injector.type(chunk, delayMicros: Settings.shared.typeDelayMicros)
        case .paste:
            // ادغام تکه‌ها با تایمر کوتاه: پیست‌های کمتر، برای RDP امن‌تر
            pasteBuf.append(chunk)
            pasteTimer?.invalidate()
            pasteTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                self?.flushPasteBuf()
            }
        case .collect:
            break
        }
    }

    private func flushPasteBuf() {
        pasteTimer?.invalidate()
        pasteTimer = nil
        guard !pasteBuf.isEmpty else { return }
        let text = pasteBuf.joined()
        pasteBuf.removeAll()
        injector.paste(text, delayMicros: Settings.shared.pasteDelayMicros)
    }

    @objc private func frontChanged(_ n: Notification) {
        pump()    // برگشت به مقصد: صف خالی می‌شود
        render()
    }

    private func retarget() {
        // مقصد جدید: همین اپ جلویی؛ صف همین‌جا خالی می‌شود
        target = NSWorkspace.shared.frontmostApplication
        zlog("session: retarget to \(target?.bundleIdentifier ?? "?")")
        pump()
    }

    private func toggleLang() {
        let newLang = Settings.shared.lang == "fa-IR" ? "en-US" : "fa-IR"
        Settings.shared.lang = newLang
        engine.setLang(newLang)
        render()
    }

    // MARK: پایان (Esc یا دابل‌تپ دوباره)

    func finish() {
        guard !finished else { return }
        finished = true
        engine.stop()          // موتور قبل از بستن salvage می‌کند و finalها همین‌جا می‌رسند
        flushPasteBuf()
        // باقی صف: اگر مقصد جلوست درج کن، وگرنه فقط کپی نجاتش می‌دهد
        if !queue.isEmpty, Injector.accessibilityOK, targetIsFront, !Injector.secureInputActive,
           Settings.shared.insertMode(for: target?.bundleIdentifier) == .type {
            injector.type(queue.joined(separator: " ") + " ", delayMicros: Settings.shared.typeDelayMicros)
            queue.removeAll()
        } else if !queue.isEmpty, Injector.accessibilityOK, targetIsFront, !Injector.secureInputActive,
                  Settings.shared.insertMode(for: target?.bundleIdentifier) == .paste {
            injector.paste(queue.joined(separator: " ") + " ", delayMicros: Settings.shared.pasteDelayMicros)
            queue.removeAll()
        }
        // بیمه: کل متن سشن، یک بار، ماندگار در کلیپ‌بورد (نقطه اتصال پاس اصلاح متن)
        let full = TextRefiners.active.refine(transcript.joined(separator: " ").trimmingCharacters(in: .whitespaces))
        if !full.isEmpty { Injector.copyFinal(full) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        panel.hide()
        zlog("session: finished, \(transcript.count) chunks, \(full.count) chars copied")
        onFinish?()
    }

    // MARK: کمکی

    private func appendToSessionFile(_ chunk: String) {
        let line = chunk + "\n"
        guard let d = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: sessionFile) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: d)
        } else {
            try? d.write(to: sessionFile)
        }
    }

    private func render() {
        var m = PanelModel()
        m.interim = interim
        m.status = statusText
        m.queued = queue.count + pasteBuf.count
        m.locked = locked
        m.listening = listening
        m.error = errorState
        m.lang = Settings.shared.lang
        m.waitingForTarget = !queue.isEmpty && !targetIsFront
        m.targetName = target?.localizedName ?? ""
        panel.render(m)
    }
}
