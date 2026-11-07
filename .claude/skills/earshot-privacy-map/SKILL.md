---
name: earshot-privacy-map
description: Which of Earshot's three functions keeps what, and where each privacy promise is written. Use when a change touches audio, transcripts, notes, logging, the clipboard or wording about privacy.
---

# Three functions, three promises

| Function | Started by | Words go to | Kept |
|---|---|---|---|
| **Recordings** | Record (meetings, calls) | a recording: transcript, speakers, summary | audio and text in `~/Recordings/whisper` |
| **Notes** | **Record a note** on the Notes page | a note in Earshot | the text only, in `~/Library/Application Support/Earshot/notes.json`; audio deleted at once |
| **Dictation** | the hotkey, in any app | the app in front | nothing. Exceptions: one failed clip in the temp folder until the next dictation; the clipboard in the two fallbacks (no Accessibility, or you switched windows) |

The three share no data and no settings page. They share one thing on purpose: the corrections dictionary
(`EarshotApp/DictationDictionary.swift`), which is the user's vocabulary.

## Where the promise is written (change all of them together)

- `README.md` (Dictation and Notes sections)
- the Settings footnote in `EarshotApp/DictationSettingsView.swift`
- the in-app Help (`bash EarshotApp/Tests/help-check.sh` guards the feature names)
- `docs/adrs/ADR-2611062250-notes-log-of-dictations.md` (both amendments)

## Never

- Log transcript or note text. Never put either in a log line, a notification title, or an error.
- Type into a secure field (the session never emits an insert while secure input is on).
- Leave a recorded audio file on any path, including failures. Ask the `privacy-auditor` agent
  (`.claude/agents/privacy-auditor.md`) to check after any change here.
