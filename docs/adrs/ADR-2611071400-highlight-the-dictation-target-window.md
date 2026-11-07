# ADR-2611071400: Highlight the window dictation will type into

**Status:** Accepted
**Date:** 2026-11-07
**Drivers:** The owner wants to see which window a dictation is going to land in. Super Whisper was
described as showing a marker on the target; its UI was not seen, so this is the owner's intent, not a
copy of it.

## Context

Dictation pastes into whichever app has focus. The pill sits at the bottom of the screen and says
nothing about where the text will go. With several windows open, or several displays, it is easy to
dictate into the wrong one, and a paste cannot be taken back.

## Decision

1. **Set the target window alight** while dictation is listening or transcribing: little flames
   licking up from the edges of the focused window of the frontmost app, over a thin warm glow. It is
   removed when the text is inserted or the dictation fails or is cancelled. (Amended the same day:
   the owner asked for "a little flaming fire" instead of a plain border.) The look has three styles,
   chosen by a pure function of the dictation state and the Reduce Motion setting:
   - **flames** while listening: a particle fire along the window's edges (orange to yellow, additive,
     rising, short-lived), drawn with a Core Animation emitter and a gradient dot generated in code, so
     no image asset is added;
   - **embers** while transcribing or tidying: the same fire turned low and dim, so "heard you, working"
     reads differently from "listening";
   - **border** when Reduce Motion is on: no animation at all, just a static warm rounded border and
     glow. Motion is never forced on someone who asked for less.
   - **none** when dictation is idle or inserting.
2. **The target is read once, at key-down.** Earshot reads only the geometry (position and size) of
   the frontmost app's focused window through the Accessibility permission dictation already
   requires. It reads no window title, no text, nothing from a secure field, and nothing when secure
   input is on. The outline does not follow the window if it moves mid-dictation.
3. **The overlay is click-through and never takes focus**, like the pill, so the paste still lands in
   the right place. It is drawn above normal windows, as a border only (the inside is transparent).
4. **Do nothing rather than guess.** No outline if the frontmost app is Earshot itself, if the window
   reports no frame, if it is under 40 pt in either direction, or if it lies off every screen.
5. **Pure logic, tested without UI** in `WindowHighlight.swift`:
   - converting an Accessibility frame (origin top-left of the primary screen, y down) to an AppKit
     frame (origin bottom-left, y up): `y = primaryHeight - (axY + height)`;
   - choosing the outline rectangle: the window grown by a 4 pt margin and clamped to the screen
     it sits on, or nothing;
   - which dictation states show it (listening and transcribing; not idle or inserting).
6. **A setting**, "Highlight the window I'm dictating into" (Settings → Dictation), **on by default**,
   because it only draws. A wrongly typed saved value reads as the default, on.

Not in this change: following the window or the caret, a different color per state, highlighting for
Notes (they type nowhere), and dimming the other windows.

## Coordinate system

Accessibility and CGWindow frames: origin at the top-left of the primary display, y increases
downward, other displays can have negative x or y. AppKit: origin at the bottom-left of the primary
display, y increases upward. Both measure from the primary display, so one conversion with the
primary display's height covers every screen.

## Consequences

- A safer paste, at the cost of a colored border over other windows for the length of a dictation.
- Another use of the Accessibility permission, but no new permission.
- Some apps report no focused window (a few full-screen or helper windows): no outline, no harm.

## Implementation

Gate, written before the code: `bash EarshotApp/Tests/run.sh` exits 0 with new `HighlightTests`
(hand-written rectangles including a second display to the right and one above the primary, a
window overflowing the screen, tiny and off-screen windows, the state table, and the preference),
which fails itself below its check floor, and the app typechecks and builds with `build.sh`'s
file glob. The look itself is checked by running the app and reading what it draws, not by tests.

## References

- ADR-2611061900-dictate-into-any-app
- ADR-2611071300-pill-names-the-cleanup-stage
