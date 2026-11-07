// Earshot's Notes page: the log of what you dictated, kept on this Mac as text.
// Matches HomeView's look. Pure SwiftUI + AppKit colors; no dependency on the app.
import SwiftUI
import AppKit

struct NoteItem: Identifiable, Equatable {
    let id: String
    var date: Date
    var text: String
    var seconds: Double?
}

struct NotesView: View {
    let items: [NoteItem]
    let recordingSince: Date?
    let transcribing: Bool
    let level: () -> Float
    let onRecord: () -> Void
    let onStop: () -> Void
    let onCopy: (String) -> Void
    let onDelete: (String) -> Void
    let onClear: () -> Void

    @State private var confirmClear = false
    @State private var pulse = false

    init(items: [NoteItem], recordingSince: Date?, transcribing: Bool, level: @escaping () -> Float,
         onRecord: @escaping () -> Void, onStop: @escaping () -> Void,
         onCopy: @escaping (String) -> Void, onDelete: @escaping (String) -> Void, onClear: @escaping () -> Void) {
        self.items = items
        self.recordingSince = recordingSince
        self.transcribing = transcribing
        self.level = level
        self.onRecord = onRecord
        self.onStop = onStop
        self.onCopy = onCopy
        self.onDelete = onDelete
        self.onClear = onClear
    }

    private var sortedItems: [NoteItem] { items.sorted { $0.date > $1.date } }

    private var groups: [(day: Date, items: [NoteItem])] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: sortedItems) { cal.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { (day: $0, items: byDay[$0] ?? []) }
    }

    private var busy: Bool { recordingSince != nil || transcribing }

    private var recordButton: some View {
        Button(action: onRecord) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.red).frame(width: 22, height: 22)
                    Circle().fill(Color.white).frame(width: 10, height: 10)
                }
                Text("Record a note").font(.body.weight(.semibold)).lineLimit(1)
            }
            .fixedSize()
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .frame(height: 38)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .overlay(Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
    }

    private var titleText: some View {
        Text("Notes").font(.largeTitle.bold()).lineLimit(1).minimumScaleFactor(0.5)
    }

    private var subtitle: String {
        if recordingSince != nil { return "Recording… press Stop when you are done." }
        if transcribing { return "Transcribing on this Mac…" }
        return "Your own voice notes. Press Record, speak, and the text is saved here. Nothing is typed into other apps."
    }

    @ViewBuilder private var header: some View {
        if busy {
            titleText.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    titleText.frame(minWidth: 120, alignment: .leading)
                    Spacer(minLength: 12)
                    recordButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    titleText
                    recordButton
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let since = recordingSince {
                    recordingCard(since)
                } else if transcribing {
                    transcribingCard
                }

                if !items.isEmpty {
                    HStack {
                        Spacer()
                        Button("Clear all") { confirmClear = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .fixedSize()
                    }
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
                } else if !busy {
                    emptyState("mic", "No notes yet. Press Record a note and say what is on your mind.")
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
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }

    private static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func recordingCard(_ since: Date) -> some View {
        card {
            HStack(spacing: 8) {
                Circle().fill(Color.red).frame(width: 10, height: 10)
                    .opacity(pulse ? 0.35 : 1)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                Text("Recording").font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Self.clock(Int(ctx.date.timeIntervalSince(since))))
                        .font(.title3.monospacedDigit())
                        .lineLimit(1)
                }
            }
            waveform
            Button(action: onStop) {
                Label("Stop", systemImage: "stop.fill").lineLimit(1)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .fixedSize()
        }
        .onAppear { pulse = true }
    }

    private var transcribingCard: some View {
        card {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Transcribing on this Mac…").font(.headline).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }

    private var waveform: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { ctx in
            let db = Double(level())
            let norm = 0.08 + 0.92 * min(1, max(0, (db + 60) / 60))
            let t = ctx.date.timeIntervalSinceReferenceDate
            let loud = db > -50
            HStack(spacing: 3) {
                ForEach(0..<40, id: \.self) { i in
                    let x = Double(i)
                    let shape = 0.675 + 0.325 * sin(x * 0.55 + t * 3.1) * cos(x * 0.21 - t * 1.7)
                    let h = max(4, 36 * norm * shape)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(loud ? Color.red : Color.secondary)
                        .frame(maxWidth: 4, minHeight: h, maxHeight: h)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
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
                    .lineLimit(8)
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
        guard let secs = item.seconds else { return nil }
        let total = Int(secs.rounded())
        return total > 60 ? String(format: "%d:%02d", total / 60, total % 60) : "\(total) s"
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "TODAY" }
        if cal.isDateInYesterday(day) { return "YESTERDAY" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
    }
}
