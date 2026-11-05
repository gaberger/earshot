// Tests for end-of-meeting detection. They feed 4 Hz level samples and check the verdicts.
// The oracle for the property test is built from how the audio was generated, not from the detector.
// Run: bash EarshotApp/Tests/run.sh
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

/// A seeded generator, so a failing property case can be replayed.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

let step = 0.25  // seconds between samples: four a second, as the app samples

/// Drives one detector and remembers when each verdict first appeared.
struct Sim {
    var d: EndOfMeetingDetector
    var t = 0.0
    var firstWarning: Double?
    var firstWarningSeconds: Int?
    var endedAt: Double?
    var samples = 0

    init(_ config: EndOfMeetingDetector.Config = .init()) { d = EndOfMeetingDetector(config) }

    /// Feeds `seconds` of samples; `level` gets the sample's index within this stretch.
    mutating func feed(_ seconds: Double, _ level: (Int) -> Float?) {
        let n = Int((seconds / step).rounded())
        for i in 0..<n {
            t += step
            samples += 1
            switch d.ingest(level: level(i), at: t) {
            case .listening: break
            case .warning(let left):
                if firstWarning == nil { firstWarning = t; firstWarningSeconds = left }
            case .end:
                if endedAt == nil { endedAt = t }
            }
        }
    }
    mutating func ambient(_ seconds: Double, _ floor: Float = -50) { feed(seconds) { _ in floor } }
    /// Speech with a word gap every fourth sample, 25 dB over the floor.
    mutating func speech(_ seconds: Double, _ floor: Float = -50) {
        feed(seconds) { $0 % 4 == 3 ? floor : floor + 25 }
    }
    mutating func gap(_ seconds: Double) { t += seconds }  // the Mac slept, or the app stalled
    func ended(within s: Double, of start: Double) -> Bool { endedAt.map { $0 <= start + s } ?? false }
}

func within(_ got: Double?, _ want: Double, _ tol: Double = 1.0) -> Bool {
    got.map { abs($0 - want) <= tol } ?? false
}

