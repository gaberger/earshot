import AVFoundation
import AppKit
import Combine
import Foundation

/// The AppKit side of recording a note inside Earshot (ADR-2611062250 amendments). `NoteSession`
/// decides; this class captures from the microphone, transcribes with whisper through the owner's
/// helper, and hands the corrected text to `onSaved`. Nothing is typed anywhere.
///
/// The audio is always deleted: the wav and whisper's side files go on every path. The log never
/// carries the note text.
@MainActor
final class NoteRecorder: ObservableObject {
    // Injected by the owner, so this class never reaches into the library itself.
    var isMeetingRecording: () -> Bool = { false }
    var isDictationBusy: () -> Bool = { false }
    var scriptPath: () -> String = { "" }
    /// Runs the transcribe script with these arguments. `nil` means success, else the error text.
    var runHelper: ([String]) async -> String? = { _ in "No transcriber is set up." }
    var microphoneID: () -> String = { "" }
    var log: (String) -> Void = { _ in }
    var onNotice: (String) -> Void = { _ in }
    /// Called with (note text, seconds recorded) when a note is ready to keep.
    var onSaved: (String, Double?) -> Void = { _, _ in }

    @Published private(set) var recordingSince: Date?
    @Published private(set) var transcribing = false

    /// Input level in decibels; -160 when not recording.
    var level: Float { recorder?.level ?? -160 }

    private var session = NoteSession()
    private var recorder: MicRecorder?
    private var ticker: Timer?
    private var captureStart: TimeInterval?
    private var recordedSeconds: Double?
    private var watchdog: Task<Void, Never>?

    // MARK: Controls

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            send(.start(at: ProcessInfo.processInfo.systemUptime,
                        meetingRecording: isMeetingRecording(), dictationBusy: isDictationBusy()))
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            onNotice("Microphone access was just requested. Allow it, then press Record again.")
        default:
            onNotice("Notes need the microphone. Allow Earshot in System Settings → Privacy & Security → Microphone.")
        }
    }

    func stop() {
        send(.stop(at: ProcessInfo.processInfo.systemUptime))
    }

    // MARK: Session

    private func send(_ event: NoteSession.Event) {
        let actions = session.handle(event)
        sync()
        for action in actions { apply(action) }
    }

    /// Keeps the published state and the one-second tick in step with the session.
    private func sync() {
        let recording = session.state == .recording
        if recording, recordingSince == nil { recordingSince = Date() }
        if !recording, recordingSince != nil { recordingSince = nil }
        let busy = session.state == .transcribing
        if transcribing != busy { transcribing = busy }
        if busy, watchdog == nil {
            watchdog = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                guard !Task.isCancelled, let self, self.session.state == .transcribing else { return }
                self.watchdog = nil
                self.log("Notes: transcription timed out.")
                self.send(.failed)
            }
        } else if !busy, let w = watchdog {
            w.cancel()
            watchdog = nil
        }
        if recording, ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.send(.tick(at: ProcessInfo.processInfo.systemUptime))
                }
            }
        } else if !recording {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func apply(_ action: NoteSession.Action) {
        switch action {
        case .startCapture: beginRecording()
        case .stopCapture: stopCapture()
        case .discardCapture: discardCapture()
        case .save(let text): onSaved(text, recordedSeconds)
        case .notice(let message): onNotice(message)
        }
    }

    // MARK: Capture

    private func beginRecording() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("earshot-note-\(UUID().uuidString).wav")
        do {
            let new = try MicRecorder(deviceID: microphoneID(), url: url) { [weak self] rec, error in
                Task { @MainActor in self?.recorderFinished(rec, error: error) }
            }
            recorder = new
            new.start()
            captureStart = ProcessInfo.processInfo.systemUptime
            recordedSeconds = nil
        } catch {
            log("Notes: could not start the microphone: \(error.localizedDescription)")
            send(.failed)
        }
    }

    private func stopCapture() {
        // The finished callback carries on from here. With no recorder nothing will call back.
        guard let recorder else { return send(.failed) }
        if let start = captureStart {
            recordedSeconds = max(0, ProcessInfo.processInfo.systemUptime - start)
            captureStart = nil
        }
        recorder.stop()
    }

    private func discardCapture() {
        captureStart = nil
        guard let old = recorder else { return }
        recorder = nil  // its finished callback is now for a stranger and is ignored
        old.stop()
        // stop() finishes the file asynchronously; the files are removed once it has.
        let url = old.url
        Task.detached {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            Self.deleteFiles(for: url)
        }
    }

    private func recorderFinished(_ rec: MicRecorder, error: Error?) {
        guard rec === recorder else {
            Self.deleteFiles(for: rec.url)  // a discarded capture, now closed
            return
        }
        recorder = nil
        if let error {
            log("Notes: recording failed: \(error.localizedDescription)")
            Self.deleteFiles(for: rec.url)
            return send(.failed)
        }
        // The device ended the capture while the user was still recording: nothing to transcribe.
        if session.state == .recording {
            Self.deleteFiles(for: rec.url)
            return send(.failed)
        }
        transcribe(rec.url)
    }

    /// Transcribes the wav at `url`. The wav and whisper's side files are deleted either way.
    private func transcribe(_ url: URL) {
        let script = scriptPath()
        let helper = runHelper
        Task { @MainActor in
            let text = await Task.detached { () -> String? in
                let failure = await helper([script, url.path])
                let transcript = url.deletingPathExtension().appendingPathExtension("txt")
                let text = failure == nil ? try? String(contentsOf: transcript, encoding: .utf8) : nil
                Self.deleteFiles(for: url)
                return text
            }.value
            watchdog?.cancel()
            watchdog = nil
            if text == nil { log("Notes: transcription failed.") }
            let corrected = text.map { DictationDictionary.load().apply($0) }
            send(.transcript(corrected))
        }
    }

    /// Removes the wav and everything whisper wrote beside it.
    nonisolated private static func deleteFiles(for wav: URL) {
        try? FileManager.default.removeItem(at: wav)
        let base = wav.deletingPathExtension()
        for ext in ["txt", "srt", "json"] {
            try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
        }
    }
}
