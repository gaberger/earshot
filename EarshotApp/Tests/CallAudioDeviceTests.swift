// sources: CallAudio.swift
// Spec tests for ADR-2611241100 (docs/specs/ADR-2611241100.json): the call-audio source is an input device
// or all system audio, in the Recording card. Run one: node --test --test-name-pattern='^S01$' EarshotApp/Tests/call-audio-devices.test.mjs
import Foundation

final class FakeTap: CallAudioTap {
    var events: [String] = []
    var level: Float?
    func start(_ plan: TapPlan) throws { events.append("start:\(plan)") }
    func stop() { events.append("stop"); level = nil }
    func finish() -> AudioSignal { stop(); return AudioSignal(samples: [], sampleRate: 16_000, channels: 1) }
}
/// A second adapter with the same port, to show the logic does not care which one it drives.
final class FakeDeviceTap: CallAudioTap {
    var events: [String] = []
    var level: Float?
    func start(_ plan: TapPlan) throws { events.append("start:\(plan)") }
    func stop() { events.append("stop") }
    func finish() -> AudioSignal { stop(); return AudioSignal(samples: [], sampleRate: 16_000, channels: 1) }
}

struct Rng {
    var s: UInt64
    mutating func next() -> Float {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Float(Int64(bitPattern: s >> 11) % 2000) / 1000 - 1
    }
}

func ctx(_ mode: CaptureMode = .recordings, _ source: CallAudioSource = .none, os: Bool = true,
         _ perm: CallAudioPermission = .granted, devices: Set<String> = ["bh", "lb"]) -> CallAudioContext {
    CallAudioContext(mode: mode, source: source, osSupportsTap: os, permission: perm, availableDevices: devices)
}
func read(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }
func swiftSources() -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: ".")) ?? []
    return names.filter { $0.hasSuffix(".swift") }.map(read)
}
func sine(_ hz: Double, rate: Double, seconds: Double, amp: Float = 0.3) -> AudioSignal {
    let n = Int(rate * seconds)
    return AudioSignal(samples: (0..<n).map { amp * Float(sin(2 * Double.pi * hz * Double($0) / rate)) }, sampleRate: rate, channels: 1)
}
func goertzel(_ x: [Float], hz: Double) -> Double {
    let w = 2 * Double.pi * hz / CallAudioMix.outputRate
    var re = 0.0, im = 0.0
    for (i, v) in x.enumerated() { re += Double(v) * cos(w * Double(i)); im += Double(v) * sin(w * Double(i)) }
    return (re * re + im * im).squareRoot() / Double(max(1, x.count))
}

let inputs: [(id: String, name: String)] = [("mic", "MacBook Mic"), ("bh", "BlackHole 2ch"), ("lb", "Loopback")]
func names(_ o: [CallAudioOption]) -> [String] { o.map(\.name) }

