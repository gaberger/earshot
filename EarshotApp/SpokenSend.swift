import Foundation

/// A spoken command at the end of a dictation (ADR-2611080900): the words "exclamation point" or
/// "exclamation mark" mean "press Control-Return". Pure logic, no UI.
enum SpokenSend {
    struct Result: Equatable {
        let text: String
        let send: Bool
    }

    /// Virtual key code of Return.
    static let returnKeyCode: UInt16 = 36
    /// Raw value of the Control modifier flag (CGEventFlags.maskControl).
    static let controlFlagRaw: UInt64 = 0x40000

    private static let pattern = try? NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_])exclamation[\s-]+(?:point|mark)(?![\p{L}\p{N}_])[\s\p{P}]*$"#,
        options: [.caseInsensitive])

    private static let danglers: Set<Character> = [",", ";", ":", "-", "\u{2013}", "\u{2014}"]

    static func apply(enabled: Bool, to text: String) -> Result {
        guard enabled else { return Result(text: text, send: false) }
        return parse(text)
    }

    static func parse(_ text: String) -> Result {
        if text.allSatisfy({ $0.isWhitespace }) { return Result(text: "", send: false) }
        let whole = NSRange(text.startIndex..., in: text)
        guard let regex = pattern, let match = regex.firstMatch(in: text, options: [], range: whole),
              let range = Range(match.range, in: text) else {
            return Result(text: text, send: false)
        }
        var rest = String(text[..<range.lowerBound])
        while true {
            while let last = rest.last, last.isWhitespace { rest.removeLast() }
            if let last = rest.last, danglers.contains(last) {
                rest.removeLast()
            } else {
                break
            }
        }
        while let first = rest.first, first.isWhitespace { rest.removeFirst() }
        return Result(text: rest, send: true)
    }
}
