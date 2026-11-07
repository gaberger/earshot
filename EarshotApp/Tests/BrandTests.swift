// Tests for Brand (ADR-2611072000). Run: bash EarshotApp/Tests/run.sh
// The expected contrast ratios were computed separately, by hand, with the WCAG formula on the hex
// values below. They are not produced by the code under test.
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}
func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.02) -> Bool { abs(a - b) <= tolerance }

@main struct BrandTests {
    static func main() {
        // MARK: the tokens
        checkTrue("the accent is flame orange F97316", Brand.accent == 0xF97316)
        checkTrue("text on an accent fill is near-black 141414", Brand.onAccent == 0x141414)
        checkTrue("accent text in light mode is B93C0A", Brand.accentTextLight == 0xB93C0A)
        checkTrue("the warning colour is amber FBBF24", Brand.warning == 0xFBBF24)
        checkTrue("warning text in light mode is 92400E", Brand.warningTextLight == 0x92400E)

        // MARK: fills and dark mode (surfaces: window 1E1E1E, card 2A2A2C)
        checkTrue("dark text on the orange fill is 6.57:1", near(Brand.contrast(Brand.onAccent, Brand.accent), 6.57),
                  "\(Brand.contrast(Brand.onAccent, Brand.accent))")
        checkTrue("orange on the dark window is 5.95:1", near(Brand.contrast(Brand.accent, 0x1E1E1E), 5.95),
                  "\(Brand.contrast(Brand.accent, 0x1E1E1E))")
        checkTrue("orange on a dark card is 5.11:1 (at least 4.5)", near(Brand.contrast(Brand.accent, 0x2A2A2C), 5.11)
                  && Brand.contrast(Brand.accent, 0x2A2A2C) >= 4.5)
        checkTrue("amber on the dark window is 9.99:1", near(Brand.contrast(Brand.warning, 0x1E1E1E), 9.99),
                  "\(Brand.contrast(Brand.warning, 0x1E1E1E))")
        checkTrue("amber on a dark card is 8.58:1", near(Brand.contrast(Brand.warning, 0x2A2A2C), 8.58),
                  "\(Brand.contrast(Brand.warning, 0x2A2A2C))")

        // MARK: light mode text (surfaces: white FFFFFF, F5F5F5, window ECECEC)
        checkTrue("light accent text on white is 5.65:1", near(Brand.contrast(Brand.accentTextLight, 0xFFFFFF), 5.65),
                  "\(Brand.contrast(Brand.accentTextLight, 0xFFFFFF))")
        checkTrue("light accent text on F5F5F5 is 5.19:1", near(Brand.contrast(Brand.accentTextLight, 0xF5F5F5), 5.19),
                  "\(Brand.contrast(Brand.accentTextLight, 0xF5F5F5))")
        checkTrue("light accent text on the ECECEC window is 4.79:1 (at least 4.5)",
                  near(Brand.contrast(Brand.accentTextLight, 0xECECEC), 4.79) && Brand.contrast(Brand.accentTextLight, 0xECECEC) >= 4.5,
                  "\(Brand.contrast(Brand.accentTextLight, 0xECECEC))")
        checkTrue("light warning text on white is 7.09:1", near(Brand.contrast(Brand.warningTextLight, 0xFFFFFF), 7.09),
                  "\(Brand.contrast(Brand.warningTextLight, 0xFFFFFF))")
        checkTrue("light warning text on F5F5F5 is 6.50:1", near(Brand.contrast(Brand.warningTextLight, 0xF5F5F5), 6.50),
                  "\(Brand.contrast(Brand.warningTextLight, 0xF5F5F5))")
        checkTrue("light warning text on the ECECEC window is 6.00:1", near(Brand.contrast(Brand.warningTextLight, 0xECECEC), 6.00),
                  "\(Brand.contrast(Brand.warningTextLight, 0xECECEC))")
        checkTrue("plain orange on white would fail (2.8:1), which is why light mode has its own text colour",
                  Brand.contrast(Brand.accent, 0xFFFFFF) < 3.0, "\(Brand.contrast(Brand.accent, 0xFFFFFF))")

        // MARK: accent versus warning must be tellable apart
        checkTrue("the accent hue is about 24.6 degrees", near(Brand.hue(Brand.accent), 24.6, 0.4), "\(Brand.hue(Brand.accent))")
        checkTrue("the amber hue is about 43.3 degrees", near(Brand.hue(Brand.warning), 43.3, 0.4), "\(Brand.hue(Brand.warning))")
        checkTrue("in dark mode accent and warning differ by at least 15 degrees of hue",
                  abs(Brand.hue(Brand.warning) - Brand.hue(Brand.accent)) >= 15)

        // MARK: the contrast function itself
        checkTrue("black on white is 21:1", near(Brand.contrast(0x000000, 0xFFFFFF), 21.0, 0.001))
        checkTrue("a colour against itself is 1:1", near(Brand.contrast(0x336699, 0x336699), 1.0, 0.0001))
        checkTrue("contrast does not depend on the order of its arguments",
                  Brand.contrast(0x123456, 0xFEDCBA) == Brand.contrast(0xFEDCBA, 0x123456))

        print("\(checks) checks, \(failures) failed")
        if checks < 23 { print("VACUOUS: only \(checks) checks ran, need 23"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
