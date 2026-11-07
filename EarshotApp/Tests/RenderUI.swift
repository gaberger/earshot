// Renders Earshot's settings views to PNGs so a person can look at them (ADR-2611062045 follow-up).
// Run: bash EarshotApp/Tests/render.sh   -> writes /tmp/earshot-ui/<scene>.png
// It fails if a scene did not render, or rendered as a blank or single-colour image.
import SwiftUI
import AppKit

let sampleHits: [SearchHit] = [
    .destination(id: "shortcut", title: "Shortcut", detail: "Dictation · change the dictation shortcut"),
    .recording(id: "c", title: "Roadmap review", snippet: "Nothing about dates."),
    .recording(id: "a", title: "Weekly sync", snippet: "…we talked about the roadmap and the launch date."),
]

func sampleHomeItems() -> [HomeItem] {
    let now = Date()
    return [
        .init(id: "a", date: now, title: "Weekly sync with the platform team", detail: "42 min · transcribed · summarized", state: .done),
        .init(id: "b", date: now.addingTimeInterval(-3 * 3600), title: "Call with Priya", detail: "18 min · transcribed", state: .done),
        .init(id: "c", date: now.addingTimeInterval(-5 * 3600), title: "product-meeting-0910.m4a", detail: "Imported file · 1 h 04 min", state: .working),
        .init(id: "d", date: now.addingTimeInterval(-86400), title: "Recording 2026-11-05 16:12", detail: "6 min", state: .failed("Could not transcribe: the audio file is empty")),
        .init(id: "e", date: now.addingTimeInterval(-86400 - 7200), title: "Roadmap review", detail: "55 min · transcribed · summarized", state: .done),
    ]
}

func sampleNoteItems() -> [NoteItem] {
    let now = Date()
    return [
        .init(id: "1", date: now, text: "Remind me to check the failing build before the standup and ask Priya about the roadmap slip.", seconds: 9),
        .init(id: "2", date: now.addingTimeInterval(-5400), text: "Idea for the onboarding screen: show the shortcut first, then the permission, and only then the settings.", seconds: 14),
        .init(id: "3", date: now.addingTimeInterval(-86400), text: "An idea for this weekend: turn the garage into a workshop, start with the shelving and the workbench.", seconds: 12),
        .init(id: "4", date: now.addingTimeInterval(-86400 - 3600), text: "Short one.", seconds: 2),
    ]
}

func setUpDictationOn() {
    UserDefaults.standard.set(true, forKey: DictationPrefs.enabled)
    UserDefaults.standard.set(true, forKey: DictationPrefs.toggle)
    DictationDictionary(entries: [
        .init(heard: "ear shot", write: "Earshot"),
        .init(heard: "kay eight s", write: "k8s"),
    ]).save()
}

/// The brand mark, loaded from disk because AppIcon lives in Earshot.swift, which the harness does not compile.
@MainActor func brandMark() -> AnyView {
    let path = "../docs/brand/logo-b-512.png"
    if FileManager.default.fileExists(atPath: path), let img = NSImage(contentsOfFile: path) {
        return AnyView(Image(nsImage: img).resizable().interpolation(.high)
            .frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 6)))
    }
    return AnyView(RoundedRectangle(cornerRadius: 6).fill(Color.brandAccent).frame(width: 26, height: 26))
}

