// Earshot — a small Mac app over the local `transcribe` script (whisper.cpp),
// with summaries from Apple's on-device model. Everything runs on this Mac;
// nothing is sent anywhere.

import AVFoundation
import AppKit
import Combine
import CoreAudio
import Darwin
import FoundationModels
import IOKit
import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct EarshotApp: App {
    @StateObject private var library = Library()
    @StateObject private var nav = Navigator()

    init() {
        PrefsMigration.run()
    }

    var body: some Scene {
        WindowGroup(id: MainWindow.id) {
            ContentView(lib: library, nav: nav, models: library.models)
                .frame(minWidth: 1180, minHeight: 560)
                // Files opened from Finder ("Open With", or dropped on the Dock icon).
                .onOpenURL { library.importFile($0) }
                .tint(Color.brandAccent)
        }
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: ["*"])
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Earshot") {
                    // The standard panel shows "Version 1.0.0 (…)"; put the build and commit in the brackets.
                    NSApp.orderFrontStandardAboutPanel(options: [.version: "\(AppVersion.build), \(AppVersion.commit)"])
                }
            }
            CommandGroup(replacing: .help) { HelpMenuItem() }
            CommandGroup(replacing: .appSettings) { SettingsCommand(nav: nav) }
            CommandGroup(after: .textEditing) {
                Button("Search") { nav.focusSearch += 1 }
                    .keyboardShortcut("k", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                RecordCommands(lib: library)
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy Current Tab") { library.copyCurrentTab() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }

        Window("How Earshot Works", id: HelpView.windowID) {
            HelpView()
                .tint(Color.brandAccent)
        }
        .defaultSize(width: 640, height: 720)

        // Quick access from the menu bar, like Plaud: record, see the timer, open recent recordings.
        MenuBarExtra {
            MenuBarPanel(lib: library, nav: nav)
        } label: {
            MenuBarLabel(lib: library)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Which page the main window shows, shared with the menu bar and the menu commands.
final class Navigator: ObservableObject {
    @Published var section: AppSection = .recordings
    @Published var focusSearch = 0
}

/// The Settings… menu item: Settings is a page in the main window.
struct SettingsCommand: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var nav: Navigator

    var body: some View {
        Button("Settings…") {
            nav.section = .settings
            openWindow(id: MainWindow.id)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

/// File-menu Record and Import items; observes the library so the title follows the recording state.
struct RecordCommands: View {
    @ObservedObject var lib: Library

    var body: some View {
        Button(lib.recording ? "Stop Recording" : "Record") { lib.toggleRecording() }
            .keyboardShortcut("r", modifiers: .command)
        Button("Import…") { lib.chooseFile() }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(lib.recording)
    }
}

enum MainWindow {
    static let id = "main"
}

/// The version build.sh stamps into Info.plist: release number (VERSION), build number, commit.
enum AppVersion {
    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "?"
    }
    static let version = info("CFBundleShortVersionString")
    static let build = info("CFBundleVersion")
    static let commit = info("EarshotCommit")
    /// "1.0.0 (16, 3113bfa)"
    static let display = "\(version) (\(build), \(commit))"
}

// MARK: - Model

/// One audio file in ~/Recordings/whisper, plus the .txt / .srt / .summary.md files beside it.
/// Files imported from elsewhere are symlinks named "<timestamp> <original name>".
struct Recording: Identifiable, Hashable {
    let audio: URL
    let date: Date
    let title: String

    var id: String { audio.lastPathComponent }
    private var base: String { audio.deletingPathExtension().path }
    var transcriptURL: URL { URL(fileURLWithPath: base + ".txt") }
    var srtURL: URL { URL(fileURLWithPath: base + ".srt") }
    var summaryURL: URL { URL(fileURLWithPath: base + ".summary.md") }
    /// A name the user gave the recording. It wins over the summary's title.
    var nameURL: URL { URL(fileURLWithPath: base + ".name") }
    var hasCustomName: Bool { FileManager.default.fileExists(atPath: nameURL.path) }
    var hasTranscript: Bool { FileManager.default.fileExists(atPath: transcriptURL.path) }
    var hasSummary: Bool { FileManager.default.fileExists(atPath: summaryURL.path) }
    /// True once the user has changed the summary by hand (marked by a hidden comment in the file).
    var summaryIsEdited: Bool {
        (try? String(contentsOf: summaryURL, encoding: .utf8))?.contains(Library.editedMarker) ?? false
    }

    static let stampFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }()

    init(audio: URL) {
        self.audio = audio
        let name = audio.deletingPathExtension().lastPathComponent
        var fallback = name
        if let d = Self.stampFormat.date(from: String(name.prefix(17))) {
            date = d
            let rest = name.dropFirst(17).trimmingCharacters(in: .whitespaces)
            fallback = rest.isEmpty ? "Recording" : rest
        } else {
            date = (try? audio.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        }
        // A name the user typed wins; otherwise, once summarized, the summary's "# Title" names it.
        let base = audio.deletingPathExtension().path
        let custom = (try? String(contentsOfFile: base + ".name", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = (try? String(contentsOfFile: base + ".summary.md", encoding: .utf8))?
            .split(separator: "\n").first { $0.hasPrefix("# ") }
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        title = [custom, heading].compactMap { $0 }.first { !$0.isEmpty } ?? fallback
    }

    /// The summary as shown and copied: its "# Title" line follows the user's name for the recording.
    func displayedSummary(_ markdown: String) -> String {
        guard hasCustomName else { return markdown }
        return markdown.replacingOccurrences(of: #"(?m)^# .*$"#,
                                             with: "# " + NSRegularExpression.escapedTemplate(for: title),
                                             options: .regularExpression)
    }
}

@MainActor
final class Library: ObservableObject {
    enum Tab: String, CaseIterable { case summary = "Summary", transcript = "Transcript" }

    static let audioTypes: Set<String> = [
        "wav", "m4a", "mp3", "aiff", "aif", "caf", "flac", "ogg", "opus", "mp4", "mov", "m4v", "webm",
    ]

    @Published var items: [Recording] = []
    @Published var selection: Recording.ID? {
        willSet { if editingSummary { saveSummaryDraft() } }
        didSet { editingSummary = false; loadSelected() }
    }
    @Published var tab: Tab = .summary
    @Published var transcript = ""
    @Published var summary = ""
    @Published var transcribing: Set<Recording.ID> = []
    @Published var summarizing: Set<Recording.ID> = []
    @Published var findingSpeakers: Set<Recording.ID> = []
    @Published var errors: [Recording.ID: String] = [:] {
        didSet { failedStep = failedStep.filter { errors[$0.key] != nil } }
    }
    /// Which step an error came from, so Home's Try Again retries that step (ADR-2611072100 B1).
    @Published private(set) var failedStep: [Recording.ID: HomeAction.Step] = [:]
    @Published var recording = false
    /// Notes typed on the recording screen; saved beside the recording when it stops (ADR-2611142100).
    @Published var meetingNotes = ""
    @Published var startedAt: Date?
    /// Translate to English. Kept between launches now that it lives in Settings (ADR-2611072100 B3).
    @Published var translate = UserDefaults.standard.bool(forKey: Prefs.translate) {
        didSet { UserDefaults.standard.set(translate, forKey: Prefs.translate) }
    }
    @Published var notice: String?
    @Published var renaming: Recording.ID?  // drives the Rename sheet
    @Published var editingSummary = false
    @Published var summaryDraft = ""  // the summary's Markdown while editing, without the hidden header lines
    @Published var pendingOverwrite: PendingSummary?  // drives "Replace your edited summary?"

    struct PendingSummary: Identifiable {
        let id: Recording.ID
        let template: String?
    }

    nonisolated static let editedMarker = "<!-- edited -->"
    @Published var micName: String?
    /// Seconds until the recording stops itself for lack of speech; nil when not counting down.
    @Published var endingIn: Int?

    private var detector = EndOfMeetingDetector()
    private var levelTimer: Timer?
    private var watchStart: TimeInterval = 0
    private var lastQuietLog: TimeInterval = 0
    // The other-app microphone probe runs once a second; nil means unknown.
    private var otherAppCapturing: Bool?
    private var lastProbe: TimeInterval = -1
    private var sawOtherApp = false
    // Call-start offers: a second 1 s timer that runs whenever Earshot is open and not recording.
    private var callDetector = CallStartDetector()
    private var offerTimer: Timer?
    private let callNotifier = CallOfferNotifier()
    private let callPanel = CallOfferPanel()

    let dir: URL
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var recorder: MicRecorder?
    // True while waiting for the microphone permission answer, so a second click can't start a second recorder.
    private var starting = false
    /// A meeting has the microphone from the click on Record, including while macOS asks for permission,
    /// so a note or a dictation cannot start in that gap (ADR-2611072100 A5).
    var meetingHoldsMicrophone: Bool { recording || starting }
    private var savedTranscript = ""
    let dictation = DictationService()
    let notes = NotesStore()
    let noteRecorder = NoteRecorder()
    /// Downloads the speech and speaker models on first run (ADR-2611141630).
    let models = ModelDownloader()
    /// Recordings that could not be transcribed because a model was missing; transcribed once it arrives.
    private var waitingForModels: Set<Recording.ID> = []
    func isWaitingForModels(_ id: Recording.ID) -> Bool { waitingForModels.contains(id) }

    init() {
        dir = home.appendingPathComponent("Recordings/whisper")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        log("Earshot \(AppVersion.display) started")
        models.log = { [weak self] in self?.log($0) }
        if models.needsRequired {
            log("models missing: \(models.missingRequired.map(\.installedPath).joined(separator: ", "))")
        }
        // Leftover temporary audio from a crashed or killed run; nothing can be capturing yet.
        let tmp = NSTemporaryDirectory()
        for name in (try? FileManager.default.contentsOfDirectory(atPath: tmp)) ?? []
        where name.hasPrefix("earshot-note-") || name.hasPrefix("earshot-dictation-") {
            try? FileManager.default.removeItem(atPath: (tmp as NSString).appendingPathComponent(name))
        }
        reload()
        selection = items.first?.id
        loadSelected()
        // Quitting while recording still finishes the file cleanly.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recorder?.stop() }
        }
        dictation.isMeetingRecording = { [weak self] in
            guard let self else { return false }
            return self.meetingHoldsMicrophone || self.noteRecorder.recordingSince != nil || self.noteRecorder.transcribing
        }
        dictation.scriptPath = { [weak self] in self?.bin("transcribe") ?? "" }
        dictation.speakScriptPath = { [weak self] in self?.bin("earshot-speak") ?? "" }
        dictation.runHelper = { await Library.run($0, timeout: HelperRun.clipTimeout).userMessage }
        dictation.log = { [weak self] in self?.log($0) }
        dictation.tidy = { text in
            let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
            guard case .available = model.availability else { return nil }
            let session = LanguageModelSession(model: model, instructions: DictationCleanup.instructions)
            return try? await session.respond(to: text).content
        }
        dictation.microphoneID = { UserDefaults.standard.string(forKey: MicRecorder.settingKey) ?? "" }
        noteRecorder.isMeetingRecording = { [weak self] in self?.meetingHoldsMicrophone ?? false }
        noteRecorder.isDictationBusy = { [weak self] in self?.dictation.isBusy ?? false }
        noteRecorder.scriptPath = { [weak self] in self?.bin("transcribe") ?? "" }
        noteRecorder.runHelper = { await Library.run($0, timeout: HelperRun.clipTimeout).userMessage }
        noteRecorder.microphoneID = { UserDefaults.standard.string(forKey: MicRecorder.settingKey) ?? "" }
        noteRecorder.log = { [weak self] in self?.log($0) }
        noteRecorder.onNotice = { [weak self] in self?.notice = $0 }
        noteRecorder.onSaved = { [weak self] text, secs in
            guard let self else { return }
            let removed = self.notes.add(text: text, seconds: secs)
            if self.notes.saveFailed {
                self.notice = "The note could not be saved to disk, so it will be gone after you quit."
            } else if let trimmed = DictationLog.droppedNotice(count: removed, limit: self.notes.limit) {
                self.notice = trimmed
            }
        }
        dictation.refresh()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dictation.refresh() }
        }
        callNotifier.onRecord = { [weak self] in self?.callOfferRecord() }
        callNotifier.onIgnore = { [weak self] bundleID in self?.callOfferIgnore(bundleID) }
        offerTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.offerTick() }
        }
    }

    private func callOfferRecord() {
        guard !recording else { return }
        log("call offer: user chose Record")
        toggleRecording()
    }

    private func callOfferIgnore(_ bundleID: String) {
        var ignored = UserDefaults.standard.stringArray(forKey: Prefs.callOfferIgnoredApps) ?? []
        if !ignored.contains(bundleID) { ignored.append(bundleID) }
        UserDefaults.standard.set(ignored, forKey: Prefs.callOfferIgnoredApps)
        log("call offer: user chose Not for \(bundleID)")
    }

    private func offerTick() {
        // Keep feeding the detector while recording: it must know the call was already handled.
        guard Prefs.offerOnCallEnabled() else { return }
        let ignored = Set(UserDefaults.standard.stringArray(forKey: Prefs.callOfferIgnoredApps) ?? [])
        let procs = OtherAppMicProbe.capturingProcesses()?.filter { !($0.bundleID.map(ignored.contains) ?? false) }
        let now = ProcessInfo.processInfo.systemUptime
        let capturing = procs.map { !$0.isEmpty }
        let verdict = callDetector.ingest(capturing: capturing, recording: recording, at: now)
        if callPanel.isShown,
           let reason = callPanel.tick(capturing: capturing, recording: recording, at: now) {
            log("call offer: panel dismissed (\(reason))")
        }
        guard verdict == .offer, !recording, let first = procs?.first else { return }
        let name = NSRunningApplication(processIdentifier: first.pid)?.localizedName
            ?? first.bundleID ?? "Another app"
        log("call offer: \(name) (\(first.bundleID ?? "pid \(first.pid)")) has held the microphone, offering to record")
        let bundleID = first.bundleID
        callPanel.show(appName: name, bundleID: bundleID,
                       onRecord: { [weak self] in self?.callOfferRecord() },
                       onIgnore: { [weak self] in if let bundleID { self?.callOfferIgnore(bundleID) } })
        log("call offer: panel shown for \(name)")
        Task { @MainActor in
            if let error = await callNotifier.offer(appName: name, bundleID: bundleID) {
                log("call offer: system notification unavailable (\(error)), the panel carries the offer")
                notice = "\(name) is using the microphone. Press Record to capture this meeting."
            } else {
                log("call offer: notification posted for \(name)")
            }
        }
    }

    var selected: Recording? { items.first { $0.id == selection } }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        let live = recorder?.url.lastPathComponent
        items = urls
            .filter { Self.audioTypes.contains($0.pathExtension.lowercased()) && $0.lastPathComponent != live }
            .map(Recording.init(audio:))
            .sorted { $0.date > $1.date }
    }

    private func loadSelected() {
        guard let r = selected else {
            transcript = ""; summary = ""; savedTranscript = ""
            return
        }
        transcript = (try? String(contentsOf: r.transcriptURL, encoding: .utf8)) ?? ""
        savedTranscript = transcript
        summary = (try? String(contentsOf: r.summaryURL, encoding: .utf8)) ?? ""
    }

    /// Called on every edit of the transcript tab; writes only real changes.
    func saveTranscriptIfEdited() {
        guard let r = selected, transcript != savedTranscript else { return }
        try? transcript.write(to: r.transcriptURL, atomically: true, encoding: .utf8)
        savedTranscript = transcript
    }

    // MARK: Recording

    func toggleRecording() {
        log("button pressed (recording=\(recording), starting=\(starting))")
        recording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard !starting else { return }
        noteRecorder.stop()
        starting = true
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                self.starting = false
                self.log("microphone access granted=\(granted)")
                if granted {
                    self.beginRecording()
                } else {
                    self.notice = "Microphone access is off. Turn it on in System Settings → Privacy & Security → Microphone."
                }
            }
        }
    }

    private func beginRecording() {
        guard recorder == nil else {
            notice = "Still saving the last recording. Try again in a moment."
            return
        }
        let url = dir.appendingPathComponent(Recording.stampFormat.string(from: Date()) + ".wav")
        let chosen = UserDefaults.standard.string(forKey: MicRecorder.settingKey) ?? ""
        do {
            let r = try MicRecorder(deviceID: chosen, url: url) { rec, end in
                Task { @MainActor in self.recordingFinished(rec, end: end) }
            }
            recorder = r
            startCallAudio()
            r.start()
            recording = true
            startWatchingForEnd()
            startedAt = Date()
            micName = r.deviceName
            notice = r.usedFallback ? "The chosen microphone isn't connected, so this uses \(r.deviceName)." : nil
            log("recording started with \(r.deviceName): \(url.path)")
        } catch {
            notice = "Could not start recording: \(error.localizedDescription)"
            log("recording failed: \(Self.logDescription(error))")
        }
    }

    private func stopRecording() {
        guard let r = recorder else {
            log("stop pressed but no recorder")
            clearRecordingState()
            return
        }
        // The file is finished in recordingFinished, once the capture output has flushed it.
        r.stop()
        clearRecordingState()
        log("recording stopped")
    }

    private func clearRecordingState() {
        stopWatchingForEnd()
        recording = false
        startedAt = nil
    }

    // MARK: End-of-meeting detection

    private func startWatchingForEnd() {
        stopWatchingForEnd()
        var config = EndOfMeetingDetector.Config()
        config.silenceLimit = Prefs.autoStopSeconds()
        detector = EndOfMeetingDetector(config)
        watchStart = ProcessInfo.processInfo.systemUptime
        lastQuietLog = 0
        otherAppCapturing = nil
        lastProbe = -1
        sawOtherApp = false
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopWatchingForEnd() {
        levelTimer?.invalidate()
        levelTimer = nil
        if endingIn != nil { endingIn = nil }  // @Published publishes on every assignment; only assign on change
    }

    private func tick() {
        let t = ProcessInfo.processInfo.systemUptime - watchStart
        if lastProbe < 0 || t - lastProbe >= 1 {
            lastProbe = t
            let probe = OtherAppMicProbe.otherAppCapturing()
            let answer = probe?.0
            if answer != otherAppCapturing {
                otherAppCapturing = answer
                switch answer {
                case true?:
                    sawOtherApp = true
                    log("other app capturing the microphone: \(probe?.1.joined(separator: ", ") ?? "")")
                case false?:
                    log("no other app is capturing the microphone")
                case nil:
                    log("could not tell whether another app is capturing the microphone")
                }
            }
        }
        // Call audio counts as activity (ADR-2611241200): the louder of mic and call feeds the detector, and call
        // audio above the speech threshold means the call is still going, whatever the microphone says.
        let call = callTap?.level
        var capturing = otherAppCapturing
        if CallAudioActivity.callPlaying(call: call, threshold: detector.diagnostics.threshold) { capturing = true }
        let state = detector.ingest(level: CallAudioActivity.fed(mic: micLevel(), call: call), at: t, otherAppCapturing: capturing)
        if t - lastQuietLog >= 15 {
            lastQuietLog = t
            let d = detector.diagnostics
            let callState = otherAppCapturing.map { $0 ? "other app capturing" : "no other app capturing" } ?? "unknown"
            log("quiet check: call \(callState), level \(Int(micLevel().rounded())) dB, floor \(Int(d.floor.rounded())) dB, speech above \(Int(d.threshold.rounded())) dB, silent for \(Int(d.silentFor.rounded())) s, speech heard \(Int(d.speechSeconds.rounded())) s, limit \(Int(Prefs.autoStopSeconds().rounded())) s")
        }
        switch state {
        case .listening:
            if endingIn != nil { endingIn = nil }  // @Published publishes on every assignment; only assign on change
        case .warning(let s):
            if endingIn == nil {
                NSSound.beep()
                log("quiet countdown started, \(s) s left")
            }
            if endingIn != s { endingIn = s }
        case .end:
            autoStop()
        }
    }

    private func autoStop() {
        if sawOtherApp && otherAppCapturing == false {
            log("recording stopped automatically: the call ended")
            notice = "Stopped automatically: the call ended. You can change this in Settings (⌘,)."
        } else {
            let minutes = Int((Prefs.autoStopSeconds() / 60).rounded())
            log("recording stopped automatically after \(minutes) min of silence")
            notice = "Stopped automatically after a long quiet spell. You can change this in Settings (⌘,)."
        }
        stopRecording()
    }

    /// The user chose to keep going: restart the silence clock and dismiss the countdown.
    func keepRecording() {
        detector.keepRecording(at: ProcessInfo.processInfo.systemUptime - watchStart)
        if endingIn != nil { endingIn = nil }  // @Published publishes on every assignment; only assign on change
    }

    // MARK: Call audio (ADR-2611240900, ADR-2611241100, ADR-2611241200)

    private var callTap: CallAudioTap?
    private var callSession: CallAudioSession?
    private var deviceObserver: NSObjectProtocol?

    private func stopObservingDevices() {
        if let o = deviceObserver { NotificationCenter.default.removeObserver(o) }
        deviceObserver = nil
    }

    private func startCallAudio() {
        callTap = nil; callSession = nil; stopObservingDevices()
        let defaults = UserDefaults.standard
        let source = CallAudioRules.effectiveSource(stored: defaults.string(forKey: CallAudioPrefs.source) ?? "",
                                                    microphoneID: defaults.string(forKey: MicRecorder.settingKey) ?? "",
                                                    defaultMicrophoneID: AVCaptureDevice.default(for: .audio)?.uniqueID)
        guard source != .none else { return }
        let tap: CallAudioTap = source == .allSystem ? CoreAudioTap() : InputDeviceTap()
        let session = CallAudioSession(tap: tap)
        let permission = CallAudioPrefs.permission
        session.begin(CallAudioContext(mode: .recordings, source: source, osSupportsTap: CoreAudioTap.isSupported,
                                       permission: permission == .notAsked ? .granted : permission,  // macOS asks on first use
                                       availableDevices: Set(MicRecorder.inputs().map(\.uniqueID))))
        if session.tapRunning {
            callTap = tap; callSession = session
            if source == .allSystem { CallAudioPrefs.permission = .granted }
            log("call audio started")
            if case .device(let id) = source {
                deviceObserver = NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification,
                                                                        object: nil, queue: .main) { [weak self] note in
                    guard (note.object as? AVCaptureDevice)?.uniqueID == id else { return }
                    MainActor.assumeIsolated {
                        guard let self, let s = self.callSession else { return }
                        s.deviceLost(id)
                        self.notice = s.decision.message
                        self.log("call audio device disconnected")
                    }
                }
            }
        } else if session.decision.message != nil {
            if source == .allSystem, session.decision.message?.contains("could not be started") == true { CallAudioPrefs.permission = .refused }
            notice = session.decision.message
            log("call audio not started")
        }
    }

    private func finishCallAudio(into url: URL) {
        stopObservingDevices()
        guard let tap = callTap, let session = callSession else { return }
        session.end()
        let signal = tap.finish()
        callTap = nil; callSession = nil
        do { try CallAudioWav.merge(signal, into: url) }
        catch { notice = "Call audio could not be added to the recording."; log("call audio merge failed") }
    }

    private func recordingFinished(_ r: MicRecorder, end: RecordingEnd) {
        clearRecordingState()
        recorder = nil
        micName = nil
        switch end {
        case .stopped:
            break
        case .failed(let m):
            log("recording finished with error: \(m)")
            notice = m
        case .endedByItself(let m):
            log("recording ended by itself: \(m)")
            notice = m
        }
        guard FileManager.default.fileExists(atPath: r.url.path) else { stopObservingDevices(); callTap?.stop(); callTap = nil; callSession = nil; return }
        finishCallAudio(into: r.url)
        saveMeetingNotes(for: r.url)
        reload()
        selection = r.url.lastPathComponent
        tab = .summary
        transcribe(r.url.lastPathComponent)
    }

    /// Saves what was typed in Your notes beside the recording, owner-only, then empties the box.
    private func saveMeetingNotes(for audio: URL) {
        let notes = meetingNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        meetingNotes = ""
        guard !notes.isEmpty else { return }
        if !PrivateFiles.writeAtomically(Data(notes.utf8), to: MeetingNotes.url(for: audio), tightenFolder: false) {
            notice = "Your notes could not be saved beside the recording."
            log("meeting notes not saved")
        }
    }

    /// Input loudness in decibels (about -60 quiet to 0 loud), for the level bar.
    func micLevel() -> Float { recorder?.level ?? -160 }

    // MARK: Import

    func importFile(_ url: URL) {
        guard Self.audioTypes.contains(url.pathExtension.lowercased()) else {
            notice = "\(url.lastPathComponent) is not an audio or video file."
            return
        }
        var id = url.lastPathComponent
        if url.deletingLastPathComponent().standardizedFileURL.path != dir.standardizedFileURL.path {
            // Link the file into the timeline instead of copying it, so big videos don't double up.
            id = "\(Recording.stampFormat.string(from: Date())) \(url.lastPathComponent)"
            do {
                try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent(id), withDestinationURL: url)
            } catch {
                notice = "Could not import \(url.lastPathComponent): \(error.localizedDescription)"
                return
            }
        }
        reload()
        selection = id
        tab = .summary
        if selected?.hasTranscript == false { transcribe(id) }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { panel.urls.forEach(importFile) }
    }

    // MARK: Transcribe

    func transcribe(_ id: Recording.ID) {
        guard !transcribing.contains(id) else { return }
        models.refresh()
        let needed: Set<ModelGroup> = translate ? [.speech, .translate] : [.speech]
        let missing = ModelCatalog.missing(needed, root: models.root)
        if !missing.isEmpty {
            log("transcribe waiting for models: \(id) needs \(missing.map(\.installedPath).joined(separator: ", "))")
            waitingForModels.insert(id)
            errors[id] = missing.contains { $0.group == .translate } && !models.needsRequired
                ? "Translate needs its model. Download it, or turn Translate off and transcribe again."
                : "Download the speech models first, with Download at the top of Recordings. "
                    + "This recording is transcribed as soon as they arrive."
            return
        }
        waitingForModels.remove(id)
        let path = dir.appendingPathComponent(id).path
        log("transcribing: \(path)")
        transcribing.insert(id)
        errors[id] = nil

        let args = [bin("transcribe")] + (translate ? ["-t"] : []) + [path]

        let audio = dir.appendingPathComponent(id)
        Task {
            let outcome = await Self.run(args, timeout: await Self.jobTimeout(audio))
            transcribing.remove(id)
            log(outcome.logLine("transcribe"))
            if let failure = outcome.userMessage {
                errors[id] = "Transcription failed:\n\(failure)"
                failedStep[id] = .transcribe
                return
            }
            if selection == id { loadSelected() }
            let settings = UserDefaults.standard
            let identify = settings.object(forKey: Prefs.identifySpeakers) as? Bool ?? true
            if identify && settings.integer(forKey: Prefs.speakerCount) != 1 {
                findSpeakers(id)
            } else {
                summarize(id, automatic: true)
            }
        }
    }

    /// A helper: the copy inside the app (so a DMG install works on its own), else ~/.local/bin.
    /// Native helpers (speakers) are in Contents/MacOS, scripts (transcribe) in Contents/Resources.
    func bin(_ name: String) -> String {
        if let native = Bundle.main.url(forAuxiliaryExecutable: name),
           FileManager.default.isExecutableFile(atPath: native.path) {
            return native.path
        }
        if let bundled = Bundle.main.url(forResource: name, withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }
        return home.appendingPathComponent(".local/bin/\(name)").path
    }

    /// Runs a helper off the main thread, stopping it (and what it started) after `timeout` seconds.
    nonisolated static func run(_ args: [String], timeout: TimeInterval) async -> HelperOutcome {
        // The helpers use the tools bundled in the app. Homebrew stays on PATH only as the fallback
        // for files AVFoundation can't decode (ffmpeg, for Ogg and WebM) and for source builds.
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        return await HelperRun.run(["/usr/bin/env"] + args, timeout: timeout, environment: env)
    }

    /// The time limit for a job on this recording, from its length (ADR-2611072100 A1).
    nonisolated static func jobTimeout(_ audio: URL) async -> TimeInterval {
        HelperRun.timeout(audioSeconds: try? await AVURLAsset(url: audio).load(.duration).seconds)
    }

    /// An error for the log: its domain and code, never its description, which can quote what was said.
    nonisolated static func logDescription(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }

    // MARK: Speakers

    /// `count` overrides the Settings choice for this one run: 0 detects automatically, 2+ is exact.
    func findSpeakers(_ id: Recording.ID, count: Int? = nil) {
        guard !findingSpeakers.contains(id), !transcribing.contains(id) else { return }
        let path = dir.appendingPathComponent(id).path
        guard FileManager.default.fileExists(atPath: (path as NSString).deletingPathExtension + ".json") else {
            failedStep[id] = .transcribe
            errors[id] = "Transcribe this recording again first: speaker detection needs the word timings "
                + "that newer transcriptions save."
            return
        }
        if !ModelCatalog.missing([.speakers], root: models.root).isEmpty {
            // Not an error worth a red box: the transcript is fine, it just has no names yet.
            log("speakers skipped, models missing: \(id)")
            summarize(id, automatic: true)
            return
        }
        findingSpeakers.insert(id)
        errors[id] = nil
        log("finding speakers: \(id)")
        let count = count ?? UserDefaults.standard.integer(forKey: Prefs.speakerCount)
        let args = [bin("speakers"), path] + (count > 1 ? ["-n", String(count)] : [])
        let audio = dir.appendingPathComponent(id)
        Task {
            let outcome = await Self.run(args, timeout: await Self.jobTimeout(audio))
            findingSpeakers.remove(id)
            log(outcome.logLine("speakers"))
            if let failure = outcome.userMessage {
                errors[id] = "Speaker detection failed:\n\(failure)"
                failedStep[id] = .speakers
            }
            if selection == id { loadSelected() }
            summarize(id, automatic: true)
        }
    }

    /// The speaker names used in a transcript, in order of first appearance ("Speaker 1", or a renamed "Gary").
    nonisolated static func speakerNames(in transcript: String) -> [String] {
        SummaryFormat.speakerNames(in: transcript)
    }

    /// Renames a speaker throughout the transcript, then in the summary. The summary is changed in place,
    /// not written again by the model, so it is instant, keeps hand edits, and loses no rename.
    func renameSpeaker(_ old: String, to new: String) {
        let name = new.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ":", with: "")
        guard let id = selection, !name.isEmpty, name != old else { return }
        transcript = transcript.replacingOccurrences(
            of: #"(?m)^(\[\d\d:\d\d:\d\d\] )"# + NSRegularExpression.escapedPattern(for: old) + ":",
            with: "$1" + NSRegularExpression.escapedTemplate(for: name) + ":",
            options: .regularExpression)
        saveTranscriptIfEdited()
        log("renamed speaker")
        if summarizing.contains(id) {
            // That summary was started from the old transcript; rename in it once it is written.
            pendingRenames[id, default: []].append((old, name))
        } else {
            renameInSummary(id, renames: [(old, name)])
        }
    }

    /// Speaker renames made while a summary was being written, applied when it is done.
    private var pendingRenames: [Recording.ID: [(old: String, new: String)]] = [:]

    private func renameInSummary(_ id: Recording.ID, renames: [(old: String, new: String)]) {
        guard let r = items.first(where: { $0.id == id }),
              let md = try? String(contentsOf: r.summaryURL, encoding: .utf8) else { return }
        if selection == id && editingSummary { endEditingSummary() }
        let renamed = renames.reduce(md) { Self.replacingName($1.old, with: $1.new, in: $0) }
        guard renamed != md else { return }
        try? renamed.write(to: r.summaryURL, atomically: true, encoding: .utf8)
        log("renamed speaker in summary")
        reload()  // the name may be in the summary's title
        if selection == id { summary = renamed }
    }

    /// Replaces a whole name: "Speaker 1" matches "Speaker 1's" but not "Speaker 10".
    nonisolated static func replacingName(_ old: String, with new: String, in text: String) -> String {
        text.replacingOccurrences(
            of: #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: old) + #"(?![\p{L}\p{N}])"#,
            with: NSRegularExpression.escapedTemplate(for: new),
            options: .regularExpression)
    }

    // MARK: Summarize

    /// The template a recording's summary was made with, read from the summary file's first line.
    func templateID(for r: Recording) -> String {
        let first = (try? String(contentsOf: r.summaryURL, encoding: .utf8))?
            .split(separator: "\n").first.map(String.init) ?? ""
        if let m = first.firstMatch(of: #/<!-- template: ([\w-]+) -->/#) { return String(m.1) }
        return UserDefaults.standard.string(forKey: Prefs.summaryTemplate) ?? SummaryTemplate.all[0].id
    }

    /// `automatic` is for summaries the app starts by itself; those never replace a hand-edited summary.
    /// Ones the user asks for do, but only after `replaceEdits` confirms it.
    func summarize(_ id: Recording.ID, template: String? = nil, automatic: Bool = false, replaceEdits: Bool = false) {
        guard !summarizing.contains(id), let r = items.first(where: { $0.id == id }) else { return }
        if r.summaryIsEdited && !replaceEdits {
            if automatic {
                notice = "Your edited summary was kept. Click Summarize to write a new one."
                log("kept edited summary: \(id)")
            } else {
                pendingOverwrite = PendingSummary(id: id, template: template)
            }
            return
        }
        if selection == id { editingSummary = false }
        let text = (try? String(contentsOf: r.transcriptURL, encoding: .utf8)) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errors[id] = "There is no speech in the transcript to summarize."
            failedStep[id] = .transcribe
            return
        }
        let chosen = SummaryTemplate.find(template ?? templateID(for: r))
        summarizing.insert(id)
        errors[id] = nil
        log("summarizing: \(id) with \(chosen.id)")
        Task {
            do {
                let length = try? await AVURLAsset(url: r.audio).load(.duration).seconds
                // Notes typed during the meeting go first, labelled as the recorder's own (ADR-2611142100).
                let notes = try? String(contentsOf: MeetingNotes.url(for: r.audio), encoding: .utf8)
                let material = MeetingNotes.compose(transcript: text, notes: notes)
                let md = try await Summarizer.summarize(material, template: chosen, date: r.date, seconds: length)
                try md.write(to: r.summaryURL, atomically: true, encoding: .utf8)
                summarizing.remove(id)
                log("summary finished: \(md.count) chars")
                reload()  // the summary's title renames the recording in the timeline
                if selection == id { summary = md }
                if let renames = pendingRenames.removeValue(forKey: id) { renameInSummary(id, renames: renames) }
            } catch {
                summarizing.remove(id)
                // The earlier summary is still there, with the old names.
                if let renames = pendingRenames.removeValue(forKey: id) { renameInSummary(id, renames: renames) }
                errors[id] = "Summary failed: \(Summarizer.describe(error))"
                failedStep[id] = .summary
                log("summary failed: \(Self.logDescription(error))")
            }
        }
    }

    // MARK: Editing the summary

    /// The draft and the whole summary file as they were when editing began.
    private var summaryDraftBaseline = ""
    private var summaryBeforeEditing = ""

    func beginEditingSummary() {
        guard !summary.isEmpty else { return }
        // Edit the summary file's own text. (Not the displayed one: that swaps in the recording's
        // name for the title, and saving it would overwrite the model's title in the file.)
        // The hidden header lines (template, edited) stay out of the editor and are put back on save.
        summaryDraft = summary
            .split(separator: "\n", omittingEmptySubsequences: false)
            .drop { $0.hasPrefix("<!--") }
            .joined(separator: "\n")
        summaryDraftBaseline = summaryDraft
        summaryBeforeEditing = summary
        editingSummary = true
        log("editing summary")
    }

    /// Called on every keystroke while editing; writes only real changes.
    func saveSummaryDraft() {
        guard let r = selected else { return }
        if summaryDraft == summaryDraftBaseline {
            // Back to exactly what it was (or never changed): restore the original file, unmarked.
            if summary != summaryBeforeEditing {
                try? summaryBeforeEditing.write(to: r.summaryURL, atomically: true, encoding: .utf8)
                summary = summaryBeforeEditing
            }
            return
        }
        let md = "<!-- template: \(templateID(for: r)) -->\n\(Self.editedMarker)\n" + summaryDraft
        guard md != summary else { return }
        try? md.write(to: r.summaryURL, atomically: true, encoding: .utf8)
        summary = md
    }

    func endEditingSummary() {
        saveSummaryDraft()
        editingSummary = false
        log("finished editing summary")
        reload()  // an edited "# Title" renames the recording in the timeline
    }

    // MARK: Files

    /// Names a recording. An empty name goes back to the automatic one (the summary's title).
    func rename(_ id: Recording.ID, to name: String) {
        guard let r = items.first(where: { $0.id == id }) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            try? FileManager.default.removeItem(at: r.nameURL)
        } else {
            try? clean.write(to: r.nameURL, atomically: true, encoding: .utf8)
        }
        log("renamed recording")
        reload()
    }

    func moveToTrash(_ r: Recording) {
        let json = URL(fileURLWithPath: r.audio.deletingPathExtension().path + ".json")
        for url in [r.audio, r.transcriptURL, r.srtURL, r.summaryURL, json, r.nameURL, MeetingNotes.url(for: r.audio)]
        where FileManager.default.fileExists(atPath: url.path) || url == r.audio {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        if selection == r.id { selection = nil }
        reload()
    }

    func showInFinder(_ r: Recording) {
        let target = r.hasTranscript ? r.transcriptURL : r.audio
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    func copyCurrentTab() {
        NSPasteboard.general.clearContents()
        let text = tab == .transcript ? transcript : (selected?.displayedSummary(summary) ?? summary)
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// A model download finished: transcribe what was waiting for it, if its models are now here.
    func modelsArrived() {
        models.refresh()
        for id in waitingForModels where items.contains(where: { $0.id == id }) {
            let needed: Set<ModelGroup> = translate ? [.speech, .translate] : [.speech]
            if ModelCatalog.missing(needed, root: models.root).isEmpty { transcribe(id) }
        }
    }

    func log(_ message: String) {
        let url = home.appendingPathComponent("Library/Logs/Earshot.log")
        // Owner-only, and a symlink in its place is not followed (ADR-2611072100 A3).
        PrivateFiles.appendLine("\(Date().formatted(.iso8601)) \(message)\n", to: url)
    }
}

// MARK: - Microphone

/// Asks CoreAudio whether any other process is capturing from a microphone right now.
/// Returns nil when the process list can't be read; otherwise whether another process
/// is capturing, plus the bundle ids (or pids, when there is no bundle id) for logging.
enum OtherAppMicProbe {
    /// Audio-routing daemons that hold the input open all the time, whether or not anyone is in a call.
    /// Counting them made Earshot offer to record a "meeting" that was not happening, and kept a
    /// recording from ever stopping itself. Rogue Amoeba's ARK daemon runs behind SoundSource,
    /// Loopback and Audio Hijack.
    nonisolated static let alwaysCapturingDaemons: Set<String> = ["com.rogueamoeba.arkaudiod"]

    nonisolated static func otherAppCapturing() -> (Bool, [String])? {
        guard let procs = capturingProcesses() else { return nil }
        let names = procs.map { $0.bundleID ?? "pid \($0.pid)" }
        return (!names.isEmpty, names)
    }

    /// The other processes (not this one) that are capturing input right now; nil when the process list can't be read.
    nonisolated static func capturingProcesses() -> [(pid: pid_t, bundleID: String?)]? {
        func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var listAddress = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &listAddress, 0, nil, &size, &ids) == noErr else { return nil }

        var capturing: [(pid: pid_t, bundleID: String?)] = []
        for id in ids {
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddress = address(kAudioProcessPropertyPID)
            guard AudioObjectGetPropertyData(id, &pidAddress, 0, nil, &pidSize, &pid) == noErr,
                  pid != getpid() else { continue }
            var input: UInt32 = 0
            var inputSize = UInt32(MemoryLayout<UInt32>.size)
            var inputAddress = address(kAudioProcessPropertyIsRunningInput)
            guard AudioObjectGetPropertyData(id, &inputAddress, 0, nil, &inputSize, &input) == noErr,
                  input != 0 else { continue }
            var bundle: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var bundleAddress = address(kAudioProcessPropertyBundleID)
            if AudioObjectGetPropertyData(id, &bundleAddress, 0, nil, &bundleSize, &bundle) == noErr,
               let name = bundle?.takeRetainedValue() as String?, !name.isEmpty {
                if alwaysCapturingDaemons.contains(name) { continue }
                capturing.append((pid: pid, bundleID: name))
            } else {
                capturing.append((pid: pid, bundleID: nil))
            }
        }
        return capturing
    }
}

/// Posts the "Record this meeting?" notification and reports the user's choice through closures.
final class CallOfferNotifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let categoryID = "callOffer"
    static let recordAction = "callOffer.record"
    static let ignoreAction = "callOffer.ignore"

    var onRecord: @MainActor () -> Void = {}
    var onIgnore: @MainActor (String) -> Void = { _ in }
    private var registered = false

    private func register() {
        guard !registered else { return }
        registered = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let record = UNNotificationAction(identifier: Self.recordAction, title: "Record", options: [.foreground])
        let ignore = UNNotificationAction(identifier: Self.ignoreAction, title: "Not for this app", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [record, ignore],
                                   intentIdentifiers: [], options: [])
        ])
    }

    /// Asks for permission if needed and posts the offer. Returns nil when it was posted, else why not.
    func offer(appName: String, bundleID: String?) async -> String? {
        register()
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else { return "authorization refused" }
        } catch {
            return Self.describe(error)
        }
        let content = UNMutableNotificationContent()
        content.title = "\(appName) is using the microphone"
        content.body = "Record this meeting?"
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["bundleID": bundleID ?? "", "appName": appName]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await center.add(request)
            return nil
        } catch {
            return Self.describe(error)
        }
    }

    /// "UNErrorDomain 1: Notifications are not allowed for this application".
    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let bundleID = response.notification.request.content.userInfo["bundleID"] as? String ?? ""
        let action = response.actionIdentifier
        Task { @MainActor in
            if action == Self.ignoreAction {
                if !bundleID.isEmpty { self.onIgnore(bundleID) }
            } else if action == Self.recordAction || action == UNNotificationDefaultActionIdentifier {
                self.onRecord()
            }
            completionHandler()
        }
    }
}

