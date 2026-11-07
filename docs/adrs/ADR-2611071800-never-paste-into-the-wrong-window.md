# ADR-2611071800: Never paste into a window you did not dictate into

**Status:** Accepted
**Date:** 2026-11-07
**Drivers:** The owner: "if you switch out of the window before the transcription lands, the transcription
could wind up in the wrong window. Can we prevent a user from switching to another window?"

## Context

Dictation pastes into whichever app is in front *when the transcript arrives*, which can be seconds after
the key was released. If the user switched windows in between, the text is typed somewhere they did not
mean, and a paste cannot be taken back. An app cannot, and should not, stop the user switching windows. What
it can do is refuse to type into a different window than the one the dictation started in.
ADR-2611071400 already reads the target window (as a rectangle) at key-down to outline it.

## Decision

1. At key-down, remember the **target**: the frontmost app's process id and its focused window's frame
   (position and size). Nothing else: no title, no text. The same read ADR-2611071400 does.
2. When the transcript is ready, read the current target the same way and decide, as a pure function
   (`PasteGuard.decide`):
   - **paste** when the target is the same app and the same window (frames within 8 pt), or when either
     side could not be read (no Accessibility, no window): we cannot tell, so behaviour is as before;
   - **hold** when the app differs, or the same app's focused window differs.
3. On **hold**: do not paste. Put the text on the clipboard as plain text (the only copy, so no
   clipboard-manager exclusion markers) and notify: "You switched windows, so what you said is on the clipboard.
   Press ⌘V where you want it." The dictation counts as finished.
4. Not done: bringing the original window back to the front (it would take focus away from what the user is
   doing now), and blocking window switching (not possible, and not wanted).

## Consequences

- A safer paste. Cost: a user who deliberately moves to another field in the same window is not stopped
  (the window is the same); one who moves the dictation window by more than 8 pt mid-dictation is told the
  text is on the clipboard.
- A false "hold" is harmless (the text is one ⌘V away); a false "paste" is not. The rule leans to hold.

## Implementation

Gate: `bash EarshotApp/Tests/run.sh` with `PasteGuardTests` (pure), plus the existing suites.

## References

- ADR-2611071400-highlight-the-dictation-target-window
- ADR-2611061900-dictate-into-any-app
