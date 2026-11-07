# ADR-2611061900: Dictate into any app

**Status:** Accepted
**Date:** 2026-11-06
**Drivers:** The user asked whether Earshot can do speech to text inside any app, such as filling out a
form. Earshot already records and transcribes with whisper.cpp, but only into its own library, after
the recording stops.

## Context: it is feasible

macOS lets a menu bar app type into whatever app has focus. Three pieces are needed:

1. **A global hotkey** to start and stop dictation (hold-to-talk or toggle), from any app.
2. **Short-utterance transcription.** Today `transcribe` runs on a finished file. Dictation needs the
   same engine on a few seconds of audio, fast enough to feel instant. Two routes: run whisper.cpp on
   each utterance once the user releases the key (simple, reuses the shipped script), or stream with
   Apple's `SpeechAnalyzer` (live words, but a second engine to keep in step with the first).
3. **Inserting the text** into the focused field. Two routes:
   - *Paste:* put the text on the pasteboard and post ⌘V (restore the old pasteboard after). Works in
     nearly every app. Needs the **Accessibility** permission to post the key event.
   - *Accessibility API:* set the focused element's value or selected text. Cleaner, but many web
     forms and Electron apps do not expose it.

## Decision (proposed)

Build it as a separate, opt-in mode, `Dictate`, off by default, behind **Settings → Dictation**.

1. **Pure core.** A `DictationSession` state machine (idle → listening → transcribing → inserting) with
   no AppKit, tested the way `CallStartDetector` is. Its inputs are key down/up and the transcript;
   its outputs are "start capture", "stop capture", "insert <text>".
2. **Engine: whisper.cpp per utterance** for the first version, so quality and the language/model
   settings match recordings. Revisit streaming only if latency is felt.
3. **Insertion: paste, then restore the pasteboard**, with the Accessibility permission requested the
   first time the user turns Dictation on, and a plain explanation of why.
4. **Never record without the key held.** The microphone indicator must be on only while the key is
   down. No audio from dictation is kept unless the user turns that on.
5. **Secure fields are skipped.** Do not insert into password fields (secure input is on).
6. **Separate from meeting recording.** Dictation must not start, stop or end a meeting recording, and
   the call-start detector must ignore Earshot's own dictation capture (it already ignores Earshot).

## Open questions

- ~~Hold-to-talk or press-to-toggle as the default, and which default key.~~ Decided: hold-to-talk,
  default Control+Option+Space, user-changeable (see Amendment).
- Does a model load per utterance feel too slow? If so, keep a warm process.
- Punctuation and capitalisation: whisper adds them; is a spoken "new line" command wanted?

## Consequences

- A new permission (Accessibility) on top of Microphone and Notifications. The DMG is not notarized,
  so macOS may need the user to re-grant it after an update.
- The first sandbox-free feature that touches other apps; it deserves its own hardening pass.

## Amendment 2026-11-06: changeable shortcut and a listening indicator

1. **The shortcut is a setting.** `HotKey` (`EarshotApp/HotKey.swift`, pure, tested) holds a key code and
   Carbon modifiers, saved as two integers. Settings → Dictation → Shortcut records the next key press.
   A shortcut is valid only with Control or Option, or as a function key, so it cannot steal ordinary
   typing; Escape, Control+Space and Control+Tab are refused. A saved value that is missing, mistyped or
   no longer valid falls back to the default rather than registering something surprising.
2. **A taken shortcut is reported once.** If another app owns the chosen keys, registration fails, the
   user is told, and Earshot does not retry until the setting changes.
3. **A visible indicator.** While capturing, a floating non-activating panel (`DictationHUD`) shows
   "Listening…" with a live level bar, then "Transcribing…". It never becomes key or main window, so the
   field being dictated into keeps focus, and it announces the text to VoiceOver. What it says is
   decided by the core (`State.indicatorText`, `showsLevel`), so it is tested without a window.
