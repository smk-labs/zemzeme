import Foundation

// رویداد نتیجه گفتار از استریم down گوگل
// اسکیمای google_streaming_api.proto در Chromium:
// event{status=1, result=2, endpoint=4} / result{alternative=1, final=2, stability=3}
// alternative{transcript=1, confidence=2}
struct SpeechEvent {
    var status: Int?
    var endpoint: Int?
    var finals: [String] = []
    var interim: String = ""
}

// پارسر مینیمال protobuf؛ فقط چیزی که لازم داریم، بدون هیچ وابستگی
enum Proto {
    private static func varint(_ b: Data, _ i: inout Int) -> UInt64? {
        var v: UInt64 = 0
        var s: UInt64 = 0
        while i < b.count {
            let x = b[b.startIndex + i]
            i += 1
            v |= UInt64(x & 0x7F) << s
            if x & 0x80 == 0 { return v }
            s += 7
            if s > 63 { return nil }
        }
        return nil
    }

    // (field, wire, scalar, bytes)
    private static func fields(_ b: Data) -> [(Int, Int, UInt64, Data)] {
        var out: [(Int, Int, UInt64, Data)] = []
        var i = 0
        while i < b.count {
            guard let key = varint(b, &i) else { return out }
            let f = Int(key >> 3)
            let w = Int(key & 7)
            switch w {
            case 0:
                guard let v = varint(b, &i) else { return out }
                out.append((f, w, v, Data()))
            case 2:
                guard let n = varint(b, &i), i + Int(n) <= b.count else { return out }
                out.append((f, w, 0, b.subdata(in: (b.startIndex + i)..<(b.startIndex + i + Int(n)))))
                i += Int(n)
            case 5:
                guard i + 4 <= b.count else { return out }
                out.append((f, w, 0, b.subdata(in: (b.startIndex + i)..<(b.startIndex + i + 4))))
                i += 4
            case 1:
                guard i + 8 <= b.count else { return out }
                out.append((f, w, 0, b.subdata(in: (b.startIndex + i)..<(b.startIndex + i + 8))))
                i += 8
            default:
                return out
            }
        }
        return out
    }

    static func decodeEvent(_ b: Data) -> SpeechEvent {
        var ev = SpeechEvent()
        for (f, w, v, sub) in fields(b) {
            if f == 1 && w == 0 {
                ev.status = Int(v)
            } else if f == 4 && w == 0 {
                ev.endpoint = Int(v)
            } else if f == 2 && w == 2 {
                var isFinal = false
                var txt = ""
                for (f2, w2, v2, sub2) in fields(sub) {
                    if f2 == 1 && w2 == 2 {
                        for (f3, w3, _, sub3) in fields(sub2) {
                            if f3 == 1 && w3 == 2 && txt.isEmpty {
                                txt = String(data: sub3, encoding: .utf8) ?? ""
                            }
                        }
                    } else if f2 == 2 && w2 == 0 {
                        isFinal = v2 != 0
                    }
                }
                if isFinal { ev.finals.append(txt) } else { ev.interim += txt }
            }
        }
        return ev
    }
}
