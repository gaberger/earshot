---
name: earshot-ui-change
description: How to change an Earshot screen so it is actually good at the real window width. Use when adding or restyling any SwiftUI view, or when the owner says the UI is off.
---

# Changing the UI

A view that type-checks is not done. A view that you have *looked at, at 380 pt*, might be.

1. **Scene first.** Add the scene to `EarshotApp/Tests/RenderUI.swift` (wide, and an `-narrow` twin at 380 pt
   with long titles and long error text). Views take plain values, never `Library`, so a scene can build them.
2. **Build the view** in its own file with `hexa do run ... --evidence "bash EarshotApp/Tests/render.sh"`.
   The file list is `*.swift`; `EarshotApp/Tests/render.sh` lists the files the harness compiles, so add the new file there.
3. **Read the PNGs** in `/tmp/earshot-ui/` with the Read tool. Look for: wrapping (`12:30 P`/`M`),
   truncation (`3 recor…`), anything covered by the floating bar, a trailing edge that does not line up.
4. **Then wire** it into `EarshotApp/Earshot.swift` and build with `bash EarshotApp/build.sh`.
5. **Ask the `ui-designer` agent** (`.claude/agents/ui-designer.md`) for an independent read before saying done.
6. **Say what you did not see.** You cannot screenshot the live app (macOS blocks it). Say that, and list the
   things the owner should check in the real window.

## Pitfalls we paid for

- Fix wrapping with a fixed, non-wrapping column plus `lineLimit(1)`; but `lineLimit(1)` on a *reason* turns
  wrapping into hiding. Let reasons and titles wrap to 2-3 lines.
- `ImageRenderer` draws native controls as yellow boxes: the harness renders through an offscreen
  `NSWindow` instead. Switches then look grey because that window is not key. Not a bug.
- `bash EarshotApp/Tests/render.sh` deletes `/tmp/earshot-ui/*.png` first. Do not run it while an agent is reading them.
- A Form inside a ScrollView did not collapse in a test; do not blame it without a repro.
- Time text from `formatted(date:time:)` uses a narrow no-break space: replace it with a normal space.
- Every control that changes something must look clickable; every empty state must say what to do.
