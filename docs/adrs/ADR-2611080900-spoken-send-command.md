# ADR-2611080900: A spoken "exclamation point" sends Control-Return

**Status:** Accepted
**Date:** 2026-11-08
**Drivers:** The owner works in Claude Code with dictation. Claude Code sometimes needs Control-Return to
wake the agent, which means reaching for the keyboard. They asked for the spoken words "exclamation point"
to send it.

## Context

"Press Return after typing" (ADR-2611071500) presses plain Return after every dictation, or never. It cannot
send a different key, and it cannot be decided per dictation. Whisper also adds a "!" by itself to any excited
sentence, so a typed "!" is not a usable signal.

## Decision

1. **A spoken command at the end of a dictation.** When the setting is on and the transcript ends with the
   words *exclamation point* or *exclamation mark* (any case, optional hyphen, any spaces or punctuation
   around them), Earshot removes those words and presses **Control-Return** after typing the rest. The
   remaining text is cleaned of a dangling comma or dash left by the removal.
2. **Only at the very end, only whole words.** "Use an exclamation point in the title" types as spoken.
   "Exclamation points are fun" and "nonexclamation point" are unchanged. A typed "!" never triggers.
3. **Saying only the command wakes the agent without typing.** If nothing is left after removing the words,
   Earshot types nothing and presses Control-Return.
4. **Control-Return replaces plain Return for that dictation.** Both are never sent. With the command, the key
   is Control-Return whether or not "Press Return after typing" is on. Without it, behaviour is exactly as before.
5. **Same safety as the paste.** The key is sent only when the text could be typed where the dictation started:
   not when the window changed (the paste guard, ADR-2611071800), not when Accessibility is missing, and not in
   a secure input field. In those cases nothing is sent. The log records that a key was pressed, never text.
6. **Opt-in, off by default** (Settings → Dictation → Submit: *Say "exclamation point" to send Control-Return*).
   A keystroke that sends cannot be undone, and anyone who really wants to type those words at the end of a
   sentence would otherwise lose them.
7. **Pure logic, tested without UI**: `SpokenSend.parse` and the key constants live in `SpokenSend.swift`;
   `DictationService` only performs the result.

Not in this change: other spoken commands, a custom trigger phrase, and Notes (they type nowhere).

## Consequences

- A hands-off way to wake or send in Claude Code and similar tools.
- The words "exclamation point" at the end of a sentence you want typed are swallowed while the setting is on.
  The Help and the guide say so.
- It depends on Whisper writing the words and not the symbol. When Whisper writes "!" instead, nothing happens;
  that is the safe failure.

## Implementation

Gate, written before the code: `bash EarshotApp/Tests/run.sh` exits 0 with new `SpokenSendTests` (the cases
above, the key constants and the preference), which fails itself below its check floor; the Help and the user
guide must name the command (`help-check.sh`, `scripts/readme-check`).

## References

- ADR-2611071500-press-return-after-dictating
- ADR-2611071800-never-paste-into-the-wrong-window
