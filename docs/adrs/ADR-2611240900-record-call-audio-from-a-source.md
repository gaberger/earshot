# ADR-2611240900: Record the other side of a call from a chosen audio source

**Status:** Completed
> 2026-11-24 Completed: built in 7bc8558 and amended by ADR-2611241100 and ADR-2611241200. Gate `node --test EarshotApp/Tests/call-audio*.test.mjs` passes; the owner confirmed it on live calls in build 248.
**Date:** 2026-11-24
**Drivers:** Earshot records one microphone only (`MicRecorder`, one `AVCaptureDeviceInput`). On headphones the
remote participants are never recorded; on speakers they are recorded poorly, with echo. The owner wants
Earshot to capture call audio from a source, without the user installing BlackHole or Loopback and building
an aggregate device.

## Decision

1. **A call-audio source setting** (Settings → Recording), with three values:
   - **None** (default): today's behaviour, microphone only.
   - **All system audio**: everything the Mac plays.
   - **One app**: a running app chosen from a list (Zoom, Teams, Slack, a browser). Only that app's output.
2. **Capture uses a Core Audio process tap** (`CATapDescription`, macOS 14.2+), not ScreenCaptureKit. It needs
   only the "System Audio Recording Only" permission, not Screen Recording. Where the OS is older, the
   setting is hidden and the microphone path is unchanged.
3. **One file, as before.** The tap and the microphone are mixed to the same 16 kHz mono WAV, so
   transcription, speaker labelling and summaries are untouched. The tap is captured when Record starts and
   stops with it; nothing is written elsewhere.
4. **The permission is asked when the user picks a source**, not at first launch, with the same card rules as
   ADR-2611142200 (Allow, then Open Settings if refused). Refusal falls back to microphone only and says so.
5. **Dictation and Notes never use the tap.** Only Recordings (meetings, calls) does.
6. **Privacy promise is unchanged in kind:** audio stays on this Mac. The README, the Settings footnote, the
   in-app Help, `docs/PRIVACY.md` and the `earshot-privacy-map` skill are updated together, because what is
   recorded has widened to other people's voices.
7. **Layering:** the choice of source and the mixing rule are pure and live in the domain/use-case code; the
   Core Audio tap is a driven adapter behind a port, as `MicRecorder` is.

## Consequences

- Echo: with speakers and a mic open, the mix holds the remote voice twice. The mixer must not double it;
  this is the main risk and gets its own test.
- The remote side is labelled by the existing speaker model, not by who joined the call.
- Consent for recording others stays the user's responsibility; Help says so.

## Gate

To be written as a spec (`hexa spec draft`) and accepted by a person before any code. Expected scenarios:
source None changes nothing; a chosen app that quits mid-recording ends the tap but not the recording; a
refused permission falls back to microphone only with a visible message; the mix of mic and tap stays a
16 kHz mono WAV; Dictation and Notes never request the tap permission.
