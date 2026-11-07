// DictationDictionary: the user's corrections for words dictation mishears (ADR-2611062045).
// Pure Foundation: matching is whole-word, case-insensitive and literal; the longest heard
// phrase wins; replacement is a single pass, so a correction's output is never corrected again.
import Foundation

struct DictationDictionary: Equatable {
    struct Entry: Equatable, Codable {
        var heard: String
        var write: String
    }

    var entries: [Entry]

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// Parses the Settings text form: one "heard => write" per line, split at the first "=>".
    init(parsing text: String) {
        var parsed: [Entry] = []
        for line in text.components(separatedBy: .newlines) {
            guard let arrow = line.range(of: "=>") else { continue }
            let heard = Self.trimmed(String(line[..<arrow.lowerBound]))
            if heard.isEmpty { continue }
            let write = Self.trimmed(String(line[arrow.upperBound...]))
            parsed.append(Entry(heard: heard, write: write))
        }
        self.entries = parsed
    }

    /// The text form: one "heard => write" per line, no trailing newline.
    var asText: String {
        entries
            .filter { !Self.trimmed($0.heard).isEmpty }
            .map { "\(Self.trimmed($0.heard)) => \($0.write)" }
            .joined(separator: "\n")
    }

    static let key = "dictationDictionary"

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func apply(_ text: String) -> String {
        if text.isEmpty { return text }
        // Usable entries only; the first entry for a given phrase (ignoring case) wins.
        var byHeard: [String: String] = [:]
        var phrases: [String] = []
        for entry in entries {
            let heard = Self.trimmed(entry.heard)
            if heard.isEmpty { continue }
            let lookup = heard.lowercased()
            if byHeard[lookup] != nil { continue }
            byHeard[lookup] = entry.write
            phrases.append(heard)
        }
        if phrases.isEmpty { return text }

        // One alternation, longest first, so "new york" is tried before "new".
        let alternation = phrases
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let word = "[\\p{L}\\p{N}_]"
        let pattern = "(?<!\(word))(?:\(alternation))(?!\(word))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let source = text as NSString
        var out = ""
        var last = 0
        for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: source.length)) {
            out += source.substring(with: NSRange(location: last, length: match.range.location - last))
            let found = source.substring(with: match.range).lowercased()
            if let write = byHeard[found] {
                let template = NSRegularExpression.escapedTemplate(for: write)
                out += regex.replacementString(for: match, in: text, offset: 0, template: template)
            } else {
                out += source.substring(with: match.range)
            }
            last = match.range.location + match.range.length
        }
        out += source.substring(from: last)
        return out
    }

    static func load(from defaults: UserDefaults = .standard) -> DictationDictionary {
        guard let json = defaults.object(forKey: key) as? String,
              let data = json.data(using: .utf8),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return DictationDictionary() }
        return DictationDictionary(entries: entries)
    }

    func save(to defaults: UserDefaults = .standard) {
        let kept = entries.filter { !Self.trimmed($0.heard).isEmpty }
        guard let data = try? JSONEncoder().encode(kept),
              let json = String(data: data, encoding: .utf8)
        else { return }
        defaults.set(json, forKey: Self.key)
    }
}
