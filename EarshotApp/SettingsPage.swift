// Recording, transcription, speaker and summary settings as cards, matching the Dictation page
// (ADR-2611072100 B2, B3). Plain values and bindings only, so the render harness can build it.
import SwiftUI
import AppKit

/// One choice in a settings menu: a microphone, a summary template.
struct SettingsChoice: Identifiable, Hashable {
    let id: String
    let name: String
    var icon: String? = nil
}

struct RecordingSettingsCards: View {
    @Binding var microphoneID: String
    let microphones: [SettingsChoice]
    let defaultMicrophoneName: String
    @Binding var autoStopMinutes: Int
    @Binding var offerOnCall: Bool
    @Binding var openAtLogin: Bool
    let loginNotice: String?
    let onOpenLoginItems: (() -> Void)?
    @Binding var translate: Bool
    /// Translate can't change while recording: it applies to the transcription that follows.
    let translateLocked: Bool
    @Binding var identifySpeakers: Bool
    @Binding var speakerCount: Int
    @Binding var summaryTemplate: String
    let templates: [SettingsChoice]
    /// The call-audio rows (ADR-2611240900), shown inside the Recording card under Microphone.
    var callAudioRows: AnyView = AnyView(EmptyView())

    private var chosenMissing: Bool {
        !microphoneID.isEmpty && !microphones.contains { $0.id == microphoneID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Recording") {
                SettingsRow("Microphone", detail: "System default follows the input chosen in System Settings → Sound.") {
                    menu($microphoneID) {
                        Text("System default (\(defaultMicrophoneName))").tag("")
                        if chosenMissing { Text("Not connected").tag(microphoneID) }
                        Divider()
                        ForEach(microphones) { Text($0.name).tag($0.id) }
                    }
                }
                if chosenMissing {
                    SettingsBanner("This microphone isn't connected. Recordings use the system default until it is.")
                }
                callAudioRows
                SettingsRow("Stop when quiet", detail: CallAudioRules.stopWhenQuietDetail) {
                    menu($autoStopMinutes) {
                        Text("Never").tag(0)
                        ForEach([3, 5, 10, 15, 30], id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                }
                SettingsRow("Offer to record when a call starts",
                            detail: "When Zoom, Teams, Meet or a similar app starts using the microphone. "
                                + "It only asks; it never records without your click.") {
                    Toggle("", isOn: $offerOnCall).labelsHidden().toggleStyle(.switch)
                }
                SettingsRow("Open Earshot at login",
                            detail: "Earshot has to be running to notice a call; it waits in the menu bar.") {
                    Toggle("", isOn: $openAtLogin).labelsHidden().toggleStyle(.switch)
                }
                if let loginNotice {
                    SettingsBanner(loginNotice, actionTitle: onOpenLoginItems == nil ? nil : "Open Login Items",
                                   action: onOpenLoginItems)
                }
            }

            SettingsSection("Transcription") {
                SettingsRow("Translate to English",
                            detail: translateLocked
                                ? "Stop recording to change this. It applies to the next transcription."
                                : "Speech in another language is written in English. Applies to the next transcription.") {
                    Toggle("", isOn: $translate).labelsHidden().toggleStyle(.switch).disabled(translateLocked)
                }
            }

            SettingsSection("Speakers") {
                SettingsRow("Identify speakers",
                            detail: "A local voice model labels who spoke when. Rename them in the Transcript tab.") {
                    Toggle("", isOn: $identifySpeakers).labelsHidden().toggleStyle(.switch)
                }
                SettingsRow("Number of speakers",
                            detail: "If you know how many people were there, choose it: that is more accurate.") {
                    menu($speakerCount) {
                        Text("Detect automatically").tag(0)
                        Text("1 (no labels)").tag(1)
                        ForEach(2...10, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .disabled(!identifySpeakers)
                }
            }

            SettingsSection("Summaries") {
                SettingsRow("Default template",
                            detail: "New recordings are summarized in this format. Switch any summary in its Summary tab.") {
                    menu($summaryTemplate) {
                        ForEach(templates) { t in
                            if let icon = t.icon { Label(t.name, systemImage: icon).tag(t.id) } else { Text(t.name).tag(t.id) }
                        }
                    }
                }
            }
        }
    }

    /// A pop-up menu that sizes to its choice and never pushes the row's title off the card.
    private func menu<Value: Hashable, Content: View>(_ selection: Binding<Value>,
                                                      @ViewBuilder _ content: () -> Content) -> some View {
        Picker("", selection: selection, content: content)
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 190, alignment: .trailing)
    }
}
