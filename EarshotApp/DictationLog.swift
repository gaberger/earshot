// The notes log of dictations (ADR-2611062250): pure logic, Foundation only.
import Foundation

struct DictationLog: Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        var id: String
        var date: Date
        var text: String
        var app: String?
        var seconds: Double?
    }

    /// Newest first.
    var entries: [Entry]
    let limit: Int

    init(entries: [Entry] = [], limit: Int = 2000) {
        self.limit = limit
        self.entries = entries.enumerated()
            .sorted { $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset < $1.offset }
            .map(\.element)
        if self.entries.count > limit { self.entries = Array(self.entries.prefix(max(limit, 0))) }
    }

    mutating func add(_ entry: Entry) {
        var e = entry
        e.text = e.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.text.isEmpty else { return }
        // Insert after every entry that is as new or newer, so equal dates keep the order they arrived in.
        let index = entries.firstIndex { $0.date < e.date } ?? entries.count
        entries.insert(e, at: index)
        if entries.count > limit { entries.removeLast(entries.count - max(limit, 0)) }
    }

    mutating func remove(id: String) { entries.removeAll { $0.id == id } }

    mutating func clear() { entries.removeAll() }

    @discardableResult
    func save(to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func load(from url: URL) -> DictationLog {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return DictationLog() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url), let entries = try? decoder.decode([Entry].self, from: data) {
            return DictationLog(entries: entries)
        }
        // Damaged: keep the bytes aside (replacing an older .bad) so a new log never overwrites them.
        let aside = URL(fileURLWithPath: url.path + ".bad")
        try? fm.removeItem(at: aside)
        try? fm.moveItem(at: url, to: aside)
        return DictationLog()
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Earshot/notes.json")
    }
}
