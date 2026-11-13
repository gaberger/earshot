// Tests for RecordingEnd (ADR-2611101015): a capture that ends by itself is reported, not swallowed.
// Run: bash EarshotApp/Tests/run.sh
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

// The shapes AVFoundation actually produced, copied from ~/Library/Logs/Earshot.log on 2026-11-10.
func avError(_ code: Int, finished: Bool?, _ text: String) -> NSError {
    var info: [String: Any] = [NSLocalizedDescriptionKey: text]
    if let finished { info["AVErrorRecordingSuccessfullyFinishedKey"] = finished }
    return NSError(domain: "AVFoundationErrorDomain", code: code, userInfo: info)
}
let diskFullFinished = avError(-11807, finished: true, "Disk Full")
let diskFullBroken = avError(-11807, finished: false, "Disk Full")
let normalStopFlag = avError(-11818, finished: true, "Recording Stopped")
let deviceGone = avError(-11819, finished: false, "Cannot Complete Action")

func isEndedByItself(_ e: RecordingEnd) -> Bool { if case .endedByItself = e { return true }; return false }
func isFailed(_ e: RecordingEnd) -> Bool { if case .failed = e { return true }; return false }
func message(_ e: RecordingEnd) -> String? {
    switch e {
    case .stopped: return nil
    case .failed(let m), .endedByItself(let m): return m
    }
}

@main struct RecordingEndTests {
    static func main() {
        // Asked to stop.
        checkTrue("asked, no error: stopped", RecordingEnd.classify(stopRequested: true, error: nil) == .stopped)
        checkTrue("asked, error flagged finished: stopped",
                  RecordingEnd.classify(stopRequested: true, error: normalStopFlag) == .stopped)
        checkTrue("asked, error not flagged finished: failed",
                  isFailed(RecordingEnd.classify(stopRequested: true, error: deviceGone)))
        checkTrue("asked, disk full and broken: failed, mentions the disk",
                  message(RecordingEnd.classify(stopRequested: true, error: diskFullBroken))?.contains("disk") == true)

        // Not asked: this is the 2026-11-10 incident.
        let incident = RecordingEnd.classify(stopRequested: false, error: diskFullFinished)
        checkTrue("not asked, disk full flagged finished: ended by itself", isEndedByItself(incident), "\(incident)")
        checkTrue("disk full message says the disk is full", message(incident)?.contains("disk is full") == true,
                  message(incident) ?? "nil")
        checkTrue("disk full message says the audio is kept", message(incident)?.contains("kept") == true,
                  message(incident) ?? "nil")
        checkTrue("not asked, disk full broken: ended by itself, disk message",
                  isEndedByItself(RecordingEnd.classify(stopRequested: false, error: diskFullBroken))
                  && message(RecordingEnd.classify(stopRequested: false, error: diskFullBroken))?.contains("disk is full") == true)
        checkTrue("not asked, no error: ended by itself",
                  isEndedByItself(RecordingEnd.classify(stopRequested: false, error: nil)))
        checkTrue("not asked, flagged finished, not disk: ended by itself",
                  isEndedByItself(RecordingEnd.classify(stopRequested: false, error: normalStopFlag)))
        let other = RecordingEnd.classify(stopRequested: false, error: deviceGone)
        checkTrue("not asked, other error: ended by itself with its description",
                  isEndedByItself(other) && message(other)?.contains("Cannot Complete Action") == true, "\(other)")
        checkTrue("disk full is recognised only in the AVFoundation domain",
                  message(RecordingEnd.classify(stopRequested: false,
                                                error: NSError(domain: "Other", code: -11807)))?.contains("disk is full") == false)

        if checks < 12 { print("VACUOUS: only \(checks) checks ran, need 12"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
