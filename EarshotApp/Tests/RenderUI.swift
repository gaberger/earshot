// Renders Earshot's settings views to PNGs so a person can look at them (ADR-2611062045 follow-up).
// Run: bash EarshotApp/Tests/render.sh   -> writes /tmp/earshot-ui/<scene>.png
// It fails if a scene did not render, or rendered as a blank or single-colour image.
import SwiftUI
import AppKit

@MainActor func scenes() -> [(String, () -> AnyView)] {
    [
        ("kit", { AnyView(
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
        ) }),
        ("dictation-off", {
            UserDefaults.standard.set(false, forKey: DictationPrefs.enabled)
            UserDefaults.standard.removeObject(forKey: DictationDictionary.key)
            return AnyView(DictationSettingsView(onEnable: {}).padding(24).frame(width: 680)
                .background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("dictation-on", {
            UserDefaults.standard.set(true, forKey: DictationPrefs.enabled)
            UserDefaults.standard.set(true, forKey: DictationPrefs.toggle)
            DictationDictionary(entries: [
                .init(heard: "ear shot", write: "Earshot"),
                .init(heard: "kay eight s", write: "k8s"),
            ]).save()
            return AnyView(DictationSettingsView(onEnable: {}).padding(24).frame(width: 680)
                .background(Color(nsColor: .windowBackgroundColor)))
        }),
    ]
}

@MainActor func render(into dir: URL) -> Bool {
    var ok = true
    for (name, make) in scenes() {
        let view = make()
        // A real (never shown) window, so native controls such as Picker and Toggle draw properly;
        // ImageRenderer draws them as yellow placeholders.
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard size.width > 10, size.height > 10, let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("FAIL \(name): did not render"); ok = false; continue
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
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
