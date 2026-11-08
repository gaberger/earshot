# ADR-2611080900: A spoken "bang" sends Control-Return

**Status:** Accepted
**Date:** 2026-11-08
**Drivers:** The owner works in Claude Code with dictation. Claude Code sometimes needs Control-Return to
wake the agent, which means reaching for the keyboard. They asked for a spoken word to send it. They first
asked for "exclamation point", then, before anything was released, chose **"bang"** as the better word.

## Context

"Press Return after typing" (ADR-2611071500) presses plain Return after every dictation, or never. It cannot
send a different key, and it cannot be decided per dictation. Whisper also adds a "!" by itself to any excited
sentence, so a typed "!" is not a usable signal. A single short spoken word is quicker to say than a
two-word phrase.

## Decision

1. **A spoken command at the end of a dictation.** When the setting is on and the transcript ends with the
   word *bang* (any case, any spaces or punctuation around it), Earshot removes that word and presses
   **Control-Return** after typing the rest. The remaining text is cleaned of a dangling comma or dash left by
   the removal. "Exclamation point" and "exclamation mark" are **not** commands.
2. **Only at the very end, only the whole word.** "The door went bang in the night" types as spoken.
   "Bangs", "Bangkok" and "gobang" are unchanged. A typed "!" never triggers.
3. **Saying only the command wakes the agent without typing.** If nothing is left after removing the word,
   Earshot types nothing and presses Control-Return.
4. **Control-Return replaces plain Return for that dictation.** Both are never sent. With the command, the key
   is Control-Return whether or not "Press Return after typing" is on. Without it, behaviour is exactly as before.
5. **The command is read before anything else touches the text.** It is taken off the raw transcript before the
   tidy-up pass and the dictionary run, so neither can rewrite it. Tidy-up and the dictionary then see only the
   rest.
6. **Same safety as the paste.** The key is sent only when the text could be typed where the dictation started:
   not when the window changed (the paste guard, ADR-2611071800), not when Accessibility is missing, and not in
   a secure input field. In those cases nothing is sent. The log records that a key was pressed, never text.
7. **Opt-in, off by default** (Settings → Dictation → Submit: *Say "bang" to send Control-Return*). A keystroke
   that sends cannot be undone, and anyone who really wants to type that word at the end of a sentence would
   otherwise lose it.
8. **Pure logic, tested without UI**: `SpokenSend.parse` and the key constants live in `SpokenSend.swift`;
   `DictationService` only performs the result.

Not in this change: other spoken commands, a custom trigger word, and Notes (they type nowhere).

## Consequences

- A hands-off way to wake or send in Claude Code and similar tools, with a one-syllable word.
- **A known trade-off, written into the tests:** "bang" is a real English word, so a sentence that genuinely
  ends with it ("we opened with a bang") is taken as the command while the setting is on. It is opt-in for that
  reason. "Exclamation point" was rarer at the end of a sentence; the owner preferred the shorter word.
- It depends on Whisper writing the word and not a symbol. When it writes something else, nothing happens;
  that is the safe failure.

## Implementation

Gate, written before the code: `bash EarshotApp/Tests/run.sh` exits 0 with `SpokenSendTests` (the cases above,
the key constants and the preference), which fails itself below its check floor; `order-check.sh` keeps the
command ahead of the tidy-up; the Help and the user guide must name the command (`help-check.sh`,
`scripts/readme-check`).

## References

- ADR-2611071500-press-return-after-dictating
- ADR-2611071800-never-paste-into-the-wrong-window