/// Records one chosen microphone to a 16 kHz mono WAV, the format whisper.cpp wants.
/// AVAudioRecorder can only use the system default input, so this uses a capture session.
final class MicRecorder: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    static let settingKey = "microphoneID"  // AVCaptureDevice.uniqueID; "" means the system default

    let url: URL
    let deviceName: String
    let usedFallback: Bool
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioFileOutput()
    private let queue = DispatchQueue(label: "Earshot.mic")
    private let finished: (MicRecorder, Bool, NSError?) -> Void  // stopRequested, raw error
    private var stopRequested = false

    static func inputs() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                         mediaType: .audio, position: .unspecified).devices
    }

    convenience init(deviceID: String, url: URL, finished: @escaping (MicRecorder, RecordingEnd) -> Void) throws {
        try self.init(deviceID: deviceID, url: url, raw: { rec, stopRequested, error in
            finished(rec, RecordingEnd.classify(stopRequested: stopRequested, error: error))
        })
    }

    /// Dictation and notes keep the older contract: nil unless the capture failed.
    convenience init(deviceID: String, url: URL, finished: @escaping (MicRecorder, Error?) -> Void) throws {
        try self.init(deviceID: deviceID, url: url, raw: { rec, _, error in
            // Capture outputs report some normal stops as errors, flagged as "finished successfully".
            let ok = error?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
            finished(rec, ok ? nil : error)
        })
    }

    private init(deviceID: String, url: URL, raw finished: @escaping (MicRecorder, Bool, NSError?) -> Void) throws {
        let chosen = deviceID.isEmpty ? nil : AVCaptureDevice(uniqueID: deviceID)
        guard let device = chosen ?? AVCaptureDevice.default(for: .audio) else {
            throw AppError(message: "No microphone is connected.")
        }
        self.url = url
        self.deviceName = device.localizedName
        self.usedFallback = !deviceID.isEmpty && chosen == nil
        self.finished = finished
        super.init()

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw AppError(message: "\(device.localizedName) can't be used for recording.")
        }
        session.addInput(input)
        session.addOutput(output)
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        session.commitConfiguration()
    }

    func start() {
        // startRunning blocks, so keep it off the main thread.
        queue.async { [self] in
            session.startRunning()
            output.startRecording(to: url, outputFileType: .wav, recordingDelegate: self)
        }
    }

    func stop() {
        queue.async { [self] in
            stopRequested = true
            output.stopRecording()
        }
    }

    var level: Float {
        output.connections.first?.audioChannels.map(\.averagePowerLevel).max() ?? -160
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        session.stopRunning()
        finished(self, stopRequested, error as NSError?)
    }
}

