# ADR-2611241100: The call-audio source is an input device or all system audio, in the Recording card

**Status:** Completed
> 2026-11-24 Completed: built in aa24048. Gate `node --test EarshotApp/Tests/call-audio*.test.mjs` passes; the owner confirmed it on live calls in build 248.
**Date:** 2026-11-24
**Amends:** ADR-2611240900 (decisions 1 and 2; its decisions 3 to 7 stand)
**Drivers:** The owner tried the first build. The picker listed None, All system audio and every regular app
that was running, in a section of its own. They expected the list of **input devices**, and said it belongs
in the Recording section.

## Decision

1. **The picker's values are** None (default), All system audio, and **an input device**: any audio input
   macOS lists (`AVCaptureDevice` audio inputs), including virtual ones such as BlackHole or Loopback. The
   device chosen as the microphone is not offered a second time. **"One app" is removed**, together with the
   running-app list.
2. **It is one row in Settings → Recording, directly under Microphone,** not a section of its own. The
   permission row appears under it only when the choice needs one.
3. **An input device is captured by a second capture session** and mixed with the microphone by the same
   rule as the tap (ADR-2611240900 decision 3: one 16 kHz mono WAV, the remote voice not doubled). It needs no
   permission beyond the microphone's; the System Audio Recording permission is asked only for All system
   audio.
4. **A chosen device that is unplugged, or is not there when Record is pressed,** does not stop the recording
   or fall back to another device: the microphone keeps recording and a visible message says call audio is
   not being recorded.
5. **A stored choice of "One app" from the first build** reads as None.
6. **Layering is unchanged:** the choice and the mix are pure; a device source and the tap are driven adapters
   behind the same `CallAudioTap` port.

## Gate

Scenarios from the spec for this ADR, run through `node --test EarshotApp/Tests/call-audio.test.mjs`:
the three choices (no app choice exists); the row sits under Microphone in the Recording card; a device
source starts and stops with Record and needs no System Audio permission; an unplugged or missing device
leaves the microphone recording with a message; the microphone device is not offered twice; an old
"One app" setting reads as None.
