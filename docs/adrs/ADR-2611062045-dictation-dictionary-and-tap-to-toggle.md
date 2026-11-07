# ADR-2611062045: Dictation dictionary, tap-to-toggle, and never losing what was said

**Status:** Accepted
**Date:** 2026-11-06
**Drivers:** A look at the public README of my-monkeys/OpenSuperWhisper (a larger macOS dictation app)
showed three ideas that fit Earshot's small, opt-in Dictate mode (ADR-2611061900). Nothing was read
beyond that README, so the ideas are borrowed, not copied code.

## Context

Dictate holds a shortcut, transcribes with whisper.cpp, and pastes the text. Three gaps:

1. **Whisper mishears names and jargon** ("Earshot" becomes "ear shot"), and the user can only fix it
   by hand each time.
2. **Hold-to-talk is the only mode.** A long dictation means holding keys for the whole time.
3. **Failure handling is unchecked.** It is not known what the user sees, or keeps, when whisper
   errors or returns nothing.

## Decision

Do these in order, each its own gated change:

1. **Dictionary of corrections.** Pairs of "heard" to "write", applied to the transcript before it is
   inserted. Whole-word, case-insensitive match; the longest phrase wins; applied once, so one
   correction's output is never rewritten by another. Pure logic in `Dictation.swift` with no AppKit,
   edited in Settings → Dictation with a live test field.
2. **Tap-to-toggle.** A second mode beside hold-to-talk: tap to start, tap again to stop. Held
   shortcuts keep working. A pure state-machine change in `DictationSession`.
3. **No lost dictation.** If transcription fails or is empty, tell the user plainly and keep the
   audio long enough to retry once. This overrides "audio is not kept" only for the failed utterance,
   only until the next dictation, and is never written to the library.

Not adopted: multiple engines, remote endpoints, a history feed, per-app style rules, and the agent
answer panel. They are out of scope for an opt-in mode.

## Consequences

- Better accuracy on names with little code, and it is easy to test.
- A new stored setting (the dictionary) that must survive the same write/read shape rule as `HotKey`:
  a bad saved value falls back to empty and is never silently discarded.
- Item 3 relaxes a privacy promise, so the Settings text and README must say so.

## Implementation

Gate for item 1 (written before the code): `bash EarshotApp/Tests/run.sh` exits 0 with new
`DictionaryTests` checks (longest match, whole word, no re-correction, bad saved value, empty
dictionary is a no-op), and the check count is greater than 32 so the gate cannot pass vacuously.
Record with `hexa loop gate`, then `hexa do run`.

## References

- ADR-2611061900-dictate-into-any-app
- https://github.com/my-monkeys/OpenSuperWhisper (README only)
