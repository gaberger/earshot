// Renders Earshot's settings views to PNGs so a person can look at them (ADR-2611062045 follow-up).
// Run: bash EarshotApp/Tests/render.sh   -> writes /tmp/earshot-ui/<scene>.png
// It fails if a scene did not render, or rendered as a blank or single-colour image.
import SwiftUI
import AppKit

@MainActor func scenes() -> [(String, AnyView)] {
    [
        ("kit", AnyView(
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection("Shortcuts") {
                    SettingsRow("To dictate", detail: "Hold the keys while you talk, or switch to tap mode below.") {
                        KeyChip("⌃⌥Space")
                    }
                    SettingsBanner("That shortcut is already used by macOS.", actionTitle: "Reset") {}
                    SettingsRow("Mode", detail: "A change applies from your next dictation.") {
                        Picker("", selection: .constant(0)) {
                            Text("Hold").tag(0)
                            Text("Tap").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 160)
                    }
                    SettingsRow("Sound at start and end") { Toggle("", isOn: .constant(true)).labelsHidden() }
                }
            }
            .padding(24)
            .frame(width: 680)
            .background(Color(nsColor: .windowBackgroundColor))
        )),
    ]
}

@MainActor func render(into dir: URL) -> Bool {
    var ok = true
    for (name, view) in scenes() {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("FAIL \(name): did not render"); ok = false; continue
        }
        // Not blank: sample a grid and count distinct colours.
        var seen = Set<String>()
        let w = rep.pixelsWide, h = rep.pixelsHigh
        for y in stride(from: 0, to: h, by: max(1, h / 60)) {
            for x in stride(from: 0, to: w, by: max(1, w / 60)) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    seen.insert(String(format: "%.2f%.2f%.2f", c.redComponent, c.greenComponent, c.blueComponent))
                }
            }
        }
        if seen.count < 4 { print("FAIL \(name): looks blank (\(seen.count) colours)"); ok = false; continue }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
        print("PASS \(name) \(w)x\(h), \(seen.count) colours")
    }
    return ok
}

@main struct RenderUI {
    static func main() {
        let dir = URL(fileURLWithPath: "/tmp/earshot-ui")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ok = MainActor.assumeIsolated { render(into: dir) }
        exit(ok ? 0 : 1)
    }
}
