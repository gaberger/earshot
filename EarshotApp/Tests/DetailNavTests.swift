// Tests for DetailNav: the way back from an open recording to the list.
// Run: bash EarshotApp/Tests/run.sh. Every expected value is written out by hand.
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

@main struct DetailNavTests {
    static func main() {
        // MARK: the visible back link in the top bar
        let a = DetailNav.backLink(inRecordings: true, openTitle: "Weekly sync")
        checkTrue("an open recording shows a back link labelled Recordings", a?.label == "Recordings", "\(String(describing: a))")
        checkTrue("the back link names the open recording after it", a?.trail == "Weekly sync", "\(String(describing: a))")
        checkTrue("no back link outside the Recordings category, even if a recording is open",
                  DetailNav.backLink(inRecordings: false, openTitle: "Weekly sync") == nil)
        checkTrue("no back link on the list itself (nothing is open)", DetailNav.backLink(inRecordings: true, openTitle: nil) == nil)
        checkTrue("the recording name is trimmed of spaces and new lines",
                  DetailNav.backLink(inRecordings: true, openTitle: "  Roadmap review\n")?.trail == "Roadmap review")
        checkTrue("a blank name still gets a trail, so the link is never bare",
                  DetailNav.backLink(inRecordings: true, openTitle: " \n ")?.trail == "Recording")
        let long = String(repeating: "x", count: 300)
        checkTrue("a very long name is kept whole (the view truncates it)",
                  DetailNav.backLink(inRecordings: true, openTitle: long)?.trail.count == 300)
        checkTrue("the link is spoken as Back to Recordings", DetailNav.accessibilityLabel == "Back to Recordings")
        checkTrue("the hint names both keyboard ways back", DetailNav.help.contains("Esc") && DetailNav.help.contains("⌘["), DetailNav.help)

        // MARK: the sidebar
        checkTrue("Recordings in the sidebar shows the list while a recording is open",
                  DetailNav.onSidebarTap(tappedRecordings: true, hasOpenRecording: true) == .showRecordingsList)
        checkTrue("Recordings in the sidebar shows the list when none is open",
                  DetailNav.onSidebarTap(tappedRecordings: true, hasOpenRecording: false) == .showRecordingsList)
        checkTrue("Notes or Dictation in the sidebar just open that category, even with a recording open",
                  DetailNav.onSidebarTap(tappedRecordings: false, hasOpenRecording: true) == .openSection)
        checkTrue("another category with nothing open just opens it",
                  DetailNav.onSidebarTap(tappedRecordings: false, hasOpenRecording: false) == .openSection)

        // MARK: the Escape key
        checkTrue("Esc goes back from an open recording when nothing else wants it",
                  DetailNav.escapeReturnsToList(inRecordings: true, hasOpenRecording: true, searchHasText: false, editingText: false))
        checkTrue("Esc clears the search first, and does not leave the recording",
                  !DetailNav.escapeReturnsToList(inRecordings: true, hasOpenRecording: true, searchHasText: true, editingText: false))
        checkTrue("Esc does not leave a recording while a text field is being edited",
                  !DetailNav.escapeReturnsToList(inRecordings: true, hasOpenRecording: true, searchHasText: false, editingText: true))
        checkTrue("Esc does nothing in other categories",
                  !DetailNav.escapeReturnsToList(inRecordings: false, hasOpenRecording: true, searchHasText: false, editingText: false))
        checkTrue("Esc does nothing on the list",
                  !DetailNav.escapeReturnsToList(inRecordings: true, hasOpenRecording: false, searchHasText: false, editingText: false))

        print("\(checks) checks, \(failures) failed")
        if checks < 18 { print("VACUOUS: only \(checks) checks ran, need 18"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
