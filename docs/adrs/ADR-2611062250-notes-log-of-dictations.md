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

## Amendment 2026-11-06: Notes is the in-app recorder

The owner: "Notes has to have a record button so it differentiates from [dictation into other apps]. We're
going to be an in-app transcriber." So there are three areas, and the difference is where the words go:

| Area | You start it with | The words go to |
|---|---|---|
| Recordings | Record (meetings, calls) | a recording: transcript, speakers, summary |
| **Notes** | **a Record button on the Notes page** | **a note in Earshot** (nothing is typed anywhere) |
| Dictation | a hotkey, in any app | the app in front (and, if the log is on, a copy in Notes) |

1. The Notes page gets a Record button. Press it, speak, press Stop: the audio is transcribed on this Mac,
   corrected with the user's dictionary, saved as a note with the app "Earshot", and the audio is deleted.
2. Rules, as pure logic with tests (`NoteSession`): a note will not start during a meeting recording or
   while a dictation is in progress; under one second is thrown away; it stops by itself after ten
   minutes; an empty or failed transcript saves nothing and says so.
3. **Superseded by the next amendment:** dictation no longer writes to Notes.

## Amendment 2026-11-06 (later): three functions, fully separate

The owner: "need to separate the two functions, there are three functions: recordings, personal notes and
dictation." Dictation had been writing a copy of what it typed into Notes, and the Dictation page carried the
log switch. That mixed two functions. Decision:

1. **Recordings** (meetings): unchanged.
2. **Notes**: only what the user records on the Notes page with its Record button. Stored as text on this
   Mac (`~/Library/Application Support/Earshot/notes.json`); the audio is deleted at once.
3. **Dictation**: types into the app in front and **keeps nothing**, as in ADR-2611061900. It no longer
   writes to Notes. The `DictationPrefs.keepLog` switch, the "Notes log" section of the Dictation page and
   the dictation-to-notes hook are removed.
4. The three areas share no data and no settings page. The shared dictionary (corrections) applies to both
   Notes and Dictation transcripts because it is about the user's vocabulary, not about either function.
5. The privacy text returns to: dictation keeps nothing; Notes keeps the text of notes you record.
