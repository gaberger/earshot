---
name: earshot-permissions
description: Why macOS permissions (Accessibility, Microphone) stop working for Earshot and how to diagnose and fix it. Use when the app says it is not allowed to type, the warning will not go away, or a rebuild lost a permission.
---

# macOS permissions

## The cause we hit

`codesign --sign -` (ad hoc) identifies the app to macOS by the **hash of the exact binary**, so every
build looked like a new app and its Accessibility grant went stale. `EarshotApp/build.sh` now signs with
the requirement `designated => identifier "com.gaberger.earshot"`, which does not change between builds.
Check it: `codesign -d -r- ~/Applications/Earshot.app` must not mention `cdhash`.

## Diagnose with the log, not by guessing

```bash
/usr/bin/log show --last 30m --predicate 'process == "tccd" AND eventMessage CONTAINS[c] "earshot"' --style compact | tail -20
```

`Failed to match existing code requirement … kTCCServiceAccessibility` means a stale entry from an older
build. Toggling it off and on does not replace the saved requirement.

## Fix

`tccutil reset Accessibility com.gaberger.earshot`, then switch Earshot on in System Settings → Privacy &
Security → Accessibility. The app has a **Reset and allow** button that does the same
(`DictationService.resetAccessibilityPermission`). Without Accessibility, dictation puts the text on the
clipboard so nothing is lost.

## Rules

- The permission database cannot be read without Full Disk Access; use the log.
- Do not tell the owner it is fixed until they have granted it and rebuilt once more to see it survive.
- The shortcut (a Carbon hotkey) needs no Input Monitoring; the microphone prompt appears on first use.
