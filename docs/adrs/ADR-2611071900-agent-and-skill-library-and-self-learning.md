# ADR-2611071900: An agent and skill library for Earshot, and a way to learn from ourselves

**Status:** Accepted
**Date:** 2026-11-07
**Drivers:** The owner: "make sure we have skills and agent libraries for our agent definitions, and that we
can self-learn from ourselves such that we can improve." Two designers are working in the same repository
and every session starts from nothing: `.claude/agents/` does not exist, the 14 skills are generic hexa
ones, and `hexa memory` is empty although this project has paid for several lessons.

## Context

Mistakes made in the last sessions, each of which a written rule would have prevented:

1. A screen was judged from one render at a comfortable width; at the real, narrow width times wrapped and
   cards truncated. The owner found it, not us.
2. A checklist step was marked done that was not built.
3. Dictation and Notes were merged into one idea before the owner had separated three functions.
4. Every rebuild lost the Accessibility permission: the ad-hoc signature identified the app by the hash of
   the binary.
5. A render showed yellow placeholder boxes for native controls (`ImageRenderer`), and `render.sh` deletes
   the PNGs it is about to be read from.
6. Two sessions share one working tree; a blanket `git add -A` would sweep up the other's untracked files.

## Decision

1. **Agents** live in `.claude/agents/<name>.md`, one role each, **read-only** (tools limited to Read, Grep,
   Glob) because a reviewer that can edit is no longer independent. The first three: `ui-designer` (reviews
   renders against the references, at wide and narrow widths), `privacy-auditor` (what is kept, what
   leaves the Mac, what is logged), `swift-reviewer` (AppKit/SwiftUI pitfalls in a diff).
2. **Skills** live in `.claude/skills/earshot-*/SKILL.md`, each encoding a workflow with the commands that
   work here: `earshot-ui-change`, `earshot-ship`, `earshot-permissions`, `earshot-privacy-map`,
   `earshot-retro`. A skill names real paths, and the check fails if a path it cites does not exist.
3. **Learning is a loop, not a document.** At the end of a piece of work run `earshot-retro`: list the
   unrouted follow-ups (`hexa insight punch-list`), the checklist steps marked done (`hexa loop`) against
   the commits, and the owner's corrections; store each lesson with `hexa memory store lesson:<topic>`;
   when the same lesson is stored twice, promote it into the skill it belongs to. The project store
   (`.hexa/memory.jsonl`) is seeded with the six lessons above.
4. **The library is gated.** `bash scripts/agents-check` fails on: fewer than 3 agents or 5 earshot
   skills (never passes on an empty scan); a missing or mismatched `name:`; an empty `description:`; a
   skill description without "Use when"; an agent with a tool other than Read, Grep or Glob; a repo path
   cited in backticks that does not exist; fewer than 6 `lesson:` entries in the project memory.
5. Not done: hooks that run the retro automatically (they change `settings.json`, which is the owner's
   to approve), and an agent that can write code (building stays with `hexa do run`).

## Consequences

- Reviews become repeatable and independent of whoever is working.
- The rules cost reading time at the start of a session; keeping each skill short is part of the job.
- A lesson that is only stored and never promoted is just a log. The retro skill says when to promote.

## Implementation

Gate: `bash scripts/agents-check` (see Decision 4). Build with the files written by hand: they are
prose and configuration, not code.

## References

- ADR-2611062130-restyle-the-whole-app
- docs/adrs/ADR-2611071800-never-paste-into-the-wrong-window.md
