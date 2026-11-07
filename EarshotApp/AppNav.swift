// Sidebar navigation and the Dictation page. Dictation is kept apart from recordings.
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case recordings, notes, dictation, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recordings: return "Recordings"
        case .notes: return "Notes"
        case .dictation: return "Dictation"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .recordings: return "waveform"
        case .notes: return "note.text"
        case .dictation: return "keyboard"
        case .settings: return "gearshape"
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
            ForEach([AppSection.recordings, AppSection.notes, AppSection.dictation]) { section in
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

                DictationSettingsView(onEnable: onEnable, onResetPermission: onResetPermission)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