struct SettingsView: View {
    @Binding var translate: Bool
    let translateLocked: Bool
    @AppStorage(MicRecorder.settingKey) private var microphoneID = ""
    @AppStorage(Prefs.autoStopMinutes) private var autoStopMinutes = 5
    @AppStorage(Prefs.identifySpeakers) private var identifySpeakers = true
    @AppStorage(Prefs.speakerCount) private var speakerCount = 0
    @AppStorage(Prefs.summaryTemplate) private var summaryTemplate = SummaryTemplate.all[0].id
    @AppStorage(Prefs.offerOnCall) private var offerOnCall = true
    @State private var inputs: [AVCaptureDevice] = []
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginNotice: String?

    /// On means registered, whether or not macOS still wants the user to approve it in Login Items.
    private var openAtLogin: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }

    private func refreshLogin() {
        loginStatus = SMAppService.mainApp.status
        switch loginStatus {
        case .requiresApproval:
            loginNotice = "macOS needs you to allow Earshot in System Settings → General → Login Items."
        case .notFound:
            loginNotice = "macOS can't find Earshot as a login item. Move Earshot to your Applications folder and try again."
        default:
            if loginNotice?.hasPrefix("Couldn't") != true { loginNotice = nil }
        }
    }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginNotice = nil
        } catch {
            loginNotice = "Couldn't change Open at login: \(error.localizedDescription)"
        }
        refreshLogin()
    }

    private var defaultName: String { AVCaptureDevice.default(for: .audio)?.localizedName ?? "none" }
    private var chosenMissing: Bool { !microphoneID.isEmpty && !inputs.contains { $0.uniqueID == microphoneID } }

    var body: some View {
        RecordingSettingsCards(
            microphoneID: $microphoneID,
            microphones: inputs.map { SettingsChoice(id: $0.uniqueID, name: $0.localizedName) },
            defaultMicrophoneName: defaultName,
            autoStopMinutes: $autoStopMinutes,
            offerOnCall: $offerOnCall,
            openAtLogin: Binding(get: { openAtLogin }, set: { setOpenAtLogin($0) }),
            loginNotice: loginNotice,
            onOpenLoginItems: loginStatus == .requiresApproval ? { SMAppService.openSystemSettingsLoginItems() } : nil,
            translate: $translate,
            translateLocked: translateLocked,
            identifySpeakers: $identifySpeakers,
            speakerCount: $speakerCount,
            summaryTemplate: $summaryTemplate,
            templates: SummaryTemplate.all.map { SettingsChoice(id: $0.id, name: $0.name, icon: $0.icon) },
            callAudioRows: AnyView(CallAudioSettingsRows()))
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .onAppear { inputs = MicRecorder.inputs(); refreshLogin() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshLogin() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in
            inputs = MicRecorder.inputs()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in
            inputs = MicRecorder.inputs()
        }
    }
}

