#!/usr/bin/env python3
"""Gate for ADR-2611071700: structure, links, images, accessibility, privacy and honesty rules for site/.

Run: python3 -I site/check.py
It checks what a program can check. It cannot tell whether the copy is true or the design is good;
a reviewer reads the page for that.
"""
import os
import re
import sys
from html.parser import HTMLParser
from urllib.parse import urlparse

SITE = os.path.dirname(os.path.abspath(__file__))
INDEX = os.path.join(SITE, "index.html")
SECTIONS = ["what", "how", "dictation", "notes", "privacy", "install"]
VOID = {"img", "meta", "link", "br", "hr", "input", "source", "area", "base", "col", "embed", "wbr"}
ALLOWED_HOSTS = {"github.com", "brew.sh", "huggingface.co", "modelcontextprotocol.io"}
FLOOR = 40
checks = 0
failures = 0


def check(name, ok, detail=""):
    global checks, failures
    checks += 1
    print("PASS" if ok else "FAIL", name)
    if not ok:
        failures += 1
        if detail:
            print("   ", str(detail)[:300])


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []          # (tag, id, figure_obj)
        self.tags = []           # (tag, attrs dict)
        self.text = []
        self.sec_text = {s: [] for s in SECTIONS}
        self.headings = []
        self.imgs = []           # (attrs, figure_obj or None)
        self.figures = []        # dicts {caption: bool}
        self.title = ""
        self._in_title = False
        self._skip = 0
        self.sec_li = {s: 0 for s in SECTIONS}
        self.htmllang = None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        self.tags.append((tag, a))
        if tag == "html":
            self.htmllang = a.get("lang")
        if tag == "title":
            self._in_title = True
        if tag in ("script", "style"):
            self._skip += 1
        if re.fullmatch(r"h[1-6]", tag):
            self.headings.append(int(tag[1]))
        fig = None
        if tag == "figure":
            fig = {"caption": False}
            self.figures.append(fig)
        if tag == "figcaption":
            for t, _i, f in reversed(self.stack):
                if t == "figure":
                    f["caption"] = True
                    break
        if tag == "img":
            f = None
            for t, _i, ff in reversed(self.stack):
                if t == "figure":
                    f = ff
                    break
            self.imgs.append((a, f))
        if tag == "li":
            for _t, i, _f in self.stack:
                if i in self.sec_li:
                    self.sec_li[i] += 1
        if tag not in VOID:
            self.stack.append((tag, a.get("id"), fig))

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False
        if tag in ("script", "style") and self._skip:
            self._skip -= 1
        for k in range(len(self.stack) - 1, -1, -1):
            if self.stack[k][0] == tag:
                del self.stack[k:]
                break

    def handle_data(self, data):
        if self._in_title:
            self.title += data
        if self._skip:
            return
        self.text.append(data)
        for _t, i, _f in self.stack:
            if i in self.sec_text:
                self.sec_text[i].append(data)


def words(chunks):
    return re.findall(r"[A-Za-z0-9'’]+", " ".join(chunks))


def local_target(ref):
    p = urlparse(ref)
    if p.scheme or ref.startswith("#") or ref.startswith("//") or ref.startswith("mailto:") or ref.startswith("data:"):
        return None
    path = p.path
    if not path:
        return None
    return os.path.normpath(os.path.join(SITE, path))


