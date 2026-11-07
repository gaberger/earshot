import AVFoundation
import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import UserNotifications

/// The AppKit side of push-to-talk dictation: a global hold-to-talk hotkey (the saved
/// `HotKey`, Control+Option+Space by default), a short microphone capture while it is held, whisper through the owner's helper, and a paste
/// into whatever app has focus. `DictationSession` decides; this class only does what it says.
///
/// It fails toward "type nothing", like the core. Every path out of a capture ends in a
/// `.transcript`, `.inserted` or `.failed` event, because the core has no timeout of its own in
/// transcribing or inserting. Audio is never kept: the wav and whisper's side files are deleted on
/// every path. The log never carries transcript text.
@MainActor
final class DictationService: ObservableObject {
    // Injected by the owner, so this class never reaches into the library or UserDefaults itself.
    var isMeetingRecording: () -> Bool = { false }
    var scriptPath: () -> String = { "" }
    /// Runs the transcribe script with these arguments. `nil` means success, else the error text.
    var runHelper: ([String]) async -> String? = { _ in "No transcriber is set up." }
    var log: (String) -> Void = { _ in }
    var microphoneID: () -> String = { "" }
    /// True while a dictation is listening, transcribing or typing.
    var isBusy: Bool { session.state != .idle }

    /// True while a failed clip is kept and `retryLast()` can try it again.
    @Published private(set) var retryAvailable = false
    /// The wav of the last failed transcription, in NSTemporaryDirectory; lives until the next dictation.
    private var keptClip: URL?

    private var session = DictationSession()
    private var recorder: MicRecorder?
    private var ticker: Timer?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// The shortcut currently registered, so a change in Settings can be noticed.
    private var registered: HotKey?
    /// A shortcut another app refused to give up; not retried until the saved shortcut changes.
    private var rejectedKey: HotKey?
    private let hud = DictationHUD()

