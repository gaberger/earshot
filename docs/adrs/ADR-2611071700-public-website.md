# ADR-2611071700: A public website for Earshot

**Status:** Accepted
**Date:** 2026-11-07
**Drivers:** Earshot has no website: the README is the only public page. The owner wants a
professional site like Voicebox's (voicebox.sh): a clear promise, screenshots, and an explanation of
what each part does. Only voicebox.sh's public page text was read, so its structure is borrowed (hero,
feature sections each with a screenshot, install options, footer), not its copy, art or code.

## Decision

1. **A static site in `site/`**: `index.html`, `style.css` and `img/`. No build step, no framework,
   no package manager. It can be opened from disk.
2. **It practises what the product promises.** No JavaScript at all, no third-party fonts, scripts,
   styles, images, embeds, analytics or trackers. The only outbound links are ordinary links to
   github.com, brew.sh, huggingface.co and modelcontextprotocol.io.
3. **Screenshots are renders of the real app views**, made by `EarshotApp/Tests/render.sh` with
   made-up sample data. They are not OS screen captures (the build environment cannot take those), so
   the page says "sample data" next to them, and the flames and the dictation pill, which the harness
   does not draw, are described in words until real captures exist. Every screenshot sits in a
   `<figure>` with a caption that says what it shows, and has real alt text.
4. **Honest content.** No testimonials, download counts, star counts, ratings or "best" claims: none
   exist. The requirements are stated plainly (Apple silicon, macOS 26.4 or later, Apple Intelligence
   for summaries, Homebrew tools, about 3 GB of models), and so is the first-launch step for an app
   that is not notarized ("Open Anyway"). The privacy section says what stays on the Mac and also that
   connecting an agent to the MCP server can send text to that agent's provider.
5. **Sections** (anchors): `what` (what Earshot is and does), `how` (record, transcribe, label
   speakers, summarize), `dictation`, `notes`, `privacy`, `install`, plus a footer.
6. **Publishing is a separate, deliberate step.** This change builds and checks the site locally. Turning
   on GitHub Pages (a workflow that deploys `site/`) makes it public and is done only on the owner's
   word.

Not in this change: a custom domain, analytics, a blog or docs site, a download page for builds that do
not exist, and translations.

## Consequences

- A page people can understand in a minute, at no running cost and with nothing to maintain.
- Screenshots go stale as the UI changes. `render.sh` regenerates them; a refresh is a deliberate step.
- The site's claims can drift from the product. The gate checks structure and honesty rules, not
  whether the words are true; a reviewer has to read the copy against the README.

## Implementation

Gate, written before the page: `python3 -I site/check.py` exits 0. It parses the HTML and CSS and
checks the structure, links, images, accessibility basics, the privacy rules above, the honesty rules
above, and size limits. It fails itself if it finds no page or too little text.

## References

- ADR-2611062130-restyle-the-whole-app
- ADR-2611071600-speak-the-reply-aloud (the agent caveat in the privacy section)
- https://voicebox.sh (public page text only)
