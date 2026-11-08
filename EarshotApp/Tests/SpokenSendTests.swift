// Tests for SpokenSend (ADR-2611080900). Run: bash EarshotApp/Tests/run.sh
// Every expected value is written out by hand, not computed from the rules under test.
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

func suite() -> UserDefaults {
    let name = "SpokenSendTests-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@main struct SpokenSendTests {
    static func main() {
        func p(_ s: String) -> SpokenSend.Result { SpokenSend.parse(s) }
        func same(_ s: String, _ text: String, _ send: Bool) -> Bool { p(s) == SpokenSend.Result(text: text, send: send) }

        // MARK: the command at the end
        checkTrue("plain words at the end", same("Please review the plan exclamation point", "Please review the plan", true), "\(p("Please review the plan exclamation point"))")
        checkTrue("sentence punctuation before and after is tidied, the sentence end is kept",
                  same("Please review the plan. Exclamation point.", "Please review the plan.", true))
        checkTrue("a comma before and an exclamation mark after are dropped",
                  same("Please review the plan, exclamation point!", "Please review the plan", true))
        checkTrue("exclamation mark works as well", same("Send it exclamation mark", "Send it", true))
        checkTrue("capital letters do not matter", same("Great EXCLAMATION POINT", "Great", true))
        checkTrue("a hyphen between the words is accepted", same("Great, exclamation-point", "Great", true))
        checkTrue("extra spaces between the words are accepted", same("Great   exclamation   point", "Great", true))
        checkTrue("a new line before the command is accepted", same("Send it\nexclamation point\n", "Send it", true))
        checkTrue("a dangling comma left by the removal is dropped", same("Done, exclamation point", "Done", true))
        checkTrue("a dangling dash left by the removal is dropped", same("Done — exclamation point", "Done", true))
        checkTrue("a question mark that ends the sentence is kept", same("Ready? Exclamation point", "Ready?", true))
        checkTrue("an ellipsis that ends the sentence is kept", same("Okay… exclamation point…", "Okay…", true))
        checkTrue("only the last command is removed", same("What a day exclamation mark exclamation point", "What a day exclamation mark", true))

        // MARK: saying only the command wakes the agent without typing
        checkTrue("only the words: nothing to type, still send", same("Exclamation mark", "", true))
        checkTrue("only the words with a full stop: nothing to type, still send", same("Exclamation point.", "", true))

        // MARK: things that must NOT trigger
        checkTrue("the words in the middle of a sentence are typed as spoken",
                  same("Use an exclamation point in the title", "Use an exclamation point in the title", false))
        checkTrue("a plural is a different word", same("Exclamation points are fun", "Exclamation points are fun", false))
        checkTrue("a longer word that ends the same way is not the command", same("Nonexclamation point", "Nonexclamation point", false))
        checkTrue("a typed exclamation mark alone never triggers", same("Great job!", "Great job!", false))
        checkTrue("empty text sends nothing", same("", "", false))
        checkTrue("blank text sends nothing", same("  \n ", "", false))

        // MARK: the setting
        checkTrue("off: the words are left in the text and nothing is sent",
                  SpokenSend.apply(enabled: false, to: "Send it exclamation point") == SpokenSend.Result(text: "Send it exclamation point", send: false))
        checkTrue("on: the command is applied",
                  SpokenSend.apply(enabled: true, to: "Send it exclamation point") == SpokenSend.Result(text: "Send it", send: true))
        let d = suite()
        checkTrue("the setting is off by default", DictationPrefs.isSpokenSendEnabled(d) == false)
        d.set(true, forKey: DictationPrefs.spokenSend)
        checkTrue("it can be turned on", DictationPrefs.isSpokenSendEnabled(d) == true)
        d.set("yes", forKey: DictationPrefs.spokenSend)
        checkTrue("a wrongly typed saved value reads as off", DictationPrefs.isSpokenSendEnabled(d) == false)

        // MARK: the key
        checkTrue("the key is Return (key code 36)", SpokenSend.returnKeyCode == 36)
        checkTrue("the modifier is Control (flag 0x40000)", SpokenSend.controlFlagRaw == 0x40000)

        print("\(checks) checks, \(failures) failed")
        if checks < 28 { print("VACUOUS: only \(checks) checks ran, need 28"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
