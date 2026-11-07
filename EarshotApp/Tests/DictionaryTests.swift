// Tests for DictationDictionary (ADR-2611062045). Run: bash EarshotApp/Tests/run.sh
// Every expected string is written out by hand, not computed from the rules under test.
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

func suite() -> UserDefaults {
    let name = "DictionaryTests-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

func dict(_ pairs: [(String, String)]) -> DictationDictionary {
    DictationDictionary(entries: pairs.map { DictationDictionary.Entry(heard: $0.0, write: $0.1) })
}

@main struct DictionaryTests {
    static func main() {
        // MARK: replacing
        checkTrue("an empty dictionary changes nothing", DictationDictionary().apply("hello ear shot") == "hello ear shot")
        checkTrue("empty text stays empty", dict([("a", "b")]).apply("") == "")
        let earshot = dict([("ear shot", "Earshot")])
        checkTrue("a heard phrase becomes the spelling", earshot.apply("open ear shot now") == "open Earshot now")
        checkTrue("matching ignores case", earshot.apply("Ear Shot is great") == "Earshot is great")
        checkTrue("every occurrence is replaced", earshot.apply("ear shot and ear shot") == "Earshot and Earshot")
        checkTrue("punctuation next to the phrase is kept", earshot.apply("I like ear shot.") == "I like Earshot.")
        checkTrue("a phrase at the very start and end", earshot.apply("ear shot") == "Earshot")

        // MARK: whole words only
        let cat = dict([("cat", "dog")])
        checkTrue("a word inside a longer word is left alone", cat.apply("concatenate cat catalog") == "concatenate dog catalog")
        checkTrue("an accented letter counts as part of the word", dict([("cafe", "bar")]).apply("cafés cafe") == "cafés bar")

        // MARK: which rule wins
        let places = dict([("new", "old"), ("new york", "NYC")])
        checkTrue("the longest phrase wins, whatever the order", places.apply("in new york and new jersey") == "in NYC and old jersey")
        let reversed = dict([("new york", "NYC"), ("new", "old")])
        checkTrue("and the same with the order swapped", reversed.apply("in new york and new jersey") == "in NYC and old jersey")
        checkTrue("a correction's output is not corrected again", dict([("a", "b"), ("b", "c")]).apply("a b") == "b c")
        checkTrue("a correction that contains its own heard text does not loop",
                  dict([("ai", "AI tools")]).apply("use ai") == "use AI tools")

        // MARK: text that looks like a pattern is just text
        checkTrue("the heard text is not a pattern", dict([("a.b", "X")]).apply("axb a.b") == "axb X")
        checkTrue("the written text is not a template", dict([("price", "$1 \\0 $0")]).apply("the price") == "the $1 \\0 $0")
        checkTrue("a heard phrase ending in a symbol", dict([("c plus plus", "C++")]).apply("learn c plus plus today") == "learn C++ today")

        // MARK: entries that cannot work
        checkTrue("a blank heard phrase is ignored", dict([("", "x"), ("  ", "y")]).apply("hello world") == "hello world")
        checkTrue("an entry may write nothing, to drop a word", dict([("um", "")]).apply("so um yes") == "so  yes")

        // MARK: saving and loading
        var u = suite()
        checkTrue("nothing saved loads an empty dictionary", DictationDictionary.load(from: u).entries.isEmpty)
        let mine = dict([("ear shot", "Earshot"), ("kay eight s", "k8s")])
        mine.save(to: u)
        checkTrue("a saved dictionary loads back the same", DictationDictionary.load(from: u) == mine)
        u = suite(); u.set("this is not json", forKey: DictationDictionary.key)
        checkTrue("saved text that is not a dictionary loads empty", DictationDictionary.load(from: u).entries.isEmpty)
        u = suite(); u.set(42, forKey: DictationDictionary.key)
        checkTrue("a saved value of the wrong type loads empty", DictationDictionary.load(from: u).entries.isEmpty)
        u = suite(); dict([("", "x"), ("ok", "fine")]).save(to: u)
        checkTrue("blank entries do not survive a save and load",
                  DictationDictionary.load(from: u) == dict([("ok", "fine")]))
        u = suite(); mine.save(to: u); DictationDictionary().save(to: u)
        checkTrue("saving an empty dictionary clears it", DictationDictionary.load(from: u).entries.isEmpty)

        // MARK: the text form edited in Settings: one "heard => write" per line
        let typed = "ear shot => Earshot\n\n  kay eight s=>k8s  \nno arrow here\n => nothing heard\num =>\n"
        checkTrue("lines become entries, trimmed",
                  DictationDictionary(parsing: typed) == dict([("ear shot", "Earshot"), ("kay eight s", "k8s"), ("um", "")]),
                  "\(DictationDictionary(parsing: typed).entries)")
        checkTrue("empty text is an empty dictionary", DictationDictionary(parsing: "").entries.isEmpty)
        checkTrue("only the first arrow splits a line", DictationDictionary(parsing: "a => b => c") == dict([("a", "b => c")]))
        checkTrue("entries read back as one line each", mine.asText == "ear shot => Earshot\nkay eight s => k8s", mine.asText)
        checkTrue("the text form round-trips", DictationDictionary(parsing: mine.asText) == mine)
        checkTrue("an empty dictionary reads back as no text", DictationDictionary().asText == "")

        print("\(checks) checks, \(failures) failed")
        if checks < 26 { print("VACUOUS: only \(checks) checks ran, need 26"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
