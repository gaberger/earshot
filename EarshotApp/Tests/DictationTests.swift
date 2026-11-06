// Tests for DictationSession. Run: bash EarshotApp/Tests/run.sh
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

func isNotice(_ a: [DictationSession.Action]) -> Bool {
    if case .notice = a.first { return true }
    return false
}

@main struct DictationTests {
    static func main() {
        // MARK: the happy path
        var s = DictationSession()
        checkTrue("starts idle", s.state == .idle)
        var a = s.handle(.keyDown(at: 0, meetingRecording: false))
        checkTrue("key down starts capture", a == [.startCapture] && s.state == .listening, "\(a) \(s.state)")
        a = s.handle(.keyDown(at: 0.1, meetingRecording: false))
        checkTrue("key repeat while listening does nothing", a.isEmpty && s.state == .listening)
        a = s.handle(.keyUp(at: 2))
        checkTrue("key up after a real hold stops capture", a == [.stopCapture] && s.state == .transcribing, "\(a) \(s.state)")
        a = s.handle(.keyDown(at: 2.1, meetingRecording: false))
        checkTrue("a new press while transcribing is ignored", a.isEmpty && s.state == .transcribing)
        a = s.handle(.transcript("  Hello there. ", secureInput: false))
        checkTrue("transcript is cleaned and inserted", a == [.insert("Hello there.")] && s.state == .inserting, "\(a)")
        a = s.handle(.inserted)
        checkTrue("inserted returns to idle", a.isEmpty && s.state == .idle)

        // MARK: a tap is not dictation
        s = DictationSession()
        _ = s.handle(.keyDown(at: 10, meetingRecording: false))
        a = s.handle(.keyUp(at: 10.1))
        checkTrue("a tap under the minimum hold discards the capture", a == [.discardCapture] && s.state == .idle, "\(a)")
        a = s.handle(.keyDown(at: 11, meetingRecording: false))
        checkTrue("and dictation works again right after", a == [.startCapture])

        // MARK: stray events
        s = DictationSession()
        a = s.handle(.keyUp(at: 1))
        checkTrue("key up while idle does nothing", a.isEmpty && s.state == .idle)
        a = s.handle(.transcript("surprise", secureInput: false))
        checkTrue("a transcript nobody asked for is dropped", a.isEmpty && s.state == .idle, "\(a)")
        a = s.handle(.inserted)
        checkTrue("an inserted event while idle does nothing", a.isEmpty && s.state == .idle)

        // MARK: never during a meeting recording
        s = DictationSession()
        a = s.handle(.keyDown(at: 0, meetingRecording: true))
        checkTrue("refuses while a meeting is being recorded, and says why", isNotice(a) && s.state == .idle, "\(a)")

        // MARK: the longest hold
        s = DictationSession()
        _ = s.handle(.keyDown(at: 0, meetingRecording: false))
        a = s.handle(.tick(at: 30))
        checkTrue("a tick inside the limit does nothing", a.isEmpty && s.state == .listening)
        a = s.handle(.tick(at: 61))
        checkTrue("a hold past the limit stops capture by itself", a == [.stopCapture] && s.state == .transcribing, "\(a)")
        a = s.handle(.keyUp(at: 70))
        checkTrue("the late key up is then harmless", a.isEmpty && s.state == .transcribing)
        _ = s.handle(.transcript("ok", secureInput: false))
        _ = s.handle(.inserted)
        checkTrue("and the session finishes cleanly", s.state == .idle)

        // MARK: nothing heard, secure fields, failures
        s = DictationSession()
        _ = s.handle(.keyDown(at: 0, meetingRecording: false)); _ = s.handle(.keyUp(at: 2))
        a = s.handle(.transcript("[BLANK_AUDIO]", secureInput: false))
        checkTrue("silence says so and inserts nothing", isNotice(a) && s.state == .idle, "\(a)")

        s = DictationSession()
        _ = s.handle(.keyDown(at: 0, meetingRecording: false)); _ = s.handle(.keyUp(at: 2))
        a = s.handle(.transcript("hunter2", secureInput: true))
        checkTrue("never inserts into a secure field", isNotice(a) && !a.contains(.insert("hunter2")) && s.state == .idle, "\(a)")

        s = DictationSession()
        _ = s.handle(.keyDown(at: 0, meetingRecording: false)); _ = s.handle(.keyUp(at: 2))
        a = s.handle(.transcript(nil, secureInput: false))
        checkTrue("a failed transcription says so and recovers", isNotice(a) && s.state == .idle, "\(a)")

        s = DictationSession()
        _ = s.handle(.keyDown(at: 0, meetingRecording: false))
        a = s.handle(.failed)
        checkTrue("a capture failure while listening resets to idle", s.state == .idle && isNotice(a), "\(a) \(s.state)")
        a = s.handle(.keyDown(at: 5, meetingRecording: false))
        checkTrue("and dictation works again afterwards", a == [.startCapture])

        // MARK: cleaning whisper's output for a form field
        let c = DictationSession.clean
        checkTrue("trims", c("  hi  ") == "hi")
        checkTrue("joins lines into one (a form field is one line)", c("one\ntwo\n\nthree") == "one two three", c("one\ntwo\n\nthree"))
        checkTrue("drops whisper's bracketed tags", c("[BLANK_AUDIO]") == "" && c("hello [Music] world") == "hello world", c("hello [Music] world"))
        checkTrue("drops a lone parenthetical sound note", c("(upbeat music)") == "" && c("*applause*") == "")
        checkTrue("keeps a parenthetical that is part of speech", c("send it (the red one) today") == "send it (the red one) today")
        checkTrue("collapses runs of spaces", c("a    b") == "a b")
        checkTrue("empty stays empty", c("") == "" && c("   \n ") == "")
        checkTrue("keeps non-English text intact", c("¿Dónde está la biblioteca?") == "¿Dónde está la biblioteca?")

        print("\(checks) checks, \(failures) failed")
        if checks < 24 { print("VACUOUS: only \(checks) checks ran, need 24"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
