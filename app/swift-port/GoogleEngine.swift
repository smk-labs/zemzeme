import Foundation
import AVFoundation

// موتور اصلی: میکروفن + استریم full-duplex + سوپروایزر.
// سوپروایزر همان سه پادزهر صفحه وب را دارد (backoff نمایی تا ۵ ثانیه،
// تسلیم بعد از ۸ چرخه بی‌نتیجه، واچ‌داگ ۱۲ ثانیه سکوت رویداد) به‌علاوه:
// چرخش سشن قبل از سقف ~۵ دقیقه سرور، و بافر صدا در فاصله قطعی‌ها که چیزی گم نشود.
// چرخه بی‌صدا (سکوت کاربر) بی‌نتیجه حساب نمی‌شود تا در مکث طولانی تسلیم نشویم.
final class GoogleEngine: Engine {
    weak var delegate: EngineDelegate?

    private let mic = Mic()
    private var micRunning = false
    private var stream: GoogleStream?
    private var draining: GoogleStream?    // سشن قبلی موقع چرخش: فقط final ازش قبول می‌شود
    private var lang = "fa-IR"
    private var running = false

    private let feedLock = NSLock()
    private var feedTarget: GoogleStream?
    private var preroll = Data()
    private let maxPreroll = 32000 * 10    // سقف ۱۰ ثانیه
    private var voiceInCycle = false

    private var lastEventAt = Date()
    private var endsSinceResult = 0
    private var gotResultThisCycle = false
    private var lastInterim = ""
    private var restartTimer: Timer?
    private var watchdog: Timer?
    private var streamStartedAt = Date()
    private var lastStatus = EngineStatus.idle
    private var lastLevelAt = Date(timeIntervalSince1970: 0)

    // MARK: Engine

