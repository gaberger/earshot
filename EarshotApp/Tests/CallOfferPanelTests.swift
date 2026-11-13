// Tests for CallOfferPanelRule (ADR-2611130933). Run: bash EarshotApp/Tests/run.sh
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

/// Shows the panel at t = 0, then feeds one sample a second until the rule dismisses it.
struct Sim {
    var rule = CallOfferPanelRule(shownAt: 0)
    var t = 0.0
    var dismissedAt: Double?
    var reason: CallOfferPanelRule.Dismissal?
    mutating func feed(_ seconds: Int, capturing: Bool?, recording: Bool = false) {
        for _ in 0..<seconds where dismissedAt == nil {
            t += 1
            if let r = rule.ingest(capturing: capturing, recording: recording, at: t) {
                dismissedAt = t; reason = r
            }
        }
    }
}

@main struct CallOfferPanelTests {
    static func main() {
        do {
            let text = CallOfferPanelRule.text(appName: "Zoom")
            checkTrue("title names the app", text.title == "Zoom is using the microphone", text.title)
            checkTrue("body asks to record", text.body == "Record this meeting?", text.body)
            checkTrue("ignore button names the app", text.ignore == "Not for Zoom", text.ignore)
        }
        do {
            var s = Sim()
            s.feed(100, capturing: true)
            checkTrue("stays while the call goes on (100 s)", s.dismissedAt == nil, "\(String(describing: s.dismissedAt))")
            s.feed(30, capturing: true)
            checkTrue("goes at the 120 s timeout", s.dismissedAt == 120 && s.reason == .timedOut,
                      "\(String(describing: s.dismissedAt)) \(String(describing: s.reason))")
        }
        do {
            var s = Sim()
            s.feed(20, capturing: true)
            s.feed(14, capturing: false)
            checkTrue("not dismissed after 14 s of quiet", s.dismissedAt == nil)
            s.feed(5, capturing: false)
            checkTrue("dismissed after 15 s of quiet", s.dismissedAt == 35 && s.reason == .callEnded,
                      "\(String(describing: s.dismissedAt)) \(String(describing: s.reason))")
        }
        do {
            var s = Sim()
            s.feed(10, capturing: true)
            s.feed(5, capturing: false)
            s.feed(20, capturing: true)
            checkTrue("a 5 s break does not dismiss", s.dismissedAt == nil)
        }
        do {
            var s = Sim()
            s.feed(5, capturing: true)
            s.feed(1, capturing: true, recording: true)
            checkTrue("recording dismisses at once", s.dismissedAt == 6 && s.reason == .recordingStarted,
                      "\(String(describing: s.dismissedAt)) \(String(describing: s.reason))")
        }
        do {
            var s = Sim()
            s.feed(10, capturing: false)
            s.feed(40, capturing: nil)
            checkTrue("nil samples do not count as quiet", s.dismissedAt == nil, "\(String(describing: s.dismissedAt))")
            s.feed(100, capturing: nil)
            checkTrue("the timeout still applies under nil", s.dismissedAt == 120 && s.reason == .timedOut,
                      "\(String(describing: s.dismissedAt))")
        }

        if checks < 10 { print("VACUOUS: only \(checks) checks ran"); exit(1) }
        print("\(checks - failures)/\(checks) passed")
        exit(failures == 0 ? 0 : 1)
    }
}
