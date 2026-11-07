// Sidebar navigation and the Dictation page. Dictation is kept apart from recordings.
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case recordings, dictation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recordings: return "Recordings"
        case .dictation: return "Dictation"
        }
    }

    var icon: String {
        switch self {
        case .recordings: return "waveform"
        case .dictation: return "keyboard"
        }
    }
}

struct SidebarNav: View {
    @Binding var selection: AppSection

    init(selection: Binding<AppSection>) {
        self._selection = selection
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(AppSection.allCases) { section in
                let selected = selection == section
                Button { selection = section } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.icon).frame(width: 22)
                        Text(section.title).font(.body.weight(.medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? Color.accentColor.opacity(0.18) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct DictationPage: View {
    let onEnable: () -> Void
    let onResetPermission: () -> Void
    @AppStorage(DictationPrefs.enabled) private var enabled = false
    @AppStorage(DictationPrefs.toggle) private var toggle = false

    init(onEnable: @escaping () -> Void, onResetPermission: @escaping () -> Void) {
        self.onEnable = onEnable
        self.onResetPermission = onResetPermission
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dictation").font(.largeTitle.bold())
                    Text("Speak in any app and Earshot types it for you. This is separate from your recordings.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    statCard("Status", enabled ? "On" : "Off")
                    statCard("Mode", toggle ? "Tap to start, tap to stop" : "Hold to talk")
                }

                DictationSettingsView(onEnable: onEnable, onResetPermission: onResetPermission)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statCard(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.08)))
    }
}
