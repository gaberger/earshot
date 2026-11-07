// Tests for NoteSession, the rules of recording a note inside Earshot (ADR-2611062250 amendment).
// Run: bash EarshotApp/Tests/run.sh
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}
func isNotice(_ a: [NoteSession.Action]) -> Bool { if case .notice = a.first { return true }; return false }

@main struct NoteSessionTests {
    static func main() {
        // MARK: the happy path
        var s = NoteSession()
        checkTrue("starts idle", s.state == .idle)
        var a = s.handle(.start(at: 0, meetingRecording: false, dictationBusy: false))
        checkTrue("start begins capture", a == [.startCapture] && s.state == .recording, "\(a) \(s.state)")
        a = s.handle(.start(at: 0.5, meetingRecording: false, dictationBusy: false))
        checkTrue("a second start while recording is ignored", a.isEmpty && s.state == .recording)
        a = s.handle(.stop(at: 5))
        checkTrue("stop after a real note stops capture and waits for the transcript", a == [.stopCapture] && s.state == .transcribing, "\(a) \(s.state)")
        a = s.handle(.start(at: 6, meetingRecording: false, dictationBusy: false))
        checkTrue("a start while transcribing is ignored", a.isEmpty && s.state == .transcribing)
        a = s.handle(.transcript("  Buy milk,\n and eggs.  "))
        checkTrue("the transcript is cleaned and saved", a == [.save("Buy milk, and eggs.")] && s.state == .idle, "\(a) \(s.state)")

        // MARK: refused starts
        s = NoteSession()
        a = s.handle(.start(at: 0, meetingRecording: true, dictationBusy: false))
        checkTrue("no note while a meeting is being recorded", isNotice(a) && s.state == .idle, "\(a)")
        a = s.handle(.start(at: 0, meetingRecording: false, dictationBusy: true))
        checkTrue("no note while a dictation is in progress", isNotice(a) && s.state == .idle, "\(a)")

        // MARK: too short
        s = NoteSession()
        _ = s.handle(.start(at: 10, meetingRecording: false, dictationBusy: false))
        a = s.handle(.stop(at: 10.4))
        checkTrue("under one second is thrown away", a == [.discardCapture] && s.state == .idle, "\(a) \(s.state)")
        a = s.handle(.start(at: 12, meetingRecording: false, dictationBusy: false))
        checkTrue("and recording works again right after", a == [.startCapture])

        // MARK: the time limit
        s = NoteSession()
        _ = s.handle(.start(at: 0, meetingRecording: false, dictationBusy: false))
        a = s.handle(.tick(at: 599))
        checkTrue("before ten minutes a tick does nothing", a.isEmpty && s.state == .recording)
        a = s.handle(.tick(at: 600))
        checkTrue("at ten minutes it stops by itself", a == [.stopCapture] && s.state == .transcribing, "\(a)")

        // MARK: nothing worth saving
        s = NoteSession()
        _ = s.handle(.start(at: 0, meetingRecording: false, dictationBusy: false)); _ = s.handle(.stop(at: 3))
        a = s.handle(.transcript(nil))
        checkTrue("a failed transcription saves nothing and says so", isNotice(a) && s.state == .idle, "\(a)")
        s = NoteSession()
        _ = s.handle(.start(at: 0, meetingRecording: false, dictationBusy: false)); _ = s.handle(.stop(at: 3))
        a = s.handle(.transcript("[BLANK_AUDIO]"))
        checkTrue("a transcript of only tags saves nothing and says so", isNotice(a) && s.state == .idle, "\(a)")
        s = NoteSession()
        _ = s.handle(.start(at: 0, meetingRecording: false, dictationBusy: false))
        a = s.handle(.failed)
        checkTrue("a capture failure returns to idle with a notice", isNotice(a) && s.state == .idle, "\(a)")
        a = s.handle(.transcript("stray"))
        checkTrue("a transcript nobody asked for is ignored", a.isEmpty && s.state == .idle)
        a = s.handle(.stop(at: 99))
        checkTrue("a stop while idle is ignored", a.isEmpty && s.state == .idle)

        print("\(checks) checks, \(failures) failed")
        if checks < 17 { print("VACUOUS: only \(checks) checks ran, need 17"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
