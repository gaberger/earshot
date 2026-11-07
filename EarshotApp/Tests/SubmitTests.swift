// Tests for DictationSubmit (ADR-2611071500). Run: bash EarshotApp/Tests/run.sh
// Every expected answer is written out by hand, not computed from the rule under test.
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

func suite() -> UserDefaults {
    let name = "SubmitTests-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@main struct SubmitTests {
    static func main() {
        func send(enabled: Bool = true, text: String = "hello there", pasted: Bool = true, secure: Bool = false) -> Bool {
            DictationSubmit.shouldSendReturn(enabled: enabled, text: text, pasted: pasted, secureInput: secure)
        }

        // MARK: the decision
        checkTrue("on, with typed text, sends Return", send() == true)
        checkTrue("off never sends Return", send(enabled: false) == false)
        checkTrue("empty text sends nothing", send(text: "") == false)
        checkTrue("whitespace-only text sends nothing", send(text: " \n\t ") == false)
        checkTrue("text left on the clipboard (not typed) sends nothing", send(pasted: false) == false)
        checkTrue("secure input sends nothing", send(secure: true) == false)
        checkTrue("a single character is enough", send(text: "k") == true)
        checkTrue("text with surrounding spaces still counts", send(text: "  yes  ") == true)
        checkTrue("off wins over everything else",
                  send(enabled: false, text: "x", pasted: true, secure: false) == false)
        checkTrue("every blocker together still sends nothing",
                  send(enabled: true, text: "", pasted: false, secure: true) == false)

        // MARK: the preference
        let d = suite()
        checkTrue("Return after typing is off by default", DictationPrefs.isSendReturnEnabled(d) == false)
        d.set(true, forKey: DictationPrefs.sendReturn)
        checkTrue("it can be turned on", DictationPrefs.isSendReturnEnabled(d) == true)
        d.set(false, forKey: DictationPrefs.sendReturn)
        checkTrue("it can be turned off again", DictationPrefs.isSendReturnEnabled(d) == false)
        d.set("yes", forKey: DictationPrefs.sendReturn)
        checkTrue("a wrongly typed saved value reads as off", DictationPrefs.isSendReturnEnabled(d) == false)
        d.set(1, forKey: DictationPrefs.sendReturn)
        checkTrue("a number is not a Bool and reads as off", DictationPrefs.isSendReturnEnabled(d) == false)

        print("\(checks) checks, \(failures) failed")
        if checks < 15 { print("VACUOUS: only \(checks) checks ran, need 15"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
