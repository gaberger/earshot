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
    /// Path of the earshot-speak script, used to stop the spoken reply.
    var speakScriptPath: () -> String = { "" }
    /// Runs the transcribe script with these arguments. `nil` means success, else the error text.
    var runHelper: ([String]) async -> String? = { _ in "No transcriber is set up." }
    var log: (String) -> Void = { _ in }
    /// Tidies a transcript with a language model; nil means "no answer", and the original is typed.
    var tidy: (String) async -> String? = { _ in nil }
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
    /// The app and window dictation started in (ADR-2611071800); nil when unknown. Cleared when idle.
    private var pasteTarget: TargetSnapshot?
    /// The target window's outline, read once at key-down; nil when off or nothing sensible to draw.
    private var highlightFrame: CGRect?
    let highlighter = WindowHighlighter()
    /// True while the cleanup (tidy) stage runs, so the indicator can name it.
    private(set) var tidying = false

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
        highlighter.hide()
        highlightFrame = nil
        // Turning it off mid-capture must not leave the microphone open. A tick far in the future
        // stops a capture in either mode; key up is ignored in tap-to-toggle mode.
        send(.tick(at: ProcessInfo.processInfo.systemUptime + 3600))
    }

    private func hotKeyChanged(pressed: Bool) {
        if pressed { stopSpeech() }
        let now = ProcessInfo.processInfo.systemUptime
        // A changed preference applies at the next dictation, never mid-capture.
        if pressed, session.state == .idle {
            session = DictationSession(DictationSession.Config(toggle: DictationPrefs.isToggle()))
            highlightFrame = DictationPrefs.isHighlightEnabled() ? captureTargetWindow() : nil
            pasteTarget = currentSnapshot()
        }
        send(pressed ? .keyDown(at: now, meetingRecording: isMeetingRecording()) : .keyUp(at: now))
    }

    /// Stops the talk-back if it is speaking. Fire and forget: a failure never touches dictation.
    private func stopSpeech() {
        let pid = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".earshot/speak.pid")
        guard let argv = SpeechStop.command(pidFileExists: FileManager.default.fileExists(atPath: pid.path),
                                            scriptPath: speakScriptPath()) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: argv[0])
        process.arguments = Array(argv.dropFirst())
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil { log("Dictation: stopped speech.") }
    }

    // MARK: Session

    private func send(_ event: DictationSession.Event) {
        let actions = session.handle(event)
        updateTicker()
        for action in actions { apply(action) }
        if session.state == .idle { pasteTarget = nil }
        refreshHUD()
    }

    private func refreshHUD() {
        hud.update(state: session.state, tidying: tidying, level: { [weak self] in self?.recorder?.level ?? -160 })
        // Tidying is the same wait as transcribing, so it looks the same.
        let state: DictationSession.State = tidying ? .transcribing : session.state
        let style = WindowHighlight.style(for: state,
                                          reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if let highlightFrame, style != .none {
            highlighter.show(frame: highlightFrame, style: style)
        } else {
            highlighter.hide()
            if session.state == .idle { highlightFrame = nil }
        }
    }

    /// The outline of the frontmost app's focused window, in AppKit coordinates, or nil. Reads
    /// geometry only (position and size): never a title or any text. Skipped during secure input.
    private func captureTargetWindow() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let target = currentSnapshot(), let axFrame = target.frame else { return nil }
        let screens = NSScreen.screens
        let flipped = WindowHighlight.appKitFrame(fromAX: axFrame,
                                                  primaryHeight: screens.first?.frame.height ?? 0)
        return WindowHighlight.rect(forWindow: flipped, screens: screens.map(\.frame))
    }

    /// What was readable of the frontmost app: pid, focused window element and its raw AX frame, and
    /// the focused element. Elements are compared with CFEqual, never hashed.
    private struct TargetSnapshot {
        var pid: Int32
        var frame: CGRect?
        var window: AXUIElement?
        var focus: AXUIElement?
    }

    /// Pairs two elements into identity tokens: unreadable on either side gives nil/nil; equal gives 1/1;
    /// different gives 1/2.
    private static func pairTokens(_ a: AXUIElement?, _ b: AXUIElement?) -> (Int?, Int?) {
        guard let a, let b else { return (nil, nil) }
        return CFEqual(a, b) ? (1, 1) : (1, 2)
    }

    private static func pasteDecision(target: TargetSnapshot?, current: TargetSnapshot?) -> PasteDecision {
        guard let target, let current else { return PasteGuard.decide(target: nil, current: nil) }
        let w = pairTokens(target.window, current.window)
        let f = pairTokens(target.focus, current.focus)
        return PasteGuard.decide(
            target: PasteTarget(pid: target.pid, frame: target.frame, window: w.0, focus: f.0),
            current: PasteTarget(pid: current.pid, frame: current.frame, window: w.1, focus: f.1))
    }

    /// One diagnostic line for the paste guard: plain words only, never text, titles, names or content.
    private static func pasteCheckLine(target: TargetSnapshot?, current: TargetSnapshot?, decision: PasteDecision) -> String {
        func word(_ a: AXUIElement?, _ b: AXUIElement?) -> String {
            guard let a, let b else { return "unreadable" }
            return CFEqual(a, b) ? "equal" : "different"
        }
        guard let target, let current else {
            return "Dictation: paste check — target snapshot: \(target != nil), current snapshot: \(current != nil), decision: \(decision == .hold ? "hold" : "paste")"
        }
        return "Dictation: paste check — app same: \(target.pid == current.pid), window: \(word(target.window, current.window)), focus: \(word(target.focus, current.focus)), decision: \(decision == .hold ? "hold" : "paste")"
    }

    /// The frontmost app's pid and its focused window's raw AX frame (the same space for both reads),
    /// or nil with no frontmost app or during secure input. Geometry only: never a title or any text.
    private func currentSnapshot() -> TargetSnapshot? {
        guard !IsSecureEventInputEnabled() else { return nil }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.25)
        func copy(_ attribute: String, of source: AXUIElement) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(source, attribute as CFString, &value) == .success ? value : nil
        }
        func axElement(_ ref: CFTypeRef?) -> AXUIElement? {
            guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
            return (ref as! AXUIElement)
        }
        let focus = axElement(copy(kAXFocusedUIElementAttribute, of: element))
        guard let window = axElement(copy(kAXFocusedWindowAttribute, of: element) ?? copy(kAXMainWindowAttribute, of: element))
        else { return TargetSnapshot(pid: pid, frame: nil, window: nil, focus: focus) }
        guard let posRef = copy(kAXPositionAttribute, of: window), CFGetTypeID(posRef) == AXValueGetTypeID(),
              let sizeRef = copy(kAXSizeAttribute, of: window), CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return TargetSnapshot(pid: pid, frame: nil, window: window, focus: focus) }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return TargetSnapshot(pid: pid, frame: nil, window: window, focus: focus) }
        return TargetSnapshot(pid: pid, frame: CGRect(origin: origin, size: size), window: window, focus: focus)
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
            var cleaned = text
            if let original = text, DictationPrefs.isCleanupEnabled() {
                let tidy = self.tidy
                tidying = true
                refreshHUD()
                let answer = await withTaskGroup(of: String?.self) { group in
                    group.addTask { await tidy(original) }
                    group.addTask { try? await Task.sleep(for: .seconds(5)); return nil }
                    let first = await group.next() ?? nil
                    group.cancelAll()
                    return first
                }
                tidying = false
                refreshHUD()
                cleaned = DictationCleanup.choose(original: original, cleaned: answer)
                if answer == nil { log("Dictation: cleanup skipped.") }
            }
            let corrected = cleaned.map { DictationDictionary.load().apply($0) }
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
        Task { @MainActor in
            // Let the previous app become frontmost again before reading the target window.
            try? await Task.sleep(nanoseconds: 300_000_000)
            pasteTarget = currentSnapshot()
            transcribe(clip)
        }
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
        let currentNow = currentSnapshot()
        let decision = Self.pasteDecision(target: pasteTarget, current: currentNow)
        log(Self.pasteCheckLine(target: pasteTarget, current: currentNow, decision: decision))
        if decision == .hold {
            // The clipboard is the only copy of the text here, so no transient markers.
            let held = NSPasteboard.general
            held.clearContents()
            held.setString(text, forType: .string)
            send(.inserted)
            notify("You switched windows, so what you said is on the clipboard. Press ⌘V where you want it.")
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

        if DictationSubmit.shouldSendReturn(enabled: DictationPrefs.isSendReturnEnabled(), text: text,
                                            pasted: true, secureInput: IsSecureEventInputEnabled()) {
            let guardTarget = pasteTarget
            Task { @MainActor in
                // Let the paste land first; this is well inside the 0.5 s clipboard restore below.
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Self.pasteDecision(target: guardTarget, current: currentSnapshot()) == .hold {
                    log("Dictation: Return not sent, the window changed")
                    return
                }
                for down in [true, false] {
                    let key = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: down)  // Return
                    key?.post(tap: .cgAnnotatedSessionEventTap)
                }
                log("Dictation: pressed Return.")
            }
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
