import AppKit
import QuartzCore

/// A borderless panel that can never take focus, so the paste still lands where the user was typing.
private final class HighlightPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws the outline (and fire) of `WindowHighlight` over one window (ADR-2611071400). Click-through,
/// never key, above normal windows. The emitter animates itself, so there are no timers here.
///
/// The view's layer is not flipped: +y is up, so a positive `yAcceleration` makes sparks rise.
@MainActor
final class WindowHighlighter {
    /// Room around the highlight rect for the glow, and above it for flames to rise past the top edge.
    private static let sideInset: CGFloat = 30
    private static let bottomInset: CGFloat = 30
    private static let topInset: CGFloat = 70

    private var panel: HighlightPanel?
    private var shown: (frame: CGRect, style: WindowHighlight.Style)?
    private let dot = WindowHighlighter.makeDot()

    func show(frame: CGRect, style: WindowHighlight.Style) {
        guard style != .none else { return hide() }
        if let shown, shown.frame == frame, shown.style == style, panel?.isVisible == true { return }
        let outer = CGRect(x: frame.minX - Self.sideInset, y: frame.minY - Self.bottomInset,
                           width: frame.width + 2 * Self.sideInset,
                           height: frame.height + Self.bottomInset + Self.topInset)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(outer, display: false)
        panel.contentView = makeContent(size: outer.size, style: style)
        panel.orderFrontRegardless()
        shown = (frame, style)
    }

    func hide() {
        shown = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    // MARK: Building

    private func makePanel() -> HighlightPanel {
        let panel = HighlightPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: true)
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        return panel
    }

    private func makeContent(size: CGSize, style: WindowHighlight.Style) -> NSView {
        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        guard let root = view.layer else { return view }
        let inner = CGRect(x: Self.sideInset, y: Self.bottomInset,
                           width: size.width - 2 * Self.sideInset,
                           height: size.height - Self.bottomInset - Self.topInset)

        let orange = NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.1, alpha: 1).cgColor
        let border = CAShapeLayer()
        border.frame = root.bounds
        border.path = CGPath(roundedRect: inner, cornerWidth: 10, cornerHeight: 10, transform: nil)
        border.fillColor = nil
        border.strokeColor = orange
        border.lineWidth = 2
        border.shadowColor = orange
        border.shadowRadius = 12
        border.shadowOpacity = 0.8
        border.shadowOffset = .zero
        root.addSublayer(border)

        if style == .flames || style == .embers {
            root.addSublayer(makeEmitter(inner: inner, style: style, bounds: root.bounds))
        }
        return view
    }

    private func makeEmitter(inner: CGRect, style: WindowHighlight.Style, bounds: CGRect) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.frame = bounds
        emitter.emitterShape = .rectangle
        emitter.emitterMode = .outline
        emitter.emitterSize = inner.size
        emitter.emitterPosition = CGPoint(x: inner.midX, y: inner.midY)
        emitter.renderMode = .additive

        func cell(rate: Float, velocity: CGFloat, scale: CGFloat, color: NSColor, range: CGFloat, alpha: Float) -> CAEmitterCell {
            let c = CAEmitterCell()
            c.contents = dot
            c.birthRate = rate
            c.lifetime = 1.2
            c.lifetimeRange = 0.3
            c.velocity = velocity
            c.velocityRange = velocity * 0.4
            c.emissionRange = .pi / 3
            c.yAcceleration = 60  // positive y is up: the layer is not flipped
            c.scale = scale
            c.scaleRange = scale * 0.3
            c.scaleSpeed = -scale * 0.3
            c.redRange = Float(range)
            c.greenRange = Float(range)
            c.alphaSpeed = -alpha / 1.2
            c.color = color.withAlphaComponent(CGFloat(alpha)).cgColor
            return c
        }

        switch style {
        case .flames:
            let body = cell(rate: 140, velocity: 45, scale: 0.4,
                            color: NSColor(calibratedRed: 1.0, green: 0.5, blue: 0.1, alpha: 1), range: 0.3, alpha: 0.9)
            let core = cell(rate: 50, velocity: 40, scale: 0.2,
                            color: NSColor(calibratedRed: 1.0, green: 0.9, blue: 0.5, alpha: 1), range: 0.1, alpha: 0.9)
            emitter.emitterCells = [body, core]
        default:
            let ember = cell(rate: 35, velocity: 12, scale: 0.4,
                             color: NSColor(calibratedRed: 0.9, green: 0.25, blue: 0.05, alpha: 1), range: 0.15, alpha: 0.5)
            emitter.emitterCells = [ember]
        }
        return emitter
    }

    /// A soft white dot, generated here so no image asset is needed.
    private static func makeDot() -> CGImage? {
        let side = 32
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return nil }
        let c = CGPoint(x: side / 2, y: side / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(side) / 2, options: [])
        return ctx.makeImage()
    }
}
