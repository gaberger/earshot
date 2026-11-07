import Foundation

/// The visible way back from an open recording: a "Recordings" link and the recording's name after it.
struct BackLink: Equatable {
    let label: String
    let trail: String
}

/// Decisions about leaving an open recording. Pure, so they can be tested without a window.
enum DetailNav {
    static let accessibilityLabel = "Back to Recordings"
    static let help = "Back to the recordings list (Esc or ⌘[)"

    static func backLink(inRecordings: Bool, openTitle: String?) -> BackLink? {
        guard inRecordings, let openTitle else { return nil }
        let trimmed = openTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return BackLink(label: "Recordings", trail: trimmed.isEmpty ? "Recording" : trimmed)
    }

    enum SidebarAction { case openSection, showRecordingsList }

    static func onSidebarTap(tappedRecordings: Bool, hasOpenRecording: Bool) -> SidebarAction {
        tappedRecordings ? .showRecordingsList : .openSection
    }

    static func escapeReturnsToList(inRecordings: Bool, hasOpenRecording: Bool, searchHasText: Bool, editingText: Bool) -> Bool {
        inRecordings && hasOpenRecording && !searchHasText && !editingText
    }
}