/// A horizontal bar that shows how loud the microphone input is.
struct LevelBar: View {
    let decibels: Float

    var body: some View {
        // Map -60 dB (silence) … 0 dB (very loud) to 0 … 1.
        let fill = CGFloat(max(0, min(1, (decibels + 60) / 60)))
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(fill > 0.9 ? Color.red : fill > 0.7 ? Color.brandWarning : Color.green)
                    .frame(width: geo.size.width * fill)
            }
        }
        .frame(width: 240, height: 8)
        .animation(.linear(duration: 0.08), value: fill)
    }
}

// MARK: - Resource meter

/// Samples CPU and memory for this app plus its helper processes (bash, whisper-cli, speakers),
/// and how busy the GPU is. Whisper runs mostly on the GPU, so CPU alone would look idle.
@MainActor
final class ResourceMonitor: ObservableObject {
    @Published var cpuPercent = 0.0  // share of the whole Mac's CPU, 0–100
    @Published var memoryBytes: UInt64 = 0
    @Published var gpuPercent: Int?  // whole GPU, every app; per-process GPU use isn't public

    private var lastCPU: [pid_t: UInt64] = [:]
    private var lastSample = DispatchTime.now().uptimeNanoseconds
    private var timer: Timer?
    private let cores = Double(ProcessInfo.processInfo.activeProcessorCount)
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var tb = mach_timebase_info()
        mach_timebase_info(&tb)
        return (UInt64(tb.numer), UInt64(tb.denom))
    }()

    init() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    private func sample() {
        let now = DispatchTime.now().uptimeNanoseconds
        let wall = Double(now - lastSample)
        lastSample = now

        var cpu: [pid_t: UInt64] = [:]
        var footprint: UInt64 = 0
        for pid in Self.family(of: getpid()) {
            var info = rusage_info_v2()
            let rc = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard rc == 0 else { continue }
            // rusage times are in Mach ticks on Apple Silicon; convert to nanoseconds.
            cpu[pid] = (info.ri_user_time + info.ri_system_time) * timebase.numer / timebase.denom
            footprint += info.ri_phys_footprint
        }
        let used = cpu.reduce(0.0) { sum, entry in
            sum + Double(entry.value &- (lastCPU[entry.key] ?? 0))
        }
        lastCPU = cpu
        if wall > 0 { cpuPercent = min(100, max(0, used / (wall * cores) * 100)) }
        memoryBytes = footprint
        gpuPercent = Self.gpuUtilization()
    }

    /// This process and its descendants, a few levels deep (app → bash → whisper-cli).
    private static func family(of root: pid_t) -> [pid_t] {
        var result = [root]
        var frontier = [root]
        for _ in 0..<4 where !frontier.isEmpty {
            var next: [pid_t] = []
            for pid in frontier {
                var kids = [pid_t](repeating: 0, count: 32)
                _ = proc_listchildpids(pid, &kids, Int32(kids.count * MemoryLayout<pid_t>.size))
                next += kids.filter { $0 > 0 }
            }
            result += next
            frontier = next
        }
        return result
    }

    private static func gpuUtilization() -> Int? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(it) }
        var best: Int?
        while case let service = IOIteratorNext(it), service != 0 {
            defer { IOObjectRelease(service) }
            if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                           kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let util = stats["Device Utilization %"] as? Int {
                best = max(best ?? 0, util)
            }
        }
        return best
    }
}

