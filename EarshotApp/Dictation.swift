import Foundation

/// Decides what push-to-talk dictation does next, from key events, transcription results and the
/// clock, and says what the app should do about it.
///
/// It fails toward "type nothing". Text that never appears costs the user one more key press; text
/// typed into the wrong place, or into a password field, cannot be taken back. So:
/// - A press shorter than `minimumHold` is a tap, not dictation: the capture is thrown away.
/// - A hold longer than `maximumHold` stops by itself, so a stuck key cannot record forever.
/// - Dictation never starts while a meeting is being recorded; it says why instead.
/// - Nothing heard, a failed transcription, or a secure input field insert nothing and say so.
/// - An event that does not fit the current state (a stray key up, a transcript nobody asked for)
///   changes nothing.
///
/// It is a pure value type: time is passed in with each event, so it is deterministic.
struct DictationSession {
    struct Config {
        /// Seconds a key must be held for the press to count as dictation.
        var minimumHold: TimeInterval = 0.3
        /// Seconds after which a hold stops capture by itself.
        var maximumHold: TimeInterval = 60
    }

    enum State: Equatable {
        case idle
        case listening
        case transcribing
        case inserting
    }

    enum Event: Equatable {
        case keyDown(at: TimeInterval, meetingRecording: Bool)
        case keyUp(at: TimeInterval)
        case tick(at: TimeInterval)
        /// The transcription result; `nil` means transcription failed.
        case transcript(String?, secureInput: Bool)
        case inserted
        case failed
    }

    enum Action: Equatable {
        case startCapture
        case stopCapture
        case discardCapture
        case insert(String)
        case notice(String)
    }

    private(set) var state: State = .idle
    private let config: Config
    /// When the current key press began.
    private var heldSince: TimeInterval?

    init(_ config: Config = Config()) {
        self.config = config
    }

    mutating func handle(_ event: Event) -> [Action] {
        switch (state, event) {
        case (.idle, .keyDown(let t, let meetingRecording)):
            if meetingRecording {
                return [.notice("Dictation is off while a meeting is being recorded.")]
            }
            heldSince = t
            state = .listening
            return [.startCapture]

        case (.listening, .keyUp(let t)):
            let held = t - (heldSince ?? t)
            heldSince = nil
            if held < config.minimumHold {
                state = .idle
                return [.discardCapture]
            }
            state = .transcribing
            return [.stopCapture]

        case (.listening, .tick(let t)):
            guard let since = heldSince, t - since >= config.maximumHold else { return [] }
            heldSince = nil
            state = .transcribing
            return [.stopCapture]

        case (.listening, .failed):
            heldSince = nil
            state = .idle
            return [.notice("Dictation could not capture audio.")]

        case (.transcribing, .transcript(let raw, let secureInput)):
            guard let raw else {
                state = .idle
                return [.notice("Dictation could not transcribe that.")]
            }
            let text = Self.clean(raw)
            if text.isEmpty {
                state = .idle
                return [.notice("Dictation heard nothing.")]
            }
            if secureInput {
                state = .idle
                return [.notice("Dictation does not type into secure fields.")]
            }
            state = .inserting
            return [.insert(text)]

        case (.transcribing, .failed), (.inserting, .failed):
            state = .idle
            return [.notice("Dictation failed.")]

        case (.inserting, .inserted):
            state = .idle
            return []

        default:
            return []
        }
    }

    /// Makes whisper's output fit a one-line form field: drops its bracketed tags (`[BLANK_AUDIO]`)
    /// and a lone sound note (`(upbeat music)`, `*applause*`), joins lines, and collapses spaces.
    /// A parenthetical inside real speech is kept.
    static func clean(_ raw: String) -> String {
        let untagged = raw.replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
        let text = untagged
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let isSoundNote = text.range(of: "^(\\([^()]*\\)|\\*[^*]*\\*)$", options: .regularExpression) != nil
        return isSoundNote ? "" : text
    }
}
