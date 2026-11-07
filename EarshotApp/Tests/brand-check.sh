#!/usr/bin/env bash
# Guards ADR-2611072000: the app uses the brand tokens, not the system accent or system orange, the
# root tint is set, and the icon follows concept B. It checks structure, not looks; the looks are
# checked by Tests/render.sh and Tests/brand-pixels.py. It fails itself when it finds too little to check.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
say() { echo "$1"; }

# MARK: no system accent or system orange in the views. A line marked brand-ok is exempt (the speaker
# avatar palette is not a status colour).
files=$(ls *.swift | grep -v -E '^(Brand|BrandColors)\.swift$')
bad=$(grep -n -E 'accentColor|\.orange\b|systemOrange|\.yellow\b' $files | grep -v 'brand-ok' || true)
if [ -n "$bad" ]; then
  say "FAIL system accent or orange still used (use Color.brand*):"; echo "$bad" | head -20; fail=1
else
  say "PASS no accentColor, system orange or system yellow left in the views"
fi
badblue=$(grep -n -E 'Color\.blue|\.blue\b' $files | grep -v 'brand-ok' || true)
if [ -n "$badblue" ]; then
  say "FAIL system blue still used:"; echo "$badblue" | head; fail=1
else
  say "PASS no system blue left in the views"
fi

# MARK: the tokens are actually used (so a deleted usage cannot pass vacuously)
uses=$(grep -h -o 'Color\.brand[A-Za-z]*' $files | wc -l | tr -d ' ')
if [ "$uses" -ge 14 ]; then say "PASS Color.brand* is used $uses times (at least 14)"; else say "FAIL Color.brand* used only $uses times, need at least 14"; fail=1; fi
for f in Brand.swift BrandColors.swift; do
  if [ -f "$f" ]; then say "PASS $f exists"; else say "FAIL $f is missing"; fail=1; fi
done

# MARK: the root tint is set for the main window and Settings
tints=$(grep -c -E '\.tint\(Color\.brandAccent\)' Earshot.swift || true)
if [ "$tints" -ge 2 ]; then say "PASS the root tint is set ($tints places in Earshot.swift)"; else say "FAIL .tint(Color.brandAccent) found $tints times in Earshot.swift, need at least 2 (main window and Settings)"; fail=1; fi

# MARK: speaker palette keeps its marked exemption (so the guard above is not hiding real uses)
if grep -q 'brand-ok' Earshot.swift; then say "PASS the speaker palette is marked brand-ok"; else say "FAIL the speaker palette line is not marked brand-ok"; fail=1; fi

# MARK: the icon follows concept B
python3 -I - <<'EOF' || fail=1
import json, re, sys, os
ICON = os.path.join("..", "assets", "Earshot.icon")
ok = True
def lum(c):
    def lin(x): return x/12.92 if x <= 0.03928 else ((x+0.055)/1.055)**2.4
    r, g, b = c
    return 0.2126*lin(r)+0.7152*lin(g)+0.0722*lin(b)
try:
    data = json.load(open(os.path.join(ICON, "icon.json")))
    stops = data["fill"]["linear-gradient"]
    lums = []
    for s in stops:
        nums = [float(x) for x in re.findall(r"[-0-9.]+", s.split(":")[1])][:3]
        lums.append(lum(nums))
    if len(lums) >= 2 and all(l < 0.06 for l in lums):
        print("PASS the icon fill is a dark gradient (luminance %s)" % ", ".join("%.3f" % l for l in lums))
    else:
        print("FAIL the icon fill is not dark: luminance %s" % lums); ok = False
except Exception as e:
    print("FAIL cannot read icon.json: %s" % e); ok = False
layers = ["ear.svg", "wave-near.svg", "wave-mid.svg", "wave-far.svg"]
for name in layers:
    try:
        svg = open(os.path.join(ICON, "Assets", name), encoding="utf-8").read().lower()
        if "#f97316" in svg and "#ffffff" not in svg:
            print("PASS %s is orange (F97316) and not white" % name)
        else:
            print("FAIL %s must stroke #F97316 and contain no #FFFFFF" % name); ok = False
    except Exception as e:
        print("FAIL cannot read %s: %s" % (name, e)); ok = False
sys.exit(0 if ok else 1)
EOF

if [ "$fail" -ne 0 ]; then echo "brand-check FAILED"; exit 1; fi
echo "brand-check passed"
