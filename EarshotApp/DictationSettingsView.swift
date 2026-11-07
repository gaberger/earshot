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
        Button(listening ? "Press the new shortcut… (Esc to cancel)" : hotKey.display) {
            if listening { stop() } else { start() }
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
    @AppStorage(DictationPrefs.enabled) private var enabled = false
    @AppStorage(DictationPrefs.toggle) private var toggle = false
    @State private var hotKey = HotKey.load()
    @State private var hotKeyNotice: String?
    @State private var trusted = AXIsProcessTrusted()
    private let trustTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    @State private var corrections: [CorrectionRow] =
        DictationDictionary.load().entries.map { CorrectionRow(heard: $0.heard, write: $0.write) }

    init(onEnable: @escaping () -> Void) {
        self.onEnable = onEnable
    }

    private func save() {
        DictationDictionary(entries: corrections.map { .init(heard: $0.heard, write: $0.write) }).save()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Dictation") {
                SettingsRow("Dictate into any app",
                            detail: "Hold a shortcut in any app, speak, and Earshot types what you said.") {
                    Toggle("", isOn: $enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: enabled) { _, on in
                            if on { onEnable() }
                        }
                }
                if enabled && !trusted {
                    SettingsBanner("Earshot is not allowed to type for you yet. If Earshot is already in the list, remove it with the minus button and add it again; macOS forgets the permission after an update.",
                                   actionTitle: "Open Accessibility settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Group {
                SettingsSection("Shortcut") {
                    SettingsRow("To dictate",
                                detail: toggle ? "Tap to start, tap again to stop." : "Hold the keys while you talk, then let go.") {
                        HStack {
                            HotKeyRecorder(hotKey: $hotKey, notice: $hotKeyNotice)
                                .buttonStyle(.plain)
                                .font(.body.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                                )
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

                SettingsSection("Corrections") {
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

                Text("Nothing is typed into password fields. The audio is deleted at once, except a clip that could not be transcribed, which stays in a private temporary file until your next dictation so you can retry it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
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
