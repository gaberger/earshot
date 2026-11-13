# ADR-2611130933: Show the call offer in Earshot's own floating panel

**Status:** Accepted
**Date:** 2026-11-13
**Amends:** ADR-2611061830 (point 4, the offer)
**Drivers:** The owner reported that Earshot "still does not detect a Zoom meeting". The log shows that
detection works: on 2026-11-12 and 2026-11-13 the detector offered for Zoom (`us.zoom.xos`) and Slack
huddles. Every offer, though, ended in `notification not allowed, showing a notice instead`. A probe
bundle signed the way `build.sh` signs Earshot (ad hoc, `--sign -`), launched through LaunchServices,
gets `authorizationStatus == .notDetermined` and then `UNErrorDomain Code=1 "Notifications are not
allowed for this application"` from `requestAuthorization`. macOS never shows the prompt. This Mac has
no code-signing identity (`security find-identity -v -p codesigning` lists 0). So the offer always fell
back to a notice inside Earshot's window, and that window sits behind the call. To the user that looks
the same as not detecting the call.

## Decision

1. **The offer is a floating panel that Earshot draws**, so it does not depend on notification
   permission. It is a non-activating `NSPanel` at status-bar level that joins all Spaces and full-screen
   apps, sits at the top right of the screen that holds the mouse, and never takes focus away from the
   call. It reads "<App> is using the microphone" / "Record this meeting?" and has **Record**,
   **Not for <App>** and a close button.
2. **The system notification is still posted when macOS allows it**, for the Notification Center
   history. The panel is shown either way, so a correctly signed build behaves the same.
3. **Errors are logged, not swallowed.** `requestAuthorization` and `add` errors are written to the log
   with their domain and code.
4. **The panel goes away by itself** (pure rule `CallOfferPanelRule` in `CallStart.swift`): when
   recording starts by any route, after `callEndedAfter` (15 s) of no capture, or `timeout` (120 s)
   after it appeared. A nil probe counts toward neither.
5. The in-window notice stays as a second trace of the offer.

## Consequences

- An offer is now visible during any call, whatever the signature or the notification settings.
- A panel that the user did not ask for appears above other apps. It is small, takes no focus, goes
  away by itself, and **Not for <App>** and the Settings toggle turn it off.
- Signing Earshot with a real identity would bring back notifications. It is not needed for the offer.

## Gate

`cd EarshotApp && bash Tests/run.sh`, where `Tests/CallOfferPanelTests.swift` (written first) checks
the wording and the dismissal rule: it stays while the call goes on; it goes 15 s after capture stops and
not before; a short break does not dismiss it; it goes at once when recording starts; it goes at the
timeout; nil samples dismiss nothing. It fails itself if fewer than 10 checks ran.