/// The window's bottom status bar: current activity on the left, the CPU · GPU · MEM meter on the right.
struct StatusBar: View {
    @ObservedObject var lib: Library
    @ObservedObject var monitor: ResourceMonitor

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                activity
                Spacer()
                ResourceMeter(monitor: monitor)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(.bar)
    }

    @ViewBuilder private var activity: some View {
        let jobs = [
            (lib.transcribing.count, "Transcribing"),
            (lib.findingSpeakers.count, "Finding speakers"),
            (lib.summarizing.count, "Summarizing"),
        ].filter { $0.0 > 0 }.map { $0.0 > 1 ? "\($0.1) (\($0.0))" : $0.1 }

        if lib.recording {
            Label("Recording" + (lib.micName.map { " · \($0)" } ?? ""), systemImage: "record.circle")
                .foregroundStyle(.red)
        } else if !jobs.isEmpty {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(jobs.joined(separator: " · ") + "…")
            }
        } else {
            Label("\(lib.items.count) recording\(lib.items.count == 1 ? "" : "s") · all on this Mac",
                  systemImage: "lock.fill")
        }
    }
}

struct ResourceMeter: View {
    @ObservedObject var monitor: ResourceMonitor

    var body: some View {
        HStack(spacing: 12) {
            reading("CPU", String(format: "%.0f%%", monitor.cpuPercent))
            reading("GPU", monitor.gpuPercent.map { "\($0)%" } ?? "–")
            reading("MEM", ByteCountFormatter.string(fromByteCount: Int64(monitor.memoryBytes), countStyle: .memory))
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 8)
        .help("""
            CPU and MEM: this app plus Whisper and the speaker tool while they run (CPU as a share of the whole Mac).
            GPU: the whole Mac's graphics chip, where Whisper does most of its work.
            Summaries run inside a macOS system process, so they show in GPU but not in CPU or MEM.
            """)
    }

    private func reading(_ name: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(name).foregroundStyle(.secondary)
            Text(value)
        }
    }
}

// MARK: - In-app docs

struct HelpMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("How Earshot Works") { openWindow(id: HelpView.windowID) }
            .keyboardShortcut("?", modifiers: .command)
    }
}

/// The app's own icon, as macOS draws it (Liquid Glass and all). Apple's guidelines put the
/// logo in places like About and welcome screens, not repeated through the interface.
struct AppIcon: View {
    let size: CGFloat
    var body: some View {
        // Ask for the icon the way Finder does, so the layered Liquid Glass icon renders as in the Dock.
        Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityLabel("Earshot")
    }
}

// MARK: - Menu bar

/// The menu bar item: the Earshot ear, or a red dot and the timer while recording.
struct MenuBarLabel: View {
    @ObservedObject var lib: Library

    static let ear: NSImage = {
        let img = Bundle.main.url(forResource: "menubar", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "ear", accessibilityDescription: "Earshot")!
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = true  // macOS colors it to match a light or dark menu bar
        return img
    }()

    // The label is drawn into the status item as an image, not hosted live. A TimelineView here
    // re-renders on every redraw, which loops forever and hangs the app; a plain timer ticks once a second.
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let start = lib.startedAt {
                HStack(spacing: 4) {
                    Image(systemName: "record.circle")
                    Text(elapsed(from: start, to: now)).monospacedDigit()
                }
                .accessibilityLabel("Earshot is recording")
            } else {
                Image(nsImage: Self.ear).accessibilityLabel("Earshot")
            }
        }
        .onReceive(tick) { date in
            if lib.startedAt != nil { now = date }
        }
    }
}

/// Offers to try again when a dictation clip could not be transcribed.
struct RetryDictationRow: View {
    @ObservedObject var dictation: DictationService

    var body: some View {
        if dictation.retryAvailable {
            Button {
                dictation.retryLast()
            } label: {
                Label("Retry last dictation", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)
        }
    }
}

/// The first-launch "Set up Earshot" card with live permission state (ADR-2611142200). Accessibility is
/// checked every second while the card shows, so its row ticks as soon as it is switched on.
struct SetupCardHost: View {
    @AppStorage(DictationPrefs.enabled) private var dictationEnabled = false
    @AppStorage("setupDictationSkipped") private var dictationSkipped = false
    @State private var microphone = SetupCardHost.micStatus()
    @State private var trusted = AXIsProcessTrusted()

    private var checklist: SetupChecklist {
        SetupChecklist(microphone: microphone, dictationEnabled: dictationEnabled,
                       accessibilityTrusted: trusted, dictationSkipped: dictationSkipped)
    }

    var body: some View {
        SetupCard(
            checklist: checklist,
            onAllowMicrophone: {
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    DispatchQueue.main.async { microphone = Self.micStatus() }
                }
            },
            onOpenMicrophoneSettings: { Self.openPrivacy("Privacy_Microphone") },
            onTurnOnDictation: {
                dictationEnabled = true
                DictationService.requestPermissions()
            },
            onOpenAccessibilitySettings: { Self.openPrivacy("Privacy_Accessibility") },
            onSkipDictation: { dictationSkipped = true })
        .padding(.bottom, checklist.showsCard ? 22 : 0)  // space above Home's greeting, only while shown
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard checklist.showsCard else { return }
            trusted = AXIsProcessTrusted()
            microphone = Self.micStatus()
        }
    }

    static func micStatus() -> SetupChecklist.Mic {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .allowed
        case .notDetermined: return .notAsked
        default: return .refused
        }
    }

    static func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The panel that opens from the menu bar.
