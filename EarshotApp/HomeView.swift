// Earshot's home screen: greeting, status cards, filterable day-grouped feed, floating record bar,
// and the sidebar status card. Pure SwiftUI + AppKit colors; no dependency on Library or the app.
import SwiftUI
import AppKit

struct HomeItem: Identifiable, Equatable {
    enum State: Equatable {
        case done
        case working
        case failed(String)
    }

    let id: String
    var date: Date
    var title: String
    var detail: String
    var state: State
}

struct HomeView: View {
    let items: [HomeItem]
    let onOpen: (String) -> Void
    var rowMenu: ((HomeItem) -> AnyView)? = nil

    private enum Filter { case all, errors }
    @State private var filter: Filter = .all

    init(items: [HomeItem], onOpen: @escaping (String) -> Void) {
        self.items = items
        self.onOpen = onOpen
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var failedCount: Int {
        items.filter { if case .failed = $0.state { return true } else { return false } }.count
    }

    private var todayCount: Int {
        items.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    private var weekCount: Int {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        return items.filter { $0.date >= cutoff }.count
    }

    private var visibleItems: [HomeItem] {
        let base: [HomeItem]
        switch filter {
        case .all: base = items
        case .errors: base = items.filter { if case .failed = $0.state { return true } else { return false } }
        }
        return base.sorted { $0.date > $1.date }
    }

    private var groups: [(day: Date, items: [HomeItem])] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: visibleItems) { cal.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { (day: $0, items: byDay[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting).font(.largeTitle.bold())
                    Text("Press Record, or drop an audio or video file here. Everything stays on this Mac.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    statCard("Today", "\(todayCount) \(todayCount == 1 ? "recording" : "recordings")")
                    statCard("This week", "\(weekCount) \(weekCount == 1 ? "recording" : "recordings")")
                    statCard("Needs attention", failedCount == 0 ? "None" : "\(failedCount)")
                }

                HStack(spacing: 8) {
                    pill("All", selected: filter == .all) { filter = .all }
                    if failedCount > 0 {
                        pill("Errors · \(failedCount)", selected: filter == .errors) { filter = .errors }
                    }
                }

                if items.isEmpty {
                    Text("Nothing here yet. Press Record to start.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(dayTitle(group.day))
                                    .font(.caption.bold())
                                    .tracking(0.8)
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
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
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: failedCount) { _, count in
            if count == 0 { filter = .all }
        }
    }

    private func statCard(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            Text(value).font(.title3.weight(.semibold)).lineLimit(1).truncationMode(.tail)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.08)))
    }

    private func pill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(selected ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Color.primary : Color.clear))
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Color(nsColor: .separatorColor), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func row(_ item: HomeItem) -> some View {
        let failed: String? = { if case .failed(let m) = item.state { return m } else { return nil } }()
        return Button { onOpen(item.id) } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(item.date.formatted(date: .omitted, time: .shortened))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 84, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(failed != nil ? .body.weight(.semibold) : .body)
                        .foregroundStyle(failed != nil ? Color.orange : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let failed {
                        Text(failed).font(.callout).foregroundStyle(Color.orange)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 8)
                if item.state == .working {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { if let rowMenu { rowMenu(item) } }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "TODAY" }
        if cal.isDateInYesterday(day) { return "YESTERDAY" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
    }
}

struct RecordBar: View {
    let recordingSince: Date?
    let onRecord: () -> Void
    let onImport: () -> Void

    init(recordingSince: Date?, onRecord: @escaping () -> Void, onImport: @escaping () -> Void) {
        self.recordingSince = recordingSince
        self.onRecord = onRecord
        self.onImport = onImport
    }

    var body: some View {
        HStack(spacing: 28) {
            Button(action: onImport) {
                VStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.down").font(.title3)
                    Text("Import").font(.caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                Button(action: onRecord) {
                    ZStack {
                        Circle().fill(Color.red).frame(width: 56, height: 56)
                        Circle().strokeBorder(Color.white, lineWidth: 4).frame(width: 56, height: 56)
                        if recordingSince != nil {
                            RoundedRectangle(cornerRadius: 4).fill(Color.white).frame(width: 18, height: 18)
                        } else {
                            Circle().fill(Color.white).frame(width: 18, height: 18)
                        }
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                if let since = recordingSince {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.elapsed(from: since, to: context.date))
                            .font(.caption.monospacedDigit())
                    }
                }
            }

            VStack(spacing: 3) {
                Text("⌘R").font(.caption).foregroundStyle(.secondary)
                Text(recordingSince != nil ? "Stop" : "Record").font(.caption)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct SidebarStatusCard: View {
    let ready: Bool
    let detail: String

    init(ready: Bool, detail: String) {
        self.ready = ready
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(ready ? Color.green : Color.red).frame(width: 7, height: 7)
                Text(ready ? "Ready · on this Mac" : "Recording")
                    .font(.callout.weight(.semibold))
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}
