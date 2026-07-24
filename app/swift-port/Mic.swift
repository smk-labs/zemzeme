import AVFoundation

// میکروفن به PCM خام: s16le مونو ۱۶ کیلوهرتز، تکه‌های حدودا ۱۰۰ میلی‌ثانیه.
// کال‌بک‌ها روی نخ صدا صدا زده می‌شوند.
final class Mic {
    var onChunk: ((Data) -> Void)?
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let outFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var started = false
    private var observer: NSObjectProtocol?

    func start() throws {
        let input = engine.inputNode
        let inFormat = input.inputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw NSError(domain: "zemzeme", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "میکروفنی در دسترس نیست"])
        }
        converter = AVAudioConverter(from: inFormat, to: outFormat)
        input.installTap(onBus: 0, bufferSize: 4800, format: inFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
        started = true

        // تعویض دستگاه صدا (هدست وصل/قطع): تپ را از نو بچین
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self, self.started else { return }
            zlog("mic: configuration change, restarting tap")
            self.engine.inputNode.removeTap(onBus: 0)
            try? self.restartTap()
        }
    }

    private func restartTap() throws {
        let input = engine.inputNode
        let inFormat = input.inputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else { return }
        converter = AVAudioConverter(from: inFormat, to: outFormat)
        input.installTap(onBus: 0, bufferSize: 4800, format: inFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        guard let conv = converter else { return }
        let ratio = 16000.0 / buffer.format.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: cap) else { return }
        var fed = false
        var err: NSError?
        let st = conv.convert(to: out, error: &err) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard st != .error, out.frameLength > 0, let ch = out.int16ChannelData else { return }
        let n = Int(out.frameLength)
        let data = Data(bytes: ch[0], count: n * 2)

        // RMS تقریبی با نمونه‌برداری هر هشتم، برای نقطه ضربان
        var acc: Float = 0
        var cnt = 0
        var i = 0
        while i < n {
            let v = Float(ch[0][i]) / 32768
            acc += v * v
            cnt += 1
            i += 8
        }
        onLevel?(min(1, sqrt(acc / Float(max(1, cnt))) * 5))
        onChunk?(data)
    }

    func stop() {
        guard started else { return }
        started = false
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        observer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
