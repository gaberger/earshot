#!/usr/bin/env bash
# Builds and runs the rich-text editor tests. Exit code 0 means every test passed.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swiftc -swift-version 5 -target arm64-apple-macosx26.4 RichText.swift Tests/main.swift -o "$out/tests"
"$out/tests"
