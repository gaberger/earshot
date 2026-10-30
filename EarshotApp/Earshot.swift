// Earshot — a small Mac app over the local `transcribe` script (whisper.cpp),
// with summaries from Apple's on-device model. Everything runs on this Mac;
// nothing is sent anywhere.

import AVFoundation
import AppKit
import Combine
import Darwin
import FoundationModels
import IOKit
import SwiftUI

@main
struct EarshotApp: App {
    @StateObject private var library = Library()

    init() {
        Prefs.migrate()
    }

    var body: some Scene {
        WindowGroup(id: MainWindow.id) {
            ContentView(lib: library)
                .frame(minWidth: 1180, minHeight: 560)
                // Files opened from Finder ("Open With", or dropped on the Dock icon).
                .onOpenURL { library.importFile($0) }
        }
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: ["*"])
        .commands {
            CommandGroup(replacing: .help) { HelpMenuItem() }
        }

        Window("How Earshot Works", id: HelpView.windowID) {
            HelpView()
        }
        .defaultSize(width: 640, height: 720)

        Settings {
            SettingsView()
        }

        // Quick access from the menu bar, like Plaud: record, see the timer, open recent recordings.
        MenuBarExtra {
            MenuBarPanel(lib: library)
        } label: {
            MenuBarLabel(lib: library)
        }
        .menuBarExtraStyle(.window)
    }
}

enum MainWindow {
    static let id = "main"
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
    @Published var errors: [Recording.ID: String] = [:]
    @Published var recording = false
    @Published var startedAt: Date?
    @Published var translate = false
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

    let dir: URL
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var recorder: MicRecorder?
    // True while waiting for the microphone permission answer, so a second click can't start a second recorder.
    private var starting = false
    private var savedTranscript = ""

