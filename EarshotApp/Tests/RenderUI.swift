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
        ("home", {
            let now = Date()
            let items: [HomeItem] = [
                .init(id: "a", date: now, title: "Weekly sync with the platform team", detail: "42 min · transcribed · summarized", state: .done),
                .init(id: "b", date: now.addingTimeInterval(-3 * 3600), title: "Call with Priya", detail: "18 min · transcribed", state: .done),
                .init(id: "c", date: now.addingTimeInterval(-5 * 3600), title: "product-meeting-0910.m4a", detail: "Imported file · 1 h 04 min", state: .working),
                .init(id: "d", date: now.addingTimeInterval(-86400), title: "Recording 2026-11-05 16:12", detail: "6 min", state: .failed("Could not transcribe: the audio file is empty")),
                .init(id: "e", date: now.addingTimeInterval(-86400 - 7200), title: "Roadmap review", detail: "55 min · transcribed · summarized", state: .done),
            ]
            return AnyView(
                HomeView(items: items, onOpen: { _ in })
                    .overlay(alignment: .bottom) { RecordBar(recordingSince: nil, onRecord: {}, onImport: {}).padding(.bottom, 16) }
                    .frame(width: 760, height: 640)
                    .background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("sidebar-status", {
            AnyView(VStack(spacing: 16) {
                SidebarStatusCard(ready: true, detail: "Whisper · MacBook Pro Microphone")
                SidebarStatusCard(ready: false, detail: "Recording… 12:41")
            }.padding(16).frame(width: 260).background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("recording", {
            AnyView(RecordingScreen(start: Date().addingTimeInterval(-754), micName: "MacBook Pro Microphone",
                                    level: { -18 }, endingIn: nil, onKeepRecording: {}, onStop: {})
                .frame(width: 760, height: 520).background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("recording-ending", {
            AnyView(RecordingScreen(start: Date().addingTimeInterval(-2210), micName: "MacBook Pro Microphone",
                                    level: { -55 }, endingIn: 24, onKeepRecording: {}, onStop: {})
                .frame(width: 760, height: 520).background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("detail-header", {
            AnyView(RecordingHeader(title: "Weekly sync with the platform team", date: Date(),
                                    chips: ["42 min", "Transcribed", "Summarized"],
                                    tabs: ["Summary", "Transcript"], selectedTab: .constant(0),
                                    actions: [
                                        HeaderAction(title: "Summarize", icon: "sparkles", enabled: true, action: {}),
                                        HeaderAction(title: "Copy", icon: "doc.on.doc", enabled: true, action: {}),
                                        HeaderAction(title: "Finder", icon: "folder", enabled: true, action: {}),
                                    ], onRename: {})
                .padding(24).frame(width: 760).background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("sidebar-nav", {
            AnyView(VStack(spacing: 16) {
                SidebarNav(selection: .constant(.recordings))
                SidebarNav(selection: .constant(.dictation))
            }.padding(16).frame(width: 260).background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("dictation-page", {
            UserDefaults.standard.set(true, forKey: DictationPrefs.enabled)
            UserDefaults.standard.set(false, forKey: DictationPrefs.toggle)
            DictationDictionary(entries: [.init(heard: "ear shot", write: "Earshot")]).save()
            return AnyView(DictationPage(onEnable: {}, onResetPermission: {})
                .frame(width: 760, height: 900).background(Color(nsColor: .windowBackgroundColor)))
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
