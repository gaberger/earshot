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

/// Decides when the "record this meeting?" panel goes away by itself, from the same stream of
/// "is another app capturing the microphone" samples and whether Earshot is recording.
///
/// The panel is a question, not a notice, so it leaves as soon as the question has no point:
/// - Recording started: the user answered it. It goes at once.
/// - The call ended: `callEndedAfter` seconds of continuous quiet since the last capture. A short
///   break inside a call does not dismiss it.
/// - Nobody answered: it goes `timeout` seconds after it was shown, whatever the samples say.
/// - No evidence (a `nil` probe) counts toward neither capture nor quiet: it clears both, so quiet
///   must be seen again, from scratch, before the panel counts the call as over.
///
/// The offer is made while another app is capturing, so the last capture starts at `shownAt`.
/// It is a pure value type: time is passed in with each sample, so it is deterministic.
struct CallOfferPanelRule {
    struct Config {
        /// Seconds of continuous quiet after the last capture that mean the call is over.
        var callEndedAfter: TimeInterval = 15
        /// Seconds after the panel is shown that it goes, unanswered.
        var timeout: TimeInterval = 120
    }

    enum Dismissal: Equatable { case recordingStarted, callEnded, timedOut }

    let config: Config
    let shownAt: TimeInterval
    private var lastCapture: TimeInterval?
    private var quietSince: TimeInterval?

    init(shownAt: TimeInterval, _ config: Config = Config()) {
        self.config = config
        self.shownAt = shownAt
        self.lastCapture = shownAt
    }

    /// Feeds one sample. Returns why the panel should go, or `nil` to keep it.
    mutating func ingest(capturing: Bool?, recording: Bool, at t: TimeInterval) -> Dismissal? {
        if recording { return .recordingStarted }
        if t - shownAt >= config.timeout { return .timedOut }
        switch capturing {
        case true?:
            lastCapture = t
            quietSince = nil
        case false?:
            if quietSince == nil { quietSince = lastCapture ?? t }
            if let since = quietSince, t - since >= config.callEndedAfter { return .callEnded }
        case nil:
            lastCapture = nil
            quietSince = nil
        }
        return nil
    }

    /// The panel's words: a title naming the app, the question, and the ignore button.
    static func text(appName: String) -> (title: String, body: String, ignore: String) {
        ("\(appName) is using the microphone", "Record this meeting?", "Not for \(appName)")
    }
}
