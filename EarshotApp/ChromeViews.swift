// Window chrome: the top bar with the ⌘K search field and results, and the sidebar footer.
import SwiftUI
import AppKit

private struct KeyHint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
    }
}

struct TopBar: View {
    let title: String
    @Binding var query: String
    let hits: [SearchHit]
    let focusToken: Int
    let onPick: (SearchHit) -> Void
    @FocusState private var focused: Bool

    init(title: String, query: Binding<String>, hits: [SearchHit], focusToken: Int, onPick: @escaping (SearchHit) -> Void) {
        self.title = title
        self._query = query
        self.hits = hits
        self.focusToken = focusToken
        self.onPick = onPick
    }

    private var showResults: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.callout).foregroundStyle(.secondary)
                Spacer()
                searchField
            }
            .padding(.horizontal, 28)
            .frame(height: 52)
            Divider()
        }
        .overlay(alignment: .topTrailing) {
            if showResults {
                results
                    .padding(.trailing, 28)
                    .offset(y: 46)
            }
        }
        .zIndex(100)
        .onChange(of: focusToken) { _, _ in focused = true }
        .onExitCommand {
            query = ""
            focused = false
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search recordings, notes, settings", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
            if query.isEmpty {
                KeyHint("⌘K")
            } else {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 320)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
    }

    private var results: some View {
        let shown = Array(hits.prefix(8))
        return VStack(spacing: 0) {
            if shown.isEmpty {
                Text("No matches for “\(query)”")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, hit in
                    if index > 0 { Divider() }
                    row(hit)
                }
            }
        }
        .frame(width: 420)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor)))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .zIndex(100)
    }

    private func row(_ hit: SearchHit) -> some View {
        let icon: String
        let title: String
        let detail: String
        switch hit {
        case let .recording(_, t, snippet): icon = "waveform"; title = t; detail = snippet
        case let .destination(_, t, d): icon = "gearshape"; title = t; detail = d
        case let .note(_, t, snippet): icon = "note.text"; title = t; detail = snippet
        }
        return Button { onPick(hit) } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SidebarFooter: View {
    let settingsSelected: Bool
    let onSettings: () -> Void
    let onHelp: () -> Void

    init(settingsSelected: Bool, onSettings: @escaping () -> Void, onHelp: @escaping () -> Void) {
        self.settingsSelected = settingsSelected
        self.onSettings = onSettings
        self.onHelp = onHelp
    }

    var body: some View {
        VStack(spacing: 4) {
            footerRow("Settings", icon: "gearshape", hint: "⌘,", selected: settingsSelected, action: onSettings)
            footerRow("Help", icon: "questionmark.circle", hint: nil, selected: false, action: onHelp)
        }
    }

    private func footerRow(_ title: String, icon: String, hint: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 22)
                Text(title).font(.body.weight(.medium))
                Spacer(minLength: 0)
                if let hint { KeyHint(hint) }
            }
            .foregroundStyle(selected ? Color.brandAccentText : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.brandAccent.opacity(0.18) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
