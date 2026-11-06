import Foundation

/// Decides when to offer to record, from a stream of "is another app capturing the microphone"
/// samples and whether Earshot is already recording.
///
/// It fails toward "do not interrupt". An offer that never comes costs one click on the menu bar;
/// an offer for a Siri request or a dictation burst is noise the user learns to ignore. So:
/// - Capture must last `minimumCapture` seconds without a break before it counts as a call.
/// - An episode (one call) is offered at most once. Recording, or having been offered, marks it
///   handled, so stopping a recording mid-call does not bring the offer back.
/// - Only `quietReset` seconds of continuous quiet re-arms the detector for the next call; a short
///   break inside a call does not.
/// - No evidence (a `nil` probe, a gap in samples) changes nothing. A gap restarts the capture streak
///   and never re-arms.
///
/// It is a pure value type: time is passed in with each sample, so it is deterministic.
struct CallStartDetector {
    struct Config {
        /// Seconds of unbroken capture that make a call.
        var minimumCapture: TimeInterval = 10
        /// Seconds of continuous quiet that end an episode, so the next call is offered again.
        var quietReset: TimeInterval = 15
        /// A longer step between samples than this is no evidence: it restarts the capture streak
        /// and never counts toward `quietReset`.
        var maxGap: TimeInterval = 10
    }

    enum Verdict: Equatable {
        case none
        case offer
    }

    private let config: Config
    private var lastT: TimeInterval?
    /// When the current unbroken run of capture began.
    private var captureSince: TimeInterval?
    /// When the current unbroken run of quiet began.
    private var quietSince: TimeInterval?
    /// True once this episode was offered or recorded.
    private var handled = false

    init(_ config: Config = Config()) {
        self.config = config
    }

    mutating func ingest(capturing: Bool?, recording: Bool, at t: TimeInterval) -> Verdict {
        if let last = lastT, t - last > config.maxGap {
            captureSince = nil
            quietSince = nil
        }
        lastT = t

        if recording {
            handled = true
            captureSince = nil
        }

        switch capturing {
        case true?:
            quietSince = nil
            if recording { return .none }
            if captureSince == nil { captureSince = t }
            if !handled, let since = captureSince, t - since >= config.minimumCapture {
                handled = true
                return .offer
            }
        case false?:
            captureSince = nil
            if quietSince == nil { quietSince = t }
            if let since = quietSince, t - since >= config.quietReset { handled = false }
        case nil:
            break
        }
        return .none
    }
}
