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
        checkTrue("the word at the end", same("Please review the plan bang", "Please review the plan", true), "\(p("Please review the plan bang"))")
        checkTrue("sentence punctuation before and after is tidied, the sentence end is kept",
                  same("Please review the plan. Bang.", "Please review the plan.", true))
        checkTrue("a comma before and an exclamation mark after are dropped",
                  same("Please review the plan, bang!", "Please review the plan", true))
        checkTrue("capital letters do not matter", same("Send it BANG", "Send it", true))
        checkTrue("a capital after a comma works", same("Great, Bang", "Great", true))
        checkTrue("a new line before the command is accepted", same("Send it\nbang\n", "Send it", true))
        checkTrue("a dangling comma left by the removal is dropped", same("Done, bang", "Done", true))
        checkTrue("a dangling dash left by the removal is dropped", same("Done — bang", "Done", true))
        checkTrue("a question mark that ends the sentence is kept", same("Ready? Bang", "Ready?", true))
        checkTrue("an ellipsis that ends the sentence is kept", same("Okay… bang…", "Okay…", true))
        checkTrue("only the last command is removed", same("Bang bang", "Bang", true))

        // MARK: saying only the command wakes the agent without typing
        checkTrue("only the word: nothing to type, still send", same("Bang", "", true))
        checkTrue("only the word with a full stop: nothing to type, still send", same("Bang.", "", true))
        checkTrue("only the word with an exclamation mark: nothing to type, still send", same("bang!", "", true))

        // MARK: things that must NOT trigger
        checkTrue("the word in the middle of a sentence is typed as spoken",
                  same("The door went bang in the night", "The door went bang in the night", false))
        checkTrue("a plural is a different word", same("Bangs are cut short", "Bangs are cut short", false))
        checkTrue("a longer word that starts with it is not the command", same("I flew to Bangkok", "I flew to Bangkok", false))
        checkTrue("a longer word that ends with it is not the command", same("Let us play gobang", "Let us play gobang", false))
        checkTrue("a typed exclamation mark alone never triggers", same("Great job!", "Great job!", false))
        checkTrue("the old words no longer trigger", same("Send it exclamation point", "Send it exclamation point", false))
        checkTrue("empty text sends nothing", same("", "", false))
        checkTrue("blank text sends nothing", same("  \n ", "", false))
        // A known quirk, written down on purpose: the word is common enough to end a real sentence.
        checkTrue("KNOWN QUIRK: a sentence that really ends in the word is taken as the command",
                  same("We opened with a bang", "We opened with a", true))

        // MARK: the setting
        checkTrue("off: the word is left in the text and nothing is sent",
                  SpokenSend.apply(enabled: false, to: "Send it bang") == SpokenSend.Result(text: "Send it bang", send: false))
        checkTrue("on: the command is applied",
                  SpokenSend.apply(enabled: true, to: "Send it bang") == SpokenSend.Result(text: "Send it", send: true))
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
        if checks < 30 { print("VACUOUS: only \(checks) checks ran, need 30"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
