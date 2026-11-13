import AppKit
import SwiftUI

/// A panel that never takes focus: the user is in a call, and the call app must keep the keyboard.
/// It still takes clicks, so its buttons work.
private final class OfferPanelWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets a single click on a button work without first activating the window.
private final class OfferHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// What the offer shows: who holds the microphone, the question, and the choices.
private struct OfferView: View {
    let appName: String
    let showsIgnore: Bool
    let record: () -> Void
    let ignore: () -> Void
    let dismiss: () -> Void

    var body: some View {
        let text = CallOfferPanelRule.text(appName: appName)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(text.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if showsIgnore {
                    Button(text.ignore, action: ignore)
                        .controlSize(.regular)
                }
                Button("Record", action: record)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The on-screen "Record this meeting?" offer (ADR-2611130933). It never takes focus, takes
/// single clicks, sits top-right of the screen holding the mouse, and goes by itself when
/// `CallOfferPanelRule` says so.
@MainActor
final class CallOfferPanel {
    private var panel: NSPanel?
    private var rule: CallOfferPanelRule?

    var isShown: Bool { rule != nil }

    func show(appName: String, bundleID: String?, onRecord: @escaping () -> Void, onIgnore: @escaping () -> Void) {
        rule = CallOfferPanelRule(shownAt: ProcessInfo.processInfo.systemUptime)
        let view = OfferView(
            appName: appName,
            showsIgnore: bundleID != nil,
            record: { [weak self] in self?.hide(); onRecord() },
            ignore: { [weak self] in self?.hide(); onIgnore() },
            dismiss: { [weak self] in self?.hide() })
        let host = OfferHostingView(rootView: view)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        place(panel)
        panel.orderFrontRegardless()
        let text = CallOfferPanelRule.text(appName: appName)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "\(text.title). \(text.body)"])
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        rule = nil
    }

    /// Feeds one sample to the rule; hides the panel and returns the reason when it should go.
    @discardableResult
    func tick(capturing: Bool?, recording: Bool, at t: TimeInterval) -> CallOfferPanelRule.Dismissal? {
        guard var current = rule else { return nil }
        let verdict = current.ingest(capturing: capturing, recording: recording, at: t)
        rule = current
        if verdict != nil { hide() }
        return verdict
    }

    private func makePanel() -> NSPanel {
        let panel = OfferPanelWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        return panel
    }

    /// Top-right of the visible frame of the screen holding the mouse, 16 pt in from each edge.
    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: area.maxX - size.width - 16, y: area.maxY - size.height - 16))
    }
}
