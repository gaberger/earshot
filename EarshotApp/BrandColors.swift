// SwiftUI and AppKit bridge for the brand tokens (ADR-2611072000).
import SwiftUI
import AppKit

private func brandNS(_ rgb: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
}

private func brandDynamic(dark: Int, light: Int) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? brandNS(dark) : brandNS(light)
    })
}

extension Color {
    init(brandHex rgb: Int) { self.init(nsColor: brandNS(rgb)) }

    static let brandAccent = Color(brandHex: Brand.accent)
    static let brandOnAccent = Color(brandHex: Brand.onAccent)
    static let brandAccentText = brandDynamic(dark: Brand.accent, light: Brand.accentTextLight)
    static let brandWarning = Color(brandHex: Brand.warning)
    static let brandWarningText = brandDynamic(dark: Brand.warning, light: Brand.warningTextLight)
}
