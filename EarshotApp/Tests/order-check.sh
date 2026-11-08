#!/usr/bin/env bash
# Guards the order of the dictation pipeline (ADR-2611080900): the spoken command must be taken off the RAW
# transcript before the tidy-up pass and the dictionary run. Tidy up is told to fix punctuation, so it could turn
# the spoken words "exclamation point" into a "!" and the command would silently never fire.
# It is a blunt source check (line order), and it fails itself if it cannot find the three steps.
set -euo pipefail
cd "$(dirname "$0")/.."
f=DictationService.swift
count=$(grep -c "SpokenSend.apply(" "$f" || true)
apply=$(grep -n "SpokenSend.apply(" "$f" | head -1 | cut -d: -f1 || true)
tidy=$(grep -n "await tidy(" "$f" | head -1 | cut -d: -f1 || true)
dict=$(grep -n "DictationDictionary.load().apply" "$f" | head -1 | cut -d: -f1 || true)
if [ -z "$apply" ] || [ -z "$tidy" ] || [ -z "$dict" ]; then
  echo "VACUOUS: could not find all three steps in $f (apply=$apply tidy=$tidy dictionary=$dict)"; exit 1
fi
echo "lines: SpokenSend.apply=$apply tidy=$tidy dictionary=$dict"
fail=0
if [ "$count" -eq 1 ]; then echo "PASS SpokenSend.apply is called exactly once"; else echo "FAIL SpokenSend.apply is called $count times"; fail=1; fi
if [ "$apply" -lt "$tidy" ]; then echo "PASS the spoken command is parsed before the tidy-up pass"; else echo "FAIL the command is parsed after the tidy-up pass"; fail=1; fi
if [ "$apply" -lt "$dict" ]; then echo "PASS the spoken command is parsed before the dictionary"; else echo "FAIL the command is parsed after the dictionary"; fail=1; fi
exit $fail
