// Call-audio source for recordings (ADR-2611240900, amended by ADR-2611241100 and ADR-2611241200).
// Pure: no Core Audio, no AVFoundation, no I/O. The tap and the input-device capture are driven adapters behind
// `CallAudioTap`; this file only decides and mixes.
import Foundation

/// What the user chose. Stored as "" (None), "all", or "device:" plus the input device's id.
/// "One app" from the first build is gone: an old "app:<bundle id>" value reads as None.
enum CallAudioSource: Equatable {
    case none, allSystem, device(String)

    static func read(_ stored: String) -> CallAudioSource {
        if stored == "all" { return .allSystem }
        if stored.hasPrefix("device:"), stored.count > "device:".count { return .device(String(stored.dropFirst("device:".count))) }
        return .none
    }
    var stored: String {
        switch self { case .none: return ""; case .allSystem: return "all"; case .device(let id): return "device:\(id)" }
    }
}

/// Which function is capturing. Only `.recordings` can ever cause call audio.
enum CaptureMode: Equatable { case dictation, notes, recordings }

enum CallAudioPermission: Equatable { case notAsked, granted, refused }

enum TapPlan: Equatable { case none, allSystem, device(String) }

struct CallAudioContext: Equatable {
    var mode: CaptureMode
    var source: CallAudioSource
    var osSupportsTap: Bool
    var permission: CallAudioPermission
    var availableDevices: Set<String>
}

struct CallAudioDecision: Equatable {
    var tap: TapPlan
    var message: String?
}

struct CallAudioOption: Equatable {
    var id: String      // the stored value
    var name: String
}

enum CallAudioRules {
    static let defaultSource: CallAudioSource = .none
    static let notRecorded = "Call audio is not being recorded"

    /// Shown under Stop when quiet (ADR-2611241200 decision 6).
    static let stopWhenQuietDetail = "Stops after this long with no one speaking, and warns you for the last 30 seconds. "
        + "During a call it stops about a minute after you leave the call. When call audio is on, sound from the call counts as activity."

    /// None, All system audio (where a tap exists), then every input except the microphone, once each.
    static func options(inputs: [(id: String, name: String)], microphoneID: String, defaultMicrophoneID: String?,
                        osSupportsTap: Bool) -> [CallAudioOption] {
        let mic = microphoneID.isEmpty ? defaultMicrophoneID : microphoneID
        var out = [CallAudioOption(id: "", name: "None")]
        if osSupportsTap { out.append(CallAudioOption(id: "all", name: "All system audio")) }
        var seen = Set<String>()
        for d in inputs where d.id != mic && seen.insert(d.id).inserted {
            out.append(CallAudioOption(id: "device:\(d.id)", name: d.name))
        }
        return out
    }

    /// The stored choice, unless it names the microphone itself, which would capture one device twice.
    static func effectiveSource(stored: String, microphoneID: String, defaultMicrophoneID: String?) -> CallAudioSource {
        let source = CallAudioSource.read(stored)
        let mic = microphoneID.isEmpty ? defaultMicrophoneID : microphoneID
        if case .device(let id) = source, id == mic { return .none }
        return source
    }

    /// Only All system audio needs a permission of its own; a device needs only the microphone's.
    static func shouldAskPermission(source: CallAudioSource, permission: CallAudioPermission, osSupportsTap: Bool) -> Bool {
        osSupportsTap && source == .allSystem && permission == .notAsked
    }

    /// What the permission row shows: Allow first, Open Settings once refused (ADR-2611142200).
    enum CardAction: Equatable { case allow, openSettings, none }
    static func cardAction(source: CallAudioSource, permission: CallAudioPermission, osSupportsTap: Bool) -> CardAction {
        guard osSupportsTap, source == .allSystem else { return .none }
        switch permission { case .notAsked: return .allow; case .refused: return .openSettings; case .granted: return .none }
    }

    static func decide(_ c: CallAudioContext) -> CallAudioDecision {
        guard c.mode == .recordings else { return .init(tap: .none, message: nil) }
        switch c.source {
        case .none:
            return .init(tap: .none, message: nil)
        case .allSystem:
            guard c.osSupportsTap else { return .init(tap: .none, message: nil) }
            guard c.permission == .granted else {
                return .init(tap: .none, message: c.permission == .refused
                    ? "\(notRecorded) because permission was refused."
                    : "\(notRecorded) because permission has not been given.")
            }
            return .init(tap: .allSystem, message: nil)
        case .device(let id):
            guard c.availableDevices.contains(id) else {
                return .init(tap: .none, message: "\(notRecorded): the chosen input device is not connected.")
            }
            return .init(tap: .device(id), message: nil)
        }
    }
}

