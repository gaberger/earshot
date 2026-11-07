import CoreGraphics
import Foundation

/// Pure rules for the outline drawn around the window dictation will type into (ADR-2611071400).
/// No AppKit: the geometry and the state table are testable without a screen.
///
/// Coordinates: Accessibility frames have their origin at the top-left of the primary display with
/// y increasing downward; AppKit frames have it at the bottom-left with y increasing upward. Both
/// measure from the primary display, so one conversion with its height covers every screen.
enum WindowHighlight {
    /// How the target window is drawn.
    enum Style: Equatable {
        case none
        /// A rising particle fire, while listening.
        case flames
        /// The same fire turned low and dim, while transcribing or tidying.
        case embers
        /// A static border with no animation, when Reduce Motion is on.
        case border
    }

    /// Converts an Accessibility frame to an AppKit frame: `y = primaryHeight - (axY + height)`.
    static func appKitFrame(fromAX ax: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: ax.origin.x, y: primaryHeight - (ax.origin.y + ax.size.height),
               width: ax.size.width, height: ax.size.height)
    }

    /// The window grown by `margin` on every side and clamped to the screen holding most of it, or
    /// `nil` when there is nothing sensible to draw (bad numbers, under 40 pt, or on no screen).
    static func rect(forWindow window: CGRect, screens: [CGRect], margin: CGFloat = 4) -> CGRect? {
        let parts = [window.origin.x, window.origin.y, window.size.width, window.size.height]
        guard parts.allSatisfy({ $0.isFinite }) else { return nil }
        guard window.size.width >= 40, window.size.height >= 40 else { return nil }
        var best: (screen: CGRect, area: CGFloat)?
        for screen in screens {
            let overlap = window.intersection(screen)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (screen, area) }
        }
        guard let best else { return nil }
        let grown = window.insetBy(dx: -margin, dy: -margin)
        let clamped = grown.intersection(best.screen)
        return clamped.isNull ? nil : clamped
    }

    /// Listening and transcribing show the outline; idle and inserting do not.
    static func isActive(_ state: DictationSession.State) -> Bool {
        switch state {
        case .listening, .transcribing: return true
        case .idle, .inserting: return false
        }
    }

    /// The look for a state. Reduce Motion always gets the static border.
    static func style(for state: DictationSession.State, reduceMotion: Bool) -> Style {
        guard isActive(state) else { return .none }
        if reduceMotion { return .border }
        return state == .listening ? .flames : .embers
    }
}
