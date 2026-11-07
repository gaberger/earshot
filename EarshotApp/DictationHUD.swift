import AppKit
import SwiftUI

/// A panel that can never take focus. The text field the user is dictating into must keep it,
/// or the paste lands nowhere.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// What the indicator shows. The level is polled, not pushed, so the view owns its own timer.
private struct HUDView: View {
    let state: DictationSession.State
    var tidying = false
    let level: () -> Float

    @State private var meter: CGFloat = 0
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if state == .transcribing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.red)
                        .opacity(pulse ? 0.45 : 1)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                }
                Text(state.indicatorText(tidying: tidying) ?? "")
                    .font(.system(size: 13, weight: .medium))
            }
            if state.showsLevel {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: 120, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.red).frame(width: 120 * meter, height: 3)
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .fixedSize()
        .onAppear { pulse = true }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            guard state.showsLevel else { return }
            // dB: -60 (quiet) ... 0 (loud) onto 0...1.
            let db = Double(level())
            meter = CGFloat(min(max((db + 60) / 60, 0), 1))
        }
    }
}

/// A small floating indicator that shows dictation is live. It never takes focus, never takes
/// the mouse, and follows the mouse to whichever screen the user is working on.
@MainActor
final class DictationHUD {
    private var panel: NSPanel?
    private var host: NSHostingView<HUDView>?
    private var lastText: String?

    /// Shows or updates the panel while the state has something to say, else hides it.
    func update(state: DictationSession.State, tidying: Bool = false, level: @escaping () -> Float) {
        guard let text = state.indicatorText(tidying: tidying) else { return hide() }
        let view = HUDView(state: state, tidying: tidying, level: level)
        if let host {
            host.rootView = view
        } else {
            host = NSHostingView(rootView: view)
        }
        guard let host else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        place(panel)
        panel.orderFrontRegardless()
        if text != lastText {
            lastText = text
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: text])
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        host = nil
        lastText = nil
    }

    private func makePanel() -> NSPanel {
        let panel = HUDPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        return panel
    }

    /// Horizontally centered on the screen holding the mouse, about 90 pt above the bottom edge.
    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.minY + 90))
    }
}
