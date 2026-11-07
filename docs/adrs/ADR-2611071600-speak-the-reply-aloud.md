# ADR-2611071600: Speak a short version of the assistant's reply aloud

**Status:** Accepted
**Date:** 2026-11-07
**Drivers:** The owner dictates to Claude Code with Earshot and wants the answer spoken back, so a
conversation needs no keyboard and no reading. Voicebox's page describes agents that speak through
the app; this is the smallest version of that idea.

## Context

Dictation plus "Press Return after typing" (ADR-2611071500) covers the speaking half. Nothing
speaks the reply. Earshot has no assistant of its own (a built-in one would need a cloud model, which
breaks "nothing leaves this Mac"), so Earshot stays the ears and mouth and the assistant is whatever
the owner connects. Here that is Claude Code, which can run a command when it finishes a reply.

## Decision

1. **A Stop hook runs `scripts/earshot-speak`.** It is a stdlib-only Python 3 script, like the other
   helpers. It reads the hook's JSON on stdin, takes the assistant's last reply (the
   `last_assistant_message` field if present, else the last assistant text after the last user
   message in `transcript_path`), turns it into a short speakable text, and says it with the macOS
   `say` command. Speech is local; nothing is sent anywhere.
2. **Off until switched on.** The hook does nothing unless the flag file `~/.earshot/voice-on`
   exists (`EARSHOT_STATE_DIR` overrides the directory). `earshot-speak on`, `off` and `status`
   manage it, so the owner can silence it in one command without editing settings.

   **Amendment, same day: one session at a time.** The first version spoke for every Claude Code
   session on the machine, because the hook is installed in user settings, so a reply finishing in
   another window or shell talked over the one the owner was dictating into. Now:
   - `earshot-speak on`, run from inside a Claude Code session, records that session's id
     (`CLAUDE_CODE_SESSION_ID`, which is the `session_id` the hook receives) in the flag file as
     `{"session_id": "..."}`. The hook speaks only for that session. Running `on` from another
     session moves the voice there.
   - `on --all` is the explicit opt-in to speak for every session (`{"all": true}`).
   - `on` with no session id and no `--all` (a plain terminal) refuses, with a message, and changes
     nothing: it cannot know which session is meant.
   - A flag file that is empty or unreadable counts as off. The earlier global empty flag is
     therefore retired, and `on` must be run again.
   - A hook payload with no `session_id` stays silent when the voice is bound to a session.
   - `status` prints `on` or `off` on the first line, and for `on` says on the second line whether
     it is bound to this session, to another session, or to all sessions.
3. **Short and speakable.** Fenced code, tables, bare URLs and markdown marks are removed, links keep
   their text, and the result is cut at a sentence boundary within 280 characters. If a reply had
   only code or tables, it says "Done. The details are on screen." Nothing is spoken for an empty
   reply.
4. **One voice at a time, and it can be stopped.** A new reply stops the previous speech first
   (the script keeps the speech process's pid in the state directory and kills only that one).
   `earshot-speak stop` stops speech at once.

   **Amendment, same day: the dictation hotkey stops the talk-back.** The owner asked that pressing
   the hotkey cut the voice off, so they can talk over it. Every hotkey press (the key going down, in
   hold or tap mode) now runs `earshot-speak stop` first, then dictation starts as before. The app
   does this only when `~/.earshot/speak.pid` exists, so it starts no process when nothing is
   speaking, and it runs `stop` through `/usr/bin/python3` in the background without waiting. The
   script is bundled into the app's Resources like `transcribe` and `speakers`, so a DMG install
   needs nothing in `~/.local/bin`. The decision (which command, or none) is a pure function,
   `SpeechStop.command(pidFileExists:scriptPath:)`, tested without any UI. A failed stop never
   affects dictation.
5. **The hook never gets in the way.** It exits 0 and prints nothing on every path, including bad
   input or a missing transcript, and it returns immediately: speech runs in a detached process.
6. **Hook installation is a separate step**: a `Stop` entry merged into the owner's Claude Code user
   settings next to the existing hooks. It is not part of the repo.

Not in this change: a voice choice setting, listening for speech to interrupt, speaking inside the
Earshot app, a "Speaking…" pill state, and neural voices. Those belong to the larger design
(an Earshot `speak` command for agents) that this change is meant to test first.

## Consequences

- The conversation loop works with no change to the Earshot app.
- Anyone within earshot (the pun is unavoidable) hears the replies while it is on.
- `say` reads whatever it is given, so the speakable-text rules are what keep it from reading code
  aloud; they are a heuristic and will miss odd cases.

## Implementation

Gate, written before the code: `python3 -I scripts/earshot-speak-test` exits 0. It tests the text
rules on hand-written inputs, then drives the real script as a hook with a fake `say` that records
what it was given. It covers the flag, both input shapes, one-voice-at-a-time, `stop`, and the
never-fail rules, and fails itself below its check floor. It also runs from `Tests/run.sh`.

## References

- ADR-2611071500-press-return-after-dictating
- ADR-2611071100-local-mcp-server-for-agents
- https://github.com/jamiepine/voicebox (GitHub page only)
