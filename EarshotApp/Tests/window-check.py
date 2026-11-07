#!/usr/bin/env python3
"""Pixel gate for the composed window renders: run AFTER `bash Tests/render.sh`.

The earlier product pictures showed only the content pane, so the app looked like it had no categories
and no search. These scenes compose the real views in the same layout as the real window (sidebar with
brand, categories, status and footer, then a top bar with the search field, then the content), and this
script proves the pieces are really in the picture and that the selected category moves between windows.
It fails itself if any render is missing or blank, so it cannot pass on nothing.
Run: python3 -I EarshotApp/Tests/window-check.py
"""
import colorsys
import os
import sys

from PIL import Image

D = "/tmp/earshot-ui"
NAMES = ["window-recordings", "window-notes", "window-dictation", "window-search"]
FLOOR = 14
checks = 0
failures = 0


def check(name, ok, detail=""):
    global checks, failures
    checks += 1
    print("PASS" if ok else "FAIL", name)
    if not ok:
        failures += 1
        if detail != "":
            print("   ", detail)


def hsv_deg(px):
    r, g, b = px
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    return h * 360, s, v


def is_orange(px):
    d, s, v = hsv_deg(px)
    return 14 <= d <= 32 and s >= 0.45 and v >= 0.5


def is_green(px):
    d, s, v = hsv_deg(px)
    return 85 <= d <= 155 and s >= 0.4 and v >= 0.45


def region_pixels(im, box):
    x0, y0, x1, y1 = box
    px = im.load()
    for y in range(max(0, y0), min(im.height, y1)):
        for x in range(max(0, x0), min(im.width, x1)):
            yield x, y, px[x, y]


missing = [n for n in NAMES if not os.path.exists(os.path.join(D, n + ".png"))]
if missing:
    print("VACUOUS: missing renders %s; run bash EarshotApp/Tests/render.sh first" % missing)
    sys.exit(1)

ims = {n: Image.open(os.path.join(D, n + ".png")).convert("RGB") for n in NAMES}
sizes = {n: im.size for n, im in ims.items()}
print("sizes:", sizes)

# MARK: every window render is a real, full-size window
check("every window render is at least 1000 x 600", all(w >= 1000 and h >= 600 for w, h in sizes.values()), sizes)
check("all window renders have the same size", len(set(sizes.values())) == 1, sizes)
for n, im in ims.items():
    colourful = sum(1 for _x, _y, p in region_pixels(im, (0, 0, im.width, im.height))
                    if hsv_deg(p)[1] >= 0.45 and hsv_deg(p)[2] >= 0.5)
    if colourful < 300:
        print("VACUOUS: %s has only %d saturated pixels; it looks blank" % (n, colourful))
        sys.exit(1)

W, H = sizes[NAMES[0]]
SIDEBAR = 250

# MARK: the brand header sits at the top of the sidebar (the orange ear of the icon)
for n in NAMES:
    cnt = sum(1 for _x, _y, p in region_pixels(ims[n], (0, 0, SIDEBAR, 70)) if is_orange(p))
    check("%s: the brand mark (orange) shows at the top of the sidebar" % n, cnt >= 30, cnt)

# MARK: the categories are there, and the selected one moves: Recordings above Notes above Dictation
centroid = {}
for n in ["window-recordings", "window-notes", "window-dictation"]:
    pts = [y for _x, y, p in region_pixels(ims[n], (0, 74, SIDEBAR, 300)) if is_orange(p)]
    check("%s: an orange selected category shows in the sidebar" % n, len(pts) >= 30, len(pts))
    centroid[n] = sum(pts) / len(pts) if pts else -1
print("selected-category centroid y:", centroid)
check("the selection moves down from Recordings to Notes (at least 8 px)",
      centroid["window-notes"] - centroid["window-recordings"] >= 8, centroid)
check("the selection moves down from Notes to Dictation (at least 8 px)",
      centroid["window-dictation"] - centroid["window-notes"] >= 8, centroid)

# MARK: the ready status card (green dot) sits low in the sidebar
green = sum(1 for _x, _y, p in region_pixels(ims["window-recordings"], (0, H - 220, SIDEBAR, H)) if is_green(p))
check("the status card's green ready dot shows at the bottom of the sidebar", green >= 8, green)

# MARK: the search results dropdown is drawn in the search window and not in the plain one
a, b = ims["window-recordings"], ims["window-search"]
pa, pb = a.load(), b.load()
diff = 0
for y in range(40, 280):
    for x in range(SIDEBAR + 60, W):
        if sum(abs(pa[x, y][i] - pb[x, y][i]) for i in range(3)) > 60:
            diff += 1
check("the search window differs from the plain one in the top bar and dropdown area (at least 3000 pixels)", diff >= 3000, diff)

# MARK: the search window keeps the same sidebar
sdiff = 0
for y in range(70, 200):
    for x in range(0, SIDEBAR):
        if sum(abs(pa[x, y][i] - pb[x, y][i]) for i in range(3)) > 60:
            sdiff += 1
check("the sidebar is the same in the search window (under 200 differing pixels)", sdiff < 200, sdiff)

print("%d checks, %d failed" % (checks, failures))
if checks < FLOOR:
    print("VACUOUS: only %d checks ran, need %d" % (checks, FLOOR))
    sys.exit(1)
sys.exit(0 if failures == 0 else 1)
