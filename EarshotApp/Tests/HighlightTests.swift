// Tests for WindowHighlight (ADR-2611071400). Run: bash EarshotApp/Tests/run.sh
// Every expected rectangle is written out by hand, not computed from the rules under test.
// Coordinates: Accessibility is top-left origin, y down; AppKit is bottom-left origin, y up.
import CoreGraphics
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

func suite() -> UserDefaults {
    let name = "HighlightTests-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@main struct HighlightTests {
    static func main() {
        // MARK: Accessibility frame to AppKit frame
        checkTrue("a window in the middle of a 1000 pt tall screen flips to y=350",
                  WindowHighlight.appKitFrame(fromAX: CGRect(x: 100, y: 50, width: 800, height: 600), primaryHeight: 1000)
                    == CGRect(x: 100, y: 350, width: 800, height: 600))
        checkTrue("a window at the very top of the screen sits at the top in AppKit",
                  WindowHighlight.appKitFrame(fromAX: CGRect(x: 0, y: 0, width: 500, height: 300), primaryHeight: 900)
                    == CGRect(x: 0, y: 600, width: 500, height: 300))
        checkTrue("a window on a display above the primary has a negative AX y and a y above the primary in AppKit",
                  WindowHighlight.appKitFrame(fromAX: CGRect(x: 100, y: -500, width: 600, height: 400), primaryHeight: 900)
                    == CGRect(x: 100, y: 1000, width: 600, height: 400))
        checkTrue("x and the size never change in the flip",
                  WindowHighlight.appKitFrame(fromAX: CGRect(x: -1200, y: 10, width: 640, height: 480), primaryHeight: 800)
                    == CGRect(x: -1200, y: 310, width: 640, height: 480))

        // MARK: the outline rectangle
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        checkTrue("the outline is the window grown by 4 pt on every side",
                  WindowHighlight.rect(forWindow: CGRect(x: 100, y: 100, width: 600, height: 400), screens: [primary])
                    == CGRect(x: 96, y: 96, width: 608, height: 408))
        checkTrue("a window on a second display to the right is outlined there",
                  WindowHighlight.rect(forWindow: CGRect(x: 1500, y: 400, width: 600, height: 400), screens: [primary, right])
                    == CGRect(x: 1496, y: 396, width: 608, height: 408))
        checkTrue("a window hanging off the screen is clamped to it",
                  WindowHighlight.rect(forWindow: CGRect(x: -100, y: 100, width: 1640, height: 700), screens: [primary])
                    == CGRect(x: 0, y: 96, width: 1440, height: 708))
        checkTrue("a window straddling two displays is clamped to the one holding most of it",
                  WindowHighlight.rect(forWindow: CGRect(x: 1300, y: 100, width: 600, height: 400), screens: [primary, right])
                    == CGRect(x: 1440, y: 96, width: 460 + 4, height: 408),
                  "\(String(describing: WindowHighlight.rect(forWindow: CGRect(x: 1300, y: 100, width: 600, height: 400), screens: [primary, right])))")
        checkTrue("a window under 40 pt wide gets no outline",
                  WindowHighlight.rect(forWindow: CGRect(x: 100, y: 100, width: 39, height: 400), screens: [primary]) == nil)
        checkTrue("a window under 40 pt tall gets no outline",
                  WindowHighlight.rect(forWindow: CGRect(x: 100, y: 100, width: 400, height: 39), screens: [primary]) == nil)
        checkTrue("a window exactly 40 pt each way is outlined",
                  WindowHighlight.rect(forWindow: CGRect(x: 100, y: 100, width: 40, height: 40), screens: [primary]) != nil)
        checkTrue("a window on no screen gets no outline",
                  WindowHighlight.rect(forWindow: CGRect(x: 5000, y: 5000, width: 300, height: 300), screens: [primary, right]) == nil)
        checkTrue("no screens means no outline",
                  WindowHighlight.rect(forWindow: CGRect(x: 100, y: 100, width: 300, height: 300), screens: []) == nil)
        checkTrue("a window with a NaN origin gets no outline",
                  WindowHighlight.rect(forWindow: CGRect(x: CGFloat.nan, y: 100, width: 300, height: 300), screens: [primary]) == nil)

        // MARK: which states show it
        typealias S = DictationSession.State
        checkTrue("listening shows the outline", WindowHighlight.isActive(S.listening))
        checkTrue("transcribing shows the outline", WindowHighlight.isActive(S.transcribing))
        checkTrue("inserting hides it (the text is arriving)", !WindowHighlight.isActive(S.inserting))
        checkTrue("idle hides it", !WindowHighlight.isActive(S.idle))

        // MARK: which look (flames, embers, a static border, or nothing)
        checkTrue("listening burns with flames", WindowHighlight.style(for: S.listening, reduceMotion: false) == .flames)
        checkTrue("transcribing burns low, as embers", WindowHighlight.style(for: S.transcribing, reduceMotion: false) == .embers)
        checkTrue("reduce motion makes listening a static border", WindowHighlight.style(for: S.listening, reduceMotion: true) == .border)
        checkTrue("reduce motion makes transcribing a static border", WindowHighlight.style(for: S.transcribing, reduceMotion: true) == .border)
        checkTrue("idle has no look, with or without reduce motion",
                  WindowHighlight.style(for: S.idle, reduceMotion: false) == .none
                    && WindowHighlight.style(for: S.idle, reduceMotion: true) == .none)
        checkTrue("inserting has no look, with or without reduce motion",
                  WindowHighlight.style(for: S.inserting, reduceMotion: false) == .none
                    && WindowHighlight.style(for: S.inserting, reduceMotion: true) == .none)
        checkTrue("a look exists exactly when the state is active",
                  [S.idle, S.listening, S.transcribing, S.inserting].allSatisfy {
                      (WindowHighlight.style(for: $0, reduceMotion: false) != .none) == WindowHighlight.isActive($0)
                  })

        // MARK: the preference
        let d = suite()
        checkTrue("the highlight is on by default", DictationPrefs.isHighlightEnabled(d) == true)
        d.set(false, forKey: DictationPrefs.highlight)
        checkTrue("the highlight can be turned off", DictationPrefs.isHighlightEnabled(d) == false)
        d.set("no", forKey: DictationPrefs.highlight)
        checkTrue("a wrongly typed saved value reads as the default, on", DictationPrefs.isHighlightEnabled(d) == true)

        print("\(checks) checks, \(failures) failed")
        if checks < 28 { print("VACUOUS: only \(checks) checks ran, need 28"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