    /// Asks for the two permissions dictation needs: the microphone, and Accessibility (to type).
    static func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Removes a stale Accessibility entry (left by an old build) and asks macOS again.
    static func resetAccessibilityPermission() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.gaberger.earshot"
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleID]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            DispatchQueue.main.async { requestPermissions() }
        }
    }

    // MARK: Hotkey

    /// Registers or unregisters the hotkey to match the preference. Safe to call any number of times.
    func refresh() {
        guard DictationPrefs.isEnabled() else { return unregister() }
        // The saved shortcut was refused and has not changed: no retry, no second notice.
        if let rejectedKey {
            if rejectedKey == HotKey.load() { return }
            self.rejectedKey = nil
        }
        if hotKey != nil, registered != HotKey.load() {
            // Keep the handler; only the key changes.
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil
            registered = nil
        }
        register()
    }

    private func register() {
        guard hotKey == nil, rejectedKey != HotKey.load() else { return }
        if handler == nil {
            var kinds = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
            ]
            // A C callback cannot capture, so the service travels through userData. Carbon delivers
            // hotkey events on the main thread, which is what assumeIsolated checks.
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                let service = Unmanaged<DictationService>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { service.hotKeyChanged(pressed: pressed) }
                return noErr
            }, kinds.count, &kinds, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else {
                log("Dictation: could not install the hotkey handler (\(status)).")
                return
            }
        }
        let id = EventHotKeyID(signature: 0x4552_5348, id: 1)  // 'ERSH'
        let key = HotKey.load()
        let status = RegisterEventHotKey(key.keyCode, key.modifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKey)
        if status == noErr {
            registered = key
        } else {
            hotKey = nil
            registered = nil
            rejectedKey = key
            log("Dictation: could not register \(key.display) (\(status)).")
            notify("Another app already uses \(key.display). Choose a different shortcut in Settings → Dictation.")
        }
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        registered = nil
        rejectedKey = nil
        discardKeptClip()
        hud.hide()
        // Turning it off mid-capture must not leave the microphone open. A tick far in the future
        // stops a capture in either mode; key up is ignored in tap-to-toggle mode.
        send(.tick(at: ProcessInfo.processInfo.systemUptime + 3600))
    }

    private func hotKeyChanged(pressed: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        // A changed preference applies at the next dictation, never mid-capture.
        if pressed, session.state == .idle {
            session = DictationSession(DictationSession.Config(toggle: DictationPrefs.isToggle()))
        }
        send(pressed ? .keyDown(at: now, meetingRecording: isMeetingRecording()) : .keyUp(at: now))
    }

    // MARK: Session

    private func send(_ event: DictationSession.Event) {
        let actions = session.handle(event)
        updateTicker()
        for action in actions { apply(action) }
        hud.update(state: session.state, level: { [weak self] in self?.recorder?.level ?? -160 })
    }

    /// A one-second tick runs only while listening, so the core can stop a stuck key.
    private func updateTicker() {
        if session.state == .listening, ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.send(.tick(at: ProcessInfo.processInfo.systemUptime))
                }
            }
        } else if session.state != .listening {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func apply(_ action: DictationSession.Action) {
        switch action {
        case .startCapture: startCapture()
        case .stopCapture: stopCapture()
        case .discardCapture: discardCapture()
        case .insert(let text):
            paste(text)
        case .notice(let message): notify(message)
        }
    }

    // MARK: Capture

    private func startCapture() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            denied("Microphone access was just requested. Allow it, then hold the keys again.")
        default:
            denied("Dictation needs the microphone. Allow Earshot in System Settings → Privacy & Security → Microphone.")
        }
    }

    private func denied(_ message: String) {
        send(.failed)
        notify(message)
    }

    private func beginRecording() {
        discardKeptClip()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("earshot-dictation-\(UUID().uuidString).wav")
        do {
            let new = try MicRecorder(deviceID: microphoneID(), url: url) { [weak self] rec, error in
                Task { @MainActor in self?.recorderFinished(rec, error: error) }
            }
            recorder = new
            new.start()
            if let tink = NSSound(named: "Tink") {
                tink.volume = 0.3
                tink.play()
            }
        } catch {
            log("Dictation: could not start the microphone: \(error.localizedDescription)")
            send(.failed)
        }
    }

    private func stopCapture() {
        // The finished callback carries on from here. If there is no recorder, nothing will
        // call back, so fail now instead of waiting forever.
        guard let recorder else { return send(.failed) }
        recorder.stop()
    }

    private func discardCapture() {
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
            log("Dictation: recording failed: \(error.localizedDescription)")
            Self.deleteFiles(for: rec.url)
            return send(.failed)
        }
        // The device ended the capture while the key was still held: nothing to transcribe.
        if session.state == .listening {
            Self.deleteFiles(for: rec.url)
            return send(.failed)
        }
        transcribe(rec.url)
    }

    /// Transcribes the wav at `url`. On failure the wav is kept (in the temp directory only) for
    /// one retry; whisper's side files are always removed. On success everything is deleted.
    private func transcribe(_ url: URL) {
        let script = scriptPath()
        let helper = runHelper
        Task { @MainActor in
            let text = await Task.detached { () -> String? in
                let failure = await helper([script, url.path])
                let transcript = url.deletingPathExtension().appendingPathExtension("txt")
                let text = failure == nil ? try? String(contentsOf: transcript, encoding: .utf8) : nil
                if text == nil {
                    Self.deleteSideFiles(for: url)
                } else {
                    Self.deleteFiles(for: url)
                }
                return text
            }.value
            if text == nil {
                log("Dictation: transcription failed.")
                keptClip = url
                retryAvailable = true
            } else if keptClip == url {
                keptClip = nil
                retryAvailable = false
            }
            let corrected = text.map { DictationDictionary.load().apply($0) }
            send(.transcript(corrected, secureInput: IsSecureEventInputEnabled()))
        }
    }

    /// Retries the clip kept from the last failed transcription, once.
    func retryLast() {
        guard let clip = keptClip, FileManager.default.fileExists(atPath: clip.path) else {
            keptClip = nil
            retryAvailable = false
            return
        }
        send(.retry(meetingRecording: isMeetingRecording()))
        if session.state != .transcribing { return }
        // Give focus back to the app the user was typing in, so the paste lands there.
        NSApp.deactivate()
        transcribe(clip)
    }

    /// Deletes the kept clip, if any, and clears its state.
    private func discardKeptClip() {
        if let clip = keptClip { Self.deleteFiles(for: clip) }
        keptClip = nil
        retryAvailable = false
    }

    /// Removes the wav and everything whisper wrote beside it.
    nonisolated private static func deleteFiles(for wav: URL) {
        try? FileManager.default.removeItem(at: wav)
        deleteSideFiles(for: wav)
    }

    /// Removes only what whisper wrote beside the wav.
    nonisolated private static func deleteSideFiles(for wav: URL) {
        let base = wav.deletingPathExtension()
        for ext in ["txt", "srt", "json"] {
            try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
        }
    }

    // MARK: Insert

    private func paste(_ text: String) {
        guard AXIsProcessTrusted() else {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            // The clipboard is the only copy of the text here, so no transient markers.
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(text, forType: .string)
            send(.inserted)
            notify("Earshot can't type for you yet, so what you said is on the clipboard: press ⌘V to paste it. To type automatically, allow Earshot in System Settings → Privacy & Security → Accessibility.")
            return
        }
        let board = NSPasteboard.general
        // Every type of every item, so an image or a file list survives the round trip.
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // Clipboard managers skip these, so a dictated sentence is not stored in their history.
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        board.clearContents()
        board.writeObjects([item])
        let ours = board.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let key = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)  // V
            key?.flags = .maskCommand
            key?.post(tap: .cgAnnotatedSessionEventTap)
        }

        Task { @MainActor in
            // Give the target app time to read the pasteboard before putting the old contents back.
            try? await Task.sleep(nanoseconds: 500_000_000)
            // If something else wrote to the pasteboard meanwhile, that newer copy is the user's.
            if board.changeCount == ours {
                board.clearContents()
                let items = saved.map { entries -> NSPasteboardItem in
                    let restored = NSPasteboardItem()
                    for (type, data) in entries { restored.setData(data, forType: type) }
                    return restored
                }
                if !items.isEmpty { board.writeObjects(items) }
            }
            send(.inserted)
        }
    }

    // MARK: Notices

    private func notify(_ message: String) {
        NSSound.beep()
        log("Dictation: \(message)")
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Dictation"
            content.body = message
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