@main struct EndOfMeetingTests {
    static func main() {
        // Speech, then silence: a countdown of `warning` seconds, then the end at the limit.
        do {
            var s = Sim()
            s.speech(60)
            checkTrue("while people talk it keeps listening", s.firstWarning == nil && s.endedAt == nil)
            let quietFrom = s.t
            s.ambient(600)
            checkTrue("it warns 30 s before the limit", within(s.firstWarning, quietFrom + 270), "\(String(describing: s.firstWarning))")
            checkTrue("the first warning counts down from 30", s.firstWarningSeconds == 30, "\(String(describing: s.firstWarningSeconds))")
            checkTrue("it ends 300 s after the last speech", within(s.endedAt, quietFrom + 300), "\(String(describing: s.endedAt))")
        }

        // Pauses just under the limit never trigger anything.
        do {
            var s = Sim()
            for _ in 0..<5 { s.speech(20); s.ambient(255) }  // 255 s of quiet is before the warning
            checkTrue("pauses shorter than limit minus warning never warn", s.firstWarning == nil && s.endedAt == nil)
            checkTrue("the pauses test really ran", s.samples > 4_000)
        }

        // Speaking during the countdown cancels it and restarts the clock from that speech.
        do {
            var s = Sim()
            s.speech(60); s.ambient(280)
            checkTrue("in the countdown", s.firstWarning != nil && s.endedAt == nil)
            s.speech(2)
            let resumed = s.t
            s.firstWarning = nil
            s.ambient(260)
            checkTrue("speech in the countdown cancels it", s.firstWarning == nil && s.endedAt == nil)
            s.ambient(100)
            checkTrue("the clock restarts from the new speech", within(s.endedAt, resumed + 300), "\(String(describing: s.endedAt))")
        }

        // "Keep recording" does the same.
        do {
            var s = Sim()
            s.speech(60); s.ambient(285)
            checkTrue("warned before keepRecording", s.firstWarning != nil && s.endedAt == nil)
            s.d.keepRecording(at: s.t)
            let kept = s.t
            s.ambient(100)
            checkTrue("keepRecording stops the countdown", s.endedAt == nil)
            s.ambient(250)
            checkTrue("and the limit restarts from it", within(s.endedAt, kept + 300), "\(String(describing: s.endedAt))")
        }

        // Never ends early: the minimum length and the minimum amount of speech.
        do {
            var config = EndOfMeetingDetector.Config()
            config.silenceLimit = 60; config.warning = 10
            var s = Sim(config)
            s.speech(20)
            s.ambient(300)
            checkTrue("it never ends before the minimum recording length", (s.endedAt ?? 0) >= config.minimumDuration, "\(String(describing: s.endedAt))")
            checkTrue("it still warns before it ends", (s.firstWarning ?? .infinity) < (s.endedAt ?? 0))
        }
        do {
            var s = Sim()
            s.speech(6)  // about 4.5 s of speech: below the 15 s that arms the detector
            let last = s.t
            s.ambient(700)
            checkTrue("a little speech does not arm the 5 minute limit", !s.ended(within: 600, of: last), "\(String(describing: s.endedAt))")
            s.ambient(300)
            checkTrue("it ends by the no-speech limit instead", within(s.endedAt, last + 900), "\(String(describing: s.endedAt))")
        }
        do {
            var s = Sim()
            s.ambient(1_200)
            checkTrue("a recording that never hears speech ends at the no-speech limit", within(s.endedAt, 900), "\(String(describing: s.endedAt))")
            checkTrue("and not a second before 5 minutes of silence", (s.endedAt ?? 0) > 300)
        }

        // The same limit in a loud room and in a quiet one.
        for floor: Float in [-30, -60] {
            var s = Sim()
            s.speech(60, floor)
            let quietFrom = s.t
            s.ambient(400, floor)
            checkTrue("floor \(floor) dB: ends 300 s after the speech", within(s.endedAt, quietFrom + 300), "\(String(describing: s.endedAt))")
        }
        do {
            var s = Sim()
            s.ambient(10, -60)
            s.speech(60, -60)
            s.feed(240) { _ in -45 }  // a fan 15 dB over the old floor, switched on mid-silence
            checkTrue("a noise that starts mid-silence is not mistaken for silence at once", s.endedAt == nil)
        }

        // Ten minutes of nonstop talking must not teach the detector that talking is silence.
        do {
            var s = Sim()
            s.speech(600)
            checkTrue("ten minutes of talking never warns", s.firstWarning == nil && s.endedAt == nil)
            let quietFrom = s.t
            s.ambient(400)
            checkTrue("and it still ends 300 s after they stop", within(s.endedAt, quietFrom + 300), "\(String(describing: s.endedAt))")
        }

        // A fan that never stops is not a voice: no end for the first 5 minutes, then it is silence.
        do {
            var s = Sim()
            s.speech(60, -60)
            let fanOn = s.t
            s.feed(1_000) { _ in -35 }
            checkTrue("a fan that turns on does not end the meeting in its first 5 minutes", (s.endedAt ?? .infinity) > fanOn + 300, "\(String(describing: s.endedAt))")
            checkTrue("but it does not keep it open forever", s.ended(within: 800, of: fanOn), "\(String(describing: s.endedAt))")
        }

        // No evidence is not silence.
        do {
            var s = Sim()
            s.speech(60); s.ambient(200)
            s.gap(60)  // slept for a minute
            let resumed = s.t
            s.ambient(260)  // 200 s before the gap plus 260 after would be past the limit if the gap counted
            checkTrue("a gap in samples restarts the silence clock", s.endedAt == nil && s.firstWarning == nil)
            s.ambient(100)
            checkTrue("and the limit counts from the resume", within(s.endedAt, resumed + 300, 1.5), "\(String(describing: s.endedAt))")
        }
        do {
            var s = Sim()
            s.speech(60)
            s.feed(500) { _ in -160 }
            checkTrue("a dead input (-160 dB) is not silence", s.firstWarning == nil && s.endedAt == nil)
            s.feed(500) { _ in nil }
            checkTrue("a missing level is not silence", s.firstWarning == nil && s.endedAt == nil)
        }

        // Off.
        do {
            var config = EndOfMeetingDetector.Config()
            config.silenceLimit = 0
            var s = Sim(config)
            s.speech(60); s.ambient(7_200)
            checkTrue("a limit of 0 never ends, even after two quiet hours", s.firstWarning == nil && s.endedAt == nil)
        }

        // Property: over random meetings, it only ever ends after a true silence at least as long as the limit.
        do {
            var ended = 0, kept = 0
            for seed in 0..<200 {
                var rng = SplitMix64(state: UInt64(seed) &+ 1)
                let ambient = Float.random(in: -65 ... -25, using: &rng)
                // Some meetings pause for at most 2.5 minutes, some for up to 8: only the latter can end.
                let longestPause = [150.0, 280.0, 500.0].randomElement(using: &rng)!
                var d = EndOfMeetingDetector()
                var t = 0.0
                var lastSpeech = 0.0          // oracle: last sample the generator made loud
                var speechSeconds = 0.0
                var endedAt: Double?
                outer: while t < 2_400 {
                    let isSpeechSegment = Bool.random(using: &rng)
                    let length = isSpeechSegment ? Double.random(in: 2...60, using: &rng) : Double.random(in: 1...longestPause, using: &rng)
                    for i in 0..<Int(length / step) {
                        t += step
                        let level: Float
                        if isSpeechSegment && i % 4 != 3 {
                            level = ambient + 25 + Float.random(in: -5...5, using: &rng)
                        } else {
                            level = ambient + Float.random(in: -2...2, using: &rng)
                        }
                        if level > ambient + 15 { lastSpeech = t; speechSeconds += step }
                        if case .end = d.ingest(level: level, at: t) { endedAt = t; break outer }
                    }
                }
                if let T = endedAt {
                    ended += 1
                    let silence = T - lastSpeech
                    let armed = speechSeconds >= 15
                    let limit = armed ? 300.0 : 900.0
                    checkTrue("seed \(seed): ends only after a true silence of the limit", silence >= limit - 1 && T >= 120,
                              "ended at \(T), last speech \(lastSpeech), speech \(speechSeconds)s, ambient \(ambient)")
                } else { kept += 1 }
            }
            checkTrue("the property test ended some meetings and kept others", ended >= 20 && kept >= 20, "ended \(ended), kept \(kept)")
        }

        // An empty run is not a pass.
        checkTrue("at least 12 checks ran", checks >= 12, "\(checks)")
        print(failures == 0 ? "All end-of-meeting tests passed (\(checks) checks)" : "\(failures) end-of-meeting test(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
