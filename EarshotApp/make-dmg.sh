#!/usr/bin/env bash
# Packs a built Earshot.app into a drag-to-Applications disk image.
#   bash EarshotApp/make-dmg.sh [APP] [OUT]
# APP defaults to the one build.sh installs; OUT defaults to Earshot.dmg in the current directory.
set -euo pipefail

APP="${1:-$HOME/Applications/Earshot.app}"
OUT="${2:-Earshot.dmg}"
[ -d "$APP" ] || { echo "No app at $APP. Run EarshotApp/build.sh first." >&2; exit 1; }

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

# The window shows the app next to an Applications shortcut: drag one onto the other to install.
ditto "$APP" "$stage/Earshot.app"
ln -s /Applications "$stage/Applications"

rm -f "$OUT"
hdiutil create -volname Earshot -srcfolder "$stage" -fs APFS -format UDZO -ov "$OUT" >/dev/null
hdiutil verify "$OUT" >/dev/null

echo "Created: $OUT"
