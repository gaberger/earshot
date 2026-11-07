# ADR-2611072000: One brand: flame orange, a dark mark, a matching site

**Status:** Accepted
**Date:** 2026-11-07
**Drivers:** The owner looked at the new website and said it looked nothing like the app, and that
the logo, the app and the site disagreed. Three looks existed: an indigo logo, an app accented with
the system blue, and an orange website. The owner chose concept B from the brand decision sheet
(`docs/brand/brand-sheet.html` in the designer's worktree): a dark charcoal tile with an orange ear
and orange waves, with flame orange as the one accent everywhere. The app's signature feature, the
dictation fire, is already orange.

## Decision

1. **The app accent becomes flame orange `#F97316`** in place of the system accent. It tints native
   controls (toggles, segmented pickers, buttons) through one `.tint` at the root of each window, and
   it colours the selected pills, selected sidebar items and the dictation shortcut field. A fixed
   orange does not follow the user's macOS accent setting; the owner accepted that for a strong
   identity.
2. **Tokens live in one place.** `Brand.swift` (pure Foundation: the hex values and the WCAG contrast
   function) and `BrandColors.swift` (the SwiftUI and AppKit bridge: `Color.brandAccent`,
   `brandAccentText`, `brandOnAccent`, `brandWarning`, `brandWarningText`). No view uses
   `Color.accentColor` or system orange any more.
3. **Text needs its own colours, because `#F97316` fails on light backgrounds** (2.8:1 on white).
   - Accent fills and dark-mode accent text: `#F97316`. Text on an accent fill: `#141414` (6.57:1).
   - Accent text in light mode: `#B93C0A` (at least 4.79:1 on white, `#F5F5F5` and `#ECECEC`).
   - The text colours adapt to the appearance, using a dynamic AppKit colour.
4. **Warnings move to amber so they differ from the accent.** Dark mode `#FBBF24`, light mode text
   `#92400E` (at least 6.0:1). Recording stays red and success stays green. The speaker avatar palette is
   not a status colour and keeps its mix (its line is marked `brand-ok`). In light mode the warning
   brown and the accent burnt orange are close in hue; warnings are always accompanied by an icon or a
   sentence, so colour alone never carries the meaning.
5. **The icon follows concept B.** `assets/Earshot.icon`: the fill becomes a charcoal gradient
   (`#2E2E30` to `#161617`) and the ear and wave layers become orange strokes (`#F97316`) instead of
   white. The menu bar template (`assets/menubar.svg`) is monochrome and does not change. The app
   icon is a layered Liquid Glass file that this environment cannot render, so how it looks in the Dock
   has to be checked by the owner.
6. **The website follows the app** in a separate change (ADR-2611071700 amended): the app's dark
   charcoal surfaces, hairline borders, rounded cards and this accent, with the app's own renders, taken
   at 2x with this accent, as the product visuals. The README logo (`assets/earshot-logo.svg`) is
   redrawn to match the new icon in that change.

Not in this change: the website, the README artwork, a user-selectable accent, and any dark-mode-only
decision (the app still follows the system appearance).

## Consequences

- One recognisable identity across icon, app and site, with the fire as its signature.
- The accent no longer follows the macOS setting; users who chose a different accent lose that.
- Several lines across the views change at once. The gate checks that none is missed.
- The Dock icon cannot be seen from here; a wrong-looking glass layer is possible.

## Implementation

Gate, written before the code: `EarshotApp/Tests/run.sh` exits 0 with new `BrandTests` (the exact hex
values and the contrast of every text and fill pair, checked against ratios computed independently
and written out by hand), `Tests/brand-check.sh` (no `accentColor` or system orange left in the views,
the root tint is set, the icon fill is dark and every icon layer is orange), the app typechecks, and
after `Tests/render.sh` the script `Tests/brand-pixels.py` finds orange accent pixels and amber
warning pixels in the Recordings home render and essentially no system-blue pixels. The pixel check
fails itself if the render is missing or blank.

## References

- ADR-2611062130-restyle-the-whole-app
- ADR-2611071700-public-website
- docs/brand/brand-sheet.html (the designer's decision sheet)
