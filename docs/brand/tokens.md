# Earshot app design tokens, as the code defines them

Source: `EarshotApp/SettingsKit.swift`, `ChromeViews.swift`, `AppNav.swift`, `HomeView.swift`,
`RecordingViews.swift`, `NotesView.swift`, `DictationSettingsView.swift`, `WindowHighlighter.swift`
(read from the main checkout; the worktree copy of the repo predates these files).

The app defines almost no colours of its own. It uses **semantic system colours**, so the
look is "native macOS", dark when the Mac is dark. Hex values below are what these resolve to
in Dark appearance, measured from the PNG renders.

## Surfaces

| Role | Code | Dark value |
|---|---|---|
| Window background | `Color(nsColor: .windowBackgroundColor)` | about #1C1C1C |
| Card / grouped section | `.controlBackgroundColor`, 12 pt radius | about #1C1C1C to #1E1E1E (flat; the card is told apart by its border) |
| Input / key chip | `.textBackgroundColor`, 8 pt radius (search field 10) | darker than the window |
| Hairline border | `Color(nsColor: .separatorColor)`, `strokeBorder` 1 pt | about #323232 |
| Divider between rows | `Divider()` | same separator |
| Neutral pill / chip fill | `Color.primary.opacity(0.07 ... 0.10)` | about #2B2B2B |
| Bottom record bar | Capsule, hairline border | |

## Radii

5 (key hint) / 8 (key chip, text input) / 10 (sidebar row selection, search field, warning
box) / 12 (settings card, status card, search results) / 14 (note card) / 16 (live recording
card) / Capsule (filter pills, tabs, record bar).

## Type

All system font (SF Pro). No custom family, no hard-coded sizes except 11 pt semibold caps
for day headers and a 34 pt semibold rounded timer.

- Page title: `.largeTitle.bold()`; subtitle `.title3`, secondary
- Section title: `.headline`; row title `.body.weight(.semibold)`
- Row detail: `.callout` or `.caption`, `.secondary`
- Sidebar item: `.body.weight(.medium)`; pill: `.callout`, semibold when selected

## Text colours

`Color.primary` for content, `.secondary` for detail (about #9A9A9A on the window, 6.1:1).

## Accent, today

- `Color.accentColor` = **the user's macOS accent colour** (system blue by default, #0A84FF in
  Dark). Used for:
  - the selected filter pill: text `accentColor`, fill `accentColor.opacity(0.22)` (HomeView:122,125)
  - the selected sidebar row and the Settings row: text `accentColor`, fill `.opacity(0.18)`
    (AppNav:42-46, ChromeViews:160-163)
  - the shortcut recorder border while listening (DictationSettingsView:36)
- Native `Toggle(.switch)`, segmented `Picker`, `.borderedProminent` buttons and focus rings
  also take the system accent automatically (no code names the colour).

## Status colours

- Orange (`Color.orange`) = **warning and error**: failed row title and message, the
  permission banner (text orange, fill `orange.opacity(0.12)`, `.tint(.orange)` button),
  the "ending soon" notice. Dark value about #FF9F0A, 8.3:1 on the window.
- Red (`Color.red`) = **recording**: the big record button, the live dot, level bars when loud,
  the Stop button tint, the Record a note dot.
- Green = status card "ready" dot.

## The signature: the dictation flame

`WindowHighlighter.swift` draws a glowing flame outline around the target window. Its colours
are hard-coded orange: border and glow `rgb(1.0, 0.55, 0.10)` = #FF8C1A, particles
`(1, 0.5, 0.1)` core, `(1, 0.9, 0.5)` hot centre, `(0.9, 0.25, 0.05)` ember.
This is the only place the app has a colour of its own, and it is orange, not blue.

## Mismatch summary

| Layer | Hue it speaks in |
|---|---|
| App icon | indigo gradient #5B5BF0 to #2A1A7A, white glyph |
| App UI accent | system blue (user-adjustable) |
| App UI warnings + flame | orange |
| Website | paper-white page, flame orange #E0400D, black display type |

## Tokens as changed for the FLAME renders (scratch copies only)

- `Color.accentColor` replaced by `Color.flame` = #F97316 (rgb 0.976, 0.451, 0.086) everywhere it
  appears, so pills and sidebar selection take it.
- Switch and segmented control: the native ones draw in the grey inactive state when rendered
  off-screen, so both variants use a small stand-in drawn with the accent colour. This matches
  what an active window shows (blue today, orange when tinted), but it is a stand-in.
- Dictation settings scene: permission banner suppressed (`trusted = true`) and cleanup on, so the
  page shows the good state.
