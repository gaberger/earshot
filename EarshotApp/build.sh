#!/usr/bin/env bash
# Builds Earshot.app and installs it in ~/Applications, plus the helper
# scripts it runs (transcribe, speakers) in ~/.local/bin. This repo is the
# master copy: edit here, then run this script.
set -euo pipefail
cd "$(dirname "$0")"

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
install -m 755 ../scripts/transcribe ../scripts/speakers "$BIN/"

APP="$HOME/Applications/Earshot.app"
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT

swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macosx26.4 \
  Earshot.swift -o "$build/Earshot"

# The app icon is a layered Icon Composer file. actool turns it into Assets.car (Liquid Glass
# icon for macOS 26) plus Earshot.icns (fallback), as Apple's guidelines ask.
xcrun actool "$(cd ../assets && pwd)/Earshot.icon" --compile "$build" --platform macosx \
  --minimum-deployment-target 26.4 --app-icon Earshot \
  --output-partial-info-plist "$build/icon.plist" >/dev/null

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp "$build/Earshot" "$APP/Contents/MacOS/Earshot"
cp "$build/Assets.car" "$build/Earshot.icns" "$APP/Contents/Resources/"
# Menu bar artwork (a template image: macOS tints it for light and dark menu bars).
cp ../assets/menubar.svg "$APP/Contents/Resources/"

# Ad-hoc signature so macOS remembers the microphone permission for this app.
codesign --force --deep --sign - "$APP"
# Tell Finder/Launchpad about the app (and its "Open With" file types).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

echo "Installed: $APP"
