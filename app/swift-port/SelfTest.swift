import Foundation

// تست بدون میکروفن و بدون UI: فایل خام s16le/16k با سرعت واقعی به GoogleStream
// داده می‌شود؛ همان مسیر کد اصلی (اتصال، آپلود استریمی، پارس فریم‌ها) محک می‌خورد.
// اجرا: zemzeme --selftest audio.raw [en-US|fa-IR]
enum SelfTest {
    static func run(file: String, lang: String) -> Int32 {
        guard let audio = FileManager.default.contents(atPath: file) else {
            print("selftest: cannot read \(file)")
            return 2
        }
        print("selftest: \(audio.count) bytes (~\(audio.count / 32000)s), lang=\(lang)")
        var finals = 0
        var interims = 0
        let sem = DispatchSemaphore(value: 0)
        let s = GoogleStream(lang: lang)
        s.onEvent = { ev in
            for f in ev.finals {
                finals += 1
                print("FINAL: \(f)")
            }
            if !ev.interim.isEmpty {
                interims += 1
                if interims % 8 == 1 { print("interim: \(ev.interim)") }
            }
        }
        s.onClose = { reason in
            print("closed: \(reason)")
            sem.signal()
        }
        s.connect()

        let q = DispatchQueue(label: "selftest.pace")
        var off = 0
        let timer = DispatchSource.makeTimerSource(queue: q)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler {
            let n = min(3200, audio.count - off)
            if n <= 0 {
                s.finishUpload()
                timer.cancel()
                return
            }
            s.feed(audio.subdata(in: off..<(off + n)))
            off += n
        }
        timer.resume()

        let deadline = DispatchTime.now() + .seconds(audio.count / 32000 + 60)
        if sem.wait(timeout: deadline) == .timedOut {
            print("selftest: TIMEOUT")
            s.cancel()
            _ = sem.wait(timeout: .now() + .seconds(5))
        }
        print("selftest: finals=\(finals) interim_events=\(interims)")
        return finals > 0 ? 0 : 1
    }
}
