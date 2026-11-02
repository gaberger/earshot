// Splits long text into pieces that each fit a token budget, so a transcript too long for
// one model call can be summarized in parts. Pure Foundation: the caller supplies the counter.

import Foundation

enum TokenChunker {
    /// Counts the tokens in a piece of text. Usually backed by the model's own tokenizer.
    typealias Count = (String) async throws -> Int

    /// Splits text into pieces that each fit budget tokens per count, keeping all text in order.
    /// Splits on the coarsest boundary that gives more than one piece: lines, then words, then
    /// characters. A single character over budget is returned as is. Count errors propagate.
    static func split(_ text: String, budget: Int, count: Count) async throws -> [String] {
        precondition(budget > 0, "budget must be positive")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        if try await count(trimmed) <= budget { return [trimmed] }

        let (units, separator) = units(of: trimmed)
        if units.count < 2 { return [trimmed] }
        let mid = units.count / 2
        let first = units[..<mid].joined(separator: separator)
        let second = units[mid...].joined(separator: separator)
        return try await split(first, budget: budget, count: count)
            + split(second, budget: budget, count: count)
    }

    /// The coarsest units of text that number more than one, and the separator that rejoins them.
    private static func units(of text: String) -> ([String], String) {
        let lines = text.split(separator: "\n").map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if lines.count > 1 { return (lines, "\n") }
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count > 1 { return (words, " ") }
        return (text.map(String.init), "")
    }
}
