# ADR-2611061830: Offer to record when a call starts

**Status:** Accepted
**Date:** 2026-11-06
**Drivers:** People forget to press Record at the start of a call. ADR-2611061700 already reads, from
Core Audio, whether another app is capturing the microphone. The same signal says a call has begun.

## Decision

While Earshot is running and not recording, watch for the start of a call and **ask**; never record
without a click.

1. **Pure detector.** `CallStartDetector` (`EarshotApp/CallStart.swift`) takes the probe's answer
   (`Bool?`), whether Earshot is recording, and the time. It returns `.offer` once another app has
   captured the microphone for `minimumCapture` (10 s) without a break. Siri and dictation are
   shorter than that.
2. **One offer per call.** After an offer, or after the user starts recording by any route, the
   detector is quiet until nothing has captured for `quietReset` (15 s). A mute, a reconnect or a
   one-sample probe blip in the middle of a call therefore does not ask again.
3. **No evidence is not an event.** A nil answer, or a gap in samples over `maxGap` (10 s, the Mac
   slept), restarts the capture streak and never resets the episode.
4. **The offer.** A system notification, "<App> is using the microphone. Record this meeting?", with
   **Record** and **Not for <App>**. Record starts the same path as the Record button. The notification
   is also what brings Earshot forward. The ignore list is `Prefs.callOfferIgnoredApps` (bundle ids).
5. **The probe reports who.** `OtherAppMicProbe` returns the capturing processes with bundle id and
   pid, so the offer can name the app (`NSRunningApplication` localized name, else the bundle id).
6. **Settings.** "Offer to record when a call starts" (`Prefs.offerOnCall`, default on) and
   "Open Earshot at login" (`SMAppService.mainApp`, default off). The second is what makes the first
   work with no window open: an app cannot be started by a call, so it has to already be running in the
   menu bar. Both are described in Help.

## Consequences

- Any app holding the microphone for 10 s triggers one offer per episode (a dictation tool left on, a
  voice memo). **Not for <App>** is the escape hatch.
- If Earshot is not running, nothing happens. That is stated beside the login setting.
- Notification permission is requested the first time an offer is due. If it is refused, the offer falls
  back to a banner inside the window and a badge on the menu bar item is not attempted.
- The first start of Earshot at login shows the macOS "Login Items" approval; nothing else is installed.

## Gate

`cd EarshotApp && swiftc -typecheck -parse-as-library -swift-version 5 -target arm64-apple-macosx26.4 Earshot.swift RichText.swift Chunking.swift EndOfMeeting.swift CallStart.swift && bash Tests/run.sh`

Tests (`Tests/CallStartTests.swift`, first): offers at 10 s of capture and not before; only once per
call; never while recording; no offer after a recording stops mid-call; a 5 s capture never offers;
15 s of quiet re-arms; a 3 s break mid-call does not re-offer; nil changes nothing; a sample gap
restarts the streak; at least 10 checks must run.
