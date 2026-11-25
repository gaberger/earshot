// sources: CallAudio.swift EndOfMeeting.swift
// Spec tests for ADR-2611241200 (docs/specs/ADR-2611241200.json): stop-when-quiet hears the call audio.
import Foundation

final class FakeTap: CallAudioTap {
    var events: [String] = []
    var level: Float?
    func start(_ plan: TapPlan) throws { events.append("start:\(plan)") }
    func stop() { events.append("stop"); level = nil }
    func finish() -> AudioSignal { stop(); return AudioSignal(samples: [], sampleRate: 16_000, channels: 1) }
}

struct Rng {
    var s: UInt64
    mutating func next() -> Float {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Float(Int64(bitPattern: s >> 11) % 2000) / 1000 - 1
    }
}

func read(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }

/// Speech-like level: alternates loud and quiet samples, so the floor stays low and the loud ones count.
func speech(_ i: Int) -> Float { i % 2 == 0 ? -20 : -50 }
let silent: Float = -90

struct Run {
    var d = EndOfMeetingDetector(EndOfMeetingDetector.Config())
    var t = 0.0
    var step = 0
    var endedAt: Double?
    /// One sample every 0.25 s, fed the way the app does: the louder of mic and call, and call audio playing
    /// counts as a call in progress.
    mutating func go(seconds: Double, mic: (Int) -> Float?, call: ((Int) -> Float?)?, other: Bool? = nil) {
        let n = Int(seconds * 4)
        for _ in 0..<n {
            t += 0.25; step += 1
            let m = mic(step), c = call?(step)
            var capturing = other
            if CallAudioActivity.callPlaying(call: c, threshold: d.diagnostics.threshold) { capturing = true }
            let v = d.ingest(level: CallAudioActivity.fed(mic: m, call: c), at: t, otherAppCapturing: capturing)
            if v == .end, endedAt == nil { endedAt = t }
        }
    }
}

