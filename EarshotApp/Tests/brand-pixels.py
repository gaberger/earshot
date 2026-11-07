#!/usr/bin/env python3
"""Pixel check for ADR-2611072000: run AFTER `bash Tests/render.sh`.

Looks at the Recordings home render and asserts the brand shows up: orange accent pixels (the selected
filter pill), amber warning pixels (the failed-recording row), and essentially no system-blue pixels.
Fails itself if the render is missing, tiny or blank, so it cannot pass on nothing.
Run: python3 -I EarshotApp/Tests/brand-pixels.py
"""
import colorsys
import os
import sys

from PIL import Image

PATH = "/tmp/earshot-ui/home.png"
FLOOR_CHECKS = 4
checks = 0
failures = 0


def check(name, ok, detail=""):
    global checks, failures
    checks += 1
    print("PASS" if ok else "FAIL", name)
    if not ok:
        failures += 1
        if detail:
            print("   ", detail)


if not os.path.exists(PATH):
    print("VACUOUS: %s does not exist; run bash EarshotApp/Tests/render.sh first" % PATH)
    sys.exit(1)

im = Image.open(PATH).convert("RGB")
w, h = im.size
if w < 300 or h < 200:
    print("VACUOUS: the render is only %dx%d" % (w, h))
    sys.exit(1)

counts = {"orange": 0, "amber": 0, "blue": 0, "coloured": 0}
for r, g, b in im.getdata():
    hh, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    deg = hh * 360
    if s < 0.45 or v < 0.5:
        continue
    counts["coloured"] += 1
    if 14 <= deg <= 32:
        counts["orange"] += 1
    elif 36 <= deg <= 52:
        counts["amber"] += 1
    elif 195 <= deg <= 255:
        counts["blue"] += 1

print("pixel counts:", counts)
if counts["coloured"] < 200:
    print("VACUOUS: only %d saturated pixels in the render, it looks blank" % counts["coloured"])
    sys.exit(1)

check("the accent shows: at least 40 orange pixels (selected filter pill, hue 14 to 32)", counts["orange"] >= 40, counts["orange"])
check("warnings are amber, not orange: at least 40 amber pixels (the failed recording row, hue 36 to 52)", counts["amber"] >= 40, counts["amber"])
check("no system blue is left: at most 20 blue pixels", counts["blue"] <= 20, counts["blue"])
check("the render is the size the harness draws (760 wide)", w == 760, (w, h))

print("%d checks, %d failed" % (checks, failures))
if checks < FLOOR_CHECKS:
    print("VACUOUS: only %d checks ran" % checks)
    sys.exit(1)
sys.exit(0 if failures == 0 else 1)
