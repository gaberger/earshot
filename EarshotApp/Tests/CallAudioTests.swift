// sources: CallAudio.swift
// Spec tests for ADR-2611240900 (docs/specs/ADR-2611240900.json). One scenario per entry, S01...S26.
// Run one: bash EarshotApp/Tests/run-one.sh EarshotApp/Tests/CallAudioTests.swift S01
import Foundation

final class FakeTap: CallAudioTap {
    var events: [String] = []
    var failStart = false
    var level: Float?
    func finish() -> AudioSignal { stop(); return AudioSignal(samples: [], sampleRate: 16_000, channels: 1) }
    func start(_ plan: TapPlan) throws {
        if failStart { throw NSError(domain: "fake", code: 1) }
        events.append("start:\(plan)")
    }
    func stop() { events.append("stop") }
}

struct Rng {
    var s: UInt64
    mutating func next() -> Float {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Float(Int64(bitPattern: s >> 11) % 2000) / 1000 - 1
    }
}

func ctx(_ mode: CaptureMode = .recordings, _ source: CallAudioSource = .none, os: Bool = true,
         _ perm: CallAudioPermission = .granted, devices: Set<String> = ["zoom", "teams"]) -> CallAudioContext {
    CallAudioContext(mode: mode, source: source, osSupportsTap: os, permission: perm, availableDevices: devices)
}

func read(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }
func swiftSources() -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: ".")) ?? []
    return names.filter { $0.hasSuffix(".swift") }.map(read)
}
func sine(_ hz: Double, rate: Double, seconds: Double, channels: Int = 1, amp: Float = 0.3) -> AudioSignal {
    let n = Int(rate * seconds)
    var s = [Float](); s.reserveCapacity(n * channels)
    for i in 0..<n { let v = amp * Float(sin(2 * Double.pi * hz * Double(i) / rate)); for _ in 0..<channels { s.append(v) } }
    return AudioSignal(samples: s, sampleRate: rate, channels: channels)
}
func goertzel(_ x: [Float], hz: Double) -> Double {
    let w = 2 * Double.pi * hz / CallAudioMix.outputRate
    var re = 0.0, im = 0.0
    for (i, v) in x.enumerated() { re += Double(v) * cos(w * Double(i)); im += Double(v) * sin(w * Double(i)) }
    return (re * re + im * im).squareRoot() / Double(max(1, x.count))
}

