// Tests for SearchIndex, the logic behind the ⌘K search. Run: bash EarshotApp/Tests/run.sh
// Expected results are written out by hand, not computed with the rules under test.
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

func doc(_ id: String, _ title: String, _ text: String) -> SearchDoc { SearchDoc(id: id, title: title, text: text) }
func ids(_ hits: [SearchHit]) -> [String] {
    hits.map { if case .recording(let id, _, _) = $0 { return "r:" + id } else if case .destination(let id, _, _) = $0 { return "d:" + id } else if case .note(let id, _, _) = $0 { return "n:" + id } else { return "?" } }
}
func snippet(_ hit: SearchHit) -> String { if case .recording(_, _, let s) = hit { return s } else { return "" } }

@main struct SearchTests {
    static func main() {
        let a = doc("a", "Weekly sync", "We talked about the roadmap and the launch date.")
        let b = doc("b", "Call with Priya", "Priya said the roadmap slips. Weekly numbers are fine.")
        let c = doc("c", "Roadmap review", "Nothing about dates.")
        let docs = [a, b, c]

        // MARK: matching and order
        checkTrue("a title match comes before body matches, input order kept inside each group",
                  ids(SearchIndex.search("roadmap", recordings: docs, destinations: [])) == ["r:c", "r:a", "r:b"],
                  "\(ids(SearchIndex.search("roadmap", recordings: docs, destinations: [])))")
        checkTrue("every word must match", ids(SearchIndex.search("weekly sync", recordings: docs, destinations: [])) == ["r:a"])
        checkTrue("words may match in the title and the body", ids(SearchIndex.search("priya numbers", recordings: docs, destinations: [])) == ["r:b"])
        checkTrue("case does not matter", ids(SearchIndex.search("ROADMAP", recordings: docs, destinations: [])) == ["r:c", "r:a", "r:b"])
        checkTrue("accents do not matter", ids(SearchIndex.search("cafe", recordings: [doc("x", "Lunch", "We met at the café.")], destinations: [])) == ["r:x"])
        checkTrue("an empty query finds nothing", SearchIndex.search("", recordings: docs, destinations: []).isEmpty)
        checkTrue("a blank query finds nothing", SearchIndex.search("   \n", recordings: docs, destinations: []).isEmpty)
        checkTrue("no match finds nothing", SearchIndex.search("zebra", recordings: docs, destinations: []).isEmpty)
        checkTrue("surrounding spaces are ignored", ids(SearchIndex.search("  launch  ", recordings: docs, destinations: [])) == ["r:a"])

        // MARK: the limit
        let many = (1...10).map { doc("m\($0)", "Meeting \($0)", "agenda") }
        checkTrue("recordings are limited", SearchIndex.search("agenda", recordings: many, destinations: [], limit: 3).count == 3)
        checkTrue("the default limit is eight", SearchIndex.search("agenda", recordings: many, destinations: []).count == 8)

        // MARK: snippets
        let long = String(repeating: "x", count: 100) + " launch " + String(repeating: "y", count: 100)
        let hit = SearchIndex.search("launch", recordings: [doc("l", "Plan", long)], destinations: [])
        checkTrue("a long text is cut around the match with ellipses",
                  hit.count == 1 && snippet(hit[0]).contains("launch") && snippet(hit[0]).hasPrefix("…") && snippet(hit[0]).hasSuffix("…"),
                  hit.isEmpty ? "no hit" : snippet(hit[0]))
        checkTrue("the cut is short", hit.count == 1 && snippet(hit[0]).count <= 100, hit.isEmpty ? "" : "\(snippet(hit[0]).count)")
        let short = SearchIndex.search("dates", recordings: [c], destinations: [])
        checkTrue("a short text is returned whole, no ellipsis", snippet(short[0]) == "Nothing about dates.", snippet(short[0]))
        let spaced = SearchIndex.search("roadmap", recordings: [doc("s", "T", "line one\n\nthe   roadmap\nends")], destinations: [])
        checkTrue("line breaks and runs of spaces are collapsed", snippet(spaced[0]) == "line one the roadmap ends", snippet(spaced[0]))

        // MARK: pages and settings
        let shortcut = SearchDestination(id: "shortcut", title: "Shortcut", detail: "Change the dictation shortcut", keywords: ["hotkey", "keys"])
        let mic = SearchDestination(id: "mic", title: "Microphone", detail: "Choose what Earshot records from", keywords: ["input"])
        let dests = [shortcut, mic]
        checkTrue("a keyword finds a setting", ids(SearchIndex.search("hotkey", recordings: [], destinations: dests)) == ["d:shortcut"])
        checkTrue("a word in the description finds a setting", ids(SearchIndex.search("records", recordings: [], destinations: dests)) == ["d:mic"])
        let talk = doc("t", "Standup", "we should change the shortcut")
        checkTrue("settings come before recordings",
                  ids(SearchIndex.search("shortcut", recordings: [talk], destinations: dests)) == ["d:shortcut", "r:t"],
                  "\(ids(SearchIndex.search("shortcut", recordings: [talk], destinations: dests)))")
        let five = (1...6).map { SearchDestination(id: "p\($0)", title: "Page \($0)", detail: "", keywords: ["page"]) }
        checkTrue("settings are limited to four", SearchIndex.search("page", recordings: [], destinations: five).count == 4)


        // MARK: notes (voice notes recorded in Earshot) are searched too
        let n1 = doc("n1", "Remind me to check the build", "Remind me to check the build before the standup and ask about the roadmap.")
        let n2 = doc("n2", "Garage idea", "Turn the garage into a workshop.")
        checkTrue("a note is found by a word in its text", ids(SearchIndex.search("standup", recordings: docs, destinations: [], notes: [n1, n2])) == ["n:n1"],
                  "\(ids(SearchIndex.search("standup", recordings: docs, destinations: [], notes: [n1, n2])))")
        checkTrue("settings first, then notes, then recordings",
                  ids(SearchIndex.search("roadmap", recordings: [a], destinations: [SearchDestination(id: "d", title: "Roadmap settings", detail: "", keywords: [])], notes: [n1]))
                  == ["d:d", "n:n1", "r:a"],
                  "\(ids(SearchIndex.search("roadmap", recordings: [a], destinations: [SearchDestination(id: "d", title: "Roadmap settings", detail: "", keywords: [])], notes: [n1])))")
        let sixNotes = (1...6).map { doc("m\($0)", "Meeting note \($0)", "agenda") }
        checkTrue("notes are limited to four", SearchIndex.search("agenda", recordings: [], destinations: [], notes: sixNotes).count == 4)
        let longNote = doc("ln", "Long", String(repeating: "x", count: 100) + " launch " + String(repeating: "y", count: 100))
        let noteHit = SearchIndex.search("launch", recordings: [], destinations: [], notes: [longNote])
        checkTrue("a note snippet is cut around the match like a recording's",
                  noteHit.count == 1 && { if case .note(_, _, let s) = noteHit[0] { return s.contains("launch") && s.hasPrefix("…") && s.count <= 100 } else { return false } }())
        checkTrue("an empty query finds no notes either", SearchIndex.search("", recordings: [], destinations: [], notes: [n1]).isEmpty)

        print("\(checks) checks, \(failures) failed")
        if checks < 24 { print("VACUOUS: only \(checks) checks ran, need 24"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
