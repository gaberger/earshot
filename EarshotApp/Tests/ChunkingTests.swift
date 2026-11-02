// Tests for token-budgeted chunking, with deterministic counters instead of a real tokenizer.
// Run: bash EarshotApp/Tests/run.sh
import Foundation

var failures = 0
func check(_ name: String, _ got: String, _ want: String) {
    let ok = got == want
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; print("--- want ---\n\(want)\n--- got ---\n\(got)\n---") }
}
func checkTrue(_ name: String, _ ok: Bool) { print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1 } }

func words(_ s: String) -> [String] { s.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
let wordCount: TokenChunker.Count = { words($0).count }
let charCount: TokenChunker.Count = { $0.count }
struct Boom: Error {}

@main struct ChunkingTests {
    static func main() async {
        do {
            let short = "Gary: Hello there."
            let one = try await TokenChunker.split(short, budget: 10, count: wordCount)
            check("text that fits returns one piece", one.joined(separator: "|"), short)
            checkTrue("text that fits returns exactly one piece", one.count == 1)

            let empty = try await TokenChunker.split("", budget: 10, count: wordCount)
            checkTrue("empty text returns no pieces", empty.isEmpty)
            let blank = try await TokenChunker.split("  \n\t ", budget: 10, count: wordCount)
            checkTrue("whitespace-only text returns no pieces", blank.isEmpty)

            let speakers = ["Gary", "Ana", "Ken"]
            let transcript = (0..<40).map { i in
                "\(speakers[i % 3]): point number \(i) about the Acme renewal and its budget"
            }.joined(separator: "\n")
            let pieces = try await TokenChunker.split(transcript, budget: 30, count: wordCount)
            checkTrue("transcript splits into several pieces", pieces.count > 1)
            checkTrue("transcript pieces fit the budget", pieces.allSatisfy { words($0).count <= 30 })
            check("transcript words survive in order",
                  pieces.flatMap(words).joined(separator: " "), words(transcript).joined(separator: " "))
            checkTrue("transcript pieces keep whole lines", pieces.allSatisfy { $0.split(separator: "\n").allSatisfy { words(String($0)).count == 11 } })

            let longLine = (0..<500).map { "word\($0)" }.joined(separator: " ")
            let linePieces = try await TokenChunker.split(longLine, budget: 37, count: wordCount)
            checkTrue("long line splits into several pieces", linePieces.count > 1)
            checkTrue("long line pieces fit the budget", linePieces.allSatisfy { words($0).count <= 37 })
            check("long line words survive in order", linePieces.flatMap(words).joined(separator: " "), longLine)

            let japanese = String(repeating: "会議の議事録", count: 2000 / 6 + 1).prefix(2000)
            let jp = String(japanese)
            checkTrue("japanese fixture is 2000 characters", jp.count == 2000)
            let jpPieces = try await TokenChunker.split(jp, budget: 100, count: charCount)
            checkTrue("unspaced text splits into several pieces", jpPieces.count > 1)
            checkTrue("unspaced pieces fit the budget", jpPieces.allSatisfy { $0.count <= 100 })
            check("unspaced pieces concatenate to the original", jpPieces.joined(), jp)

            let single = try await TokenChunker.split("会議", budget: 1, count: { _ in 5 })
            check("a single character over budget is kept", single.joined(separator: "|"), "会|議")
        } catch {
            failures += 1; print("FAIL unexpected error", error)
        }

        do {
            _ = try await TokenChunker.split("anything at all", budget: 5, count: { _ in throw Boom() })
            checkTrue("a throwing counter propagates its error", false)
        } catch is Boom {
            checkTrue("a throwing counter propagates its error", true)
        } catch {
            checkTrue("a throwing counter propagates its own error", false)
        }

        print(failures == 0 ? "All chunking tests passed" : "\(failures) chunking test(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