struct MenuBarPanel: View {
    @ObservedObject var lib: Library
    @ObservedObject var nav: Navigator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarPanelView(
            icon: AnyView(AppIcon(size: 28)),
            recordingSince: lib.startedAt,
            micName: lib.micName,
            level: { lib.micLevel() },
            endingIn: lib.endingIn,
            recent: lib.items.prefix(5).map { MenuBarRecent(id: $0.id, title: $0.title, date: $0.date) },
            version: AppVersion.display,
            extra: AnyView(RetryDictationRow(dictation: lib.dictation)),
            onRecord: lib.toggleRecording,
            onKeepRecording: lib.keepRecording,
            onOpen: { open($0) },
            onSettings: openSettings,
            onQuit: { NSApp.terminate(nil) })
    }

    private func openSettings() {
        nav.section = .settings
        openWindow(id: MainWindow.id)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func open(_ id: Recording.ID?) {
        if let id {
            lib.selection = id
            lib.tab = .summary
        }
        // Bring the existing window forward; open one only if it was closed.
        if let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue.contains(MainWindow.id) == true && $0.isVisible
        }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: MainWindow.id)
        }
        NSApp.activate()
    }
}

/// The "How Earshot Works" window: what runs where, and what never leaves the Mac.
struct HelpView: View {
    static let windowID = "help"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    AppIcon(size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Everything stays on this Mac").font(.title.bold())
                        Text("Earshot has no account and no cloud service, and after the one-time model download it needs no internet. "
                             + "Your recordings, transcripts and summaries are made and kept on this computer.")
                            .foregroundStyle(.secondary)
                        Text("Earshot \(AppVersion.display)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                section("Try it yourself", "wifi.slash") {
                    para("Turn off Wi-Fi and record something. Transcription and summaries still work, "
                         + "because no step needs the internet.")
                }

                section("Recording the other side of a call", "phone.arrow.down.left") {
                    para("In Settings, Call audio can add the sound a call plays to your recording, from all system "
                         + "audio or from an input device. It is off until you choose a source. That audio stays on this Mac, like the "
                         + "rest. It can include other people's voices, and getting their consent, or recording only "
                         + "where the law allows it, is your responsibility.")
                }

                section("Download the speech models", "arrow.down.circle") {
                    para("The first time you open Earshot, it asks to download its models (about 1.7 GB) into "
                         + "~/Models. This is the only time Earshot uses the internet: it fetches the files from "
                         + "Hugging Face and GitHub, checks each one against a fixed fingerprint (SHA-256), and "
                         + "sends nothing about you. Translate needs one more model (1.1 GB), offered the first "
                         + "time you turn Translate on.")
                }

                section("What does each job", "cpu") {
                    item("Speech to text",
                         "Whisper large-v3-turbo, an open model from OpenAI, run by whisper.cpp on this Mac's graphics chip. "
                         + "The model is a file in ~/Models/whisper.")
                    item("Translate to English",
                         "Whisper large-v3, the full model. The turbo model can't translate, so the app switches "
                         + "to this one when Translate is on.")
                    item("Skipping silence",
                         "Silero, a very small voice-detection model. It finds the parts with speech, so Whisper "
                         + "does not invent words in quiet stretches.")
                    item("Summaries",
                         "Apple's on-device Foundation Model, part of Apple Intelligence. It runs inside macOS on this Mac. "
                         + "Earshot never uses Apple's Private Cloud Compute, the version that runs on Apple's servers.")
                    item("Audio conversion",
                         "macOS itself (AVFoundation), which turns any audio or video file it can play into the format "
                         + "Whisper reads. For Ogg and WebM, which macOS can't read, Earshot uses ffmpeg if it is installed.")
                    item("Speakers",
                         "sherpa-onnx with the pyannote and WeSpeaker voice models, built into the app. It finds who "
                         + "spoke when and labels the transcript Speaker 1, Speaker 2.")
                }

                section("Where your files are", "folder") {
                    item("Recordings and results", "~/Recordings/whisper. For each recording: the audio, "
                         + ".txt (transcript), .srt (with timestamps) and .summary.md (summary).")
                    item("Imported files", "Linked into the timeline, not copied. The original stays where it was.")
                    item("Activity log", "~/Library/Logs/Earshot.log. It records clicks, file names and job results, never what was said.")
                    para("Rename a recording with the pencil next to its title, by double-clicking the title, or with "
                         + "right-click → Rename. Until you name it, it takes the title Apple's model gives the summary.")
                    para("Delete a recording with right-click → Move to Trash. That removes the audio, transcript and summary.")
                }

                section("The header bar", "menubar.rectangle") {
                    item("Back to Recordings", "Open a recording and a Recordings / name link appears at the top left. "
                         + "Click it, press Esc or Command-[, or click Recordings in the sidebar, to return to the list.")
                    item("Record / Stop", "Starts and stops the microphone. The timer shows how long it has recorded. ⌘R.")
                    item("Your notes", "While recording, type names, decisions and to-dos in the box under the timer. "
                         + "They are saved beside the recording and its summary uses them.")
                    item("Automatic stop", "If no one speaks for a while, Earshot stops recording by itself. "
                         + "It counts down for 30 seconds first, and Keep recording carries on. "
                         + "Change the time, or turn it off, in Settings. While a call app such as Zoom is using the "
                         + "microphone Earshot keeps recording, and it stops about a minute after the call ends.")
                    item("Import", "Transcribe an audio or video file you already have. You can also drag files into the window. ⌘O.")
                    item("Translate", "In Settings → Transcription. When on, speech in another language is written in English.")
                    item("Summarize", "Writes a new summary of the selected recording.")
                    item("Copy", "Copies the open tab, transcript or summary. ⇧⌘C.")
                    item("Finder", "Shows the recording's files in Finder.")
                    item("Privacy", "Opens this page. ⌘?.")
                    item("Menu bar", "The ear at the top of your screen records without opening the window. "
                         + "While recording it shows the timer. It also lists your five latest recordings.")
                    item("Settings", "Choose which microphone to record from. While recording, the screen "
                         + "shows the microphone's name and a level bar, so you can see it hears you. ⌘,.")
                }

                section("Calls", "phone.badge.waveform") {
                    item("Offer to record", "When another app, such as Zoom, Teams or Meet, has been using the "
                         + "microphone for about 10 seconds, Earshot shows a small panel at the top right of the "
                         + "screen: Record this meeting? with Record and Not for <App>. It goes away by itself when "
                         + "the call ends or after two minutes. It only asks; it never records without your click. Choose Not for that app to stop "
                         + "asking about it. Earshot has to be running to notice a call, so turn on Open Earshot at "
                         + "login in Settings and it waits in the menu bar.")
                }

                section("The status bar", "rectangle.bottomthird.inset.filled") {
                    item("Left side", "What Earshot is doing now: recording, transcribing, finding speakers or "
                         + "summarizing. When it is idle, how many recordings you have.")
                    item("CPU · GPU · MEM", "How hard the Mac is working. CPU and memory count this app and Whisper. "
                         + "GPU counts the whole graphics chip, where Whisper and the summary model do most of their work.")
                }

                section("Dictation", "keyboard") {
                    item("Dictate into any app", "Off until you turn it on in Settings, Dictation. Hold the shortcut "
                         + "(Control, Option, Space unless you change it), speak, and let go: Earshot types what you "
                         + "said into the app in front. It needs Microphone and Accessibility permission.")
                    item("Tap to start, tap to stop", "An alternative to holding the keys, in Settings, Dictation, Mode.")
                    item("Fix words it mishears", "In Settings, Dictation, Corrections, write one per line as: "
                         + "ear shot => Earshot. Whole words only, ignoring case.")
                    item("Tidy up what I say", "Optional, off by default. Removes ums and fixes punctuation using "
                         + "Apple's on-device model, so the text stays on this Mac. It can reword slightly, and if "
                         + "the model is unavailable the original words are typed.")
                    item("Highlight the window", "A little fire around the window your words will be typed into while "
                         + "you dictate. It only reads the window position and size. With Reduce Motion on, it is a "
                         + "plain glowing border. Turn it off in Settings, Dictation.")
                    item("Press Return after typing", "Off by default. Presses Return once after the text is typed, "
                         + "so a chat message sends or a form submits. It does nothing for empty text, or when the "
                         + "text could only be left on the clipboard.")
                    item("Say bang to send", "With Say bang to send switched on in "
                         + "Settings, end a dictation with the word bang and Earshot types the rest "
                         + "and presses Control-Return, so you can wake Claude Code without touching the keyboard. "
                         + "Saying only that word just presses Control-Return.")
                    para("Dictation keeps nothing: no text and no audio is saved, except a clip that could not be "
                         + "transcribed, which is kept until your next dictation so Retry last dictation in the menu "
                         + "bar can try again. It never types into password fields, and it is off while a meeting is "
                         + "being recorded.")
                }

                section("Notes", "note.text") {
                    para("Notes is a separate area for your own voice notes. Press Record a note, speak, press Stop. "
                         + "The note is transcribed on this Mac and saved in the list, grouped by day, with Copy and "
                         + "Delete on each. Only the text is kept; the audio is deleted at once. Clear all deletes "
                         + "every note. Nothing is typed into other apps.")
                }

                section("Agents and spoken replies", "waveform") {
                    item("MCP server for agents", "scripts/earshot-mcp is a small read-only server that lets an agent "
                         + "such as Claude Code list your recordings and read their transcripts and summaries. It opens "
                         + "no port and uses no network. Connecting an agent means that agent receives the text it asks "
                         + "for and may send it to its own provider, which is outside the promise that everything "
                         + "stays on this Mac.")
                    item("Hear spoken replies", "scripts/earshot-speak says a short version of each Claude Code reply "
                         + "out loud using the macOS say command, entirely on this Mac. It is off until you run "
                         + "earshot-speak on, and it speaks only for the session you ran it from. earshot-speak off "
                         + "turns it off. Pressing the dictation hotkey stops the voice so you can talk over it.")
                }

                section("Good to know", "info.circle") {
                    para("Summaries need macOS 26.4 or later with Apple Intelligence turned on, in System Settings → "
                         + "Apple Intelligence & Siri.")
                    para("Apple's on-device model reads about 15 minutes of speech at a time. For longer recordings, "
                         + "Earshot summarizes each part first, then summarizes those notes.")
                    para("Transcripts come from speech recognition, so names and technical words can be wrong. "
                         + "You can correct the Transcript tab directly, then click Summarize again.")
                    para("To fix a summary by hand, click Edit above it, change the text, then click Done. "
                         + "Changes save as you type. Earshot asks before replacing an edited summary, and never "
                         + "rewrites one by itself.")
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textSelection(.enabled)
    }

    private func section<Content: View>(_ title: String, _ icon: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
    }

    private func item(_ name: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).fontWeight(.medium)
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 28)
    }

    private func para(_ text: String) -> some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 28)
    }
}

/// Preference keys, shared by the Settings window (@AppStorage) and the library.
enum Prefs {
    static let identifySpeakers = "identifySpeakers"  // Bool, default true
    static let speakerCount = "speakerCount"          // Int, 0 = detect automatically
    static let summaryTemplate = "summaryTemplate"    // SummaryTemplate.id
    static let autoStopMinutes = "autoStopMinutes"    // Int minutes of silence that stop a recording, 0 = off, default 5 when unset

    static let offerOnCall = "offerOnCall"                    // Bool, default true when unset
    static let translate = "translate"                        // Bool, default false
    static let callOfferIgnoredApps = "callOfferIgnoredApps"  // [String] bundle ids never offered for

