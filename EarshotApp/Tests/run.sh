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
# DictationTests also uses @main and fails itself if fewer than 54 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library Dictation.swift Tests/DictationTests.swift -o "$out/dictation-tests"
"$out/dictation-tests"
# HotKeyTests also uses @main and fails itself if fewer than 30 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library HotKey.swift Tests/HotKeyTests.swift -o "$out/hotkey-tests"
"$out/hotkey-tests"
# DictionaryTests also uses @main and fails itself if fewer than 26 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library DictationDictionary.swift Tests/DictionaryTests.swift -o "$out/dictionary-tests"
"$out/dictionary-tests"
# SearchTests also uses @main and fails itself if fewer than 24 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library SearchIndex.swift Tests/SearchTests.swift -o "$out/search-tests"
"$out/search-tests"
# DictationLogTests also uses @main and fails itself if fewer than 17 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library DictationLog.swift Tests/DictationLogTests.swift -o "$out/dictation-log-tests"
"$out/dictation-log-tests"
# NoteSessionTests also uses @main and fails itself if fewer than 17 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library Dictation.swift NoteSession.swift Tests/NoteSessionTests.swift -o "$out/note-session-tests"
"$out/note-session-tests"
# CleanupTests also uses @main and fails itself if fewer than 24 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library Dictation.swift DictationCleanup.swift Tests/CleanupTests.swift -o "$out/cleanup-tests"
"$out/cleanup-tests"
# earshot-mcp: the MCP server is driven over stdio (ADR-2611071100); it fails itself if fewer than 24 checks ran.
python3 -I ../scripts/earshot-mcp-test
# earshot-mcp hardening: hostile filesystem and protocol input; it fails itself if fewer than 100 checks ran.
python3 -I ../scripts/earshot-mcp-hardening-test
# speakers: the transcript rewrite must be atomic (readers see old or new, never partial); fails itself if fewer than 7 checks ran.
python3 -I ../scripts/speakers-test