    func start(lang: String) {
        guard !running else { return }
        self.lang = lang
        running = true
        endsSinceResult = 0
        status(.connecting)
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.running else { return }
                if !granted {
                    self.running = false
                    self.status(.gaveUp("اجازه میکروفن نیست. تنظیمات سیستم، بخش حریم خصوصی، میکروفن را برای زمزمه روشن کن."))
                    return
                }
                self.startMicAndStream()
            }
        }
    }

    func setLang(_ l: String) {
        guard l != lang else { return }
        lang = l
        guard running else { return }
        salvage()
        endsSinceResult = 0
        stream?.cancel()    // مسیر close با زبان جدید ری‌استارت می‌کند
    }

    func stop() {
        let wasRunning = running
        running = false
        if wasRunning { salvage() }
        stream?.cancel()
        draining?.cancel()
        stream = nil
        draining = nil
        feedLock.lock()
        feedTarget = nil
        preroll.removeAll()
        feedLock.unlock()
        stopMicAndTimers()
        status(.idle)
        if wasRunning { zlog("engine: stopped by user") }
    }

    // MARK: راه‌اندازی

    private func startMicAndStream() {
        mic.onChunk = { [weak self] data in
            guard let self else { return }
            self.feedLock.lock()
            if let s = self.feedTarget {
                self.feedLock.unlock()
                s.feed(data)
            } else {
                self.preroll.append(data)
                if self.preroll.count > self.maxPreroll {
                    self.preroll.removeFirst(self.preroll.count - self.maxPreroll)
                }
                self.feedLock.unlock()
            }
        }
        mic.onLevel = { [weak self] rms in
            guard let self else { return }
            if rms > 0.07 {
                self.feedLock.lock()
                self.voiceInCycle = true
                self.feedLock.unlock()
            }
            let now = Date()
            if now.timeIntervalSince(self.lastLevelAt) > 0.1 {
                self.lastLevelAt = now
                DispatchQueue.main.async { self.delegate?.engineLevel(rms) }
            }
        }
        do {
            if !micRunning {
                try mic.start()
                micRunning = true
            }
        } catch {
            running = false
            status(.gaveUp("میکروفن راه نیفتاد: \(error.localizedDescription)"))
            return
        }
        openStream()
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func openStream() {
        guard running else { return }
        let s = GoogleStream(lang: lang)
        stream = s
        streamStartedAt = Date()
        lastEventAt = Date()
        gotResultThisCycle = false
        s.onEvent = { [weak self, weak s] ev in
            DispatchQueue.main.async { self?.handleEvent(ev, from: s) }
        }
        s.onClose = { [weak self, weak s] reason in
            DispatchQueue.main.async { self?.handleClose(reason, from: s) }
        }
        s.connect()
        feedLock.lock()
        feedTarget = s
        voiceInCycle = false
        let pre = preroll
        preroll.removeAll()
        feedLock.unlock()
        if !pre.isEmpty { s.feed(pre) }
        zlog("engine: stream open pair=\(s.pair) lang=\(lang) preroll=\(pre.count)B")
    }

    // MARK: رویدادها (روی نخ اصلی)

    private func handleEvent(_ ev: SpeechEvent, from s: GoogleStream?) {
        guard let s else { return }
        if s === draining {
            for f in ev.finals { deliverFinal(f) }
            return
        }
        guard s === stream else { return }
        lastEventAt = Date()
        if lastStatus != .listening { status(.listening) }
        if let st = ev.status, st != 0 { zlog("engine: server status \(st)") }

        if !ev.finals.isEmpty || !ev.interim.isEmpty {
            gotResultThisCycle = true
            endsSinceResult = 0
        }
        for f in ev.finals {
            lastInterim = ""
            deliverFinal(f)
        }
        if ev.interim != lastInterim || !ev.finals.isEmpty {
            lastInterim = ev.interim
            delegate?.engineInterim(lastInterim)
        }
        if !ev.finals.isEmpty, Date().timeIntervalSince(streamStartedAt) > 240 {
            rotate()    // چرخش فرصت‌طلبانه سر مرز یک نتیجه قطعی
        }
    }

    private func handleClose(_ reason: String, from s: GoogleStream?) {
        if let s, s === draining {
            draining = nil
            zlog("engine: drained pair=\(s.pair) (\(reason))")
            return
        }
        guard let s, s === stream else { return }
        feedLock.lock()
        if feedTarget === s { feedTarget = nil }
        let hadVoice = voiceInCycle
        feedLock.unlock()
        stream = nil
        zlog("engine: closed pair=\(s.pair) reason=\(reason) result=\(gotResultThisCycle) voice=\(hadVoice)")
        salvage()
        guard running else { return }
        if hadVoice && !gotResultThisCycle { endsSinceResult += 1 }
        scheduleRestart()
    }

    // متن خاکستری معلق را قبل از هر مرگ/ری‌استارت قطعی کن که هیچ‌وقت گم نشود
    private func salvage() {
        let t = lastInterim.trimmingCharacters(in: .whitespacesAndNewlines)
        lastInterim = ""
        delegate?.engineInterim("")
        guard !t.isEmpty else { return }
        zlog("engine: salvaged \(t.count) chars")
        deliverFinal(t)
    }

    private func scheduleRestart() {
        guard running else { return }
        if endsSinceResult >= 8 {
            running = false
            stopMicAndTimers()
            status(.gaveUp("شبکه ناپایداره؛ برای تلاش دوباره دابل‌تپ کن"))
            zlog("engine: gave up after \(endsSinceResult) fruitless cycles")
            return
        }
        if endsSinceResult >= 3 { status(.reconnecting(attempt: endsSinceResult)) }
        let delay = min(0.3 * pow(2, Double(max(0, endsSinceResult - 1))), 5.0)
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.openStream()
        }
    }

    private func tick() {
        guard running, let s = stream else { return }
        let quiet = Date().timeIntervalSince(lastEventAt)
        let age = Date().timeIntervalSince(streamStartedAt)
        if quiet > 12 {
            zlog("engine: watchdog quiet \(Int(quiet))s, recycling pair=\(s.pair)")
            salvage()
            s.cancel()    // مسیر close ری‌استارت را می‌برد
            return
        }
        if age > 285 { rotate() }    // چرخش اجباری قبل از سقف سرور
    }

    private func rotate() {
        guard running, let old = stream else { return }
        zlog("engine: rotate pair=\(old.pair) age=\(Int(Date().timeIntervalSince(streamStartedAt)))s")
        draining?.cancel()
        draining = old
        old.finishUpload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak old] in
            if let self, let old, self.draining === old {
                old.cancel()
                self.draining = nil
            }
        }
        openStream()
    }

    private func deliverFinal(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        delegate?.engineFinal(t)
    }

    private func stopMicAndTimers() {
        if micRunning {
            mic.stop()
            micRunning = false
        }
        watchdog?.invalidate()
        watchdog = nil
        restartTimer?.invalidate()
        restartTimer = nil
    }

    private func status(_ s: EngineStatus) {
        lastStatus = s
        delegate?.engineStatus(s)
    }
}
