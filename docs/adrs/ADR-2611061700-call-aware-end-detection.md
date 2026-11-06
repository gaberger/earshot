# ADR-2611061700: Call-aware end-of-meeting detection

**Status:** Accepted
**Date:** 2026-11-06
**Drivers:** ADR-2611051236 did not stop a real recording. The log shows the room at -54 dB with
noise bumps to -42..-37 dB every 20-30 s, just over the 12 dB speech margin, so the silence clock
reset for the whole meeting. Loudness cannot tell a quiet room from quiet talk.

## Context

When the meeting is a call (Zoom, Teams, Meet, Slack huddle, FaceTime), the call app holds the
microphone open for the whole call, muted or not, and releases it when the call ends. macOS 14.2+
exposes this: Core Audio lists every process with an audio connection
(`kAudioHardwarePropertyProcessObjectList`), and each reports `kAudioProcessPropertyIsRunningInput`,
its PID and its bundle id. That is a direct signal for "a meeting is in progress", not an inference.

## Decision

Add a second signal to `EndOfMeetingDetector`: whether any process **other than Earshot** is
capturing input (`otherAppCapturing: Bool?`; nil = the probe failed, which changes nothing).

1. **Another app capturing holds the recording open.** The silence clock restarts on every sample.
   Time spent in that state is `callSeconds`.
2. **The other app letting go ends the meeting quickly.** Once `callSeconds >= minimumCall` (30 s),
   the silence limit drops to `callEndedLimit` (60 s, never more than the user's limit) and the
   recording is armed even if the level detector heard little speech. The last `warning` seconds are
   the usual countdown with "Keep recording"; the other app capturing again cancels it. Speech
   does not cancel it, because room noise is exactly what the level detector cannot judge.
3. **Unchanged guards.** `minimumDuration`, "Off" (`silenceLimit` 0), and fail-toward-recording
   still apply. A call shorter than `minimumCall` (Siri, dictation) does not shorten anything.
4. **The probe is an adapter.** `OtherAppMicProbe` in `Earshot.swift` reads Core Audio, excludes
   `getpid()`, and returns nil when a property read fails. `Library.tick()` samples it once a second.
   The decision stays in the pure detector.

## Consequences

- A call ends the recording about a minute after the user leaves the call, instead of never.
- Any app that keeps the mic open (a dictation tool, a browser tab left on a meeting page) keeps
  Earshot recording. This is the safe direction; the user can still press Stop.
- In-person meetings, and calls where no other app captures the mic, still rely on the level
  detector and its limits.
- Zoom's window is not inspected: the mic signal is more reliable and needs no extra permission
  (no Accessibility, no Screen Recording).

## Gate

`cd EarshotApp && swiftc -typecheck -parse-as-library -swift-version 5 -target arm64-apple-macosx26.4 Earshot.swift RichText.swift Chunking.swift EndOfMeeting.swift && bash Tests/run.sh`

Tests, written first in `EndOfMeetingTests.swift`: another app capturing holds a silent recording
open past the limit; a call of at least 30 s then release ends after about 60 s with a warning in
the last 30 s; a call under 30 s then release leaves the normal limit; capturing again during the
countdown cancels it; nil behaves as before; Off never ends; the existing property test is
unchanged and still passes.
