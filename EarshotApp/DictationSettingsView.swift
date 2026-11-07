import SwiftUI
import AppKit
import Combine
import ApplicationServices

/// Records a new dictation shortcut: click, then press the combination. Esc cancels.
struct HotKeyRecorder: View {
    @Binding var hotKey: HotKey
    @Binding var notice: String?
    @State private var listening = false
    @State private var monitor: Any?
    @State private var resignObserver: Any?

    var body: some View {
        Button {
            if listening { stop() } else { start() }
        } label: {
            HStack(spacing: 6) {
                if listening {
                    Text("Press the new shortcut… (Esc to cancel)")
                } else {
                    Text(hotKey.display)
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(listening ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .onDisappear { stop() }
    }

    private func start() {
        notice = nil
        listening = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { _ in
            stop()
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 {
            stop()
            return
        }
        let candidate = HotKey(keyCode: UInt32(event.keyCode),
                               modifiers: HotKey.carbonModifiers(fromCocoa: event.modifierFlags.rawValue))
        if !candidate.isValid {
            notice = "Use Control or Option with a key, or a function key like F5. Shortcuts that macOS already uses can't be chosen."
            return
        }
        if candidate.save() {
            hotKey = candidate
            notice = nil
        }
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        listening = false
    }
}

private struct CorrectionRow: Identifiable {
    let id = UUID()
    var heard: String
    var write: String
}

struct DictationSettingsView: View {
    let onEnable: () -> Void
    var onResetPermission: () -> Void = {}
    @AppStorage(DictationPrefs.enabled) private var enabled = false
    @AppStorage(DictationPrefs.toggle) private var toggle = false
    @AppStorage(DictationPrefs.cleanup) private var cleanup = false
    @AppStorage(DictationPrefs.highlight) private var highlight = true
    @AppStorage(DictationPrefs.sendReturn) private var sendReturn = false
    @State private var hotKey = HotKey.load()
    @State private var hotKeyNotice: String?
    @State private var trusted = AXIsProcessTrusted()
    private let trustTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    @State private var corrections: [CorrectionRow] =
        DictationDictionary.load().entries.map { CorrectionRow(heard: $0.heard, write: $0.write) }

    init(onEnable: @escaping () -> Void, onResetPermission: @escaping () -> Void = {}) {
        self.onEnable = onEnable
        self.onResetPermission = onResetPermission
    }

    private func save() {
        DictationDictionary(entries: corrections.map { .init(heard: $0.heard, write: $0.write) }).save()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Dictation") {
                SettingsRow("Dictate into any app",
                            detail: enabled ? "Hold a shortcut in any app, speak, and Earshot types what you said."
                                            : "Turn this on to choose a shortcut.") {
                    Toggle("", isOn: $enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: enabled) { _, on in
                            if on { onEnable() }
                        }
                }
                if enabled && !trusted {
                    SettingsBanner("Earshot can't type for you yet. Press Reset and allow, then switch Earshot on in the list.",
                                   actionTitle: "Reset and allow") {
                        onResetPermission()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Group {
                SettingsSection("Shortcut", dimmed: !enabled) {
                    SettingsRow("To dictate",
                                detail: "Click the shortcut to change it. " + (toggle ? "Tap to start, tap again to stop." : "Hold the keys while you talk, then let go.")) {
                        HStack {
                            HotKeyRecorder(hotKey: $hotKey, notice: $hotKeyNotice)
                                .buttonStyle(.plain)
                                .font(.body.weight(.semibold))
                            if hotKey != .default {
                                Button("Reset") {
                                    HotKey.reset()
                                    hotKey = HotKey.load()
                                    hotKeyNotice = nil
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    if let hotKeyNotice {
                        SettingsBanner(hotKeyNotice)
                    }
                    SettingsRow("Mode", detail: "A change applies from your next dictation.") {
                        Picker("", selection: $toggle) {
                            Text("Hold").tag(false)
                            Text("Tap").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }

                SettingsSection("Highlight", dimmed: !enabled) {
                    SettingsRow("Highlight the window I am dictating into",
                                detail: "A little fire around the window your words will be typed into. Respects Reduce Motion.") {
                        Toggle("", isOn: $highlight)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                SettingsSection("Tidy up", dimmed: !enabled) {
                    SettingsRow("Tidy up what I say",
                                detail: "Removes ums and fixes punctuation using Apple's on-device model. Off by default; may reword slightly.") {
                        Toggle("", isOn: $cleanup)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                SettingsSection("Submit", dimmed: !enabled) {
                    SettingsRow("Press Return after typing",
                                detail: "Presses Return once the text is typed, so a message sends or a form submits. Off by default. Turn it on only if you want that.") {
                        Toggle("", isOn: $sendReturn)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                SettingsSection("Corrections", dimmed: !enabled) {
                    SettingsRow("Fix words it mishears",
                                detail: "Whole words only, ignoring case. The longest match wins.") {
                        Button("Add") {
                            corrections.append(CorrectionRow(heard: "", write: ""))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    ForEach($corrections) { $row in
                        HStack {
                            TextField("What it hears", text: $row.heard)
                                .textFieldStyle(.roundedBorder)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            TextField("How to write it", text: $row.write)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                corrections.removeAll { $0.id == row.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    if corrections.isEmpty {
                        Text("No corrections yet. Example: ear shot → Earshot")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "lock.fill").font(.caption2)
                    Text("Nothing is typed into password fields. The audio is deleted at once, except a clip that could not be transcribed, which stays in a private temporary file until your next dictation so you can retry it.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .onChange(of: corrections.map { [$0.heard, $0.write] }) { _, _ in save() }
        .onAppear { trusted = AXIsProcessTrusted() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = AXIsProcessTrusted()
        }
        .onReceive(trustTimer) { _ in
            trusted = AXIsProcessTrusted()
        }
    }
}