    /// Whether to offer to record when a call starts: true when the setting is unset.
    static func offerOnCallEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: offerOnCall) != nil else { return true }
        return defaults.bool(forKey: offerOnCall)
    }

    /// Seconds of silence that stop a recording: 300 when the setting is unset, 0 when it is off.
    static func autoStopSeconds(_ defaults: UserDefaults = .standard) -> TimeInterval {
        guard defaults.object(forKey: autoStopMinutes) != nil else { return 300 }
        return TimeInterval(defaults.integer(forKey: autoStopMinutes) * 60)
    }
}

// SummaryTemplate lives in SummaryFormat.swift; AppError and Summarizer live in Summarizer.swift (ADR-2611181715).

// MARK: - Views

struct NotesPage: View {
    @ObservedObject var store: NotesStore
    @ObservedObject var recorder: NoteRecorder

    var body: some View {
        NotesView(items: store.items, recordingSince: recorder.recordingSince,
                  transcribing: recorder.transcribing, level: { recorder.level },
                  onRecord: { recorder.start() }, onStop: { recorder.stop() },
                  onCopy: { text in
                      NSPasteboard.general.clearContents()
                      NSPasteboard.general.setString(text, forType: .string)
                  },
                  onDelete: { store.remove(id: $0) },
                  onClear: { store.clear() })
            .onDisappear { recorder.stop() }
    }
}

struct ContentView: View {
    @ObservedObject var lib: Library
    @ObservedObject var nav: Navigator
    @ObservedObject var models: ModelDownloader
    @State private var askTranslateModel = false
    @Environment(\.openWindow) private var openWindow
    @StateObject private var monitor = ResourceMonitor()
    @State private var dropTargeted = false
    @State private var newName = ""
    @State private var query = ""
    @State private var searchTexts: [String: String] = [:]

    private static let destinations: [SearchDestination] = [
        SearchDestination(id: "shortcut", title: "Shortcut", detail: "Dictation · change the dictation shortcut", keywords: ["hotkey", "keys", "press"]),
        SearchDestination(id: "mode", title: "Mode", detail: "Dictation · hold to talk or tap to start and stop", keywords: ["hold", "tap", "toggle"]),
        SearchDestination(id: "corrections", title: "Corrections", detail: "Dictation · fix words it mishears", keywords: ["dictionary", "words", "spelling", "replace"]),
        SearchDestination(id: "accessibility", title: "Accessibility permission", detail: "Dictation · allow Earshot to type for you", keywords: ["permission", "privacy"]),
        SearchDestination(id: "microphone", title: "Microphone", detail: "Settings · choose what Earshot records from", keywords: ["input", "mic"]),
        SearchDestination(id: "autostop", title: "Stop recording automatically", detail: "Settings · stop after silence", keywords: ["silence", "auto", "stop"]),
        SearchDestination(id: "speakers", title: "Speakers", detail: "Settings · identify who spoke", keywords: ["diarization", "names"]),
        SearchDestination(id: "noteslog", title: "Notes", detail: "Notes · record a voice note", keywords: ["notes", "record", "voice", "memo"]),
        SearchDestination(id: "login", title: "Open at login", detail: "Settings · start Earshot when you log in", keywords: ["startup", "launch"]),
    ]

