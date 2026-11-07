// PasteGuard (ADR-2611071800): paste only into the window and field dictation started in.
// Pure rule, no AppKit: the caller reads the frontmost app, its window and focused field
// (as opaque identity tokens) and, when readable, the window frame.
import Foundation
import CoreGraphics

/// Where dictation started (or where focus is now): the app, and as far as readable the window
/// and focused field identity, plus the window frame as a fallback.
struct PasteTarget: Equatable {
    var pid: Int32
    /// Window frame; only consulted when the window identity token is unavailable on either side.
    var frame: CGRect?
    /// Opaque identity of the window (e.g. its CGWindowID); nil when it cannot be read.
    var window: Int?
    /// Opaque identity of the focused field or pane; nil when it cannot be read.
    var focus: Int?

    init(pid: Int32, frame: CGRect? = nil, window: Int? = nil, focus: Int? = nil) {
        self.pid = pid
        self.frame = frame
        self.window = window
        self.focus = focus
    }
}

enum PasteDecision: Equatable {
    case paste
    case hold
}

enum PasteGuard {
    /// Hold the paste when focus has moved to another app, another window, or another field.
    /// Rules, in order:
    /// - either side nil: paste (the guard must never block on a guess);
    /// - different pid: hold;
    /// - both window tokens known and different: hold; both focus tokens known and different: hold;
    /// - both window tokens known and equal: paste, the frame is ignored (the window may have moved);
    /// - otherwise (a window token is missing) fall back to the frame: either frame unreadable pastes;
    ///   else each of x, y, width and height may differ by at most `tolerance` (inclusive).
    /// Frames are compared in one coordinate space (the caller's).
    static func decide(target: PasteTarget?, current: PasteTarget?, tolerance: CGFloat = 8) -> PasteDecision {
        guard let target = target, let current = current else { return .paste }
        if target.pid != current.pid { return .hold }
        if let a = target.window, let b = current.window, a != b { return .hold }
        if let a = target.focus, let b = current.focus, a != b { return .hold }
        if let a = target.window, let b = current.window, a == b { return .paste }
        guard let a = target.frame, let b = current.frame else { return .paste }
        let same = abs(a.origin.x - b.origin.x) <= tolerance
            && abs(a.origin.y - b.origin.y) <= tolerance
            && abs(a.size.width - b.size.width) <= tolerance
            && abs(a.size.height - b.size.height) <= tolerance
        return same ? .paste : .hold
    }
}
