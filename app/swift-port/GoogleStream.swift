import Foundation

// یک جفت اتصال up/down به full-duplex گوگل با کلید عمومی Chromium.
// چرخه عمر: connect() سپس feed(صدا)... سپس finishUpload() یا cancel().
// onEvent روی صف دلیگیت URLSession صدا زده می‌شود؛ onClose دقیقا یک بار.
final class GoogleStream: NSObject {
    static let key = "AIzaSyBOti4mM-6x9WDnZIjIeyEU21OpBXqWBgw"
    static let base = "https://www.google.com/speech-api/full-duplex/v1"

    let pair: String
    let lang: String
    var onEvent: ((SpeechEvent) -> Void)?
    var onClose: ((String) -> Void)?

    private var session: URLSession!
    private var upTask: URLSessionUploadTask?
    private var downTask: URLSessionDataTask?

    private let lock = NSLock()
    private var pending = Data()        // صدای در انتظار ارسال
    private var uploadDone = false
    private var cancelled = false
    private var closedOnce = false

    private var output: OutputStream?
    private var writerThread: Thread?
    private var stopWriter = false

    private var buf = Data()            // بافر فریم‌های down (فقط روی صف دلیگیت)
    private(set) var downHTTP = 0

    init(lang: String) {
        self.lang = lang
        self.pair = (0..<8).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
        super.init()
    }

    func connect() {
        let up = URL(string: "\(Self.base)/up?key=\(Self.key)&pair=\(pair)&lang=\(lang)"
            + "&client=chromium&continuous&interim&maxAlternatives=1&pFilter=0&output=pb")!
        let down = URL(string: "\(Self.base)/down?key=\(Self.key)&pair=\(pair)&output=pb")!

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 25    // سکوت طولانی‌تر را واچ‌داگ موتور زودتر می‌کشد
        cfg.timeoutIntervalForResource = 600
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)

        downTask = session.dataTask(with: URLRequest(url: down))
        downTask?.resume()

        var ureq = URLRequest(url: up)
        ureq.httpMethod = "POST"
        ureq.setValue("audio/l16; rate=16000", forHTTPHeaderField: "Content-Type")
        upTask = session.uploadTask(withStreamedRequest: ureq)
        upTask?.resume()
    }

    func feed(_ data: Data) {
        lock.lock()
        if uploadDone || cancelled {
            lock.unlock()
            return
        }
        pending.append(data)
        lock.unlock()
        nudgeWriter()
    }

    // پایان نرم: باقی صدا ارسال و بدنه بسته می‌شود تا سرور نتیجه‌های آخر را بفرستد
    func finishUpload() {
        lock.lock()
        uploadDone = true
        lock.unlock()
        nudgeWriter()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        uploadDone = true
        lock.unlock()
        nudgeWriter()
        upTask?.cancel()
        downTask?.cancel()
    }

    // MARK: نخ نویسنده (بدنه استریمی up)

    private func nudgeWriter() {
        if let t = writerThread, !t.isFinished {
            perform(#selector(drainNow), on: t, with: nil, waitUntilDone: false)
        }
    }

    @objc private func drainNow() {
        drain()
    }

    // فقط روی نخ writer
    private func drain() {
        guard let o = output else { return }
        while o.hasSpaceAvailable {
            lock.lock()
            if pending.isEmpty {
                let done = uploadDone
                lock.unlock()
                if done { closeOutput() }
                return
            }
            var chunk = pending.prefix(16384) as Data
            lock.unlock()
            let n = chunk.withUnsafeBytes { p -> Int in
                guard let base = p.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return o.write(base, maxLength: chunk.count)
            }
            if n < 0 {
                closeOutput()
                return
            }
            lock.lock()
            pending.removeFirst(n)
            lock.unlock()
            chunk.removeAll()
        }
    }

    private func closeOutput() {
        guard let o = output else { return }
        o.close()
        o.remove(from: .current, forMode: .default)
        o.delegate = nil
        output = nil
        stopWriter = true
    }

    // MARK: بستن یک‌باره

    private func reportClose(_ reason: String) {
        lock.lock()
        let already = closedOnce
        closedOnce = true
        lock.unlock()
        if already { return }
        session?.finishTasksAndInvalidate()
        onClose?(reason)
    }
}

extension GoogleStream: URLSessionDataDelegate, StreamDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
        var input: InputStream?
        var out: OutputStream?
        Stream.getBoundStreams(withBufferSize: 65536, inputStream: &input, outputStream: &out)
        guard let o = out else {
            completionHandler(nil)
            return
        }
        output = o
        let t = Thread { [weak self] in
            guard let self else { return }
            o.delegate = self
            o.schedule(in: .current, forMode: .default)
            o.open()
            while !self.stopWriter && RunLoop.current.run(mode: .default, before: .distantFuture) {}
        }
        t.name = "zemzeme.up.writer.\(pair)"
        writerThread = t
        t.start()
        completionHandler(input)
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard aStream === output else { return }
        switch eventCode {
        case .hasSpaceAvailable:
            drain()
        case .errorOccurred, .endEncountered:
            closeOutput()
        default:
            break
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if dataTask === downTask, let http = response as? HTTPURLResponse {
            downHTTP = http.statusCode
            if http.statusCode != 200 { zlog("stream \(pair) down http \(http.statusCode)") }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard dataTask === downTask else { return }
        buf.append(data)
        while buf.count >= 4 {
            var len = 0
            for k in 0..<4 { len = (len << 8) | Int(buf[buf.startIndex + k]) }
            guard len >= 0, len < 1_000_000 else {
                zlog("stream \(pair) framing error len=\(len)")
                cancel()
                return
            }
            guard buf.count >= 4 + len else { break }
            let body = buf.subdata(in: (buf.startIndex + 4)..<(buf.startIndex + 4 + len))
            buf.removeFirst(4 + len)
            onEvent?(Proto.decodeEvent(body))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        var reason = "ok"
        if let e = error as NSError? {
            reason = e.code == NSURLErrorCancelled ? "cancelled" : "err \(e.code) \(e.localizedDescription)"
        } else if let http = task.response as? HTTPURLResponse, http.statusCode != 200 {
            reason = (task === upTask ? "up" : "down") + " http \(http.statusCode)"
        } else if task === upTask {
            return  // پایان عادی آپلود؛ صبر برای نتیجه‌های آخر down
        }
        reportClose(reason)
    }
}
