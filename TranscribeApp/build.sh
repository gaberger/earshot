#!/usr/bin/env bash
# Builds Transcribe.app and installs it in ~/Applications, plus the helper
# scripts it runs (transcribe, speakers) in ~/.local/bin. This repo is the
# master copy: edit here, then run this script.
set -euo pipefail
cd "$(dirname "$0")"

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
install -m 755 ../scripts/transcribe ../scripts/speakers "$BIN/"

APP="$HOME/Applications/Transcribe.app"
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT

swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macosx26.4 \
  Transcribe.swift -o "$build/Transcribe"

swift make-icon.swift "$build/AppIcon.iconset"
iconutil -c icns "$build/AppIcon.iconset" -o "$build/AppIcon.icns"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp "$build/Transcribe" "$APP/Contents/MacOS/Transcribe"
cp "$build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so macOS remembers the microphone permission for this app.
codesign --force --deep --sign - "$APP"
# Tell Finder/Launchpad about the app (and its "Open With" file types).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

echo "Installed: $APP"
