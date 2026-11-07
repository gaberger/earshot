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
  Earshot.swift RichText.swift Chunking.swift EndOfMeeting.swift CallStart.swift Dictation.swift DictationDictionary.swift DictationLog.swift NotesStore.swift NoteSession.swift NoteRecorder.swift DictationService.swift HotKey.swift DictationHUD.swift SettingsKit.swift HomeView.swift NotesView.swift RecordingViews.swift AppNav.swift ChromeViews.swift SearchIndex.swift DictationSettingsView.swift -o "$build/Earshot"

# The app icon is a layered Icon Composer file. actool turns it into Assets.car (Liquid Glass
# icon for macOS 26) plus Earshot.icns (fallback), as Apple's guidelines ask.
xcrun actool "$(cd ../assets && pwd)/Earshot.icon" --compile "$build" --platform macosx \
  --minimum-deployment-target 26.4 --app-icon Earshot \
  --output-partial-info-plist "$build/icon.plist" >/dev/null

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

# Version: the release number from ../VERSION, a build number that rises with every commit, and the
# commit itself ("-dirty" when built from uncommitted changes). The app shows all three.
version=$(tr -d '[:space:]' < ../VERSION)
build_number=$(git rev-list --count HEAD 2>/dev/null || echo 0)
commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
git diff --quiet HEAD 2>/dev/null || commit="$commit-dirty"
plist="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" \
  -c "Set :CFBundleVersion $build_number" -c "Add :EarshotCommit string $commit" "$plist"
cp "$build/Earshot" "$APP/Contents/MacOS/Earshot"
cp "$build/Assets.car" "$build/Earshot.icns" "$APP/Contents/Resources/"
# Menu bar artwork (a template image: macOS tints it for light and dark menu bars).
cp ../assets/menubar.svg "$APP/Contents/Resources/"
# The app runs its own copy of the helpers, so an install from the DMG needs nothing in ~/.local/bin.
install -m 755 ../scripts/transcribe ../scripts/speakers "$APP/Contents/Resources/"

# Ad-hoc signing alone makes macOS identify the app by the hash of the exact binary, so every build
# looked like a new app and lost its Accessibility and Microphone permission. The explicit
# designated requirement keeps the identity the same across builds.
codesign --force --deep --sign - -r='designated => identifier "com.gaberger.earshot"' "$APP"
# Tell Finder/Launchpad about the app (and its "Open With" file types).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

echo "Installed: $APP (Earshot $version, build $build_number, $commit)"
