import AppKit

struct PanelModel {
    var interim = ""
    var status = ""
    var queued = 0
    var locked = false
    var listening = false
    var error = false
    var lang = "fa-IR"
    var waitingForTarget = false
    var targetName = ""
}

// نوار شناور باریک: بدون گرفتن فوکس، روی همه Space ها و فول‌اسکرین.
// فقط بافر خاکستری و وضعیت را نشان می‌دهد؛ متن قطعی در خود اپ مقصد می‌نشیند.
final class PanelController: NSObject {
    private let W: CGFloat = 500
    private let H: CGFloat = 46

    private var panel: NSPanel!
    private let effect = NSVisualEffectView()
    private let dot = NSView()
    private let text = NSTextField(labelWithString: "")
    private let chipBg = NSView()
    private let chipLabel = NSTextField(labelWithString: "")
    private var btnClose: NSButton!
    private var btnLang: NSButton!
    private var btnTarget: NSButton!
    private var btnLock: NSButton!

    var onClose: (() -> Void)?
    var onToggleLock: (() -> Void)?
    var onRetarget: (() -> Void)?
    var onToggleLang: (() -> Void)?

    private var pulsing = false
    private var model = PanelModel()

    override init() {
        super.init()
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        effect.frame = NSRect(x: 0, y: 0, width: W, height: H)
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 15
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        panel.contentView = effect

        dot.wantsLayer = true
        dot.frame = NSRect(x: W - 25, y: (H - 9) / 2, width: 9, height: 9)
        dot.layer?.cornerRadius = 4.5
        effect.addSubview(dot)

        text.font = Fonts.ui(15)
        text.textColor = .secondaryLabelColor
        text.alignment = .right
        text.lineBreakMode = .byTruncatingHead
        text.usesSingleLineMode = true
        text.cell?.truncatesLastVisibleLine = true
        effect.addSubview(text)

        chipBg.wantsLayer = true
        chipBg.layer?.cornerRadius = 9
        chipBg.isHidden = true
        effect.addSubview(chipBg)
        chipLabel.font = Fonts.ui(11)
        chipLabel.textColor = .secondaryLabelColor
        chipLabel.alignment = .center
        chipBg.addSubview(chipLabel)

        btnClose = makeButton("xmark", "بستن و درج همه (Esc)", #selector(closeTap))
        btnLang = NSButton(title: "فا", target: self, action: #selector(langTap))
        btnLang.isBordered = false
        btnLang.font = Fonts.ui(11, medium: true)
        btnLang.contentTintColor = .secondaryLabelColor
        btnLang.toolTip = "تغییر زبان"
        effect.addSubview(btnLang)
        btnTarget = makeButton("scope", "مقصد همینجا: درج در همین اپ جلویی", #selector(targetTap))
        btnLock = makeButton("lock.open", "قفل: درج نکن، فقط جمع کن", #selector(lockTap))

        layoutViews()
        applyColors()
    }

    private func makeButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        let b = NSButton(image: img ?? NSImage(), target: self, action: action)
        b.isBordered = false
        b.setButtonType(.momentaryChange)
        b.contentTintColor = .secondaryLabelColor
        b.toolTip = tip
        effect.addSubview(b)
        return b
    }

    private func layoutViews() {
        // چیدمان راست‌به‌چپ با فریم دستی: نقطه سمت راست، دکمه‌ها سمت چپ
        let cy = (H - 24) / 2
        btnClose.frame = NSRect(x: 10, y: cy, width: 24, height: 24)
        btnLang.frame = NSRect(x: 38, y: cy, width: 26, height: 24)
        btnTarget.frame = NSRect(x: 66, y: cy, width: 24, height: 24)
        btnLock.frame = NSRect(x: 94, y: cy, width: 24, height: 24)

        let chipW = chipBg.isHidden ? 0 : chipBg.frame.width
        let left = 124 + chipW + (chipBg.isHidden ? 0 : 8)
        let right = W - 25 - 12
        text.frame = NSRect(x: left, y: (H - 22) / 2, width: max(40, right - left), height: 22)
        if !chipBg.isHidden {
            chipBg.frame.origin = NSPoint(x: 124, y: (H - 18) / 2)
        }
    }

    private func applyColors() {
        effect.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        chipBg.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
    }

    // MARK: نمایش

    func show() {
        applyColors()
        if let saved = UserDefaults.standard.string(forKey: "panelOrigin") {
            let parts = saved.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                let p = NSPoint(x: parts[0], y: parts[1])
                if NSScreen.screens.contains(where: { NSPointInRect(p, $0.frame) }) {
                    panel.setFrameOrigin(p)
                    panel.orderFrontRegardless()
                    return
                }
            }
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let f = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(NSPoint(x: f.midX - W / 2, y: f.minY + 90))
        panel.orderFrontRegardless()
    }

    func hide() {
        let o = panel.frame.origin
        UserDefaults.standard.set("\(o.x),\(o.y)", forKey: "panelOrigin")
        stopPulse()
        panel.orderOut(nil)
    }

    func render(_ m: PanelModel) {
        model = m
        // متن: خاکستری لحظه‌ای؛ وقتی نیست، خط وضعیت
        if !m.interim.isEmpty {
            text.stringValue = m.interim
            text.font = Fonts.ui(15)
            text.textColor = .secondaryLabelColor
        } else {
            text.stringValue = m.status
            text.font = Fonts.ui(12.5)
            text.textColor = m.error ? .systemRed : .tertiaryLabelColor
        }
        text.alignment = m.lang == "en-US" && !m.interim.isEmpty ? .left : .right

        // چیپ صف/قفل
        var chip = ""
        if m.locked {
            chip = "قفل"
        } else if m.queued > 0 {
            chip = faDigits("\(m.queued)") + " در صف"
        }
        if m.waitingForTarget && !m.targetName.isEmpty {
            chipBg.toolTip = "برگرد به \(m.targetName) تا درج ادامه پیدا کند"
        } else {
            chipBg.toolTip = nil
        }
        if chip.isEmpty {
            chipBg.isHidden = true
        } else {
            chipBg.isHidden = false
            chipLabel.stringValue = chip
            chipLabel.sizeToFit()
            let w = chipLabel.frame.width + 16
            chipBg.frame = NSRect(x: 124, y: (H - 18) / 2, width: w, height: 18)
            chipLabel.frame = NSRect(x: 8, y: 0, width: w - 16, height: 17)
        }

        // دکمه‌ها
        btnLang.title = m.lang == "fa-IR" ? "فا" : "EN"
        let lockImg = NSImage(systemSymbolName: m.locked ? "lock.fill" : "lock.open",
                              accessibilityDescription: "قفل")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        btnLock.image = lockImg
        btnLock.contentTintColor = m.locked ? .controlAccentColor : .secondaryLabelColor

        // نقطه
        let color: NSColor = m.error ? .systemGray : (m.listening ? NSColor(red: 0.88, green: 0.19, blue: 0.19, alpha: 1) : .systemOrange)
        dot.layer?.backgroundColor = color.cgColor
        if m.listening && !pulsing { startPulse() }
        if !m.listening && pulsing { stopPulse() }

        layoutViews()
    }

    func pulse(level: Float) {
        let s = 1 + CGFloat(min(max(level, 0), 1)) * 0.5
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.layer?.setAffineTransform(CGAffineTransform(scaleX: s, y: s))
        CATransaction.commit()
    }

    private func startPulse() {
        pulsing = true
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1.0
        a.toValue = 0.35
        a.duration = 0.6
        a.autoreverses = true
        a.repeatCount = .infinity
        dot.layer?.add(a, forKey: "pulse")
    }

    private func stopPulse() {
        pulsing = false
        dot.layer?.removeAnimation(forKey: "pulse")
        dot.layer?.opacity = 1
    }

    // MARK: اکشن دکمه‌ها

    @objc private func closeTap() { onClose?() }
    @objc private func lockTap() { onToggleLock?() }
    @objc private func targetTap() { onRetarget?() }
    @objc private func langTap() { onToggleLang?() }

    // MARK: اسکرین‌شات برای بازبینی طراحی (بدون نیاز به اجازه ضبط صفحه)

    private static func demo(interim: String = "", status: String = "", queued: Int = 0,
                             locked: Bool = false, listening: Bool = false, error: Bool = false,
                             waiting: Bool = false, target: String = "") -> PanelModel {
        var m = PanelModel()
        m.interim = interim
        m.status = status
        m.queued = queued
        m.locked = locked
        m.listening = listening
        m.error = error
        m.waitingForTarget = waiting
        m.targetName = target
        return m
    }

    func makeShots(dir: String) {
        var states: [(String, PanelModel)] = []
        states.append(("listening", Self.demo(interim: "دارم متن نمونه را برای نوار زمزمه می‌گویم که ببینیم", listening: true)))
        states.append(("status", Self.demo(status: "دارم گوش می‌دم", listening: true)))
        states.append(("queued", Self.demo(interim: "این تکه هنوز خاکستری است", queued: 3, listening: true, waiting: true, target: "Windows App")))
        states.append(("locked", Self.demo(status: "دارم گوش می‌دم", locked: true, listening: true)))
        states.append(("error", Self.demo(status: "شبکه ناپایداره؛ برای تلاش دوباره دابل‌تپ کن", error: true)))
        panel.orderFrontRegardless()
        for (name, m) in states {
            render(m)
            effect.layoutSubtreeIfNeeded()
            guard let rep = effect.bitmapImageRepForCachingDisplay(in: effect.bounds) else { continue }
            effect.cacheDisplay(in: effect.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("panel-\(name).png"))
            }
        }
        panel.orderOut(nil)
    }
}
