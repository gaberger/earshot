// Earshot's Notes page: the log of what you dictated, kept on this Mac as text.
// Matches HomeView's look. Pure SwiftUI + AppKit colors; no dependency on the app.
import SwiftUI
import AppKit

struct NoteItem: Identifiable, Equatable {
    let id: String
    var date: Date
    var text: String
    var app: String?
    var seconds: Double?
}

struct NotesView: View {
    let items: [NoteItem]
    let keepLog: Bool
    let shortcut: String
    let onCopy: (String) -> Void
    let onDelete: (String) -> Void
    let onClear: () -> Void

    @State private var selectedApp: String? = nil
    @State private var confirmClear = false

    init(items: [NoteItem], keepLog: Bool, shortcut: String,
         onCopy: @escaping (String) -> Void, onDelete: @escaping (String) -> Void, onClear: @escaping () -> Void) {
        self.items = items
        self.keepLog = keepLog
        self.shortcut = shortcut
        self.onCopy = onCopy
        self.onDelete = onDelete
        self.onClear = onClear
    }

    private var topApps: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in items { if let app = item.app, !app.isEmpty { counts[app, default: 0] += 1 } }
        let sorted = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        return sorted.prefix(4).map { (name: $0.key, count: $0.value) }
    }

    private var visibleItems: [NoteItem] {
        let base = selectedApp.map { app in items.filter { $0.app == app } } ?? items
        return base.sorted { $0.date > $1.date }
    }

    private var groups: [(day: Date, items: [NoteItem])] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: visibleItems) { cal.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { (day: $0, items: byDay[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes").font(.largeTitle.bold())
                    Text("What you dictate, kept on this Mac as text. The audio is deleted at once.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if keepLog && !items.isEmpty {
                    HStack(spacing: 12) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                pill("All · \(items.count)", selected: selectedApp == nil) { selectedApp = nil }
                                ForEach(topApps, id: \.name) { app in
                                    pill("\(app.name) · \(app.count)", selected: selectedApp == app.name) { selectedApp = app.name }
                                }
                            }
                        }
                        Button("Clear all") { confirmClear = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .fixedSize()
                    }
                }

                if !keepLog {
                    emptyState("text.badge.xmark", "The notes log is off. Turn on Keep a log in the Dictation page.")
                } else if items.isEmpty {
                    emptyState("mic", "Nothing here yet. Hold \(shortcut) in any app and speak: what you say is typed there and kept here.")
                } else if visibleItems.isEmpty {
                    emptyState("line.3.horizontal.decrease", "No notes from this app.")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.day) { groupIndex, group in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(dayTitle(group.day))
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(0.6)
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, groupIndex > 0 ? 18 : 0)
                                    .padding(.bottom, 4)
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { Divider() }
                                    row(item)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Delete all \(items.count) notes?", isPresented: $confirmClear) {
            Button("Delete all", role: .destructive) { onClear() }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: items) { _, newItems in
            if let app = selectedApp, !newItems.contains(where: { $0.app == app }) { selectedApp = nil }
        }
    }

    private func emptyState(_ icon: String, _ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle)
            Text(message)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func pill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func row(_ item: NoteItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(item.date.formatted(date: .omitted, time: .shortened)
                    .replacingOccurrences(of: "\u{202F}", with: " ")
                    .replacingOccurrences(of: "\u{00A0}", with: " "))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.text)
                    .font(.body)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let meta = metaLine(item) {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                Button { onCopy(item.text) } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy")
                Button { onDelete(item.id) } label: { Image(systemName: "trash") }
                    .help("Delete")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metaLine(_ item: NoteItem) -> String? {
        var parts: [String] = []
        if let app = item.app, !app.isEmpty { parts.append(app) }
        if let secs = item.seconds {
            let total = Int(secs.rounded())
            parts.append(total > 60 ? String(format: "%d:%02d s", total / 60, total % 60) : "\(total) s")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "TODAY" }
        if cal.isDateInYesterday(day) { return "YESTERDAY" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
    }
}
