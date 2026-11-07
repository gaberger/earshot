// PasteGuard (ADR-2611071800): paste only into the window dictation started in.
// Pure rule, no AppKit: the caller reads the frontmost app and its window frame.
import Foundation
import CoreGraphics

/// The window dictation started in (or the one in front now): its app and, when readable, its frame.
struct PasteTarget: Equatable {
    var pid: Int32
    var frame: CGRect?
}

enum PasteDecision: Equatable {
    case paste
    case hold
}

enum PasteGuard {
    /// Hold the paste when focus has moved to another app or to a clearly different window.
    /// When either side cannot be read, paste as before: the guard must never block on a guess.
    /// Frames are compared in one coordinate space (the caller's); each of x, y, width and height
    /// may differ by at most `tolerance` (inclusive) for the windows to count as the same.
    static func decide(target: PasteTarget?, current: PasteTarget?, tolerance: CGFloat = 8) -> PasteDecision {
        guard let target = target, let current = current else { return .paste }
        if target.pid != current.pid { return .hold }
        guard let a = target.frame, let b = current.frame else { return .paste }
        let same = abs(a.origin.x - b.origin.x) <= tolerance
            && abs(a.origin.y - b.origin.y) <= tolerance
            && abs(a.size.width - b.size.width) <= tolerance
            && abs(a.size.height - b.size.height) <= tolerance
        return same ? .paste : .hold
    }
}