/// Composes the real views in the same layout as ContentView in Earshot.swift.
@MainActor func windowShell(section: AppSection, query: String, hits: [SearchHit], showRecordBar: Bool, content: AnyView) -> AnyView {
    let sidebar = VStack(alignment: .leading, spacing: 12) {
        HStack {
            brandMark()
            Text("Earshot").font(.headline)
            Spacer()
        }
        SidebarNav(selection: .constant(section))
        Spacer()
        SidebarStatusCard(ready: true, detail: "Whisper · MacBook Pro Microphone")
        SidebarFooter(settingsSelected: false, onSettings: {}, onHelp: {})
    }
    .padding(12)
    .frame(width: 230)
    .frame(maxHeight: .infinity)
    .background(Color(nsColor: .underPageBackgroundColor))

    let detail = VStack(spacing: 0) {
        TopBar(title: section.title, query: .constant(query), hits: hits, focusToken: 0, onPick: { _ in })
        content.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .overlay(alignment: .bottom) {
        if showRecordBar { RecordBar(recordingSince: nil, onRecord: {}, onImport: {}).padding(.bottom, 16) }
    }

    // A drawn stand-in for the system title bar: the real toolbar and status bar need the live Library,
    // so they are not drawn here.
    let titleBar = ZStack {
        Text("Earshot").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
        HStack(spacing: 8) {
            Circle().fill(Color(red: 1.0, green: 0.373, blue: 0.341)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 0.996, green: 0.737, blue: 0.180)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 0.157, green: 0.784, blue: 0.251)).frame(width: 12, height: 12)
            Spacer()
        }
        .padding(.leading, 12)
    }
    .frame(height: 28)
    .frame(maxWidth: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .overlay(alignment: .bottom) { Divider() }

    return AnyView(
        VStack(spacing: 0) {
            titleBar
            HStack(spacing: 0) {
                sidebar
                Divider()
                detail
            }
        }
        .frame(width: 1100, height: 720)
        .background(Color(nsColor: .windowBackgroundColor)))
}

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
            setUpDictationOn()
            return AnyView(DictationSettingsView(onEnable: {}).padding(24).frame(width: 680)
                .background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("home", {
            let items = sampleHomeItems()
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
        ("topbar", {
            AnyView(TopBar(title: "Recordings", query: .constant(""), hits: [], focusToken: 0, onPick: { _ in })
                .frame(width: 760).background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("topbar-results", {
            let hits = sampleHits
            return AnyView(TopBar(title: "Recordings", query: .constant("roadmap"), hits: hits, focusToken: 0, onPick: { _ in })
                .frame(width: 760, height: 320, alignment: .top).background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("topbar-none", {
            AnyView(TopBar(title: "Dictation", query: .constant("zebra"), hits: [], focusToken: 0, onPick: { _ in })
                .frame(width: 760, height: 200, alignment: .top).background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("sidebar-footer", {
            AnyView(VStack(spacing: 16) {
                SidebarFooter(settingsSelected: false, onSettings: {}, onHelp: {})
                SidebarFooter(settingsSelected: true, onSettings: {}, onHelp: {})
            }.padding(16).frame(width: 260).background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("home-narrow", {
            let now = Date()
            let items: [HomeItem] = [
                .init(id: "a", date: now, title: "Second quarter planning with the whole platform team", detail: "42 min · transcribed · summarized", state: .done),
                .init(id: "b", date: now.addingTimeInterval(-3 * 3600 - 1800), title: "BOA call", detail: "Not transcribed yet", state: .done),
                .init(id: "c", date: now.addingTimeInterval(-9 * 3600), title: "Recording 2026-10-30 12:04", detail: "6 min", state: .failed("Could not transcribe: the audio file is empty")),
            ]
            return AnyView(HomeView(items: items, onOpen: { _ in })
                .overlay(alignment: .bottom) { RecordBar(recordingSince: nil, onRecord: {}, onImport: {}).padding(.bottom, 16) }
                .frame(width: 380, height: 640).background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("notes", {
            let items = sampleNoteItems()
            return AnyView(NotesView(items: items, recordingSince: nil, transcribing: false, level: { -30 },
                                     onRecord: {}, onStop: {}, onCopy: { _ in }, onDelete: { _ in }, onClear: {})
                .frame(width: 760, height: 640).background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("notes-recording", {
            let now = Date()
            let items: [NoteItem] = [.init(id: "1", date: now.addingTimeInterval(-5400), text: "Idea for the onboarding screen: show the shortcut first.", seconds: 14)]
            return AnyView(NotesView(items: items, recordingSince: now.addingTimeInterval(-37), transcribing: false, level: { -18 },
                                     onRecord: {}, onStop: {}, onCopy: { _ in }, onDelete: { _ in }, onClear: {})
                .frame(width: 760, height: 520).background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("notes-transcribing", {
            AnyView(NotesView(items: [], recordingSince: nil, transcribing: true, level: { -60 },
                              onRecord: {}, onStop: {}, onCopy: { _ in }, onDelete: { _ in }, onClear: {})
                .frame(width: 760, height: 360).background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("notes-empty", {
            AnyView(NotesView(items: [], recordingSince: nil, transcribing: false, level: { -60 },
                              onRecord: {}, onStop: {}, onCopy: { _ in }, onDelete: { _ in }, onClear: {})
                .frame(width: 760, height: 360).background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("notes-narrow", {
            let now = Date()
            let items: [NoteItem] = [
                .init(id: "1", date: now, text: "Remind me to check the failing build before the standup and ask Priya about the roadmap slip.", seconds: 9),
            ]
            return AnyView(NotesView(items: items, recordingSince: now.addingTimeInterval(-5), transcribing: false, level: { -25 },
                                     onRecord: {}, onStop: {}, onCopy: { _ in }, onDelete: { _ in }, onClear: {})
                .frame(width: 380, height: 520).background(Color(nsColor: .windowBackgroundColor)))
        }),
        ("window-recordings", {
            windowShell(section: .recordings, query: "", hits: [], showRecordBar: true,
                        content: AnyView(HomeView(items: sampleHomeItems(), onOpen: { _ in })))
        }),
        ("window-notes", {
            windowShell(section: .notes, query: "", hits: [], showRecordBar: false,
                        content: AnyView(NotesView(items: sampleNoteItems(), recordingSince: nil, transcribing: false, level: { -30 },
                                                   onRecord: {}, onStop: {}, onCopy: { _ in }, onDelete: { _ in }, onClear: {})))
        }),
        ("window-dictation", {
            setUpDictationOn()
            return windowShell(section: .dictation, query: "", hits: [], showRecordBar: false,
                               content: AnyView(ScrollView { DictationSettingsView(onEnable: {}).padding(24) }))
        }),
        ("window-search", {
            windowShell(section: .recordings, query: "roadmap", hits: sampleHits, showRecordBar: true,
                        content: AnyView(HomeView(items: sampleHomeItems(), onOpen: { _ in })))
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
