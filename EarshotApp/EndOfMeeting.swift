import Foundation

/// Decides when a meeting recording has ended, from a stream of input levels in dB.
///
/// It fails toward "keep recording". Ending too late costs a few minutes of silence at the end of
/// a file, which transcription already skips. Ending too early loses the rest of the meeting, and
/// nothing can bring that audio back. So whenever the detector is unsure it keeps listening:
/// - No evidence (a missing level, a dead input, a gap in samples) restarts the silence clock
///   instead of counting toward it.
/// - The speech threshold adapts to the noise floor, which is a low percentile of the quietest
///   sample of each second, so word gaps keep the floor honest during long monologues.
/// - It cannot end before it has heard real speech (or the long no-speech limit), nor before the
///   minimum recording length.
///
/// A second signal, whether another app is capturing the microphone, tells a call from a quiet room:
/// - While another app captures input, the call is in progress, so the silence clock restarts.
/// - Once such a call has lasted `minimumCall`, the other app letting go ends the recording within
///   `callEndedLimit`, even if little speech was heard. Room noise cannot postpone that bound; only
///   the other app capturing again, or `keepRecording(at:)`, can. A missing signal changes nothing.
///
/// It is a pure value type: time is passed in with each sample, so it is deterministic.
struct EndOfMeetingDetector {
    struct Config {
        /// Seconds of silence that end a meeting once speech was heard. 0 turns detection off.
        var silenceLimit: TimeInterval = 300
        /// The last seconds of the limit are reported as a countdown.
        var warning: TimeInterval = 30
        /// Total seconds of speech needed before `silenceLimit` applies.
        var minimumSpeech: TimeInterval = 15
        /// Never end a recording shorter than this.
        var minimumDuration: TimeInterval = 120
        /// Silence limit for a recording that has not heard enough speech.
        var noSpeechLimit: TimeInterval = 900
        /// dB above the noise floor that counts as speech.
        var speechMargin: Float = 12
        /// A longer step between samples than this is no evidence, and restarts the silence clock.
        var maxGap: TimeInterval = 5
        /// Seconds of history the noise floor is estimated from.
        var floorWindow: TimeInterval = 300
        /// Seconds another app must have captured input for its stopping to count as a call ending.
        var minimumCall: TimeInterval = 30
        /// Seconds after a call ends (or after "Keep recording") that end the recording. Never more
        /// than `silenceLimit`.
        var callEndedLimit: TimeInterval = 60
    }

    enum Verdict: Equatable {
        case listening
        case warning(secondsLeft: Int)
        case end
    }

    private let config: Config
    private var silentSince: TimeInterval = 0
    private var lastT: TimeInterval = 0
    private var speechSeconds: TimeInterval = 0
    /// Seconds another app has been capturing input.
    private var callSeconds: TimeInterval = 0
    /// The last time another app was seen capturing input.
    private var lastCallT: TimeInterval = 0
    /// The later of `lastCallT` and the last "Keep recording": the call-ended bound counts from here.
    private var callAnchor: TimeInterval = 0
    private var ended = false
    private var currentFloor: Float = 0
    /// The whole second the loud-sample count below belongs to, and how many loud samples it has had.
    private var loudSecond = Int.min
    private var loudCount = 0
    private var loudFirstDt: TimeInterval = 0

    struct Diagnostics {
        var floor: Float
        var threshold: Float
        var silentFor: TimeInterval
        var speechSeconds: TimeInterval
    }

    var diagnostics: Diagnostics {
        Diagnostics(floor: currentFloor, threshold: currentFloor + config.speechMargin,
                    silentFor: lastT - silentSince, speechSeconds: speechSeconds)
    }

    /// One entry per second: the quietest level seen in that second.
    private var minima: [(second: Int, level: Float)] = []
    private var head = 0  // index of the oldest live entry; trimmed lazily
    private var cachedFloor: Float = 0
    private var warm: [(t: TimeInterval, level: Float, dt: TimeInterval)] = []

    private static let minBuckets = 10

    init(_ config: Config = Config()) {
        self.config = config
    }

    mutating func keepRecording(at t: TimeInterval) {
        silentSince = t
        callAnchor = max(callAnchor, t)
    }

