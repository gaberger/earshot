#!/usr/bin/env bash
# Builds and runs the rich-text editor tests and the ChunkingTests. Exit code 0 means every test passed.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swiftc -swift-version 5 -target arm64-apple-macosx26.4 RichText.swift Tests/main.swift -o "$out/tests"
"$out/tests"
# ChunkingTests uses @main, so it is parsed as a library rather than as top-level code.
swiftc -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library Chunking.swift Tests/ChunkingTests.swift -o "$out/chunking-tests"
"$out/chunking-tests"
# EndOfMeetingTests also uses @main and fails itself if fewer than 12 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library EndOfMeeting.swift Tests/EndOfMeetingTests.swift -o "$out/end-of-meeting-tests"
"$out/end-of-meeting-tests"
# CallStartTests also uses @main and fails itself if fewer than 10 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library CallStart.swift Tests/CallStartTests.swift -o "$out/call-start-tests"
"$out/call-start-tests"
