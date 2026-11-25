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
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library PrivateFiles.swift DictationLog.swift Tests/DictationLogTests.swift -o "$out/dictation-log-tests"
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
# SpeakerMergeTests (ADR-2611141800): the native speakers tool matches the Python oracle byte for byte, and its
# transcript rewrite is atomic (readers see old or new, never partial). Fails itself if fewer than 25 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library Tools/AudioDecode.swift Tools/SpeakerMerge.swift Tests/SpeakerMergeTests.swift -o "$out/speaker-merge-tests"
"$out/speaker-merge-tests"
# HighlightTests also uses @main and fails itself if fewer than 30 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library Dictation.swift WindowHighlight.swift Tests/HighlightTests.swift -o "$out/highlight-tests"
"$out/highlight-tests"
# PreferencesMigrationTests: settings under the old bundle IDs are copied once; fails itself if fewer than 17 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library PreferencesMigration.swift Tests/PreferencesMigrationTests.swift -o "$out/prefs-migration-tests"
"$out/prefs-migration-tests"
# HelperRunTests (ADR-2611072100 A1, A2): a hung helper is stopped with its children, and log lines never carry
# helper output. Fails itself if fewer than 27 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library HelperRun.swift Tests/HelperRunTests.swift -o "$out/helper-run-tests"
"$out/helper-run-tests"
# PrivateFilesTests (ADR-2611072100 A3): notes.json, its folder and the log are owner-only. Fails itself if fewer than 15 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library PrivateFiles.swift DictationLog.swift Tests/PrivateFilesTests.swift -o "$out/private-files-tests"
"$out/private-files-tests"
# HomeActionTests (ADR-2611072100 B1): which buttons a Home row shows. Fails itself if fewer than 15 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library Brand.swift BrandColors.swift HomeView.swift Tests/HomeActionTests.swift -o "$out/home-action-tests"
"$out/home-action-tests"
# MeetingNotesTests (ADR-2611142100): notes typed during a meeting reach the summary. Fails itself if fewer than 7 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library MeetingNotes.swift Tests/MeetingNotesTests.swift -o "$out/meeting-notes-tests"
"$out/meeting-notes-tests"
# SetupChecklistTests (ADR-2611142200): the first-launch setup card. Fails itself if fewer than 15 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library Brand.swift BrandColors.swift SetupCard.swift Tests/SetupChecklistTests.swift -o "$out/setup-checklist-tests"
"$out/setup-checklist-tests"
# SubmitTests also uses @main and fails itself if fewer than 15 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library Dictation.swift Tests/SubmitTests.swift -o "$out/submit-tests"
"$out/submit-tests"
# earshot-speak: the Stop hook that speaks replies (ADR-2611071600); it fails itself if fewer than 56 checks ran.
python3 -I ../scripts/earshot-speak-test
# SpeechStopTests also uses @main and fails itself if fewer than 7 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library Dictation.swift Tests/SpeechStopTests.swift -o "$out/speech-stop-tests"
"$out/speech-stop-tests"
# The in-app Help must mention every user-facing feature (it went several features stale once).
bash Tests/help-check.sh
# PasteGuardTests also uses @main and fails itself if fewer than 22 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library PasteGuard.swift Tests/PasteGuardTests.swift -o "$out/paste-guard-tests"
"$out/paste-guard-tests"
# BrandTests also uses @main and fails itself if fewer than 23 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library Brand.swift Tests/BrandTests.swift -o "$out/brand-tests"
"$out/brand-tests"
# The views use the brand tokens, the root tint is set, and the icon follows concept B (ADR-2611072000).
bash Tests/brand-check.sh
# DetailNavTests also uses @main and fails itself if fewer than 18 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library DetailNav.swift Tests/DetailNavTests.swift -o "$out/detail-nav-tests"
"$out/detail-nav-tests"
# SpokenSendTests also uses @main and fails itself if fewer than 30 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library Dictation.swift SpokenSend.swift Tests/SpokenSendTests.swift -o "$out/spoken-send-tests"
"$out/spoken-send-tests"
# The spoken send command is parsed from the raw transcript, before tidy-up and the dictionary (ADR-2611080900).
bash Tests/order-check.sh
# RecordingEndTests (ADR-2611101015) also uses @main and fails itself if fewer than 12 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library RecordingEnd.swift Tests/RecordingEndTests.swift -o "$out/recording-end-tests"
"$out/recording-end-tests"
# CallOfferPanelTests (ADR-2611130933) also uses @main and fails itself if fewer than 10 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library CallStart.swift Tests/CallOfferPanelTests.swift -o "$out/call-offer-panel-tests"
"$out/call-offer-panel-tests"
# ModelCatalogTests (ADR-2611141630) also uses @main and fails itself if fewer than 25 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library ModelCatalog.swift Tests/ModelCatalogTests.swift -o "$out/model-catalog-tests"
"$out/model-catalog-tests"
# SummaryFormatTests (ADR-2611181715) also uses @main and fails itself if fewer than 88 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library SummaryFormat.swift Tests/SummaryFormatTests.swift -o "$out/summary-format-tests"
"$out/summary-format-tests"
# SummaryRecoveryTests (ADR-2611230908): a passage Apple's safety filter refuses is skipped, not fatal.
# Fails itself if fewer than 40 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library Chunking.swift SummaryFormat.swift SummaryRecovery.swift Tests/SummaryRecoveryTests.swift -o "$out/summary-recovery-tests"
"$out/summary-recovery-tests"
# WindowLayoutTests: Home's setup cards must not push the split view up under the title bar (1.5.3).
# Hosts a real NavigationSplitView in an NSWindow. Fails itself if fewer than 7 checks ran.
swiftc -O -swift-version 5 -target arm64-apple-macosx26.4 -parse-as-library Brand.swift BrandColors.swift SetupCard.swift HomeView.swift Tests/WindowLayoutTests.swift -o "$out/window-layout-tests"
"$out/window-layout-tests"
# Call-audio spec scenarios S01-S26 (ADR-2611240900), run through node --test.
node --test Tests/call-audio.test.mjs
node --test Tests/call-audio-devices.test.mjs Tests/call-audio-stop.test.mjs
