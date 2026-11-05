# ADR-2611051236: End-of-meeting detection

**Status:** Accepted
**Date:** 2026-11-05
**Drivers:** People forget to press Stop. A recording left running after the meeting fills the
timeline with hours of silence, and the summary is worse for it.

## Context

Earshot records until the user clicks Stop (`Library.toggleRecording`). The only live audio signal
is `MicRecorder.level`, the capture connection's average power in dB. It measures loudness, not
voice: it cannot tell speech from a fan, a keyboard or a TV.

The two possible mistakes are not equal:

- **Ending too late** costs a few minutes of silence at the end of a file. Whisper's voice-activity
  filter already skips silence.
- **Ending too early** loses the rest of the meeting. Nothing can bring that audio back.

So the detector must fail toward "keep recording" whenever it is unsure.

## Decision

Stop a recording automatically after a long stretch with no speech, behind four guards.

1. **Adaptive speech threshold, not a fixed dB.** The noise floor is the 10th percentile of the
   quietest sample of each second over the last `floorWindow` (5 min). Speech is a sample more
   than `speechMargin` (12 dB) above that floor. A fixed threshold would end meetings in a loud
   room or never end them in a quiet one. Talking has gaps between words, so a window of talk still
   contains floor-level seconds and a long monologue cannot teach the detector that speech is
   silence. A fan that switches on mid-meeting reads as speech until the window forgets the quiet
   (about 5 min), then as silence: the meeting ends no earlier than 5 min after the fan starts.
2. **Armed only after real speech.** The detector cannot end a meeting until it has heard
   `minimumSpeech` (15 s) of speech in total, and the recording is at least `minimumDuration`
   (2 min) long. A recording that never hears any speech ends after `noSpeechLimit` (15 min), so a
   forgotten microphone does not run all night.
3. **A long silence limit, then a warning.** Default `silenceLimit` is 5 min (user choice: Off, 3,
   5, 10, 15, 30 min). Pauses in a real meeting (reading a document, a screen share, thinking) are
   long. The last `warning` (30 s) of the limit is a visible countdown with a beep and a
   "Keep recording" button. Any speech cancels the countdown and restarts the clock.
4. **No evidence is not silence.** A sample gap longer than `maxGap` (5 s: the Mac slept, the app
   stalled) or a dead input (level at the −160 dB floor value, or no value) restarts the silence
   clock instead of counting toward it. A microphone that vanished is reported by the recorder, not
   mistaken for a quiet room.

The decision logic is a pure value type, `EndOfMeetingDetector` in `EarshotApp/EndOfMeeting.swift`,
with no AppKit or AVFoundation dependency. Time is passed in with each sample, so tests are
deterministic. `Library` samples `MicRecorder.level` four times a second while recording, feeds the
detector, and acts on its verdict: `.listening`, `.warning(secondsLeft:)` or `.end`. Ending calls the
same `stopRecording` path as the Stop button, so the file is saved, transcribed and summarized as
usual, and a notice says why it stopped.

The setting lives in `Prefs.autoStopMinutes` (Int, 0 = off, default 5) with a picker in Settings.

## Consequences

- A meeting with more than the limit of true silence ends early. The warning, the beep and the
  longer choices are the mitigation; starting a new recording continues the work.
- Loud non-speech noise (music, a fan) delays the stop by about the floor window. Accepted: that
  is the safe direction.
- Level cannot tell a quiet speaker from the room. A speaker far from the microphone may read as
  silence. The guards above bound the damage; a voice-activity model on the live stream would be
  the better signal and is a separate decision.
- The microphone records the other side of a call only if it comes out of the speakers. A call
  heard on headphones looks like one-sided speech and may end early. The Settings footer says so.

## Implementation

1. `EarshotApp/Tests/EndOfMeetingTests.swift`: the scenarios below, written before the code and
   run by `EarshotApp/Tests/run.sh`.
2. `EarshotApp/EndOfMeeting.swift`: `EndOfMeetingDetector`.
3. `Library` in `EarshotApp/Earshot.swift`: a sampling timer started in `beginRecording` and
   stopped when recording stops, `@Published var endingIn: Int?`, and `keepRecording()`.
4. UI: a countdown banner and "Keep recording" button in `RecordingNow`; a picker in
   `SettingsView`; a help line in `HelpView`.
5. Add `EndOfMeeting.swift` to the `swiftc` lines in `EarshotApp/build.sh` and the test runner.

Scenarios the tests must cover:

- Speech, then silence for the limit: warns, then ends, and the warning lasts `warning` seconds.
- Speech every few minutes with pauses just under the limit: never warns.
- Speech during the countdown: back to listening, and the clock restarts from that speech.
- Never ends before `minimumDuration`, nor before `minimumSpeech` has been heard.
- A recording with no speech ends only at `noSpeechLimit`.
- The same limit works in a loud room (floor −30 dB) and a quiet one (floor −60 dB).
- Ten minutes of nonstop talking (with word gaps) does not read as silence.
- A fan that switches on does not end the meeting in its first 5 minutes, and does not keep it
  open forever.
- A gap in samples, and dead-input samples, restart the clock.
- Property: for 200 random level sequences, the detector never ends unless a true silence of at
  least `silenceLimit` immediately precedes the end. The oracle is computed from the generated
  sequence, not from the detector.
- `silenceLimit` of 0 (Off) never ends.

Gate: the app typechecks with all its sources and `bash EarshotApp/Tests/run.sh` exits 0. The
test file fails if fewer than 12 checks ran, so an empty run is not a pass.

## References

- EarshotApp/Earshot.swift: `Library.startRecording`/`stopRecording`, `MicRecorder.level`
- ADR-2611021633: pure, injected-dependency modules tested without the platform framework
