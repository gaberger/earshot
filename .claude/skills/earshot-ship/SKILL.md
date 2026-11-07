---
name: earshot-ship
description: The gate-first way to build, test and commit a change in Earshot while another session shares the working tree. Use when about to write code, run the gate, build the app or commit.
---

# Shipping a change

1. **Decide** in an ADR under `docs/adrs/` (`hexa adr schema` gives the next id) and record it:
   `hexa loop adr <id>`.
2. **Gate before code.** Write the failing test or render scene first, record it with
   `hexa loop gate '<command>'`. A gate must fail for the right reason before the code exists, and must
   fail itself if it ran zero checks (see the `VACUOUS` guard in `EarshotApp/Tests/PasteGuardTests.swift`).
3. **Build with `hexa do run "<task>" --file <f> --also <g> --evidence "<cmd>"`.** The evidence for Swift
   changes: `cd EarshotApp && bash Tests/run.sh >/dev/null && swiftc -typecheck -swift-version 5
   -parse-as-library -target arm64-apple-macosx26.4 *.swift`. Read the diff of what it wrote: it passes
   quickly and can be wrong in ways the tests do not cover.
4. **Build the app** with `bash EarshotApp/build.sh` (it compiles `*.swift`, signs, installs to
   `~/Applications`). Relaunch with `pkill -x Earshot; open ~/Applications/Earshot.app`.
5. **Commit only your own files.** Another session works in the same tree and leaves untracked ADRs and
   folders (`site/`, `.claude/worktrees/`). Never `git add -A` blindly: `git status --short`, then
   `git add <paths>`. Use the commit trailer the harness gives.
6. **Update the checklist truthfully.** `hexa loop task done N` only for work that exists. If you marked a
   step by mistake, `hexa loop task undo N`.
7. **Docs in the same change:** `README.md`, the Help text (`bash EarshotApp/Tests/help-check.sh` fails when a
   feature name is missing from Help), and the Settings footnote.

## Pitfalls

- `hexa analyze .` cannot grade Swift ("no source files"); do not claim a grade.
- `hexa do run` restores everything when evidence fails; fix the evidence command, not the code.
- The gate list in `EarshotApp/Tests/run.sh` is appended to by every session; add your line at the end.

## Running the reviewer agents (`.claude/agents/`)

- The harness hook blocks a custom agent unless it runs with `isolation: "worktree"`, **but a worktree is a
  checkout of the default branch (release 1.0.4), not of the branch you are on**: a code reviewer there finds
  none of the new files and reports "cannot review". Only the design reviewer, which reads PNGs in `/tmp`,
  works that way.
- For code and privacy reviews use the read-only `Explore` agent and tell it to read
  `.claude/agents/<name>.md` first and to work only in the live tree. Check the first lines of the
  report for "file not found" before you trust it.
- A review is a list of claims, not facts. Read the lines it cites before fixing (two of this session's
  claims were right and were found that way; verify all of them).
