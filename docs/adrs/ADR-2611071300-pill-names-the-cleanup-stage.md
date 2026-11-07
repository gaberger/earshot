# ADR-2611071300: The dictation pill names the cleanup stage

**Status:** Accepted
**Date:** 2026-11-07
**Drivers:** Voicebox's page describes a floating pill with a separate `refining` state between
`transcribing` and the end. Earshot now has the same stage (ADR-2611071000) but its pill still says
"Transcribing…" while the model tidies the text, which can take seconds. Only the GitHub page text
was read (its screenshots carry no alt text), so this borrows an idea, not a design.

## Decision

1. While the cleanup model is running, the pill says **Tidying…** (with the same spinner) instead of
   **Transcribing…**. Nothing else about the pill changes.
2. The wording is a pure function, `DictationSession.State.indicatorText(tidying:)`, so it is tested
   without any UI. The existing `indicatorText` stays and means `indicatorText(tidying: false)`.
3. `DictationSession` (the state machine) is **not** changed. "Tidying" is a sub-stage of
   transcribing that only the service knows about, so the service holds a flag and passes it to the
   pill. The flag is cleared on every path out of cleanup, including the 5-second timeout.
4. VoiceOver is told the new text, as it is for the other stages.

Not adopted: Voicebox's `speaking` state (no speech output) and a per-stage color.

## Implementation

Gate, written before the code: `bash EarshotApp/Tests/run.sh` exits 0 with five new checks in
`CleanupTests` (floor raised from 19 to 24), and the app typechecks.

## References

- ADR-2611071000-dictation-cleanup-with-on-device-model
- ADR-2611061900-dictate-into-any-app
- https://github.com/jamiepine/voicebox (GitHub page only)