    init() {
        dir = home.appendingPathComponent("Recordings/whisper")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        reload()
        selection = items.first?.id
        loadSelected()
        // Quitting while recording still finishes the file cleanly.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recorder?.stop() }
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
            let r = try MicRecorder(deviceID: chosen, url: url) { rec, error in
                Task { @MainActor in self.recordingFinished(rec, error: error) }
            }
            recorder = r
            r.start()
            recording = true
            startedAt = Date()
            micName = r.deviceName
            notice = r.usedFallback ? "The chosen microphone isn't connected, so this uses \(r.deviceName)." : nil
            log("recording started with \(r.deviceName): \(url.path)")
        } catch {
            notice = "Could not start recording: \(error.localizedDescription)"
            log("recording failed: \(error)")
        }
    }

    private func stopRecording() {
        guard let r = recorder else {
            log("stop pressed but no recorder")
            recording = false
            return
        }
        // The file is finished in recordingFinished, once the capture output has flushed it.
        r.stop()
        recording = false
        startedAt = nil
        log("recording stopped")
    }

    private func recordingFinished(_ r: MicRecorder, error: Error?) {
        recorder = nil
        micName = nil
        if let error {
            log("recording finished with error: \(error)")
            notice = "The recording may be incomplete: \(error.localizedDescription)"
        }
        guard FileManager.default.fileExists(atPath: r.url.path) else { return }
        reload()
        selection = r.url.lastPathComponent
        tab = .summary
        transcribe(r.url.lastPathComponent)
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
        let path = dir.appendingPathComponent(id).path
        log("transcribing: \(path)")
        transcribing.insert(id)
        errors[id] = nil

        let args = [bin("transcribe")] + (translate ? ["-t"] : []) + [path]

        Task {
            let failure = await Self.run(args)
            transcribing.remove(id)
            log("transcribe finished: \(failure ?? "ok")")
            if let failure {
                errors[id] = "Transcription failed:\n\(failure)"
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

    /// A helper script: the copy inside the app (so a DMG install works on its own), else ~/.local/bin.
    private func bin(_ name: String) -> String {
        if let bundled = Bundle.main.url(forResource: name, withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }
        return home.appendingPathComponent(".local/bin/\(name)").path
    }

    /// Runs a helper script off the main thread. Returns nil on success, or the last lines of its error output.
    nonisolated private static func run(_ args: [String]) async -> String? {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = args
            // Apps opened from Finder get a bare PATH; add Homebrew (ffmpeg, whisper-cli) and ~/.local/bin (uv).
            var env = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            p.environment = env
            let err = Pipe()
            p.standardError = err
            p.standardOutput = FileHandle.nullDevice
            do {
                try p.run()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                guard p.terminationStatus != 0 else { return nil }
                let lines = String(decoding: errData, as: UTF8.self).split(separator: "\n")
                return lines.suffix(3).joined(separator: "\n")
            } catch {
                return error.localizedDescription
            }
        }.value
    }

    // MARK: Speakers

    /// `count` overrides the Settings choice for this one run: 0 detects automatically, 2+ is exact.
    func findSpeakers(_ id: Recording.ID, count: Int? = nil) {
        guard !findingSpeakers.contains(id), !transcribing.contains(id) else { return }
        let path = dir.appendingPathComponent(id).path
        guard FileManager.default.fileExists(atPath: (path as NSString).deletingPathExtension + ".json") else {
            errors[id] = "Transcribe this recording again first: speaker detection needs the word timings "
                + "that newer transcriptions save."
            return
        }
        findingSpeakers.insert(id)
        errors[id] = nil
        log("finding speakers: \(id)")
        let count = count ?? UserDefaults.standard.integer(forKey: Prefs.speakerCount)
        let args = [bin("speakers"), path] + (count > 1 ? ["-n", String(count)] : [])
        Task {
            let failure = await Self.run(args)
            findingSpeakers.remove(id)
            log("speakers finished: \(failure ?? "ok")")
            if let failure {
                errors[id] = "Speaker detection failed:\n\(failure)"
            }
            if selection == id { loadSelected() }
            summarize(id, automatic: true)
        }
    }

    /// The speaker names used in a transcript, in order of first appearance ("Speaker 1", or a renamed "Gary").
    nonisolated static func speakerNames(in transcript: String) -> [String] {
        var names: [String] = []
        for line in transcript.split(separator: "\n") {
            if let m = line.firstMatch(of: #/^\[\d\d:\d\d:\d\d\] ([^:]{1,40}):/#) {
                let name = String(m.1)
                if !names.contains(name) { names.append(name) }
            }
        }
        return names
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
            return
        }
        let chosen = SummaryTemplate.find(template ?? templateID(for: r))
        summarizing.insert(id)
        errors[id] = nil
        log("summarizing: \(id) with \(chosen.id)")
        Task {
            do {
                let length = try? await AVURLAsset(url: r.audio).load(.duration).seconds
                let md = try await Summarizer.summarize(text, template: chosen, date: r.date, seconds: length)
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
                log("summary failed: \(error)")
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
        for url in [r.audio, r.transcriptURL, r.srtURL, r.summaryURL, json, r.nameURL]
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

    func log(_ message: String) {
        let url = home.appendingPathComponent("Library/Logs/Earshot.log")
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Microphone

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
    private let finished: (MicRecorder, Error?) -> Void

    static func inputs() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                         mediaType: .audio, position: .unspecified).devices
    }

    init(deviceID: String, url: URL, finished: @escaping (MicRecorder, Error?) -> Void) throws {
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
        queue.async { [self] in output.stopRecording() }
    }

    var level: Float {
        output.connections.first?.audioChannels.map(\.averagePowerLevel).max() ?? -160
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        session.stopRunning()
        // Capture outputs report some normal stops as errors, flagged as "finished successfully".
        let ok = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
        finished(self, ok ? nil : error)
    }
}

struct SettingsView: View {
    @AppStorage(MicRecorder.settingKey) private var microphoneID = ""
    @AppStorage(Prefs.identifySpeakers) private var identifySpeakers = true
    @AppStorage(Prefs.speakerCount) private var speakerCount = 0
    @AppStorage(Prefs.summaryTemplate) private var summaryTemplate = SummaryTemplate.all[0].id
    @State private var inputs: [AVCaptureDevice] = []

    private var defaultName: String { AVCaptureDevice.default(for: .audio)?.localizedName ?? "none" }
    private var chosenMissing: Bool { !microphoneID.isEmpty && !inputs.contains { $0.uniqueID == microphoneID } }

    var body: some View {
        Form {
            Section {
                Picker("Microphone", selection: $microphoneID) {
                    Text("System default (\(defaultName))").tag("")
                    if chosenMissing { Text("Not connected").tag(microphoneID) }
                    Divider()
                    ForEach(inputs, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                }
                if chosenMissing {
                    Label("This microphone isn't connected. Recordings use the system default until it is.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Recording")
            } footer: {
                Text("Earshot records from this microphone. \"System default\" follows the input chosen in "
                     + "System Settings → Sound. The audio stays on this Mac.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Identify speakers", isOn: $identifySpeakers)
                Picker("Number of speakers", selection: $speakerCount) {
                    Text("Detect automatically").tag(0)
                    Text("1 (no speaker labels)").tag(1)
                    ForEach(2...10, id: \.self) { Text("\($0)").tag($0) }
                }
                .disabled(!identifySpeakers)
            } header: {
                Text("Speakers")
            } footer: {
                Text("After transcribing, a local voice model labels who spoke when: Speaker 1, Speaker 2… "
                     + "Rename them in the Transcript tab. If you know how many people were there, choose the "
                     + "number: it is more accurate than detecting it.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Default template", selection: $summaryTemplate) {
                    ForEach(SummaryTemplate.all) { Label($0.name, systemImage: $0.icon).tag($0.id) }
                }
            } header: {
                Text("Summaries")
            } footer: {
                Text("New recordings are summarized in this format. You can switch any summary to another "
                     + "template in its Summary tab.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { inputs = MicRecorder.inputs() }
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
                    .fill(fill > 0.9 ? Color.red : fill > 0.7 ? Color.orange : Color.green)
                    .frame(width: geo.size.width * fill)
            }
        }
        .frame(width: 240, height: 8)
        .animation(.linear(duration: 0.08), value: fill)
    }
}

// MARK: - Resource meter

/// Samples CPU and memory for this app plus its helper processes (bash, ffmpeg, whisper-cli),
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
            CPU and MEM: this app plus Whisper and ffmpeg while they run (CPU as a share of the whole Mac).
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

/// The panel that opens from the menu bar.
struct MenuBarPanel: View {
    @ObservedObject var lib: Library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                AppIcon(size: 28)
                Text("Earshot").font(.headline)
                Spacer()
                Label("On this Mac", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: lib.toggleRecording) {
                HStack {
                    if let start = lib.startedAt {
                        Image(systemName: "stop.fill")
                        TimelineView(.periodic(from: start, by: 1)) { ctx in
                            Text("Stop  " + elapsed(from: start, to: ctx.date)).monospacedDigit()
                        }
                    } else {
                        Image(systemName: "mic.fill")
                        Text("Record")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(lib.recording ? .red : .accentColor)
            .controlSize(.large)

            if lib.recording {
                VStack(alignment: .leading, spacing: 6) {
                    Label(lib.micName ?? "Microphone", systemImage: "mic")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TimelineView(.animation(minimumInterval: 0.08)) { _ in
                        LevelBar(decibels: lib.micLevel())
                    }
                }
            }

            if !lib.items.isEmpty {
                Divider()
                Text("Recent").font(.caption).foregroundStyle(.secondary)
                ForEach(lib.items.prefix(5)) { r in
                    Button { open(r.id) } label: {
                        HStack {
                            Text(r.title).lineLimit(1)
                            Spacer()
                            Text(r.date.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
            HStack {
                Button("Open Earshot") { open(nil) }
                Spacer()
                SettingsLink { Text("Settings…") }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
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

struct HelpButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button { openWindow(id: HelpView.windowID) } label: {
            Label("Privacy", systemImage: "lock.shield")
        }
        .labelStyle(.titleAndIcon)
        .help("How Earshot works, and why everything stays on this Mac (⌘?).")
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
                        Text("Earshot has no account, no cloud service and no internet connection. "
                             + "Your recordings, transcripts and summaries are made and kept on this computer.")
                            .foregroundStyle(.secondary)
                    }
                }

                section("Try it yourself", "wifi.slash") {
                    para("Turn off Wi-Fi and record something. Transcription and summaries still work, "
                         + "because no step needs the internet.")
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
                         "ffmpeg, which changes any audio or video file into the format Whisper reads.")
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
                    item("Record / Stop", "Starts and stops the microphone. The timer shows how long it has recorded. ⌘R.")
                    item("Import", "Transcribe an audio or video file you already have. You can also drag files into the window. ⌘O.")
                    item("Translate", "When on, speech in another language is written in English.")
                    item("Summarize", "Writes a new summary of the selected recording.")
                    item("Copy", "Copies the open tab, transcript or summary. ⇧⌘C.")
                    item("Finder", "Shows the recording's files in Finder.")
                    item("Privacy", "Opens this page. ⌘?.")
                    item("Menu bar", "The ear at the top of your screen records without opening the window. "
                         + "While recording it shows the timer. It also lists your five latest recordings.")
                    item("Settings", "Choose which microphone to record from. While recording, the screen "
                         + "shows the microphone's name and a level bar, so you can see it hears you. ⌘,.")
                }

                section("The status bar", "rectangle.bottomthird.inset.filled") {
                    item("Left side", "What Earshot is doing now: recording, transcribing, finding speakers or "
                         + "summarizing. When it is idle, how many recordings you have.")
                    item("CPU · GPU · MEM", "How hard the Mac is working. CPU and memory count this app and Whisper. "
                         + "GPU counts the whole graphics chip, where Whisper and the summary model do most of their work.")
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

// MARK: - Summaries (Apple's on-device model)

struct AppError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Preference keys, shared by the Settings window (@AppStorage) and the library.
enum Prefs {
    static let identifySpeakers = "identifySpeakers"  // Bool, default true
    static let speakerCount = "speakerCount"          // Int, 0 = detect automatically
    static let summaryTemplate = "summaryTemplate"    // SummaryTemplate.id

    /// The bundle ID before the app was named Earshot. Its settings are copied over once.
    static let oldBundleID = "local.whisper.transcribe"
    private static let migrated = "migratedFromOldBundleID"

    /// Copies settings saved under the old bundle ID, without replacing any set since.
    static func migrate(from oldID: String = oldBundleID, into defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migrated) else { return }
        for (key, value) in defaults.persistentDomain(forName: oldID) ?? [:]
        where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: migrated)
    }
}

/// A Plaud-style summary format: which sections the model should write.
struct SummaryTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let sections: String

    static let all: [SummaryTemplate] = [
        .init(id: "minutes", name: "Meeting minutes", icon: "person.3",
              sections: "One section per main topic discussed, with the topic as its heading. "
                + "Then a section named Decisions with what was agreed. Then Open questions, if any were raised."),
        .init(id: "quick", name: "Quick summary", icon: "text.alignleft",
              sections: "One section named Key points."),
        .init(id: "sales", name: "Sales call", icon: "briefcase",
              sections: "Use these sections, and leave out any the text says nothing about: "
                + "Customer and attendees, Current situation, Pain points, Requirements, "
                + "Objections and risks, Competitors mentioned, Budget timeline and buying process, Next steps."),
        .init(id: "oneonone", name: "One-on-one", icon: "person.2",
              sections: "Sections: Updates, Challenges, Feedback, Decisions. Leave out any with nothing in the text."),
        .init(id: "standup", name: "Daily stand-up", icon: "checklist",
              sections: "One section per person, with the name as heading. Points start with "
                + "Done:, Next: or Blocked:."),
        .init(id: "interview", name: "Interview", icon: "mic",
              sections: "A section named Background. Then one section per main question or theme. "
                + "Then Notable quotes, using the speaker's own words."),
        .init(id: "lecture", name: "Lecture or class notes", icon: "graduationcap",
              sections: "One section per concept taught, with the concept as heading and the explanation as points. "
                + "Then Examples, then Questions to review."),
        .init(id: "brainstorm", name: "Brainstorm", icon: "lightbulb",
              sections: "One section per group of related ideas. Then Most promising ideas, then Next steps."),
        .init(id: "memo", name: "Voice memo", icon: "waveform",
              sections: "Sections: Main points, Ideas. Put to-dos in the action items."),
    ]

    static func find(_ id: String) -> SummaryTemplate { all.first { $0.id == id } ?? all[0] }
}

// The shape the model must fill in. Typed fields keep a small model on track far better
// than asking it for free-form Markdown (it used to copy the instructions into the output).
@Generable
struct GeneratedSummary {
    @Guide(description: "A specific title of 3 to 8 words that names the main topic")
    var title: String
    @Guide(description: "Two to four sentences: what the recording is about and what was concluded")
    var overview: String
    @Guide(description: "The sections the instructions ask for, in that order. Only topics that take real time in the text",
           .maximumCount(6))
    var sections: [GeneratedSection]
    @Guide(description: "Tasks a speaker said they or someone else will do. Empty if there are none", .maximumCount(8))
    var actionItems: [GeneratedAction]
}

@Generable
struct GeneratedSection {
    @Guide(description: "The section heading")
    var heading: String
    @Guide(description: "Short bullet points. Each one is a fact, number, name or decision stated in the text",
           .maximumCount(6))
    var points: [String]
}

@Generable
struct GeneratedAction {
    @Guide(description: "The speaker or person the text says will do it. Unassigned if the text does not say who")
    var owner: String
    @Guide(description: "The task, starting with a verb")
    var task: String
    @Guide(description: "A day or date only if the text states one. Otherwise an empty string")
    var due: String
}

enum Summarizer {
    // On-device only. Do not switch this to PrivateCloudComputeLanguageModel: that one runs on Apple's servers.
    static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    // The on-device model reads about 4,000 tokens at once (~1.2 tokens per spoken word), and the
    // summary's schema takes some of that, so longer transcripts are boiled down to notes first.
    static let maxWords = 1_100
    static let chunkWords = 900

    static let notesInstructions = """
        You take notes on one part of a speech-to-text transcript. Lines may start with a speaker name. \
        Expect missing punctuation and some misheard words. Write 3 to 8 short Markdown bullet points \
        with the facts, names, numbers, decisions and tasks in this part, and say who said or will do \
        what. Use only what the text says.
        """

    static func instructions(for template: SummaryTemplate) -> String {
        """
        You write \(template.name.lowercased()) from a speech-to-text transcript, or from notes taken \
        from one. Lines may start with a speaker name. Expect missing punctuation and some misheard words.
        Use only what the text says. Never add advice, opinions or general statements that are not in \
        the text. Leave out anything you are unsure of.
        \(template.sections)
        """
    }

    static func summarize(_ text: String, template: SummaryTemplate, date: Date, seconds: Double?) async throws -> String {
        if case .unavailable(let reason) = model.availability {
            throw AppError(message: describe(reason))
        }
        // Timestamps cost tokens and carry no meaning for a summary; speaker names stay.
        var material = text.replacingOccurrences(of: #"(?m)^\[\d\d:\d\d:\d\d\] "#, with: "",
                                                 options: .regularExpression)
        let speakers = Library.speakerNames(in: text)
        var rounds = 0
        while wordCount(material) > maxWords && rounds < 4 {
            let words = material.split(whereSeparator: \.isWhitespace)
            var notes: [String] = []
            for start in stride(from: 0, to: words.count, by: chunkWords) {
                let chunk = words[start..<min(start + chunkWords, words.count)].joined(separator: " ")
                let session = LanguageModelSession(model: model, instructions: notesInstructions)
                notes.append(try await session.respond(to: chunk).content)
            }
            material = notes.joined(separator: "\n")
            rounds += 1
        }
        let session = LanguageModelSession(model: model, instructions: instructions(for: template))
        let g = try await session.respond(to: material, generating: GeneratedSummary.self).content
        return render(g, template: template, date: date, seconds: seconds, speakers: speakers)
    }

    /// Turns the model's fields into the Markdown the Summary tab shows and the .summary.md file keeps.
    static func render(_ g: GeneratedSummary, template: SummaryTemplate, date: Date,
                       seconds: Double?, speakers: [String]) -> String {
        var info = [date.formatted(date: .abbreviated, time: .shortened)]
        if let seconds, seconds.isFinite { info.append("\(max(1, Int((seconds / 60).rounded()))) min") }
        if !speakers.isEmpty { info.append("Speakers: " + speakers.joined(separator: ", ")) }

        var md = "<!-- template: \(template.id) -->\n"
        md += "# \(g.title.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "#*\""))))\n\n"
        md += "*\(template.name) · \(info.joined(separator: " · "))*\n\n"
        md += "## Overview\n\(g.overview)\n\n"
        // The app writes the action items itself; drop the model's own copy if it adds one as a section.
        for section in g.sections
        where !section.points.isEmpty && !section.heading.localizedCaseInsensitiveContains("action item") {
            md += "## \(section.heading)\n"
            md += section.points.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        md += "## Action items\n"
        if g.actionItems.isEmpty {
            md += "- None mentioned\n"
        } else {
            for a in g.actionItems {
                let due = a.due.trimmingCharacters(in: .whitespaces)
                md += "- [ ] **\(a.owner)** — \(a.task)" + (due.isEmpty ? "" : " *(due \(due))*") + "\n"
            }
        }
        return md
    }

    static func wordCount(_ s: String) -> Int { s.split(whereSeparator: \.isWhitespace).count }

    static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is off. Turn it on in System Settings → Apple Intelligence & Siri."
        case .modelNotReady:
            return "Apple's on-device model is still downloading. Try again in a few minutes."
        case .deviceNotEligible:
            return "This Mac can't run Apple's on-device model."
        @unknown default:
            return "Apple's on-device model is not available."
        }
    }

    static func describe(_ error: Error) -> String {
        (error as? AppError)?.message ?? error.localizedDescription
    }
}

// MARK: - Views

struct ContentView: View {
    @ObservedObject var lib: Library
    @StateObject private var monitor = ResourceMonitor()
    @State private var dropTargeted = false
    @State private var newName = ""

    var body: some View {
        NavigationSplitView {
            Timeline(lib: lib)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            Group {
                if lib.recording, let start = lib.startedAt {
                    RecordingNow(lib: lib, start: start)
                } else if let r = lib.selected {
                    RecordingDetail(lib: lib, rec: r)
                } else {
                    ContentUnavailableView {
                        VStack(spacing: 10) {
                            AppIcon(size: 96)
                            Text("Earshot")
                        }
                    } description: {
                        Text("Press Record, or drop an audio or video file here.\nEverything stays on this Mac.")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let notice = lib.notice {
                    Text(notice)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding()
                        .onTapGesture { lib.notice = nil }
                }
            }
        }
        .navigationTitle("Earshot")
        .toolbar { HeaderControls(lib: lib) }
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
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Everything in the window's header bar.
struct HeaderControls: ToolbarContent {
    @ObservedObject var lib: Library

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HelpButton()
        }

        ToolbarItem(placement: .primaryAction) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .labelStyle(.titleAndIcon)
            .help("Choose which microphone to record from (⌘,).")
        }

        ToolbarItem(placement: .navigation) {
            Button(action: lib.toggleRecording) {
                if let start = lib.startedAt {
                    // Elapsed time on the button makes it obvious the mic is still live.
                    TimelineView(.periodic(from: start, by: 1)) { ctx in
                        Label("Stop  " + elapsed(from: start, to: ctx.date), systemImage: "stop.circle.fill")
                            .monospacedDigit()
                    }
                } else {
                    Label("Record", systemImage: "mic.circle.fill")
                }
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderedProminent)
            .tint(lib.recording ? .red : .accentColor)
            .keyboardShortcut("r", modifiers: .command)
            .help(lib.recording ? "Stop recording and transcribe (⌘R)" : "Record from the microphone (⌘R)")
        }

        // Icons plus words, so nobody has to guess what a symbol means.
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: lib.chooseFile) {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .labelStyle(.titleAndIcon)
            .keyboardShortcut("o", modifiers: .command)
            .disabled(lib.recording)
            .help("Import an audio or video file and transcribe it (⌘O). You can also drag files into the window.")

            Toggle(isOn: $lib.translate) {
                Label(lib.translate ? "Translate: On" : "Translate: Off", systemImage: "globe")
            }
            .labelStyle(.titleAndIcon)
            .disabled(lib.recording)
            .help("""
                Translate to English. When on, speech in another language is written out in English. \
                When off, the text stays in the language that was spoken. Applies to the next transcription.
                """)

            Button {
                if let id = lib.selection { lib.summarize(id) }
            } label: {
                Label("Summarize", systemImage: "sparkles")
            }
            .labelStyle(.titleAndIcon)
            .disabled(lib.selected?.hasTranscript != true || lib.selection.map(lib.summarizing.contains) == true)
            .help("Write a new summary of the selected recording with Apple's on-device model. Nothing leaves this Mac.")

            Button(action: lib.copyCurrentTab) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .labelStyle(.titleAndIcon)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(lib.selected == nil)
            .help("Copy the text of the open tab, transcript or summary, to the clipboard (⇧⌘C).")

            Button {
                if let r = lib.selected { lib.showInFinder(r) }
            } label: {
                Label("Finder", systemImage: "folder")
            }
            .labelStyle(.titleAndIcon)
            .disabled(lib.selected == nil)
            .help("Show this recording's files (audio, transcript, summary) in Finder.")
        }
    }
}

func elapsed(from start: Date, to now: Date) -> String {
    let s = max(0, Int(now.timeIntervalSince(start)))
    return s >= 3600
        ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
        : String(format: "%d:%02d", s / 60, s % 60)
}

/// The sidebar: every recording, newest first, grouped by day.
struct Timeline: View {
    @ObservedObject var lib: Library

    private var days: [(day: Date, items: [Recording])] {
        Dictionary(grouping: lib.items) { Calendar.current.startOfDay(for: $0.date) }
            .map { ($0.key, $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        List(selection: $lib.selection) {
            ForEach(days, id: \.day) { group in
                Section(dayName(group.day)) {
                    ForEach(group.items) { r in
                        TimelineRow(lib: lib, rec: r)
                            .tag(r.id)
                            .contextMenu {
                                Button("Rename…") { lib.renaming = r.id }
                                Button("Show in Finder") { lib.showInFinder(r) }
                                Button("Transcribe Again") { lib.transcribe(r.id) }
                                Button("Find Speakers Again") { lib.findSpeakers(r.id) }.disabled(!r.hasTranscript)
                                Button("Summarize Again") { lib.summarize(r.id) }.disabled(!r.hasTranscript)
                                Divider()
                                Button("Move to Trash", role: .destructive) { lib.moveToTrash(r) }
                            }
                    }
                }
            }
        }
        .onDeleteCommand { if let r = lib.selected { lib.moveToTrash(r) } }
        // One quiet brand mark at the top of the sidebar, as many Mac apps do.
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                AppIcon(size: 26)
                Text("Earshot").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .overlay {
            if lib.items.isEmpty {
                ContentUnavailableView("No recordings yet", systemImage: "mic",
                                       description: Text("Press Record to start."))
            }
        }
    }

    private func dayName(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

struct TimelineRow: View {
    @ObservedObject var lib: Library
    let rec: Recording
    @State private var duration: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rec.title).lineLimit(1)
            HStack(spacing: 6) {
                Text(rec.date.formatted(date: .omitted, time: .shortened))
                if let duration { Text("· " + elapsed(from: .distantPast, to: Date.distantPast + duration)) }
                Spacer()
                status
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .task(id: rec.id) {
            if let d = try? await AVURLAsset(url: rec.audio).load(.duration), d.seconds.isFinite {
                duration = d.seconds
            }
        }
    }

    @ViewBuilder private var status: some View {
        if lib.transcribing.contains(rec.id) {
            ProgressView().controlSize(.mini).help("Transcribing")
        } else if lib.findingSpeakers.contains(rec.id) {
            Image(systemName: "person.2.wave.2").symbolEffect(.pulse).help("Finding speakers")
        } else if lib.summarizing.contains(rec.id) {
            Image(systemName: "sparkles").symbolEffect(.pulse).help("Summarizing")
        } else if lib.errors[rec.id] != nil {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help("Something went wrong")
        } else if rec.hasSummary {
            Image(systemName: "sparkles").help("Transcribed and summarized")
        } else if rec.hasTranscript {
            Image(systemName: "text.alignleft").help("Transcribed")
        }
    }
}

/// Shown while the microphone is live, so it is obvious how to stop.
struct RecordingNow: View {
    @ObservedObject var lib: Library
    let start: Date

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
            TimelineView(.periodic(from: start, by: 1)) { ctx in
                Text(elapsed(from: start, to: ctx.date))
                    .font(.system(size: 40, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            VStack(spacing: 8) {
                Label(lib.micName ?? "Microphone", systemImage: "mic.fill")
                    .font(.callout)
                TimelineView(.animation(minimumInterval: 0.08)) { _ in
                    LevelBar(decibels: lib.micLevel())
                }
                Text("Wrong microphone? Stop, then choose another in Settings (⌘,).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Text("Recording. Click Stop when you finish, and the text appears here.")
                .foregroundStyle(.secondary)
            Button(action: lib.toggleRecording) {
                Label("Stop", systemImage: "stop.fill").frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.extraLarge)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The right-hand side: title, then the Transcript and Summary tabs.
struct RecordingDetail: View {
    @ObservedObject var lib: Library
    let rec: Recording
    @StateObject private var editor = RichEditorController()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(rec.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                        .onTapGesture(count: 2) { lib.renaming = rec.id }
                        .help("Double-click to rename")
                    Button { lib.renaming = rec.id } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Rename this recording")
                }
                Text(rec.date.formatted(date: .complete, time: .shortened))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Picker("View", selection: $lib.tab) {
                ForEach(Library.Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)

            if let error = lib.errors[rec.id] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
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
                    .tint(lib.editingSummary ? .accentColor : .secondary)
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
        [Color.blue, .orange, .green, .purple, .pink, .teal, .yellow, .red][index % 8]
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