/// What stop-when-quiet is fed (ADR-2611241200). Levels are dB; nil is "no evidence", never silence.
enum CallAudioActivity {
    static func fed(mic: Float?, call: Float?) -> Float? {
        switch (mic, call) {
        case (nil, nil): return nil
        case (let m?, nil): return m
        case (nil, let c?): return c
        case (let m?, let c?): return max(m, c)
        }
    }
    /// Call audio above the speech threshold means the call is still going, whatever the microphone says.
    static func callPlaying(call: Float?, threshold: Float) -> Bool {
        guard let call, call > -150 else { return false }
        return call > threshold
    }
}

/// The driven port. The Core Audio tap and the input-device capture implement it; tests use fakes.
protocol CallAudioTap: AnyObject {
    /// Level of the most recent audio in dB, or nil when the source is not running or has failed.
    var level: Float? { get }
    func start(_ plan: TapPlan) throws
    func stop()
    /// Stops and returns everything heard, for mixing into the recording.
    func finish() -> AudioSignal
}

/// One recording's use of a call-audio source: starts with Record, stops with Stop, ends if the device goes away.
final class CallAudioSession {
    private let tap: CallAudioTap
    private(set) var decision = CallAudioDecision(tap: .none, message: nil)
    private(set) var tapRunning = false
    init(tap: CallAudioTap) { self.tap = tap }

    func begin(_ context: CallAudioContext) {
        decision = CallAudioRules.decide(context)
        guard decision.tap != .none else { return }
        do { try tap.start(decision.tap); tapRunning = true }
        catch { decision.tap = .none; decision.message = "\(CallAudioRules.notRecorded): it could not be started." }
    }
    /// The chosen device was unplugged: the source ends, the recording does not.
    func deviceLost(_ id: String) {
        guard tapRunning, decision.tap == .device(id) else { return }
        tap.stop(); tapRunning = false
        decision.message = "\(CallAudioRules.notRecorded): the input device was disconnected."
    }
    func end() { if tapRunning { tap.stop(); tapRunning = false } }
}

struct AudioSignal: Equatable {
    var samples: [Float]      // interleaved
    var sampleRate: Double
    var channels: Int
}

enum CallAudioMix {
    static let outputRate = 16_000.0
    /// Echo search window: a remote voice leaking from speakers into the mic arrives this late at most.
    static let maxEchoSeconds = 0.25

    static func mono16k(_ s: AudioSignal) -> [Float] {
        let ch = max(1, s.channels)
        guard !s.samples.isEmpty, s.sampleRate > 0 else { return [] }
        let frames = s.samples.count / ch
        guard frames > 0 else { return [] }
        var mono = [Float](repeating: 0, count: frames)
        for f in 0..<frames { var sum: Float = 0; for c in 0..<ch { sum += s.samples[f * ch + c] }; mono[f] = sum / Float(ch) }
        if s.sampleRate == outputRate { return mono }
        let outCount = Int((Double(frames) * outputRate / s.sampleRate).rounded())
        guard outCount > 0 else { return [] }
        var out = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let pos = Double(i) * s.sampleRate / outputRate
            let j = min(Int(pos), frames - 1), k = min(j + 1, frames - 1)
            let t = Float(pos - Double(j))
            out[i] = mono[j] * (1 - t) + mono[k] * t
        }
        return out
    }

    /// Removes the tap's voice from the mic when the mic only hears it again through the speakers
    /// (best single delay, least-squares gain), so the mix carries it once.
    static func removeEcho(mic: [Float], tap: [Float]) -> [Float] {
        let n = min(mic.count, tap.count)
        guard n > 1 else { return mic }
        let maxLag = min(Int(maxEchoSeconds * outputRate), n - 1)
        var best = (lag: 0, score: Float(0), gain: Float(0))
        for lag in 0...maxLag {
            var dot: Float = 0, energy: Float = 0
            for i in lag..<n { dot += mic[i] * tap[i - lag]; energy += tap[i - lag] * tap[i - lag] }
            guard energy > 1e-9 else { continue }
            let score = dot * dot / energy
            if score > best.score { best = (lag, score, dot / energy) }
        }
        guard best.gain > 0.05 else { return mic }
        var out = mic
        for i in best.lag..<n { out[i] -= best.gain * tap[i - best.lag] }
        return out
    }

    static func mix(mic: AudioSignal, tap: AudioSignal) -> [Float] {
        let m = mono16k(mic), t = mono16k(tap)
        let cleaned = removeEcho(mic: m, tap: t)
        var out = [Float](repeating: 0, count: max(m.count, t.count))
        for i in 0..<out.count { out[i] = (i < cleaned.count ? cleaned[i] : 0) + (i < t.count ? t[i] : 0) }
        let peak = out.reduce(0) { max($0, abs($1)) }
        if peak > 1 { for i in 0..<out.count { out[i] /= peak } }
        return out
    }
}
