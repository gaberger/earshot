// Tests for PasteGuard (ADR-2611071800): paste only into the window dictation started in.
// Run: bash EarshotApp/Tests/run.sh
import Foundation
import CoreGraphics

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

func t(_ pid: Int32, _ x: CGFloat = 100, _ y: CGFloat = 200, _ w: CGFloat = 800, _ h: CGFloat = 600) -> PasteTarget {
    PasteTarget(pid: pid, frame: CGRect(x: x, y: y, width: w, height: h))
}

@main struct PasteGuardTests {
    static func main() {
        checkTrue("same app, same window: paste", PasteGuard.decide(target: t(1), current: t(1)) == .paste)
        checkTrue("same app, window nudged 5 pt: paste", PasteGuard.decide(target: t(1), current: t(1, 105, 197)) == .paste)
        checkTrue("same app, window moved 9 pt: hold", PasteGuard.decide(target: t(1), current: t(1, 109)) == .hold)
        checkTrue("exactly at the tolerance: paste", PasteGuard.decide(target: t(1), current: t(1, 108)) == .paste)
        checkTrue("same app, different size: hold", PasteGuard.decide(target: t(1), current: t(1, 100, 200, 780, 600)) == .hold)
        checkTrue("same app, another window far away: hold", PasteGuard.decide(target: t(1), current: t(1, 1500, 40, 600, 500)) == .hold)
        checkTrue("a different app with an identical frame: hold", PasteGuard.decide(target: t(1), current: t(2)) == .hold)
        checkTrue("a different app with no frames read: hold",
                  PasteGuard.decide(target: PasteTarget(pid: 1, frame: nil), current: PasteTarget(pid: 2, frame: nil)) == .hold)

        checkTrue("no target remembered: paste as before", PasteGuard.decide(target: nil, current: t(2)) == .paste)
        checkTrue("the current window cannot be read: paste as before", PasteGuard.decide(target: t(1), current: nil) == .paste)
        checkTrue("same app but the target had no frame: paste",
                  PasteGuard.decide(target: PasteTarget(pid: 1, frame: nil), current: t(1)) == .paste)
        checkTrue("same app but the current window has no frame: paste",
                  PasteGuard.decide(target: t(1), current: PasteTarget(pid: 1, frame: nil)) == .paste)

        checkTrue("tolerance 0: identical pastes, 1 pt off holds",
                  PasteGuard.decide(target: t(1), current: t(1), tolerance: 0) == .paste
                  && PasteGuard.decide(target: t(1), current: t(1, 101), tolerance: 0) == .hold)
        checkTrue("a window on a second display (negative x) compares the same way",
                  PasteGuard.decide(target: t(1, -1500, 100), current: t(1, -1500, 100)) == .paste
                  && PasteGuard.decide(target: t(1, -1500, 100), current: t(1, 100, 100)) == .hold)

        print("\(checks) checks, \(failures) failed")
        if checks < 14 { print("VACUOUS: only \(checks) checks ran, need 14"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
