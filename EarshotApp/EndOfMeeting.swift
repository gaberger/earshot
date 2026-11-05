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
    private var ended = false

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
    }

    mutating func ingest(level: Float?, at t: TimeInterval) -> Verdict {
        let dt = t - lastT
        lastT = t
        if ended { return .end }
        if dt > config.maxGap { silentSince = t }

        if let level, level > -150 {
            let floor = noiseFloor(adding: level, at: t)
            if minima.count - head < Self.minBuckets {
                // Warm-up: the floor is still falling, so earlier samples are re-judged against it.
                // Otherwise the first words of a meeting would define the floor and never count.
                warm.append((t, level, min(dt, config.maxGap)))
                speechSeconds = 0
                for w in warm where w.level > floor + config.speechMargin {
                    speechSeconds += w.dt
                    silentSince = max(silentSince, w.t)
                }
            } else {
                if !warm.isEmpty { warm = [] }
                if level > floor + config.speechMargin {
                    silentSince = t
                    speechSeconds += min(dt, config.maxGap)
                }
            }
        } else {
            silentSince = t
        }

        if config.silenceLimit == 0 { return .listening }
        let armed = speechSeconds >= config.minimumSpeech
        let limit = armed ? config.silenceLimit : config.noSpeechLimit
        let remaining = max(limit - (t - silentSince), config.minimumDuration - t)
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
