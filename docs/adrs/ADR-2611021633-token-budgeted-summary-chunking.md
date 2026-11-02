# ADR-2611021633: Token-budgeted chunking for summaries

**Status:** Accepted
**Date:** 2026-11-02
**Drivers:** A summary failed because a long session transcript exceeded the on-device model's context window.

## Context

Summaries come from Apple's on-device model (`SystemLanguageModel`), which has a small context
window (about 4,096 tokens) that must hold the instructions, the `@Generable` schema, the prompt
**and** the response.

`Summarizer.summarize` (EarshotApp/Earshot.swift) already reduces long transcripts to notes first,
but sizes everything by **whitespace word count** against fixed constants (`maxWords = 1_100`,
`chunkWords = 900`), assuming ~1.2 tokens per word. That fails in four ways:

1. The ratio is optimistic. Speaker labels, numbers, names and misheard words tokenize worse.
2. Scripts without spaces (Japanese, Chinese, Thai) are one "word" per line, so a long line is
   never split.
3. The final call's budget ignores the `GeneratedSummary` schema and the size of the structured
   response (up to 6 sections × 6 points + 8 action items).
4. The reduce loop stops after 4 rounds and then sends whatever is left, however large, and never
   checks that a round actually shrank the material.

On macOS 26.4 (the app's deployment target) the SDK exposes `SystemLanguageModel.contextSize`
and `tokenCount(for:)` for prompts, instructions and generation schemas.

## Decision

Measure in **real tokens**, not words, and never send a request that does not fit.

- **Budgets** are computed from the model: `contextSize − tokens(instructions) − tokens(schema)
  − reserved response tokens − safety margin`, separately for the notes pass and the final
  summary pass.
- **Splitting** lives in a new pure module, `EarshotApp/Chunking.swift` (`TokenChunker`), with no
  FoundationModels dependency. It takes the text, a budget and an injected async token counter,
  and splits recursively on the coarsest boundary that works: lines (speaker turns), then words,
  then characters (for scripts without spaces). Every piece it returns is within budget per the
  counter, and the pieces together keep all the original text in order.
- **Map–reduce**: while the material is over the final budget, split it into notes-sized chunks,
  take notes on each, and join them. Each round must shrink the material; if it does not, or a
  round limit is reached, fail with a clear message instead of sending an oversized request.
- **Notes responses are capped** with `GenerationOptions(maximumResponseTokens:)` equal to their
  reserve, so the reserve is enforced, not assumed.
- **Overflow is a recoverable error**: if the model still reports the context window was exceeded
  (`LanguageModelSession.GenerationError.exceededContextWindowSize`), a notes chunk is halved and
  retried. The final pass is retried with a smaller budget, which forces one more reduce round.
  Both retries are bounded.

## Consequences

- Long and non-English transcripts summarize instead of failing; the failure mode that remains
  (material that will not shrink) is reported plainly.
- More `tokenCount` calls (roughly two per chunk). They run on-device and are cheap next to
  generation.
- Recursive halving yields chunks between about half and all of the budget, so a few more notes
  calls than a perfect packing would need. Accepted for simplicity.
- The splitter is unit-tested without the model, using a deterministic counter.

## Implementation

1. Add `EarshotApp/Chunking.swift` (`TokenChunker.split(_:budget:count:)`), and its tests in
   `EarshotApp/Tests/ChunkingTests.swift`, run by `EarshotApp/Tests/run.sh`.
2. Rewrite the budgeting/reduce part of `Summarizer.summarize` in `EarshotApp/Earshot.swift` to
   use token budgets, `TokenChunker`, response caps and bounded overflow retries. Remove
   `maxWords`, `chunkWords` and `wordCount`.
3. Add `Chunking.swift` to the `swiftc` lines in `EarshotApp/build.sh` and the test runner.

Gate: the app typechecks with all its sources and `bash EarshotApp/Tests/run.sh` exits 0.

## References

- EarshotApp/Earshot.swift — `enum Summarizer`, `Library.summarize`
- FoundationModels: `SystemLanguageModel.contextSize`, `SystemLanguageModel.tokenCount(for:)`,
  `GenerationOptions.maximumResponseTokens`,
  `LanguageModelSession.GenerationError.exceededContextWindowSize`
