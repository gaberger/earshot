// Brand tokens (ADR-2611072000). Pure Foundation: hex values and the WCAG 2 contrast function.
import Foundation

enum Brand {
    static let accent = 0xF97316
    static let onAccent = 0x141414
    static let accentTextLight = 0xB93C0A
    static let warning = 0xFBBF24
    static let warningTextLight = 0x92400E

    private static func channels(_ rgb: Int) -> (Double, Double, Double) {
        (Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255)
    }

    private static func luminance(_ rgb: Int) -> Double {
        func lin(_ x: Double) -> Double { x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let (r, g, b) = channels(rgb)
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// WCAG 2 contrast ratio, 1...21, the same in either argument order.
    static func contrast(_ a: Int, _ b: Int) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// HSV hue in degrees, 0..<360 (0 for greys).
    static func hue(_ rgb: Int) -> Double {
        let (r, g, b) = channels(rgb)
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        if d == 0 { return 0 }
        var h: Double
        if mx == r { h = (g - b) / d } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h *= 60
        return h < 0 ? h + 360 : h
    }
}
