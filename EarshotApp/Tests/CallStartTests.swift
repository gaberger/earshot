// Tests for CallStartDetector. Run: bash EarshotApp/Tests/run.sh
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

/// Feeds one sample a second and remembers the times of offers.
struct Sim {
    var d = CallStartDetector()
    var t = 0.0
    var offers: [Double] = []
    var recording = false
    mutating func feed(_ seconds: Int, _ capturing: Bool?) {
        for _ in 0..<seconds {
            t += 1
            if d.ingest(capturing: capturing, recording: recording, at: t) == .offer { offers.append(t) }
        }
    }
}

@main struct CallStartTests {
    static func main() {
        do {
            var s = Sim()
            s.feed(9, true)
            checkTrue("no offer before 10 s of capture", s.offers.isEmpty)
            s.feed(2, true)
            checkTrue("offers once capture has lasted 10 s", s.offers.count == 1 && s.offers[0] >= 10 && s.offers[0] <= 11, "\(s.offers)")
            s.feed(600, true)
            checkTrue("only one offer for the whole call", s.offers.count == 1, "\(s.offers)")
        }
        do {
            var s = Sim()
            s.feed(5, true); s.feed(60, false)
            checkTrue("a 5 s capture (Siri) never offers", s.offers.isEmpty)
        }
        do {
            var s = Sim()
            s.recording = true
            s.feed(120, true)
            checkTrue("no offer while Earshot is recording", s.offers.isEmpty)
            s.recording = false
            s.feed(120, true)
            checkTrue("no offer when a recording stops mid-call", s.offers.isEmpty, "\(s.offers)")
        }
        do {
            var s = Sim()
            s.feed(30, true); s.feed(14, false); s.feed(30, true)
            checkTrue("a 14 s break mid-call does not offer again", s.offers.count == 1, "\(s.offers)")
            s.feed(20, false); s.feed(30, true)
            checkTrue("20 s of quiet re-arms: the next call is offered", s.offers.count == 2, "\(s.offers)")
        }
        do {
            var s = Sim()
            s.feed(5, true); s.feed(1, false); s.feed(5, true)
            checkTrue("a blip resets the capture streak", s.offers.isEmpty)
            s.feed(6, true)
            checkTrue("and the offer comes after 10 s of unbroken capture", s.offers.count == 1, "\(s.offers)")
        }
        do {
            var s = Sim()
            s.feed(8, true); s.feed(600, nil)
            checkTrue("an unknown probe never offers", s.offers.isEmpty)
            var u = Sim()
            u.feed(30, true); u.feed(60, nil); u.feed(30, true)
            checkTrue("an unknown probe does not re-arm the episode", u.offers.count == 1, "\(u.offers)")
        }
        do {
            var s = Sim()
            s.feed(8, true)
            s.t += 300  // the Mac slept
            s.feed(5, true)
            checkTrue("a sample gap restarts the capture streak", s.offers.isEmpty, "\(s.offers)")
            s.feed(8, true)
            checkTrue("and an unbroken 10 s afterwards offers", s.offers.count == 1, "\(s.offers)")
        }
        checkTrue("at least 10 checks ran", checks >= 10, "\(checks)")
        print(failures == 0 ? "All call-start tests passed (\(checks) checks)" : "\(failures) call-start test(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
