---
name: earshot-retro
description: The end-of-work routine that turns this session's mistakes and corrections into stored lessons and better skills. Use when a piece of work is finished, the owner corrects you, or before handing over.
---

# Retro: learn from ourselves

Run this at the end of every piece of work, and whenever the owner says "that's wrong" or "you missed".
It takes five minutes and it is the only way the library gets better.

1. **Collect.**
   - `hexa insight punch-list` lists follow-ups mentioned and routed nowhere. Route each: a checklist step
     (`hexa loop task add`), an ADR, or drop it on purpose.
   - `hexa loop` against `git log --oneline -15`: every step marked done must have a commit. Undo the rest.
   - Re-read the owner's last corrections in the conversation. Each one is a lesson.
2. **Write each lesson as a cause and a rule**, not an event:
   `hexa memory store lesson:<topic> "<what happened>. Rule: <what to do instead>."`
   Topics so far: `lesson:ui-narrow-render`, `lesson:checklist-honesty`, `lesson:three-functions`,
   `lesson:signing-tcc`, `lesson:render-harness`, `lesson:shared-tree`.
3. **Promote.** If `hexa memory search lesson:<topic>` already has an entry, the lesson recurred: put the
   rule into the skill it belongs to (`earshot-ui-change`, `earshot-ship`, `earshot-permissions`,
   `earshot-privacy-map`) and say so in the commit.
4. **Check the library:** `bash scripts/agents-check` must pass (it validates names, descriptions, that the
   cited paths exist, and that the lessons are stored).
5. **Tell the owner** what you learned in two lines, and what is still unverified.

## Do not

- Store a lesson that is only an event ("the build failed"). If there is no rule, there is nothing to learn.
- Edit `.claude/settings.json` to automate this without the owner's approval; propose it instead.