    mutating func ingest(level: Float?, at t: TimeInterval, otherAppCapturing: Bool? = nil) -> Verdict {
        let dt = t - lastT
        lastT = t
        if ended { return .end }
        if dt > config.maxGap {
            silentSince = t
            callAnchor = max(callAnchor, t)  // no evidence is not silence, for the call-ended clock too
        }
        if otherAppCapturing == true {
            silentSince = t
            callSeconds += min(dt, config.maxGap)
            lastCallT = t
            callAnchor = max(callAnchor, t)
        }

        if let level, level > -150 {
            let floor = noiseFloor(adding: level, at: t)
            currentFloor = floor
            if minima.count - head < Self.minBuckets {
                // Warm-up: the floor is still falling, so earlier samples are re-judged against it.
                // Otherwise the first words of a meeting would define the floor and never count.
                warm.append((t, level, min(dt, config.maxGap)))
                // A second is speech only from its second loud sample on, so a lone click never counts.
                speechSeconds = 0
                var sec = Int.min, count = 0, firstDt: TimeInterval = 0
                for w in warm where w.level > floor + config.speechMargin {
                    let ws = Int(w.t.rounded(.down))
                    if ws != sec { sec = ws; count = 0; firstDt = w.dt }
                    count += 1
                    if count >= 2 {
                        speechSeconds += w.dt + (count == 2 ? firstDt : 0)
                        silentSince = max(silentSince, w.t)
                    }
                }
                loudSecond = sec
                loudCount = count
                loudFirstDt = firstDt
            } else {
                if !warm.isEmpty { warm = [] }
                if level > floor + config.speechMargin {
                    let sec = Int(t.rounded(.down))
                    let step = min(dt, config.maxGap)
                    if sec != loudSecond { loudSecond = sec; loudCount = 0; loudFirstDt = step }
                    loudCount += 1
                    if loudCount >= 2 {
                        silentSince = t
                        // The second sample vouches for the first, which is counted with it.
                        speechSeconds += step + (loudCount == 2 ? loudFirstDt : 0)
                    }
                }
            }
        } else {
            silentSince = t
        }

        if config.silenceLimit == 0 { return .listening }
        let callEnded = otherAppCapturing == false && callSeconds >= config.minimumCall
        let armed = callEnded || speechSeconds >= config.minimumSpeech
        let limit = armed ? config.silenceLimit : config.noSpeechLimit
        var untilEnd = limit - (t - silentSince)
        if callEnded {
            let callLimit = min(config.callEndedLimit, config.silenceLimit)
            untilEnd = min(untilEnd, callLimit - (t - callAnchor))
        }
        let remaining = max(untilEnd, config.minimumDuration - t)
        if remaining <= 0 {
            ended = true
            return .end
        }
        if remaining <= config.warning {
            return .warning(secondsLeft: Int(remaining.rounded(.up)))
        }
        return .listening
    }

    /// Records the sample in its second's minimum and returns the current noise floor.
    /// The percentile is re-sorted only when a new second begins.
    private mutating func noiseFloor(adding level: Float, at t: TimeInterval) -> Float {
        let second = Int(t.rounded(.down))
        if let last = minimums_last, last.second == second {
            if level < last.level { minima[minima.count - 1].level = level }
        } else {
            minima.append((second, level))
            trim(before: second - Int(config.floorWindow))
            recomputeFloor()
        }
        if minima.count - head < Self.minBuckets {
            // Too little history for a percentile: the minimum seen so far.
            var m = minima[head].level
            for i in head..<minima.count where minima[i].level < m { m = minima[i].level }
            return m
        }
        return cachedFloor
    }

    private var minimums_last: (second: Int, level: Float)? {
        minima.count > head ? minima[minima.count - 1] : nil
    }

    private mutating func trim(before cutoff: Int) {
        while head < minima.count, minima[head].second <= cutoff { head += 1 }
        if head > 1024 {
            minima.removeFirst(head)
            head = 0
        }
    }

    private mutating func recomputeFloor() {
        let n = minima.count - head
        guard n >= Self.minBuckets else { return }
        let sorted = minima[head...].map { $0.level }.sorted()
        cachedFloor = sorted[(n - 1) / 10]
    }
}
