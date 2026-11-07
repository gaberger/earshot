// Recording-related views: the detail header and the live recording screen.
// Pure SwiftUI + AppKit colors; no dependency on Library.
import SwiftUI
import AppKit

struct HeaderAction: Identifiable {
    let id = UUID()
    var title: String
    var icon: String
    var enabled: Bool
    var action: () -> Void
}

struct RecordingHeader: View {
    let title: String
    let date: Date
    let chips: [String]
    let tabs: [String]
    @Binding var selectedTab: Int
    let actions: [HeaderAction]
    let onRename: () -> Void

    init(title: String, date: Date, chips: [String], tabs: [String], selectedTab: Binding<Int>,
         actions: [HeaderAction], onRename: @escaping () -> Void) {
        self.title = title
        self.date = date
        self.chips = chips
        self.tabs = tabs
        self._selectedTab = selectedTab
        self.actions = actions
        self.onRename = onRename
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.title.bold())
                    .lineLimit(2)
                    .onTapGesture(count: 2, perform: onRename)
                Button(action: onRename) { Image(systemName: "pencil") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Rename")
                Spacer(minLength: 12)
                ForEach(actions) { a in
                    Button(action: a.action) { Label(a.title, systemImage: a.icon) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!a.enabled)
                }
            }
            HStack(spacing: 8) {
                Text(date.formatted(date: .complete, time: .shortened))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    Text(chip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                    Button { selectedTab = i } label: {
                        Text(tab)
                            .fontWeight(selectedTab == i ? .semibold : .regular)
                            .foregroundStyle(selectedTab == i ? Color.primary : Color.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(selectedTab == i ? Color.primary.opacity(0.10) : Color.clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RecordingScreen: View {
    let start: Date
    let micName: String
    let level: () -> Float
    let endingIn: Int?
    let onKeepRecording: () -> Void
    let onStop: () -> Void

    @State private var pulse = false

    init(start: Date, micName: String, level: @escaping () -> Float, endingIn: Int?,
         onKeepRecording: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.start = start
        self.micName = micName
        self.level = level
        self.endingIn = endingIn
        self.onKeepRecording = onKeepRecording
        self.onStop = onStop
    }

    private static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Circle().fill(Color.red).frame(width: 10, height: 10)
                        .opacity(pulse ? 0.35 : 1)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                    Text("Recording").font(.headline)
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Self.clock(Int(ctx.date.timeIntervalSince(start))))
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                waveform
                Label(micName, systemImage: "mic.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let n = endingIn {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.brandWarning)
                        Text("No one has spoken for a while. Stopping in \(n) s")
                            .font(.callout)
                        Spacer(minLength: 8)
                        Button("Keep recording", action: onKeepRecording)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.brandWarning.opacity(0.12)))
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))

            Button(action: onStop) { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.extraLarge)
            Text("Everything stays on this Mac. The text appears here when you stop.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 520)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { pulse = true }
    }

    private var waveform: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { ctx in
            let db = Double(level())
            let norm = 0.08 + 0.92 * min(1, max(0, (db + 60) / 60))
            let t = ctx.date.timeIntervalSinceReferenceDate
            let loud = db > -50
            HStack(spacing: 3) {
                ForEach(0..<48, id: \.self) { i in
                    let x = Double(i)
                    // Smooth shape in [0.35, 1]; multiplied by the level so it never exceeds it.
                    let shape = 0.675 + 0.325 * sin(x * 0.55 + t * 3.1) * cos(x * 0.21 - t * 1.7)
                    let h = max(4, 56 * norm * shape)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(loud ? Color.red : Color.secondary)
                        .frame(width: 4, height: h)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
    }
}
