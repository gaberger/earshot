# ADR-2611241200: Stop-when-quiet hears the call audio, so a call you only listen to is not cut off

**Status:** Completed
> 2026-11-24 Completed: built in aa24048. Gate `node --test EarshotApp/Tests/call-audio*.test.mjs` passes; the owner confirmed it on live calls in build 248.
**Date:** 2026-11-24
**Amends:** ADR-2611240900 and ADR-2611241100 (adds to them; nothing they decide changes)
**Drivers:** Recording a call you only listen to. `EndOfMeetingDetector` is fed `micLevel()` (the
microphone's level) and whether another app is capturing the microphone. With call audio on and the
microphone silent, the detector sees silence: it stops after the no-speech limit (15 min) if nobody was
heard, or the silence limit (5 min by default) after the last speech. A call app that lets go of the
microphone while muted also reads as "the call ended", which stops the recording about a minute after the
first 30 seconds of the call, with the call still playing.

## Decision

1. **The detector is fed the louder of the microphone level and the call-audio level** (dB, per sample),
   when a call-audio source is recording. With no call-audio source, it is fed the microphone level alone,
   exactly as before.
2. **Call audio playing counts as a call in progress.** While the call-audio level is above the speech
   threshold, the "call ended" rule (the other app letting go of the microphone) does not fire and its
   clock restarts, as if the other app were still capturing.
3. **Call audio that is silent is silence like any other.** A call that has really ended, with nothing
   playing and the microphone quiet, still stops after the usual limits.
4. **The level of the call audio is measured by the adapter** (the tap and the device source) and passed up
   as a plain number. The detector stays a pure value type with no capture framework in it.
5. **A source that fails or is unplugged mid-recording reports no level** (not silence), so the detector
   treats it as no evidence and keeps recording, as for any missing sample.
6. **Settings text** under Stop when quiet says that call audio counts as activity when it is on.

## Gate

Spec scenarios run through `node --test EarshotApp/Tests/call-audio.test.mjs` and the existing
EndOfMeetingTests: a call-audio level above the threshold keeps a silent-mic recording going past both the
no-speech and the silence limits; the same with no call source stops as before; a muted mic with the other
app letting go does not end a recording while call audio plays; silence on both stops on time; a missing
level is no evidence; the detector imports no capture framework.
