# ADR-2611071000: Dictation cleanup with the on-device model

**Status:** Accepted
**Date:** 2026-11-07
**Drivers:** A comparison with jamiepine/voicebox (a local voice studio) showed one idea that fits
Earshot: its dictation hotkey can refine the transcript with a small local LLM. Only the public
GitHub page was read, so the idea is borrowed, not copied code.

## Context

Dictation pastes Whisper's raw text, minus the user's dictionary corrections (ADR-2611062045). Spoken
language leaves "um", "uh", repeated words and loose punctuation in that text. Earshot already ships
Apple's on-device Foundation Models for summaries, so cleanup needs no new dependency, model
download or network use.

## Decision

1. **Opt-in cleanup pass.** A setting, "Tidy up what I say" (Settings → Dictation), off by default.
   When on, the transcript goes through the on-device model with an instruction to remove fillers
   and stutters and fix punctuation and capitalization, and nothing else.
2. **A guard decides whether to trust the model.** Pure logic in `DictationCleanup.swift`. The
   cleaned text is used only if it is non-empty, not much longer or shorter than the original, and
   keeps every number from the original. Otherwise the original is typed. A model that is
   unavailable, errors, or takes more than 5 seconds also means the original is typed. Cleanup can
   make dictation slightly slower; it must never make it fail or change meaning.
3. **Order:** cleanup first, then the dictionary, so the user's corrections have the last word.
4. **Privacy is unchanged.** The text stays on this Mac, Private Cloud Compute is never used, and
   nothing is stored. Notes are **not** covered: `NoteRecorder` has its own transcribe step that
   applies the dictionary only. Giving Notes the same cleanup is a follow-up, and needs the
   `tidy` closure passed to `NoteRecorder` as well.

Not adopted from Voicebox: text to speech, voice cloning, the timeline editor, effects, multiple
engines, a Python backend. They are a different product (speech generation) and would add
dependencies that break Earshot's "one app, nothing to start" shape. An MCP/HTTP interface for
agents is worth its own ADR and is not part of this change.

## Consequences

- Cleaner dictated text at the cost of up to a few hundred milliseconds, only when opted in.
- A small model can paraphrase. The guard bounds the damage but is a heuristic, which is why the
  setting is off by default and the README says the text may be reworded.
- Needs Apple Intelligence, like summaries. When it is off, cleanup silently falls back to the raw
  text and the log (never the text) records why.

## Implementation

Gate, written before the code: `bash EarshotApp/Tests/run.sh` exits 0 with new `CleanupTests`
covering: accepts a tidier text; rejects empty, runaway-long and much-shorter output; rejects output
that drops or changes a number; identical text is accepted; and the check count is above its floor
so the gate cannot pass vacuously. The app target must also typecheck.

## References

- ADR-2611061900-dictate-into-any-app
- ADR-2611062045-dictation-dictionary-and-tap-to-toggle
- https://github.com/jamiepine/voicebox (GitHub page only)