let scenarios: [String: () -> Bool] = [
    "S01": { CallAudioRules.defaultSource == .none
        && true },
    "S02": {
        let d = CallAudioRules.decide(ctx(.recordings, .device("zoom")))
        let t = FakeTap(); let s = CallAudioSession(tap: t); s.begin(ctx(.recordings, .device("zoom")))
        return d.tap == .device("zoom") && t.events == ["start:device(\"zoom\")"]
    },
    "S03": {
        let t = FakeTap(); let s = CallAudioSession(tap: t); s.begin(ctx(.recordings, .allSystem))
        return t.events == ["start:allSystem"]
    },
    "S04": {
        let t = FakeTap(); let s = CallAudioSession(tap: t); s.begin(ctx(.recordings, .none, .notAsked)); s.end()
        return t.events.isEmpty && s.decision.message == nil
            && !CallAudioRules.shouldAskPermission(source: .none, permission: .notAsked, osSupportsTap: true)
    },
    "S05": {
        let unset = CallAudioRules.decide(ctx(.recordings, .device("")))
        let gone = CallAudioRules.decide(ctx(.recordings, .device("slack")))
        return unset.tap == .none && unset.message != nil && gone.tap == .none && gone.message != nil
    },
    "S06": {
        let adapter = read("CallAudioTapAdapter.swift"), plist = read("Info.plist")
        return adapter.contains("CATapDescription") && plist.contains("NSAudioCaptureUsageDescription")
            && !plist.contains("NSScreenCaptureUsageDescription") && !adapter.contains("CGRequestScreenCaptureAccess")
    },
    "S07": {
        let d = CallAudioRules.decide(ctx(.recordings, .allSystem, os: false))
        return true && d.tap == .none
            && CallAudioRules.cardAction(source: .allSystem, permission: .notAsked, osSupportsTap: false) == .none
    },
    "S08": { !swiftSources().contains { $0.contains("ScreenCaptureKit") || $0.contains("SCStream") || $0.contains("SCShareableContent") } },
    "S09": {
        let mic = sine(440, rate: 48_000, seconds: 1, channels: 2), tap = sine(880, rate: 16_000, seconds: 1)
        let out = CallAudioMix.mix(mic: mic, tap: tap)
        return out.count == 16_000 && goertzel(out, hz: 440) > 0.05 && goertzel(out, hz: 880) > 0.05
    },
    "S10": {
        let t = FakeTap(); let s = CallAudioSession(tap: t)
        guard t.events.isEmpty else { return false }
        s.begin(ctx(.recordings, .device("zoom"))); let started = t.events.count == 1
        s.end()
        return started && t.events.last == "stop" && t.events.count == 2
    },
    "S11": {
        let t = FakeTap(); let s = CallAudioSession(tap: t); s.begin(ctx(.recordings, .device("zoom")))
        s.deviceLost("zoom"); let ended = !s.tapRunning
        s.end()
        return ended && t.events.filter { $0 == "stop" }.count == 1
    },
    "S12": {
        var r = Rng(s: 7)
        let voice = (0..<16_000).map { _ in r.next() * 0.3 }
        let own = sine(300, rate: 16_000, seconds: 1, amp: 0.2).samples
        var micSamples = own
        for i in 800..<16_000 { micSamples[i] += 0.4 * voice[i - 800] }
        let out = CallAudioMix.mix(mic: AudioSignal(samples: micSamples, sampleRate: 16_000, channels: 1),
                                   tap: AudioSignal(samples: voice, sampleRate: 16_000, channels: 1))
        var resid = 0.0, ref = 0.0
        for i in 0..<16_000 { let want = own[i] + voice[i]; resid += Double((out[i] - want) * (out[i] - want)); ref += Double(voice[i] * voice[i]) }
        let peak = out.reduce(0) { max($0, abs($1)) }
        return resid / ref < 0.05 && peak <= 1
    },
    "S13": {
        let before = (try? FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory()).sorted()) ?? []
        let t = FakeTap(); let s = CallAudioSession(tap: t); s.begin(ctx(.recordings, .allSystem)); s.end()
        _ = CallAudioMix.mix(mic: sine(440, rate: 16_000, seconds: 0.5), tap: sine(880, rate: 16_000, seconds: 0.5))
        let after = (try? FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory()).sorted()) ?? []
        return before == after
    },
    "S14": {
        var r = Rng(s: 99)
        let rates = [8_000.0, 16_000, 44_100, 48_000]
        for _ in 0..<60 {
            func sig() -> AudioSignal {
                let ch = 1 + Int(abs(r.next()) * 2) % 2
                let rate = rates[Int(abs(r.next()) * 4) % 4]
                let frames = Int(abs(r.next()) * 5_000)
                let silent = r.next() > 0.5
                return AudioSignal(samples: (0..<frames * ch).map { _ in silent ? 0 : r.next() * 2 }, sampleRate: rate, channels: ch)
            }
            let a = sig(), b = sig()
            let out = CallAudioMix.mix(mic: a, tap: b)
            func want(_ s: AudioSignal) -> Int { Int((Double(s.samples.count / s.channels) * 16_000 / s.sampleRate).rounded()) }
            if out.count != max(want(a), want(b)) { return false }
            if out.contains(where: { abs($0) > 1.0001 || $0.isNaN }) { return false }
        }
        let silentMic = AudioSignal(samples: [Float](repeating: 0, count: 8_000), sampleRate: 16_000, channels: 1)
        let out = CallAudioMix.mix(mic: silentMic, tap: sine(880, rate: 16_000, seconds: 0.5))
        return goertzel(out, hz: 880) > 0.05
    },
    "S15": {
        CallAudioRules.shouldAskPermission(source: .allSystem, permission: .notAsked, osSupportsTap: true)
            && !CallAudioRules.shouldAskPermission(source: CallAudioRules.defaultSource, permission: .notAsked, osSupportsTap: true)
            && CallAudioRules.cardAction(source: .allSystem, permission: .notAsked, osSupportsTap: true) == .allow
    },
    "S16": { CallAudioRules.cardAction(source: .allSystem, permission: .refused, osSupportsTap: true) == .openSettings },
    "S17": {
        let t = FakeTap(); let s = CallAudioSession(tap: t); s.begin(ctx(.recordings, .allSystem, .refused))
        return t.events.isEmpty && (s.decision.message ?? "").contains("permission was refused")
    },
    "S18": {
        !CallAudioRules.shouldAskPermission(source: .none, permission: .notAsked, osSupportsTap: true)
            && CallAudioRules.decide(ctx(.recordings, .none, .notAsked)).tap == .none
    },
    "S19": {
        let t = FakeTap(); let s = CallAudioSession(tap: t); s.begin(ctx(.recordings, .device("teams")))
        return t.events == ["start:device(\"teams\")"]
    },
    "S20": {
        for mode in [CaptureMode.dictation, .notes] {
            let t = FakeTap(); let s = CallAudioSession(tap: t); s.begin(ctx(mode, .allSystem, .notAsked))
            if !t.events.isEmpty || s.decision.message != nil { return false }
        }
        return true
    },
    "S21": {
        for mode in [CaptureMode.dictation, .notes, .recordings] {
            for source in [CallAudioSource.none, .allSystem, .device("zoom")] {
                for perm in [CallAudioPermission.notAsked, .granted, .refused] {
                    for os in [true, false] {
                        let d = CallAudioRules.decide(ctx(mode, source, os: os, perm))
                        let present: Bool = { if case .device = source { return true }; return false }()
                        // A device needs no tap permission or tap OS (ADR-2611241100); All system audio needs both.
                        let expect = mode == .recordings && source != .none && (present || (perm == .granted && os))
                        if (d.tap != .none) != expect { return false }
                    }
                }
            }
        }
        return true
    },
    "S22": {
        let docs = [read("../README.md"), read("../docs/PRIVACY.md"), read("../.claude/skills/earshot-privacy-map/SKILL.md")]
        let app = swiftSources().joined()
        return docs.allSatisfy { $0.contains("other people") && $0.contains("stays on this Mac") || $0.contains("stay on this Mac") }
            && app.contains("other people") && app.contains("consent")
    },
    "S23": {
        let code = ["CallAudio.swift", "CallAudioTapAdapter.swift"].map(read).joined()
        let docs = read("../docs/PRIVACY.md") + read("../README.md")
        return !code.isEmpty && !code.contains("URLSession") && !code.contains("NWConnection")
            && !docs.contains("records only the microphone") && !docs.contains("microphone only, nothing else")
    },
    "S24": {
        var seen: [String] = []
        for source in [CallAudioSource.none, .allSystem, .device("zoom")] {
            let t = FakeTap(); let s = CallAudioSession(tap: t); s.begin(ctx(.recordings, source)); seen += t.events
        }
        return seen == ["start:allSystem", "start:device(\"zoom\")"]
    },
    "S25": {
        let core = read("CallAudio.swift")
        let imports = core.split(separator: "\n").filter { $0.hasPrefix("import ") }.map(String.init)
        return imports == ["import Foundation"] && !core.contains("CATapDescription")
    },
    "S26": {
        let c = ctx(.recordings, .device("zoom"))
        let a = sine(440, rate: 48_000, seconds: 0.3, channels: 2), b = sine(880, rate: 16_000, seconds: 0.3)
        let core = read("CallAudio.swift")
        return CallAudioRules.decide(c) == CallAudioRules.decide(c)
            && CallAudioMix.mix(mic: a, tap: b) == CallAudioMix.mix(mic: a, tap: b)
            && !core.contains("UserDefaults") && !core.contains("FileManager") && !core.contains("ProcessInfo")
    },
]

@main struct CallAudioTests {
    static func main() {
        let args = CommandLine.arguments.dropFirst()
        guard let name = args.first else {
            var bad = 0
            for k in scenarios.keys.sorted() { let ok = scenarios[k]!(); print(ok ? "PASS" : "FAIL", k); if !ok { bad += 1 } }
            print("\(scenarios.count) scenarios, \(bad) failed")
            exit(bad == 0 ? 0 : 1)
        }
        guard let run = scenarios[name] else { print("FAIL no scenario named \(name)"); exit(2) }
        let ok = run()
        print(ok ? "PASS" : "FAIL", name, "(1 test)")
        exit(ok ? 0 : 1)
    }
}
