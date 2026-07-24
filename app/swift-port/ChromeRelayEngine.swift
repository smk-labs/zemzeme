import AppKit

// موتور ۲ (فال‌بک): صفحه کروم موتور تشخیص می‌ماند؛ متن زنده از کانال SSE سرور
// لوکال (/events) می‌آید و فرمان‌ها با POST /live (kind=cmd) به صفحه می‌روند.
// اگر کلید Chromium مرد، با همین موتور محصول زنده می‌ماند.
final class ChromeRelayEngine: NSObject, Engine {
    weak var delegate: EngineDelegate?

    private static let base = "http://127.0.0.1:17635"
    private var lang = "fa-IR"
    private var running = false
    private var session: URLSession?
    private var sseTask: URLSessionDataTask?
    private var sseBuf = Data()
    private var serverProc: Process?
    private var hbTimer: Timer?
    private var lastPageSeen = Date(timeIntervalSince1970: 0)

    func start(lang: String) {
        self.lang = lang
        running = true
        delegate?.engineStatus(.connecting)
        ensureServer(attempt: 0)
    }

    func setLang(_ l: String) {
        lang = l
        cmd(["kind": "cmd", "cmd": "lang", "lang": l])
    }

    func stop() {
        running = false
        cmd(["kind": "cmd", "cmd": "stop"])
        hbTimer?.invalidate()
        hbTimer = nil
        sseTask?.cancel()
        sseTask = nil
        session?.invalidateAndCancel()
        session = nil
        delegate?.engineStatus(.idle)
    }

    // صفحه موتور را در پس‌زمینه باز می‌کند (بدون دزدیدن فوکس). از منو صدا زده می‌شود.
    static func openPage() {
        ensureServerBlocking()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-g", "-na", "Google Chrome", "--args", "--app=\(base)/?relay=1"]
        try? p.run()
    }

    private static func ensureServerBlocking() {
        if ping() { return }
        spawnServer()
    }

    // MARK: سرور لوکال

    private static func ping() -> Bool {
        var ok = false
        let sem = DispatchSemaphore(value: 0)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 1
        let s = URLSession(configuration: cfg)
        s.dataTask(with: URL(string: base + "/alive")!) { _, resp, _ in
            ok = (resp as? HTTPURLResponse)?.statusCode == 200
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1.5)
        s.invalidateAndCancel()
        return ok
    }

    @discardableResult
    private static func spawnServer() -> Process? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", Zem.root.appendingPathComponent("serve.py").path]
        p.currentDirectoryURL = Zem.root
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            zlog("relay: spawned serve.py pid=\(p.processIdentifier)")
            return p
        } catch {
            zlog("relay: serve.py spawn failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func ensureServer(attempt: Int) {
        DispatchQueue.global().async {
            if Self.ping() {
                DispatchQueue.main.async { self.serverReady() }
                return
            }
            if attempt == 0 { self.serverProc = Self.spawnServer() }
            if attempt >= 6 {
                DispatchQueue.main.async {
                    guard self.running else { return }
                    self.delegate?.engineStatus(.gaveUp("سرور لوکال بالا نیامد؛ serve.py را دستی اجرا کن"))
                }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
                self.ensureServer(attempt: attempt + 1)
            }
        }
    }

    private func serverReady() {
        guard running else { return }
        openSSE()
        cmd(["kind": "cmd", "cmd": "lang", "lang": lang])
        cmd(["kind": "cmd", "cmd": "start"])
        // اگر صفحه‌ای زنده نباشد، ضربان نمی‌آید و pageNeeded می‌شود
        hbTimer?.invalidate()
        hbTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let self, self.running else { return }
            if Date().timeIntervalSince(self.lastPageSeen) > 12 {
                self.delegate?.engineStatus(.pageNeeded)
            }
        }
    }

    // MARK: SSE

    private func openSSE() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 3600
        cfg.timeoutIntervalForResource = 24 * 3600
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        session = s
        var req = URLRequest(url: URL(string: Self.base + "/events")!)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        sseTask = s.dataTask(with: req)
        sseTask?.resume()
    }

    private func handleLine(_ line: String) {
        guard line.hasPrefix("data: "),
              let d = line.dropFirst(6).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let kind = obj["kind"] as? String else { return }
        DispatchQueue.main.async {
            guard self.running else { return }
            self.lastPageSeen = Date()
            switch kind {
            case "interim":
                self.delegate?.engineInterim(obj["text"] as? String ?? "")
                self.delegate?.engineLevel(0.4)
            case "final":
                if let t = obj["text"] as? String, !t.isEmpty { self.delegate?.engineFinal(t) }
            case "state":
                switch obj["state"] as? String ?? "" {
                case "listening": self.delegate?.engineStatus(.listening)
                case "reconnecting": self.delegate?.engineStatus(.reconnecting(attempt: 3))
                case "gaveup": self.delegate?.engineStatus(.gaveUp("شبکه ناپایداره (صفحه کروم)؛ دوباره دابل‌تپ کن"))
                default: break
                }
            case "hb":
                if (obj["listening"] as? Bool) == false {
                    // صفحه زنده است ولی گوش نمی‌دهد؛ دوباره فرمان بده
                    self.cmd(["kind": "cmd", "cmd": "start"])
                }
            default:
                break
            }
        }
    }

    // MARK: فرمان به صفحه

    private func cmd(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj) else { return }
        var req = URLRequest(url: URL(string: Self.base + "/live")!)
        req.httpMethod = "POST"
        req.httpBody = d
        req.timeoutInterval = 2
        URLSession.shared.dataTask(with: req).resume()
    }
}

extension ChromeRelayEngine: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        sseBuf.append(data)
        while let nl = sseBuf.firstIndex(of: 0x0A) {
            let lineData = sseBuf.subdata(in: sseBuf.startIndex..<nl)
            sseBuf.removeSubrange(sseBuf.startIndex...nl)
            if let line = String(data: lineData, encoding: .utf8) {
                handleLine(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard running, task === sseTask else { return }
        zlog("relay: sse dropped (\(error?.localizedDescription ?? "eof")), reopening")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.running else { return }
            self.openSSE()
        }
    }
}