def main():
    if not os.path.exists(INDEX):
        print("FAIL site/index.html does not exist")
        sys.exit(1)
    html = open(INDEX, encoding="utf-8").read()
    p = Page()
    p.feed(html)
    body_words = words(p.text)
    if len(body_words) < 250:
        print("VACUOUS: only %d words on the page, need at least 250" % len(body_words))
        sys.exit(1)

    # MARK: document basics
    check("the page declares lang=en", (p.htmllang or "").lower().startswith("en"), p.htmllang)
    check("the page declares a charset", any(t == "meta" and a.get("charset") for t, a in p.tags))
    check("the page has a viewport meta", any(t == "meta" and a.get("name") == "viewport" for t, a in p.tags))
    check("the title is 10 to 70 characters", 10 <= len(p.title.strip()) <= 70, repr(p.title))
    desc = [a.get("content", "") for t, a in p.tags if t == "meta" and a.get("name") == "description"]
    check("a meta description of 50 to 160 characters", bool(desc) and 50 <= len(desc[0]) <= 160, desc)
    check("exactly one h1", p.headings.count(1) == 1, p.headings.count(1))
    check("heading levels never skip a level",
          all(b <= a + 1 for a, b in zip(p.headings, p.headings[1:])), p.headings)
    check("a header, a main and a footer element exist",
          all(any(t == k for t, _ in p.tags) for k in ("header", "main", "footer")))
    check("a nav element exists", any(t == "nav" for t, _ in p.tags))
    check("the page is substantial: at least 250 words", len(body_words) >= 250, len(body_words))
    check("the page is not a wall of text: at most 1800 words", len(body_words) <= 1800, len(body_words))

    # MARK: sections and anchors
    ids = {a.get("id") for _t, a in p.tags if a.get("id")}
    for s in SECTIONS:
        check("section #%s exists" % s, s in ids)
    hrefs = [a.get("href", "") for t, a in p.tags if t == "a"]
    check("every in-page link points at an id that exists",
          all(h[1:] in ids for h in hrefs if h.startswith("#") and len(h) > 1),
          [h for h in hrefs if h.startswith("#") and h[1:] not in ids])
    check("the navigation links to all six sections",
          all(("#" + s) in hrefs for s in SECTIONS), [s for s in SECTIONS if ("#" + s) not in hrefs])
    check("the how-it-works section lists at least 3 steps", p.sec_li["how"] >= 3, p.sec_li["how"])

    # MARK: links and no third-party loads
    bad_local = []
    for t, a in p.tags:
        for attr in ("href", "src"):
            ref = a.get(attr)
            if ref and t in ("a", "link", "img", "source"):
                target = local_target(ref)
                if target and not os.path.exists(target):
                    bad_local.append(ref)
    check("every local link and file reference exists", not bad_local, bad_local)
    check("no script element at all (no JavaScript, no trackers)", not any(t == "script" for t, _ in p.tags))
    check("no iframe, embed, object, video or audio element",
          not any(t in ("iframe", "embed", "object", "video", "audio") for t, _ in p.tags))
    loads = [a.get("src") or a.get("href") for t, a in p.tags
             if (t in ("img", "source") and (a.get("src", "").startswith(("http", "//"))))
             or (t == "link" and (a.get("href", "").startswith(("http", "//"))))]
    check("nothing is loaded from another host (images, styles, fonts)", not loads, loads)
    bad_hosts = sorted({urlparse(h).hostname for h in hrefs
                        if h.startswith("http") and urlparse(h).hostname not in ALLOWED_HOSTS})
    check("outbound links go only to allowed hosts", not bad_hosts, bad_hosts)
    check("a link to the GitHub releases page", any("github.com/gaberger/earshot/releases" in h for h in hrefs))
    check("a link to the GitHub repository", any(re.fullmatch(r"https://github\.com/gaberger/earshot/?", h) for h in hrefs))
    inline_style_urls = re.findall(r"url\(\s*['\"]?https?:", html)
    check("no remote url() in the page", not inline_style_urls)

    # MARK: images and captions
    raster = [(a, f) for a, f in p.imgs]
    check("at least 6 images", len(raster) >= 6, len(raster))
    check("every image has alt text of 12 or more characters", all(len(a.get("alt", "")) >= 12 for a, _ in raster),
          [a.get("src") for a, _ in raster if len(a.get("alt", "")) < 12])
    check("every image has width and height (no layout jump)",
          all(a.get("width", "").isdigit() and a.get("height", "").isdigit() for a, _ in raster),
          [a.get("src") for a, _ in raster if not (a.get("width", "").isdigit() and a.get("height", "").isdigit())])
    check("every image is inside a figure with a figcaption",
          all(f is not None and f["caption"] for _a, f in raster),
          [a.get("src") for a, f in raster if f is None or not f["caption"]])
    check("every image is lazy-loaded except possibly the first",
          all(a.get("loading") == "lazy" for a, _ in raster[1:]), [a.get("src") for a, _ in raster[1:] if a.get("loading") != "lazy"])
    small = []
    for a, _ in raster:
        t = local_target(a.get("src", ""))
        if t and os.path.exists(t) and t.lower().endswith((".png", ".webp", ".jpg", ".jpeg")) and os.path.getsize(t) < 5000:
            small.append(a.get("src"))
    check("no screenshot is blank or tiny (each at least 5 KB)", not small, small)
    imgdir = os.path.join(SITE, "img")
    files = sorted(os.listdir(imgdir)) if os.path.isdir(imgdir) else []
    used = {os.path.basename(a.get("src", "")) for a, _ in raster}
    check("no unused file in img/", all(f in used or f.startswith(".") for f in files), [f for f in files if f not in used])
    check("the page says the screenshots show sample data", "sample data" in " ".join(p.text).lower())

    # MARK: honesty and privacy
    alltext = " ".join(p.text)
    low = alltext.lower()
    check("states the platform requirement: Apple silicon", "apple silicon" in low)
    check("states the platform requirement: macOS 26", "macos 26" in low)
    check("says summaries need Apple Intelligence", "apple intelligence" in low)
    check("tells people about the first-launch step (Open Anyway)", "open anyway" in alltext.lower())
    check("the privacy section mentions agents and where text can go",
          "agent" in " ".join(p.sec_text["privacy"]).lower() and "provider" in " ".join(p.sec_text["privacy"]).lower())
    check("the privacy section says nothing leaves the Mac for Earshot itself",
          "leaves" in " ".join(p.sec_text["privacy"]).lower() or "stays" in " ".join(p.sec_text["privacy"]).lower())
    check("no invented numbers of downloads, users, stars, reviews or customers",
          not re.search(r"\b\d[\d,.]*\s*[kKmM+]?\s*(downloads|users|stars|reviews|customers|installs)\b", alltext, re.I))
    check("no testimonial, rating or superlative claims",
          not re.search(r"testimonial|★|⭐|\bbest[- ]in[- ]class\b|\b#1\b|\bworld'?s (best|first|fastest)\b|\bloved by\b|\btrusted by\b",
                        alltext, re.I))
    check("no placeholder text", not re.search(r"lorem ipsum|\bTODO\b|\bTBD\b|placeholder|your text here", alltext, re.I))
    check("the dictation section names the shortcut", "shortcut" in " ".join(p.sec_text["dictation"]).lower()
          or "hotkey" in " ".join(p.sec_text["dictation"]).lower())
    check("the notes section talks about notes", "note" in " ".join(p.sec_text["notes"]).lower())
    lic = open(os.path.join(SITE, "..", "LICENSE"), encoding="utf-8").read() if os.path.exists(os.path.join(SITE, "..", "LICENSE")) else ""
    check("a license named on the page matches the LICENSE file",
          ("MIT" not in alltext) or ("MIT License" in lic), lic[:60])

    # MARK: stylesheet and size
    sheets = [a.get("href") for t, a in p.tags if t == "link" and a.get("rel") == "stylesheet"]
    check("exactly one local stylesheet", len(sheets) == 1 and local_target(sheets[0]) is not None, sheets)
    css = ""
    if sheets and local_target(sheets[0]) and os.path.exists(local_target(sheets[0])):
        css = open(local_target(sheets[0]), encoding="utf-8").read()
    check("the stylesheet respects reduced motion", "prefers-reduced-motion" in css)
    check("the stylesheet shows keyboard focus", ":focus-visible" in css)
    check("the stylesheet handles light and dark (prefers-color-scheme) or is one theme with a color-scheme",
          "prefers-color-scheme" in css or "color-scheme" in css)
    check("the stylesheet has no @import and no remote url()", "@import" not in css and not re.search(r"url\(\s*['\"]?(https?:|//)", css))
    check("the stylesheet is responsive (a max-width or min-width media query)", bool(re.search(r"@media[^{]*(max|min)-width", css)))
    total = sum(os.path.getsize(os.path.join(dp, f)) for dp, _d, fs in os.walk(SITE) for f in fs)
    check("the whole site is under 3 MB", total < 3 * 1024 * 1024, total)
    check("index.html is under 120 KB", os.path.getsize(INDEX) < 120 * 1024, os.path.getsize(INDEX))
    check("style.css is under 60 KB", len(css.encode()) < 60 * 1024, len(css.encode()))

    print("%d checks, %d failed" % (checks, failures))
    if checks < FLOOR:
        print("VACUOUS: only %d checks ran, need %d" % (checks, FLOOR))
        sys.exit(1)
    sys.exit(0 if failures == 0 else 1)


if __name__ == "__main__":
    main()
