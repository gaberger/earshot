# ADR-2611062250: A notes log of what you dictate

**Status:** Accepted
**Date:** 2026-11-06
**Drivers:** The owner separated three things: recordings (meetings), dictation into other apps, and a personal
notes log of what was dictated, "kind of what OpenSuperWhisper looks like". Earshot only does the second:
the text is pasted and forgotten. The owner asked for the log and for dictation into any app to keep working.

## Context

OpenSuperWhisper has one dictation hotkey. Each dictation types into the app in front *and* is kept in a
feed, newest first, grouped by day: the text, the app it went to, how long it took. Earshot's dictation
(ADR-2611061900) deliberately kept nothing ("the audio is not kept"); keeping the text is a new privacy
position and is recorded here.

## Decision

1. **Every successful dictation is kept as a note**: the text, the time, the name of the app it was typed
   into, and how many seconds the key was held. **Text only. Audio is still deleted at once.**
2. Notes are stored **only on this Mac**, in `~/Library/Application Support/Earshot/dictations.json`
   (not the Recordings folder, not UserDefaults). At most 2,000 notes; the oldest are dropped.
3. A switch, **Keep a log of what I dictate**, in Settings → Dictation. It is on, because the log is the
   feature; turning it off stops saving, and **Clear all notes** deletes the file. Nothing typed into a
   secure (password) field is ever saved, because dictation never reaches the insert step there.
4. A new sidebar area **Notes** shows the log: day-grouped feed, each row with the time, the text and
   "app · seconds"; copy, delete, clear all. ⌘K search finds notes.
5. **Dictation into any app is unchanged** and keeps its own page for the shortcut, mode, corrections
   and permission. A later step adds "Dictate a note" inside Earshot, saved without typing anywhere.

## Consequences

- What you say is now at rest on disk (as text). The README and the Settings text must say so.
- A corrupt log file is never silently replaced: it is moved aside to `dictations.json.bad` and the log
  starts empty, so nothing is overwritten.
- The log is pure logic (`DictationLog`) with tests; the service only reports "this was dictated".

## Implementation

Gate: `bash EarshotApp/Tests/render.sh && bash EarshotApp/Tests/run.sh`, with new `DictationLogTests`.

## References

- ADR-2611061900-dictate-into-any-app
- ADR-2611062130-restyle-the-whole-app
