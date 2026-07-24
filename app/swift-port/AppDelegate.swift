import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let panel = PanelController()
    private var session: DictationSession?
    private let escTap = EscTap()
    private let rcmdTap = RCmdTap()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // فقط یک نمونه
        if let bid = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
                .filter { $0 != NSRunningApplication.current }
            if !others.isEmpty {
                zlog("app: another instance is running, exiting")
                NSApp.terminate(nil)
                return
            }
        }
        try? FileManager.default.createDirectory(at: Zem.sessionsDir, withIntermediateDirectories: true)
        Fonts.registerBundled()
        setupStatusItem()
        rcmdTap.onDoubleTap = { [weak self] in self?.toggleSession() }
        if Settings.shared.internalHotkey { rcmdTap.enable() }

        // حالت اسکرین‌شات طراحی: zemzeme --uishot <dir>
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--uishot"), args.count > i + 1 {
            panel.makeShots(dir: args[i + 1])
            NSApp.terminate(nil)
            return
        }

        if !Injector.accessibilityOK { Injector.promptAccessibility() }
        zlog("app: launched root=\(Zem.root.path) ax=\(Injector.accessibilityOK)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        session?.finish()
        escTap.disable()
        rcmdTap.disable()
    }

    // MARK: URL: zemzeme://toggle | start | stop

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        let url = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue ?? ""
        zlog("app: url \(url)")
        switch url {
        case "zemzeme://start":
            if session == nil { startSession() }
        case "zemzeme://stop":
            session?.finish()
        default:
            toggleSession()
        }
    }

    private func toggleSession() {
        if session == nil { startSession() } else { session?.finish() }
    }

    private func startSession() {
        let engine: Engine = Settings.shared.engineName == "chrome" ? ChromeRelayEngine() : GoogleEngine()
        let s = DictationSession(engine: engine, panel: panel)
        session = s
        s.onFinish = { [weak self] in
            self?.session = nil
            self?.escTap.disable()
        }
        escTap.onEsc = { [weak self] in self?.session?.finish() }
        escTap.enable()
        s.start()
    }

    // MARK: منوبار

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "زمزمه")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let active = session != nil

        item(menu, active ? "پایان دیکته" : "شروع دیکته", #selector(menuToggle))
        menu.addItem(.separator())

        header(menu, "زبان")
        item(menu, "فارسی", #selector(menuLangFa)).state = Settings.shared.lang == "fa-IR" ? .on : .off
        item(menu, "English", #selector(menuLangEn)).state = Settings.shared.lang == "en-US" ? .on : .off
        menu.addItem(.separator())

        header(menu, "موتور")
        let g = item(menu, "گوگل مستقیم", #selector(menuEngineGoogle))
        g.state = Settings.shared.engineName == "google" ? .on : .off
        g.isEnabled = !active
        let c = item(menu, "صفحه کروم (فال‌بک)", #selector(menuEngineChrome))
        c.state = Settings.shared.engineName == "chrome" ? .on : .off
        c.isEnabled = !active
        item(menu, "باز کردن صفحه موتور کروم", #selector(menuOpenChromePage))
        menu.addItem(.separator())

        header(menu, "درج متن")
        for mode in InsertMode.allCases {
            let mi = item(menu, mode.label, #selector(menuInsertMode(_:)))
            mi.representedObject = mode.rawValue
            mi.state = Settings.shared.insertMode == mode ? .on : .off
        }
        menu.addItem(.separator())

        let hk = item(menu, "هاتکی داخلی بدون Karabiner (آزمایشی)", #selector(menuToggleHotkey))
        hk.state = Settings.shared.internalHotkey ? .on : .off
        hk.toolTip = "اول رول Karabiner را خاموش کن، وگرنه دابل‌تپ به اپ نمی‌رسد"
        item(menu, "پوشه سشن‌ها", #selector(menuOpenSessions))
        item(menu, "دسترسی‌ها در تنظیمات سیستم", #selector(menuOpenAccessibility))
        menu.addItem(.separator())
        item(menu, "خروج از زمزمه", #selector(menuQuit), key: "q")
    }

    @discardableResult
    private func item(_ m: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        m.addItem(i)
        return i
    }

    private func header(_ m: NSMenu, _ title: String) {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        m.addItem(i)
    }

    // MARK: اکشن‌های منو

    @objc private func menuToggle() { toggleSession() }
    @objc private func menuLangFa() { setLang("fa-IR") }
    @objc private func menuLangEn() { setLang("en-US") }
    private func setLang(_ l: String) {
        Settings.shared.lang = l
        session?.engine.setLang(l)
    }
    @objc private func menuEngineGoogle() { Settings.shared.engineName = "google" }
    @objc private func menuEngineChrome() { Settings.shared.engineName = "chrome" }
    @objc private func menuOpenChromePage() { ChromeRelayEngine.openPage() }
    @objc private func menuInsertMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let m = InsertMode(rawValue: raw) {
            Settings.shared.insertMode = m
        }
    }
    @objc private func menuToggleHotkey() {
        Settings.shared.internalHotkey.toggle()
        if Settings.shared.internalHotkey { rcmdTap.enable() } else { rcmdTap.disable() }
    }
    @objc private func menuOpenSessions() { NSWorkspace.shared.open(Zem.sessionsDir) }
    @objc private func menuOpenAccessibility() {
        let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(u)
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}
