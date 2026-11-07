#!/usr/bin/env bash
# Guards against the in-app Help (HelpView in Earshot.swift) going stale. It is a blunt check: each
# user-facing feature name below must appear in the Help text. It cannot judge whether the words are
# right, only that a feature was not left out. It fails itself if it cannot find the Help at all,
# so it can never pass on an empty extraction.
set -euo pipefail
cd "$(dirname "$0")/.."

help=$(awk '/^struct HelpView: View/{f=1} f{print} /private func section/{if(f) exit}' Earshot.swift)
lines=$(printf '%s\n' "$help" | wc -l | tr -d ' ')
if [ -z "$help" ] || [ "$lines" -lt 50 ]; then
  echo "VACUOUS: could not read HelpView from Earshot.swift ($lines lines)"
  exit 1
fi

phrases=(
  "Dictation"
  "Notes"
  "Tap to start, tap to stop"
  "Fix words it mishears"
  "Tidy up what I say"
  "Highlight the window"
  "Press Return after typing"
  "stops the voice"
  "spoken replies"
  "MCP"
  "agent"
)
missing=0
for p in "${phrases[@]}"; do
  if grep -qF -- "$p" <<<"$help"; then
    echo "PASS Help mentions: $p"
  else
    echo "FAIL Help is missing: $p"
    missing=$((missing + 1))
  fi
done
echo "${#phrases[@]} phrases checked, $missing missing"
exit $((missing > 0 ? 1 : 0))
