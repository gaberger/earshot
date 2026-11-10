# ADR-2611101015: A meeting capture that ends by itself resets the Record button and says why

**Status:** Accepted
**Date:** 2026-11-10
**Drivers:** The owner clicked Stop at the end of a meeting and the button kept saying "Stop". The log
(`~/Library/Logs/Earshot.log`, 2026-11-10) shows what happened: at 14:45 UTC the disk filled, AVFoundation
ended the capture by itself, and Earshot transcribed the file — but the button and the menu bar timer kept
running for 27 more minutes. The click at 15:12 logged "stop pressed but no recorder". The next click
started a new recording that failed at once with "Disk Full", and the button said "Stop" again.

## Context

Three defects combined:

1. `recordingFinished` cleared the recorder but never `recording` or `startedAt`. Every UI that shows
   "Stop" (menu bar panel, menu bar timer, the recording screen, the Record bar) keeps saying it.
2. `stopRecording`'s "no recorder" branch cleared `recording` but not `startedAt`. The menu bar panel and
   timer read `startedAt`, so they still said "Stop" after the click.
3. `MicRecorder` drops any error flagged `AVErrorRecordingSuccessfullyFinishedKey = true`, since normal
   stops are reported that way. A disk-full stop is flagged the same way, so the owner got no notice at all
   and lost the last 27 minutes of the meeting without knowing.

## Decision

1. **One place resets the recording state.** Every way a capture ends — the user's Stop, the automatic stop,
   a stop with no recorder, and the capture ending by itself — clears `recording`, `startedAt` and the
   end-of-meeting watch.
2. **A capture that ends without being asked to is reported**, even when AVFoundation flags it as
   "finished successfully". Disk full gets its own message telling the owner to free space. The audio up to
   that point is kept and transcribed as before.
3. **Pure logic, tested without UI**: `RecordingEnd.classify(stopRequested:error:)` in `RecordingEnd.swift`
   decides between a normal stop, a failed stop, and a capture that ended by itself, and words the notice.

Not in this change: refusing to start when the disk is nearly full. `df` showed 662 MB free while
AVFoundation reported "Disk Full", so a free-space threshold would not have caught this case.

## Consequences

- The button can no longer get stuck on "Stop": the state follows the capture, not the click.
- A disk-full meeting now shows a notice at the moment it happens rather than nothing.

## Implementation

- `EarshotApp/RecordingEnd.swift` — `RecordingEnd.classify`.
- `EarshotApp/Earshot.swift` — `MicRecorder` remembers whether stop was requested and passes the raw error;
  `Library` resets state in one function and shows the classified notice.
- Gate: `EarshotApp/Tests/RecordingEndTests.swift` (fails itself if fewer than 12 checks ran), in `Tests/run.sh`.

## References

- ADR-2611051236 (end-of-meeting detection), ADR-2611061700 (call-aware end detection).
