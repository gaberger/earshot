# ADR-2611062130: Restyle the whole app in a card design

**Status:** Accepted
**Date:** 2026-11-06
**Drivers:** The owner likes OpenSuperWhisper's interface and wants all of Earshot to feel like it, not just
the Dictation settings. A restyle of one Settings block was not noticed (it sat inside one long grouped form).
Their public screenshots (docs/screenshots in my-monkeys/OpenSuperWhisper) were read; no code was.

## Context

Earshot today is a stock split view: a timeline list in the sidebar, a detail pane, a toolbar of eight
labelled buttons (Record, Import, Translate, Summarize, Copy, Finder, Help, Settings), and a status bar.
It works, but it looks like a default template. What makes the other app feel designed:

1. A branded sidebar: logo, a few navigation items, and a "Ready · on this Mac" status card at the bottom.
2. A **Home** page: a greeting with the key instruction, three small cards (shortcut, model, ...), filter
   pills (All / Dictations / Files / Errors), and one feed grouped by day, each row with time, text and a
   quiet "app · model · length" line. Failures are rows in the feed, in a warm accent.
3. A floating bar at the bottom with one round Record button and Hold / Import beside it.
4. Settings as pages of cards: bold title and grey description left, control right, hairline dividers.
5. One warm accent and generous spacing.

## Decision

Restyle in this order, keeping Earshot's navigation model (timeline sidebar, detail pane) and its native
controls. Each stage is a gated change, and **each view is rendered to a PNG and looked at** with
`bash EarshotApp/Tests/render.sh` before the stage is called done. A view that was only type-checked is not done.

1. **Kit** (done): `SettingsKit.swift` cards, rows, banners, chips.
2. **Settings pages**: Settings becomes a sidebar of pages (Recording, Dictation, Speakers, General),
   each a stack of cards. Dictation is already built.
3. **Home**: when nothing is selected, the detail pane shows a greeting, cards (shortcut, dictation on or
   off, recordings today), filter pills, and the recent recordings as a day-grouped feed.
4. **Shell**: sidebar gets the brand header and a status card; the toolbar loses its row of labelled
   buttons (Translate, Summarize, Copy and Finder move into the recording's own header); a floating
   Record / Import bar replaces the toolbar Record button.
5. **Menu bar panel and Listening… pill** use the same cards and accent.

Not copied: their multiple engines, Snippets, Style page, search palette, onboarding.

## Consequences

- The look is Earshot's own (native controls, system accent unless an accent is chosen), borrowing layout
  and spacing, not their artwork or code.
- Views take plain values, not `Library`, so they can be rendered with sample data in the harness.
- `Earshot.swift` (2,500 lines) shrinks as views move into their own files.
- The toolbar change moves buttons users know; the keyboard shortcuts (⌘R, ⌘O, ⇧⌘C) must keep working.

## Implementation

Gate for every stage: `bash EarshotApp/Tests/render.sh && bash EarshotApp/Tests/run.sh`. The render step
fails on a blank scene; the look itself is checked by reading the PNGs in `/tmp/earshot-ui/`.

## References

- ADR-2611062045-dictation-dictionary-and-tap-to-toggle
- https://github.com/my-monkeys/OpenSuperWhisper (README and docs/screenshots only)

## Amendment 2026-11-06: dictation and recordings are two areas

The owner, looking at OpenSuperWhisper's dark Home with a left navigation, said: "we just need to separate
dictation from recordings". Today they are mixed: Home (recordings) carries dictation cards, and the dictation
settings live in the Settings window. Decision:

1. The sidebar gets a navigation at the top with two areas, **Recordings** and **Dictation**.
2. **Recordings** is what exists: the timeline, Home, the recording screen, a recording's page. Home no
   longer mentions dictation.
3. **Dictation** is its own page in the main window: its status (on or off, shortcut, mode) and everything
   that was in Settings → Dictation (shortcut, mode, corrections, permission). The Settings window keeps
   Recording, Speakers and General, and points to the Dictation page.
4. Not in this change: a history of what was dictated. Today the text is pasted and not kept; keeping it is a
   privacy decision for the owner (text only, local, opt-in), recorded here as open.