let scenarios: [String: () -> Bool] = [
    "S01": { var r = Run(); r.go(seconds: 1_100, mic: { _ in silent }, call: speech); return r.endedAt == nil },
    "S02": {
        var r = Run()
        r.go(seconds: 60, mic: speech, call: nil)
        r.go(seconds: 700, mic: { _ in silent }, call: speech)
        return r.endedAt == nil
    },
    "S03": { CallAudioActivity.fed(mic: -30, call: -20) == -20 && CallAudioActivity.fed(mic: -20, call: -30) == -20 },
    "S04": {
        var r = Run(); r.go(seconds: 60, mic: speech, call: nil); r.go(seconds: 500, mic: { _ in silent }, call: nil)
        return r.endedAt != nil && r.endedAt! <= 60 + 300 + 15
            && CallAudioActivity.fed(mic: -33, call: nil) == -33
    },
    "S05": {
        var g = Rng(s: 3)
        for _ in 0..<200 {
            let m = -100 + abs(g.next()) * 100, c = -100 + abs(g.next()) * 100
            if CallAudioActivity.fed(mic: m, call: c)! < m { return false }
        }
        return true
    },
    "S06": {
        var g = Rng(s: 11)
        for _ in 0..<200 {
            let m = -100 + abs(g.next()) * 100, c = -100 + abs(g.next()) * 100
            if CallAudioActivity.fed(mic: m, call: c) != max(m, c) { return false }
            if CallAudioActivity.fed(mic: m, call: nil) != m || CallAudioActivity.fed(mic: nil, call: c) != c { return false }
        }
        return true
    },
    "S07": {
        var r = Run()
        r.go(seconds: 40, mic: { _ in silent }, call: speech, other: true)
        r.go(seconds: 400, mic: { _ in silent }, call: speech, other: false)
        return r.endedAt == nil
    },
    "S08": {
        var r = Run()
        r.go(seconds: 40, mic: { _ in silent }, call: speech, other: true)
        r.go(seconds: 200, mic: { _ in silent }, call: speech, other: false)
        guard r.endedAt == nil else { return false }
        r.go(seconds: 30, mic: { _ in silent }, call: speech, other: false)
        return r.endedAt == nil && r.d.diagnostics.silentFor < 5
    },
    "S09": {
        var r = Run()
        r.go(seconds: 100, mic: { _ in silent }, call: { _ in silent }, other: true)
        let releasedAt = r.t
        r.go(seconds: 200, mic: { _ in silent }, call: { _ in silent }, other: false)
        return r.endedAt != nil && r.endedAt! - releasedAt <= 70
    },
    "S10": {
        for limit in [600.0, 1_200.0] {
            var r = Run()
            r.go(seconds: 35, mic: { _ in silent }, call: speech, other: true)
            r.go(seconds: limit, mic: { _ in silent }, call: speech, other: false)
            if r.endedAt != nil { return false }
        }
        return true
    },
    "S11": {
        var r = Run(); r.go(seconds: 1_200, mic: { _ in silent }, call: { _ in silent })
        return r.endedAt != nil && r.endedAt! <= 915
    },
    "S12": {
        var r = Run()
        r.go(seconds: 60, mic: speech, call: nil)
        r.go(seconds: 600, mic: { _ in silent }, call: { _ in silent })
        return r.endedAt != nil && r.endedAt! <= 60 + 300 + 15
    },
    "S13": {
        var withSilentCall = Run(), withoutCall = Run()
        for r in [0, 1] {
            func go(_ x: inout Run) {
                x.go(seconds: 60, mic: speech, call: nil)
                x.go(seconds: 600, mic: { _ in silent }, call: r == 0 ? { _ in silent } : nil)
            }
            if r == 0 { go(&withSilentCall) } else { go(&withoutCall) }
        }
        guard let a = withSilentCall.endedAt, let b = withoutCall.endedAt else { return false }
        return abs(a - b) <= 1
    },
    "S14": {
        var r = Run()
        r.go(seconds: 100, mic: { _ in silent }, call: nil, other: true)
        let releasedAt = r.t
        r.go(seconds: 200, mic: { _ in silent }, call: nil, other: false)
        return r.endedAt != nil && r.endedAt! - releasedAt <= 70
    },
    "S15": {
        let t = FakeTap(); t.level = -20
        let level: Float? = t.level
        let adapter = read("CallAudioTapAdapter.swift")
        return level == -20 && adapter.contains("var level: Float?") && adapter.contains("func finish()")
    },
    "S16": {
        let detector = read("EndOfMeeting.swift"), core = read("CallAudio.swift")
        func imports(_ s: String) -> [String] { s.split(separator: "\n").filter { $0.hasPrefix("import ") }.map(String.init) }
        return imports(detector) == ["import Foundation"] && imports(core) == ["import Foundation"]
    },
    "S17": {
        let t = FakeTap(); t.level = -20
        let s = CallAudioSession(tap: t)
        s.begin(CallAudioContext(mode: .recordings, source: .device("bh"), osSupportsTap: true, permission: .granted, availableDevices: ["bh"]))
        s.deviceLost("bh")
        var r = Run()
        r.go(seconds: 60, mic: speech, call: nil)
        r.go(seconds: 100, mic: speech, call: { _ in t.level })
        return t.level == nil && !s.tapRunning && r.endedAt == nil
    },
    "S18": {
        let silentCall = CallAudioActivity.fed(mic: -90, call: -160)
        return CallAudioActivity.fed(mic: -90, call: nil) == -90 && CallAudioActivity.fed(mic: nil, call: nil) == nil
            && !CallAudioActivity.callPlaying(call: nil, threshold: -60) && silentCall == -90
    },
    "S19": {
        var r = Run()
        r.go(seconds: 2_000, mic: { _ in nil }, call: nil)
        var r2 = Run()
        r2.go(seconds: 2_000, mic: { _ in nil }, call: { _ in nil })
        return r.endedAt == nil && r2.endedAt == nil
    },
    "S20": { CallAudioRules.stopWhenQuietDetail.lowercased().contains("call audio") },
    "S21": {
        let text = CallAudioRules.stopWhenQuietDetail.lowercased()
        return text.contains("call audio is on") && !text.contains("always") && !text.contains("whether or not")
    },
]

@main struct CallAudioStopTests {
    static func main() {
        guard let name = CommandLine.arguments.dropFirst().first else {
            var bad = 0
            for k in scenarios.keys.sorted() { let ok = scenarios[k]!(); print(ok ? "PASS" : "FAIL", k); if !ok { bad += 1 } }
            print("\(scenarios.count) scenarios, \(bad) failed"); exit(bad == 0 ? 0 : 1)
        }
        guard let run = scenarios[name] else { print("FAIL no scenario named \(name)"); exit(2) }
        let ok = run(); print(ok ? "PASS" : "FAIL", name, "(1 test)"); exit(ok ? 0 : 1)
    }
}
