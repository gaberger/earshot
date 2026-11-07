// Tests for DictationCleanup (ADR-2611071000). Run: bash EarshotApp/Tests/run.sh
// Every expected string is written out by hand, not computed from the rules under test.
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

func suite() -> UserDefaults {
    let name = "CleanupTests-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@main struct CleanupTests {
    static func main() {
        let raw = "um so i think we should uh meet at 3 30 on june 12 maybe"

        // MARK: a good cleanup is used
        checkTrue("a tidier text is used",
                  DictationCleanup.choose(original: raw, cleaned: "I think we should meet at 3 30 on June 12, maybe.")
                    == "I think we should meet at 3 30 on June 12, maybe.")
        checkTrue("surrounding whitespace from the model is trimmed",
                  DictationCleanup.choose(original: "hello world", cleaned: "  Hello, world.\n") == "Hello, world.")
        checkTrue("identical text is accepted",
                  DictationCleanup.choose(original: "Hello.", cleaned: "Hello.") == "Hello.")

        // MARK: no model answer means the original is typed
        checkTrue("no answer keeps the original", DictationCleanup.choose(original: raw, cleaned: nil) == raw)
        checkTrue("an empty answer keeps the original", DictationCleanup.choose(original: raw, cleaned: "") == raw)
        checkTrue("a blank answer keeps the original", DictationCleanup.choose(original: raw, cleaned: " \n ") == raw)

        // MARK: drift is refused
        let runaway = String(repeating: "Here is a much longer reply that nobody asked for. ", count: 6)
        checkTrue("a runaway-long answer keeps the original",
                  DictationCleanup.choose(original: "see you at 5", cleaned: runaway) == "see you at 5")
        checkTrue("a much shorter answer keeps the original",
                  DictationCleanup.choose(original: raw, cleaned: "Meet.") == raw)
        checkTrue("a dropped number keeps the original",
                  DictationCleanup.choose(original: "call me at 555 0100 tomorrow", cleaned: "Call me tomorrow, please.")
                    == "call me at 555 0100 tomorrow")
        checkTrue("a changed number keeps the original",
                  DictationCleanup.choose(original: "the total is 150 dollars", cleaned: "The total is 115 dollars.")
                    == "the total is 150 dollars")
        checkTrue("a number moved around is still the same number",
                  DictationCleanup.choose(original: "5 apples and 7 pears", cleaned: "7 pears and 5 apples.")
                    == "7 pears and 5 apples.")
        checkTrue("an answer that adds a number keeps the original",
                  DictationCleanup.choose(original: "see you soon", cleaned: "See you at 9 soon.") == "see you soon")

        // MARK: short and empty originals
        checkTrue("an empty original stays empty", DictationCleanup.choose(original: "", cleaned: "Hi.") == "")
        checkTrue("a one-word original may gain punctuation",
                  DictationCleanup.choose(original: "yes", cleaned: "Yes.") == "Yes.")

        // MARK: the preference
        let d = suite()
        checkTrue("cleanup is off by default", DictationPrefs.isCleanupEnabled(d) == false)
        d.set(true, forKey: DictationPrefs.cleanup)
        checkTrue("cleanup can be turned on", DictationPrefs.isCleanupEnabled(d) == true)
        d.set("yes", forKey: DictationPrefs.cleanup)
        checkTrue("a wrongly typed saved value reads as off", DictationPrefs.isCleanupEnabled(d) == false)

        // MARK: the instruction
        checkTrue("the instruction forbids adding content",
                  DictationCleanup.instructions.lowercased().contains("do not add"))
        checkTrue("the instruction names filler words",
                  DictationCleanup.instructions.lowercased().contains("filler"))

        print("\(checks) checks, \(failures) failed")
        if checks < 19 { print("VACUOUS: only \(checks) checks ran, need 19"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
