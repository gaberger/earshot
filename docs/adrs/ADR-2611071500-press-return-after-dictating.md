# ADR-2611071500: Press Return after dictating

**Status:** Accepted
**Date:** 2026-11-07
**Drivers:** The owner dictates into chat boxes and prompts and has to press Return by hand after
every dictation. They want Earshot to do it.

## Context

Dictation pastes the transcript into the focused field and stops. Whatever "accept" means there
(send a message, run a command, submit a form) needs a Return key press.

## Decision

1. **An opt-in setting, "Press Return after typing"** (Settings → Dictation), **off by default**.
   A Return press can send a message or submit a form, and that cannot be taken back, so Earshot
   does not do it until the owner turns it on. (The owner asked for the behaviour; the default only
   protects people who never asked for it.)
2. **When it is on, Return is sent once, right after a successful paste**, not at the moment the key
   is released: the text only exists after transcribing and cleanup, so Return follows the text. It is
   sent to the app that received the paste, about 0.2 s after the paste, so the app has the text first.
3. **Return is never sent when:**
   - the setting is off;
   - the text is empty or only whitespace;
   - the text did not get typed, i.e. Accessibility is missing and the text was left on the clipboard
     for the user to paste (a Return then would act on the wrong thing);
   - secure input is on (a password field).
4. **The decision is a pure function**, `DictationSubmit.shouldSendReturn(enabled:text:pasted:secureInput:)`
   in `Dictation.swift`, tested without any UI. The service only does what it says.
5. **Same path for every insert**, including "Retry last dictation".
6. Notes are not affected: they type into no other app.

Not in this change: other submit keys (⌘Return, Shift-Return), a spoken "send it" command, and a
per-app list of where Return is sent.

## Consequences

- One less key press per dictation, for those who opt in.
- In a field where Return adds a new line instead of submitting, the owner gets a trailing new line.
  That is the app's meaning of Return, and the setting is easy to turn off.

## Implementation

Gate, written before the code: `bash EarshotApp/Tests/run.sh` exits 0 with new `SubmitTests` (the
decision table above, and the preference: off by default, only a Bool counts), which fails itself
below its check floor, and the app typechecks.

## References

- ADR-2611061900-dictate-into-any-app
- ADR-2611071400-highlight-the-dictation-target-window
