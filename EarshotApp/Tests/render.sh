#!/usr/bin/env bash
# Renders the settings views to PNGs in /tmp/earshot-ui. Exit code 0 means every scene rendered non-blank.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
rm -f /tmp/earshot-ui/*.png
swiftc -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library SettingsKit.swift HomeView.swift RecordingViews.swift AppNav.swift NotesView.swift ChromeViews.swift SearchIndex.swift DictationSettingsView.swift HotKey.swift DictationDictionary.swift Dictation.swift Tests/RenderUI.swift -o "$out/render"
"$out/render"