    private var hits: [SearchHit] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        let docs = lib.items.map { SearchDoc(id: $0.id, title: $0.title, text: searchTexts[$0.id] ?? "") }
        let noteDocs = lib.notes.items.map { item -> SearchDoc in
            let oneLine = item.text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            return SearchDoc(id: item.id, title: String(oneLine.prefix(60)), text: item.text)
        }
        return SearchIndex.search(query, recordings: docs, destinations: Self.destinations, notes: noteDocs)
    }

    private func pick(_ hit: SearchHit) {
        switch hit {
        case let .recording(id, _, _):
            nav.section = .recordings
            lib.selection = id
        case .note:
            nav.section = .notes
        case let .destination(id, _, _):
            if id == "noteslog" {
                nav.section = .notes
            } else {
                nav.section = ["shortcut", "mode", "corrections", "accessibility"].contains(id) ? .dictation : .settings
            }
        }
        query = ""
    }

    private func loadSearchTexts() async {
        let urls = lib.items.map { ($0.id, $0.transcriptURL) }
        let loaded = await Task.detached(priority: .utility) { () -> [String: String] in
            var out: [String: String] = [:]
            for (id, url) in urls {
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    out[id] = String(text.prefix(20000))
                }
            }
            return out
        }.value
        searchTexts = loaded
    }

    private var homeItems: [HomeItem] {
        lib.items.map { r in
            let parts = [r.hasTranscript ? "transcribed" : nil, r.hasSummary ? "summarized" : nil].compactMap { $0 }
            let state: HomeItem.State
            if lib.transcribing.contains(r.id) {
                state = .working
            } else if let message = lib.errors[r.id] {
                state = .failed(message)
            } else {
                state = .done
            }
            return HomeItem(id: r.id, date: r.date, title: r.title,
                            detail: parts.isEmpty ? "Not transcribed yet" : parts.joined(separator: " · "),
                            state: state,
                            actions: HomeAction.choices(hasTranscript: r.hasTranscript, state: state,
                                                        failedStep: lib.failedStep[r.id],
                                                        waitingForModels: lib.isWaitingForModels(r.id)))
        }
    }

    /// Home, with the setup cards as its header: inside its ScrollView, so their wrapped text cannot set
    /// the window's minimum height (it pushed both columns up under the title bar; Tests/WindowLayoutTests).
    private var recordingsHome: some View {
        var home = HomeView(items: homeItems, onOpen: { lib.selection = $0 },
                            header: AnyView(VStack(alignment: .leading, spacing: 0) {
                                ModelSetupCard(models: models)
                                    .padding(.bottom, models.needsRequired || models.state != .idle ? 22 : 0)
                                SetupCardHost()
                            }))
        home.onAction = { id, kind in
            guard let r = lib.items.first(where: { $0.id == id }) else { return }
            switch kind {
            case .transcribe, .retry(.transcribe): lib.transcribe(id)
            case .retry(.speakers): lib.findSpeakers(id)
            case .retry(.summary): lib.summarize(id)
            case .trash: lib.moveToTrash(r)
            }
        }
        home.rowMenu = { item in
            AnyView(Group {
                if let r = lib.items.first(where: { $0.id == item.id }) {
                    Button("Rename…") { lib.renaming = r.id }
                    Button("Show in Finder") { lib.showInFinder(r) }
                    Button("Transcribe Again") { lib.transcribe(r.id) }
                    Button("Find Speakers Again") { lib.findSpeakers(r.id) }.disabled(!r.hasTranscript)
                    Button("Summarize Again") { lib.summarize(r.id) }.disabled(!r.hasTranscript)
                    Divider()
                    Button("Move to Trash", role: .destructive) { lib.moveToTrash(r) }
                }
            })
        }
        return home
    }

    @ViewBuilder
    private var detailContent: some View {
        if nav.section == .settings {
            ScrollView {
                VStack(spacing: 0) {
                    ModelSetupCard(models: models)
                        .padding(.horizontal, 20)
                        .padding(.top, models.needsRequired || models.state != .idle ? 20 : 0)
                    DictationSettingsView(onEnable: { DictationService.requestPermissions() },
                                          onResetPermission: { DictationService.resetAccessibilityPermission() })
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    SettingsView(translate: $lib.translate, translateLocked: lib.recording)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        } else if nav.section == .dictation {
            DictationPage(onEnable: { DictationService.requestPermissions() },
                          onResetPermission: { DictationService.resetAccessibilityPermission() })
        } else if nav.section == .notes {
            NotesPage(store: lib.notes, recorder: lib.noteRecorder)
        } else if lib.recording, let start = lib.startedAt {
            RecordingNow(lib: lib, start: start)
        } else if let r = lib.selected {
            VStack(alignment: .leading, spacing: 0) {
                RecordingDetail(lib: lib, rec: r)
            }
        } else {
            recordingsHome
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    AppIcon(size: 26)
                    Text("Earshot").font(.headline)
                    Spacer()
                }
                SidebarNav(selection: Binding(
                    get: { nav.section },
                    set: { new in
                        switch DetailNav.onSidebarTap(tappedRecordings: new == .recordings, hasOpenRecording: lib.selection != nil) {
                        case .showRecordingsList:
                            lib.selection = nil
                            nav.section = .recordings
                        case .openSection:
                            nav.section = new
                        }
                    }))
                Spacer()
                SidebarStatusCard(ready: !lib.recording,
                                  detail: lib.recording ? "Recording" : (lib.micName ?? "Default microphone"))
                SidebarFooter(settingsSelected: nav.section == .settings,
                              onSettings: { nav.section = .settings },
                              onHelp: { openWindow(id: HelpView.windowID) })
            }
            .padding(12)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            VStack(spacing: 0) {
                TopBar(title: nav.section.title, query: $query, hits: hits,
                       focusToken: nav.focusSearch, onPick: pick,
                       back: lib.recording ? nil : DetailNav.backLink(inRecordings: nav.section == .recordings,
                                                                      openTitle: lib.selected?.title),
                       onBack: { lib.selection = nil })
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onExitCommand {
                        if DetailNav.escapeReturnsToList(inRecordings: nav.section == .recordings,
                                                         hasOpenRecording: lib.selection != nil,
                                                         searchHasText: !query.isEmpty,
                                                         editingText: lib.editingSummary || lib.renaming != nil) {
                            lib.selection = nil
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if nav.section == .recordings {
                            RecordBar(recordingSince: lib.startedAt,
                                      onRecord: lib.toggleRecording,
                                      onImport: { if lib.recording { return }; lib.chooseFile() })
                                .padding(.bottom, 16)
                        }
                    }
            }
            .overlay(alignment: .bottom) {
                if let notice = lib.notice {
                    Text(notice)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding()
                        .padding(.bottom, 90)
                        .onTapGesture { lib.notice = nil }
                }
            }
        }
        .task(id: lib.items.map(\.id)) { await loadSearchTexts() }
        .navigationTitle("Earshot")
        // A status bar along the bottom, as in Finder and Xcode: what's happening, and the meter.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar(lib: lib, monitor: monitor)
        }
        .alert("Rename Recording", isPresented: Binding(get: { lib.renaming != nil },
                                                        set: { if !$0 { lib.renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let id = lib.renaming { lib.rename(id, to: newName) }
            }
            .keyboardShortcut(.defaultAction)
            if let id = lib.renaming, lib.items.first(where: { $0.id == id })?.hasCustomName == true {
                Button("Use Automatic Name") { lib.rename(id, to: "") }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The name shows in the timeline and at the top of the summary.")
        }
        .alert("Replace your edited summary?",
               isPresented: Binding(get: { lib.pendingOverwrite != nil },
                                    set: { if !$0 { lib.pendingOverwrite = nil } })) {
            Button("Replace", role: .destructive) {
                if let p = lib.pendingOverwrite { lib.summarize(p.id, template: p.template, replaceEdits: true) }
            }
            Button("Keep My Edits", role: .cancel) {}
        } message: {
            Text("You changed this summary by hand. A new summary replaces your changes, and this can't be undone.")
        }
        .onChange(of: lib.selection) {
            if lib.selection != nil { nav.section = .recordings }
        }
        .onChange(of: models.finishedCount) { lib.modelsArrived() }
        // Translate uses a second, 1.1 GB model that the first download leaves out. Offer it when needed.
        .onChange(of: lib.translate) {
            models.refresh()
            if lib.translate && models.needsTranslate && !models.isDownloading { askTranslateModel = true }
        }
        .alert("Translate needs one more model", isPresented: $askTranslateModel) {
            Button("Download (\(ModelCatalog.size(ModelCatalog.totalBytes(models.missingTranslate))))") {
                models.download([.translate])
            }
            .keyboardShortcut(.defaultAction)
            Button("Not Now", role: .cancel) { lib.translate = false }
        } message: {
            Text("The model that writes other languages in English is separate from the speech model. "
                 + "It downloads once, and then Translate works offline.")
        }
        .onChange(of: lib.renaming) {
            newName = lib.items.first { $0.id == lib.renaming }?.title ?? ""
        }
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach(lib.importFile)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.brandAccent, lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
    }
}

func elapsed(from start: Date, to now: Date) -> String {
    let s = max(0, Int(now.timeIntervalSince(start)))
    return s >= 3600
        ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
        : String(format: "%d:%02d", s / 60, s % 60)
}

/// Shown while the microphone is live, so it is obvious how to stop.
struct RecordingNow: View {
    @ObservedObject var lib: Library
    let start: Date

    var body: some View {
        RecordingScreen(start: start, micName: lib.micName ?? "Microphone",
                        level: { lib.micLevel() }, endingIn: lib.endingIn,
                        onKeepRecording: { lib.keepRecording() },
                        onStop: { lib.toggleRecording() },
                        notes: $lib.meetingNotes)
    }
}

/// The right-hand side: title, then the Transcript and Summary tabs.
struct RecordingDetail: View {
    @ObservedObject var lib: Library
    let rec: Recording
    @StateObject private var editor = RichEditorController()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RecordingHeader(
                title: rec.title,
                date: rec.date,
                chips: (rec.hasTranscript ? [] : ["Not transcribed"])
                    + (rec.summaryIsEdited ? ["Summary edited"] : []),
                tabs: Library.Tab.allCases.map(\.rawValue),
                selectedTab: Binding<Int>(
                    get: { Library.Tab.allCases.firstIndex(of: lib.tab) ?? 0 },
                    set: { lib.tab = Library.Tab.allCases[$0] }
                ),
                actions: [
                    HeaderAction(title: rec.hasSummary ? "Re-summarize" : "Summarize", icon: "sparkles",
                                 enabled: rec.hasTranscript && !lib.summarizing.contains(rec.id),
                                 action: { lib.summarize(rec.id) }),
                    HeaderAction(title: "Copy", icon: "doc.on.doc", enabled: true,
                                 action: { lib.copyCurrentTab() }),
                    HeaderAction(title: "Finder", icon: "folder", enabled: true,
                                 action: { lib.showInFinder(rec) })
                ],
                onRename: { lib.renaming = rec.id }
            )

            if let error = lib.errors[rec.id] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.brandWarningText)
                    .textSelection(.enabled)
            }

            Group {
                switch lib.tab {
                case .transcript: transcriptTab
                case .summary: summaryTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        }
        .padding(20)
        .padding(.bottom, 90)
    }

    @ViewBuilder private var transcriptTab: some View {
        if lib.transcribing.contains(rec.id) {
            busy("Transcribing on this Mac…")
        } else if lib.findingSpeakers.contains(rec.id) {
            busy("Finding who spoke when, on this Mac…")
        } else if lib.transcript.isEmpty {
            VStack(spacing: 12) {
                Text("No transcript yet.").foregroundStyle(.secondary)
                Button("Transcribe") { lib.transcribe(rec.id) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                SpeakerBar(lib: lib, rec: rec)
                TextEditor(text: $lib.transcript)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .onChange(of: lib.transcript) { lib.saveTranscriptIfEdited() }
            }
        }
    }

    @ViewBuilder private var summaryTab: some View {
        if lib.summarizing.contains(rec.id) {
            busy("Summarizing with Apple's on-device model…")
        } else if lib.transcribing.contains(rec.id) || lib.findingSpeakers.contains(rec.id) {
            busy("Waiting for the transcript…")
        } else {
            VStack(spacing: 0) {
                HStack {
                    Menu {
                        ForEach(SummaryTemplate.all) { t in
                            Button { lib.summarize(rec.id, template: t.id) } label: {
                                Label(t.name, systemImage: t.icon)
                            }
                        }
                    } label: {
                        let t = SummaryTemplate.find(lib.templateID(for: rec))
                        Label(t.name, systemImage: t.icon)
                    }
                    .fixedSize()
                    .disabled(!rec.hasTranscript || lib.editingSummary)
                    .help("Choose a summary format. Picking one writes a new summary in that format.")
                    Spacer()
                    if rec.summaryIsEdited && !lib.editingSummary {
                        Label("Edited", systemImage: "pencil.line")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("You changed this summary by hand. Earshot asks before replacing it.")
                    }
                    Button {
                        lib.editingSummary ? lib.endEditingSummary() : lib.beginEditingSummary()
                    } label: {
                        Label(lib.editingSummary ? "Done" : "Edit",
                              systemImage: lib.editingSummary ? "checkmark" : "pencil")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(lib.editingSummary ? Color.brandAccent : Color.secondary)
                    .disabled(lib.summary.isEmpty)
                    .help(lib.editingSummary ? "Finish editing. Your changes are already saved."
                                             : "Correct the summary by hand: names, numbers, anything the model got wrong.")
                }
                .padding(10)
                Divider()
                if lib.editingSummary {
                    VStack(spacing: 0) {
                        FormatBar(editor: editor)
                        Divider()
                        RichSummaryEditor(markdown: $lib.summaryDraft, controller: editor)
                            .onChange(of: lib.summaryDraft) { lib.saveSummaryDraft() }
                    }
                } else if lib.summary.isEmpty {
                    VStack(spacing: 12) {
                        Text("No summary yet.").foregroundStyle(.secondary)
                        Button("Summarize") { lib.summarize(rec.id) }.disabled(!rec.hasTranscript)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        MarkdownView(markdown: rec.displayedSummary(lib.summary))
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func busy(_ text: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Formatting buttons for the rich summary editor.
struct FormatBar: View {
    let editor: RichEditorController

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                Button("Title") { editor.setBlock(.title) }
                Button("Heading") { editor.setBlock(.heading) }
                Button("Body") { editor.setBlock(.body) }
            } label: {
                Label("Style", systemImage: "textformat.size")
            }
            .fixedSize()
            .help("Make the selected lines a title, a heading or body text")
            Divider().frame(height: 16).padding(.horizontal, 6)
            button("bold", "Bold (⌘B)", key: "b") { editor.toggleTrait(.boldFontMask) }
            button("italic", "Italic (⌘I)", key: "i") { editor.toggleTrait(.italicFontMask) }
            Divider().frame(height: 16).padding(.horizontal, 6)
            button("list.bullet", "Bulleted list") { editor.toggleList(.bullet) }
            button("square", "Action item (checkbox)") { editor.toggleList(.task) }
            button("checkmark.square", "Done action item") { editor.toggleList(.done) }
            Spacer()
            Text("Saves as you type").font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func button(_ symbol: String, _ help: String, key: KeyEquivalent? = nil,
                        action: @escaping () -> Void) -> some View {
        let b = Button(action: action) {
            Image(systemName: symbol).frame(width: 24, height: 20)
        }
        .help(help)
        .accessibilityLabel(help)
        if let key { b.keyboardShortcut(key, modifiers: .command) } else { b }
    }
}

/// Speakers found in the transcript, as buttons; click one to give it a real name.
struct SpeakerBar: View {
    @ObservedObject var lib: Library
    let rec: Recording
    @State private var editing: String?
    @State private var newName = ""

    var body: some View {
        let names = Library.speakerNames(in: lib.transcript)
        VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2").foregroundStyle(.secondary)
                    ForEach(Array(names.enumerated()), id: \.element) { index, name in
                        Button {
                            newName = name.hasPrefix("Speaker ") ? "" : name
                            editing = name
                        } label: {
                            Label(name, systemImage: "circle.fill")
                                .labelStyle(SpeakerLabelStyle(color: SpeakerBar.color(index)))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Rename \(name) everywhere in this transcript")
                        .popover(isPresented: Binding(get: { editing == name }, set: { if !$0 { editing = nil } })) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Rename \(name)").font(.headline)
                                TextField("Name", text: $newName)
                                    .frame(width: 200)
                                    .onSubmit(commit)
                                HStack {
                                    Spacer()
                                    Button("Cancel") { editing = nil }
                                    Button("Rename", action: commit)
                                        .keyboardShortcut(.defaultAction)
                                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                                Text("The summary uses the new name too.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(14)
                        }
                    }
                    if names.isEmpty {
                        Text("No speaker labels").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Detect automatically") { lib.findSpeakers(rec.id, count: 0) }
                        Divider()
                        ForEach(2...8, id: \.self) { n in
                            Button("\(n) people") { lib.findSpeakers(rec.id, count: n) }
                        }
                    } label: {
                        Label("Speakers", systemImage: "person.2.wave.2")
                    }
                    .fixedSize()
                    .help("Run speaker detection again. If you know how many people spoke, choose the number: "
                          + "it is more accurate. This replaces any names you gave the speakers.")
                }
                .padding(10)
                Divider()
            }
    }

    private func commit() {
        if let old = editing { lib.renameSpeaker(old, to: newName) }
        editing = nil
    }

    static func color(_ index: Int) -> Color {
        [Color.blue, .orange, .green, .purple, .pink, .teal, .yellow, .red][index % 8] // brand-ok: speaker palette
    }
}

struct SpeakerLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 7)).foregroundStyle(color)
            configuration.title
        }
    }
}

/// A small Markdown renderer for the summary: headings, bullets, checkboxes, numbered lists, paragraphs.
/// SwiftUI's own Markdown support only covers inline styles (bold, italics, links).
struct MarkdownView: View {
    let markdown: String

    enum Block {
        case heading(Int, String)
        case bullet(String)
        case task(String, done: Bool)
        case numbered(String, String)
        case paragraph(String)
        case rule
    }

    private var blocks: [Block] {
        markdown.split(separator: "\n", omittingEmptySubsequences: true).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("<!--") { return nil }
            if line.allSatisfy({ $0 == "-" || $0 == "*" }) && line.count >= 3 { return .rule }
            for marker in ["- [ ] ", "* [ ] "] where line.hasPrefix(marker) {
                return .task(String(line.dropFirst(marker.count)), done: false)
            }
            for marker in ["- [x] ", "- [X] ", "* [x] "] where line.hasPrefix(marker) {
                return .task(String(line.dropFirst(marker.count)), done: true)
            }
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                return .heading(level, line.dropFirst(level).trimmingCharacters(in: .whitespaces))
            }
            for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
                return .bullet(String(line.dropFirst(marker.count)))
            }
            if let m = line.firstMatch(of: #/^(\d+)[.)]\s+(.*)$/#) {
                return .numbered(String(m.1), String(m.2))
            }
            return .paragraph(line)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    inline(text)
                        .font(level == 1 ? .title2.bold() : level == 2 ? .headline : .subheadline.bold())
                        .padding(.top, level == 1 ? 0 : 8)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        inline(text)
                    }
                case .task(let text, let done):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: done ? "checkmark.square" : "square").foregroundStyle(.secondary)
                        inline(text)
                    }
                case .numbered(let n, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(n + ".").foregroundStyle(.secondary).monospacedDigit()
                        inline(text)
                    }
                case .paragraph(let text):
                    inline(text)
                case .rule:
                    Divider()
                }
            }
        }
        .font(.system(size: 14))
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return Text((try? AttributedString(markdown: s, options: options)) ?? AttributedString(s))
    }
}
