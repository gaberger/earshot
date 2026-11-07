// NoteSession: the pure rules of recording a note inside Earshot (ADR-2611062250 amendment).
// No audio, no clock, no files: callers feed it events and carry out the actions it returns.
import Foundation

struct NoteSession {
    enum State: Equatable { case idle, recording, transcribing }

    enum Event: Equatable {
        case start(at: TimeInterval, meetingRecording: Bool, dictationBusy: Bool)
        case stop(at: TimeInterval)
        case tick(at: TimeInterval)
        case transcript(String?)
        case failed
    }

    enum Action: Equatable {
        case startCapture, stopCapture, discardCapture
        case save(String)
        case notice(String)
    }

    struct Config {
        var minimumSeconds: TimeInterval = 1
        var maximumSeconds: TimeInterval = 600
    }

    private(set) var state: State = .idle
    private let config: Config
    private var startedAt: TimeInterval = 0

    init(_ config: Config = Config()) { self.config = config }

    mutating func handle(_ event: Event) -> [Action] {
        switch (state, event) {
        case (.idle, .start(let at, let meetingRecording, let dictationBusy)):
            if meetingRecording { return [.notice("Notes are off while a meeting is being recorded.")] }
            if dictationBusy { return [.notice("Finish dictating first, then record a note.")] }
            startedAt = at
            state = .recording
            return [.startCapture]

        case (.recording, .stop(let at)):
            if at - startedAt < config.minimumSeconds {
                state = .idle
                return [.discardCapture]
            }
            state = .transcribing
            return [.stopCapture]

        case (.recording, .tick(let at)):
            guard at - startedAt >= config.maximumSeconds else { return [] }
            state = .transcribing
            return [.stopCapture]

        case (.transcribing, .transcript(let text)):
            state = .idle
            guard let text else { return [.notice("Could not transcribe that note.")] }
            let cleaned = DictationSession.clean(text)
            if cleaned.isEmpty { return [.notice("Heard nothing, so no note was saved.")] }
            return [.save(cleaned)]

        case (.recording, .failed), (.transcribing, .failed):
            state = .idle
            return [.notice("The note could not be recorded.")]

        default:
            return []
        }
    }
}
