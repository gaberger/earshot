// Tests for SpeechStop (ADR-2611071600, amendment: the hotkey stops the talk-back).
// Run: bash EarshotApp/Tests/run.sh. Every expected answer is written out by hand.
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

@main struct SpeechStopTests {
    static func main() {
        let script = "/Users/me/Applications/Earshot.app/Contents/Resources/earshot-speak"

        checkTrue("speech playing and a script known: run the system python on the script with stop",
                  SpeechStop.command(pidFileExists: true, scriptPath: script)
                    == ["/usr/bin/python3", script, "stop"])
        checkTrue("no pid file means nothing is speaking: run nothing",
                  SpeechStop.command(pidFileExists: false, scriptPath: script) == nil)
        checkTrue("no script path: run nothing", SpeechStop.command(pidFileExists: true, scriptPath: "") == nil)
        checkTrue("a blank script path: run nothing", SpeechStop.command(pidFileExists: true, scriptPath: "  \n") == nil)
        checkTrue("neither: run nothing", SpeechStop.command(pidFileExists: false, scriptPath: "") == nil)
        checkTrue("a path with spaces stays one argument",
                  SpeechStop.command(pidFileExists: true, scriptPath: "/Users/a b/Earshot.app/earshot-speak")?[1]
                    == "/Users/a b/Earshot.app/earshot-speak")
        checkTrue("the command is exactly three words: python, script, stop",
                  SpeechStop.command(pidFileExists: true, scriptPath: script)?.count == 3)

        print("\(checks) checks, \(failures) failed")
        if checks < 7 { print("VACUOUS: only \(checks) checks ran, need 7"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