let scenarios: [String: () -> Bool] = [
    "S01": {
        let o = CallAudioRules.options(inputs: Array(inputs.prefix(2)), microphoneID: "", defaultMicrophoneID: nil, osSupportsTap: true)
        return names(o) == ["None", "All system audio", "MacBook Mic", "BlackHole 2ch"]
            && CallAudioSource.read("") == .none && CallAudioRules.defaultSource == .none
    },
    "S02": {
        let o = CallAudioRules.options(inputs: inputs, microphoneID: "mic", defaultMicrophoneID: nil, osSupportsTap: true)
        return names(o) == ["None", "All system audio", "BlackHole 2ch", "Loopback"]
    },
    "S03": {
        let o = CallAudioRules.options(inputs: inputs, microphoneID: "mic", defaultMicrophoneID: nil, osSupportsTap: true)
        let code = ["CallAudio.swift", "CallAudioTapAdapter.swift", "CallAudioSettings.swift"].map(read).joined()
        return !o.contains { $0.id.hasPrefix("app:") || $0.name.contains("One app") }
            && !code.contains("runningApps") && !code.contains("NSWorkspace") && !code.contains("One app\")")
    },
    "S04": {
        var r = Rng(s: 5)
        for _ in 0..<80 {
            let n = Int(abs(r.next()) * 6)
            let list = (0..<n).map { (id: "d\(Int(abs(r.next()) * 4))", name: "Dev \($0)") }
            let mic = r.next() > 0 ? "d\(Int(abs(r.next()) * 4))" : ""
            let o = CallAudioRules.options(inputs: list, microphoneID: mic, defaultMicrophoneID: nil, osSupportsTap: true)
            var seen = Set<String>(); var want: [String] = ["", "all"]
            for d in list where d.id != mic && seen.insert(d.id).inserted { want.append("device:\(d.id)") }
            if o.map(\.id) != want { return false }
        }
        return true
    },
    "S05": {
        let stored = "device:bh"
        let before = CallAudioRules.effectiveSource(stored: stored, microphoneID: "mic", defaultMicrophoneID: nil)
        let after = CallAudioRules.effectiveSource(stored: stored, microphoneID: "bh", defaultMicrophoneID: nil)
        let o = CallAudioRules.options(inputs: inputs, microphoneID: "bh", defaultMicrophoneID: nil, osSupportsTap: true)
        return before == .device("bh") && after == .none && !o.contains { $0.id == "device:bh" }
    },
    "S06": {
        let page = read("SettingsPage.swift")
        guard let mic = page.range(of: "SettingsRow(\"Microphone\""), let row = page.range(of: "callAudioRows\n", range: mic.upperBound..<page.endIndex),
              let stop = page.range(of: "SettingsRow(\"Stop when quiet\"") else { return false }
        let between = page[mic.upperBound..<row.lowerBound]
        return row.lowerBound < stop.lowerBound && !between.contains("SettingsRow(")
            && !swiftSources().contains { $0.contains("SettingsSection(\"Call audio\")") }
    },
    "S07": {
        CallAudioRules.cardAction(source: .allSystem, permission: .notAsked, osSupportsTap: true) == .allow
            && CallAudioRules.cardAction(source: .allSystem, permission: .refused, osSupportsTap: true) == .openSettings
    },
    "S08": {
        for perm in [CallAudioPermission.notAsked, .granted, .refused] {
            if CallAudioRules.cardAction(source: .none, permission: perm, osSupportsTap: true) != .none { return false }
            if CallAudioRules.cardAction(source: .device("bh"), permission: perm, osSupportsTap: true) != .none { return false }
        }
        return true
    },
    "S09": {
        let t = FakeTap(); let s = CallAudioSession(tap: t)
        s.begin(ctx(.recordings, .device("bh"))); let started = t.events == ["start:device(\"bh\")"]
        s.end()
        let out = CallAudioMix.mix(mic: sine(440, rate: 16_000, seconds: 1), tap: sine(880, rate: 48_000, seconds: 1))
        return started && t.events.last == "stop" && out.count == 16_000 && goertzel(out, hz: 440) > 0.05 && goertzel(out, hz: 880) > 0.05
    },
    "S10": {
        let d = CallAudioRules.decide(ctx(.recordings, .device("bh"), .notAsked))
        return d.tap == .device("bh") && d.message == nil
            && !CallAudioRules.shouldAskPermission(source: .device("bh"), permission: .notAsked, osSupportsTap: true)
    },
    "S11": {
        var r = Rng(s: 7)
        let voice = (0..<16_000).map { _ in r.next() * 0.3 }
        let own = sine(300, rate: 16_000, seconds: 1, amp: 0.2).samples
        var micSamples = own
        for i in 800..<16_000 { micSamples[i] += 0.4 * voice[i - 800] }
        let out = CallAudioMix.mix(mic: AudioSignal(samples: micSamples, sampleRate: 16_000, channels: 1),
                                   tap: AudioSignal(samples: voice, sampleRate: 16_000, channels: 1))
        var resid = 0.0, ref = 0.0
        for i in 0..<16_000 { let want = own[i] + voice[i]; resid += Double((out[i] - want) * (out[i] - want)); ref += Double(voice[i] * voice[i]) }
        return resid / ref < 0.05 && out.allSatisfy { abs($0) <= 1 }
    },
    "S12": {
        CallAudioRules.shouldAskPermission(source: .allSystem, permission: .notAsked, osSupportsTap: true)
            && CallAudioRules.decide(ctx(.recordings, .allSystem, .notAsked)).tap == .none
            && CallAudioRules.decide(ctx(.recordings, .allSystem, .granted)).tap == .allSystem
    },
    "S13": {
        let t = FakeTap(); let s = CallAudioSession(tap: t); s.begin(ctx(.recordings, .device("bh")))
        s.deviceLost("bh")
        return !s.tapRunning && t.events.contains("stop") && (s.decision.message ?? "").contains("not being recorded")
    },
    "S14": {
        let t = FakeTap(); let s = CallAudioSession(tap: t); s.begin(ctx(.recordings, .device("lb"), devices: ["bh"]))
        return t.events.isEmpty && s.decision.tap == .none && (s.decision.message ?? "").contains("not being recorded")
    },
    "S15": {
        let stored = "device:lb"
        let t = FakeTap(); let s = CallAudioSession(tap: t); s.begin(ctx(.recordings, CallAudioSource.read(stored), devices: ["mic", "bh"]))
        let missing = t.events.isEmpty
        let t2 = FakeTap(); let s2 = CallAudioSession(tap: t2); s2.begin(ctx(.recordings, .device("lb"))); s2.deviceLost("lb")
        return missing && t2.events == ["start:device(\"lb\")", "stop"]
            && CallAudioSource.read(stored).stored == stored
    },
    "S16": {
        for mode in [CaptureMode.recordings] {
            for id in ["bh", "zz"] {
                for present in [true, false] {
                    let d = CallAudioRules.decide(ctx(mode, .device(id), devices: present ? ["bh"] : []))
                    let missing = !(present && id == "bh")
                    if missing != (d.tap == .none && d.message != nil) { return false }
                }
            }
        }
        return true
    },
    "S17": { CallAudioSource.read("app:com.zoom.us") == .none && CallAudioSource.read("app:") == .none },
    "S18": {
        let src = CallAudioSource.read("app:com.zoom.us")
        let t = FakeTap(); let s = CallAudioSession(tap: t); s.begin(ctx(.recordings, src, .notAsked))
        return t.events.isEmpty && s.decision.message == nil
            && CallAudioRules.cardAction(source: src, permission: .notAsked, osSupportsTap: true) == .none
    },
    "S19": {
        for id in ["a", "com.x.y", "", "zoom us"] { if CallAudioSource.read("app:\(id)") != .none { return false } }
        for s in ["", "all", "device:bh", "device:AB-12"] { if CallAudioSource.read(s).stored != s { return false } }
        return true
    },
    "S20": {
        func run(_ tap: CallAudioTap) -> [String] {
            let s = CallAudioSession(tap: tap); s.begin(ctx(.recordings, .device("bh"))); s.end()
            return [s.decision.tap == .device("bh") ? "ok" : "bad", s.tapRunning ? "running" : "stopped"]
        }
        let a = FakeTap(), b = FakeDeviceTap()
        return run(a) == run(b) && a.events == b.events
    },
    "S21": {
        let core = read("CallAudio.swift")
        let imports = core.split(separator: "\n").filter { $0.hasPrefix("import ") }.map(String.init)
        return imports == ["import Foundation"] && !core.contains("AVCapture") && !core.contains("CATapDescription")
            && !CallAudioRules.options(inputs: inputs, microphoneID: "", defaultMicrophoneID: nil, osSupportsTap: true).isEmpty
    },
]

@main struct CallAudioDeviceTests {
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
