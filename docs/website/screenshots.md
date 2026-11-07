# Website screenshots

**What these are.** Every image in `site/img/` is a PNG render of the real SwiftUI views, produced by
`EarshotApp/Tests/render.sh` with made-up sample data (names, times and meeting titles are invented).
They are not OS screenshots: there is no window chrome, no menu bar, no desktop, and the harness does
not draw the dictation flames or the dictation pill. The page must say "sample data" next to them.
All renders are dark theme only. The renders used were the ones in `/tmp/earshot-ui/` written at 15:43 on
2026-11-07; `render.sh` does not exist in this worktree's commit (it is in the main checkout), so it was
not re-run here. Re-run it in the main checkout and re-copy if the UI changes.

| File | Size (px) | What it factually shows | Section | Suggested alt text |
|---|---|---|---|---|
| `recordings-home.png` | 760 x 640 | The Recordings home: heading "Good afternoon", the line "Press Record, or drop an audio or video file here. Everything stays on this Mac.", filter pills "All 5" and "Errors 1", rows grouped under TODAY and YESTERDAY (a title, time, duration and "transcribed / summarized" status; one imported .m4a with a spinner; one orange row "Could not transcribe: the audio file is empty"), and a bottom bar with Import, a red Record button and the Command-R hint. | what (hero) | Earshot's recordings list in a dark window: meetings grouped by day with durations and transcribed or summarized status, and a red Record button with an Import button at the bottom. |
| `recording-live.png` | 760 x 520 | A recording in progress: red "Recording" label, timer 12:34, a red level waveform, the input "MacBook Pro Microphone", a Stop button, and the note "Everything stays on this Mac. The text appears here when you stop." | how | Earshot recording a meeting: a timer reading 12:34, a red audio waveform, the MacBook Pro Microphone as input, and a Stop button. |
| `recording-detail-header.png` | 760 x 156 | Only the header of a finished recording: title "Weekly sync with the platform team", date and time, badges "42 min", "Transcribed", "Summarized", buttons Summarize, Copy and Finder, and Summary / Transcript tabs. The summary, transcript and speaker labels themselves are NOT in this image. | how | The top of a finished recording in Earshot: its title, 42 minute length, Transcribed and Summarized badges, Summarize, Copy and Finder buttons, and Summary and Transcript tabs. |
| `recording-auto-stop.png` | 760 x 520 | A long recording (36:50) with a flat, dotted waveform and an orange banner "No one has spoken for a while. Stopping in 24 s" with a "Keep recording" button. | how | Earshot warning that no one has spoken for a while and that the recording will stop in 24 seconds, with a Keep recording button. |
| `dictation-settings.png` | 680 x 761 | Dictation settings, cropped (see below): Shortcut (^-Option-Space, Hold / Tap mode), Highlight toggle ("A little fire around the window your words will be typed into"), "Tidy up what I say" toggle, "Press Return after typing" toggle, Corrections list (ear shot to Earshot, kay eight s to k8s), and the footnote that nothing is typed into password fields. | dictation | Earshot's dictation settings: a shortcut with Hold and Tap modes, toggles for window highlight, tidying up speech and pressing Return, and a list of word corrections. |
| `notes-list.png` | 760 x 640 | The Notes page: "Record a note" button, text "Your own voice notes... Nothing is typed into other apps.", Clear all, notes grouped TODAY / YESTERDAY, each with a time, the transcribed text, a length in seconds, and copy and delete icons. | notes | Earshot's Notes page listing short voice notes as text with their times and lengths, each with copy and delete buttons. |
| `notes-recording.png` | 760 x 520 | Notes while recording a note: a card with "Recording", timer 0:37, waveform and Stop button, the Record a note button dimmed, and one saved note below. | notes | Earshot recording a voice note: a red waveform with a 0:37 timer and a Stop button above a saved note. |
| `sidebar-status.png` | 260 x 164 | Two status cards: "Ready - on this Mac" with "Whisper - MacBook Pro Microphone" (green dot), and "Recording" with "Recording... 12:41" (red dot). | privacy | Two Earshot status cards: Ready on this Mac with the Whisper model and microphone named, and a Recording card with a 12:41 timer. |

**Crop disclosure.** `dictation-settings.png` is `dictation-on.png` with the top 185 px removed. The
uncropped render (and `dictation-page.png`) shows an orange warning "Earshot can't type for you yet.
Press Reset and allow, then switch Earshot on in the list.", which is a permission-problem state and a bad
thing to show a stranger. The crop begins at the Shortcut group and drops the "Dictate into any app"
toggle row with its banner. Nothing was painted or altered otherwise. The dictation toggles in this crop
are in a dark-track "on" style that is hard to read as on (see defects).

**Notes for the web designer.**
- All images are dark UI. Place them on a dark or neutral frame/card; on a white page background the
  borderless dark rectangles look cut out. Give them a rounded border or shadow.
- Native sizes are small (760 px wide at most). Do not stretch them past their pixel width; they are
  already 2x-unfriendly. Cap display width at the native width.
- Aspect ratios: recordings-home and notes-list 19:16; recording-live, recording-auto-stop and
  notes-recording 38:26 (about 1.46:1); recording-detail-header 760:156 (about 4.9:1, a thin strip, best
  paired with text or used as a small caption image); dictation-settings 680:761 (portrait, about 0.89:1);
  sidebar-status 260:164 (tiny, show at native size or smaller).
- Set `width`/`height` attributes to the sizes in the table. Only the first image may omit lazy loading.
- File sizes are all under 110 KB, at least 9 KB.

## (a) Defects in the 20 renders

Fix in sample data (`EarshotApp/Tests/RenderUI.swift`, not edited here):
- **detail-header.png is only a header.** No render shows the Summary tab, the Transcript tab or speaker
  labels. This is the biggest gap: the page's main claims (speaker labels, summaries) have no visual. Worth
  adding a full detail render with a summary and a speaker-labelled transcript.
- **home.png includes an error row** ("Could not transcribe: the audio file is empty", orange) and a
  spinner row. Honest and real, but for marketing a version with only successful rows would be better.
  The hero currently uses it anyway. Worth a second fixture with no errors.
- **dictation-on.png and dictation-page.png show the "Earshot can't type for you yet" warning**; the
  dictation-page render also shows the Hold mode and a cut-off Corrections list (only one correction row,
  bottom edge clipped). Worth adding a fixture where the permission is granted so the banner is absent.
- **Toggle styling is ambiguous.** On toggles render as a dark track with a pale knob at right; off toggles
  as a pale track with the knob at left. A viewer cannot easily tell which is on. Probably a harness
  rendering artifact (the view is not key/active); worth checking.
- **dictation-off.png** is dimmed and says "Turn this on to choose a shortcut" with disabled controls:
  accurate, but dull for marketing. Not worth fixing.
- **home-narrow.png** contains an unrealistic "BOA call / Not transcribed yet" row and another error row.
  Low priority.
- **kit.png** shows "That shortcut is already used by macOS." warning: a component-kit fixture, not
  marketing. **notes-transcribing.png** is mostly empty space. **notes-empty.png** is fine but empty.
  **notes-narrow.png** has the Record a note button ghosted while recording and the note text wrapped
  to a tight column; fine as a narrow-layout check, not for the site. **topbar*.png** (search bar,
  results, no results) are small strips; usable as search illustrations but not chosen. **sidebar-nav.png**
  shows two copies of the nav list (one per selected state), a test fixture. **sidebar-footer.png** shows
  Settings and Help twice, also a fixture.
- Sample data uses date/time stamps from the render moment (3:43 PM, "Good afternoon"), so the greeting
  changes with when the render is made. Cosmetic.

## (b) Screenshots only a human can capture

These need Screen Recording permission (System Settings > Privacy & Security > Screen & System Audio
Recording, for Terminal) and a real macOS desktop. Until they exist, describe them in words on the page
(the ADR already says so).

1. **Flames outline around the target window while dictating.** Start a dictation into a TextEdit window,
   then capture while the highlight is lit:
   `screencapture -T 3 -w ~/Desktop/dictation-flames.png` (click the window within 3 seconds; or use
   `screencapture -i` and drag a region). Keep the whole window and its glow in frame.
2. **Listening / Transcribing / Tidying pill.** Capture each state separately while dictating:
   `screencapture -T 2 -i ~/Desktop/dictation-pill-listening.png`, then repeat with the file names
   `dictation-pill-transcribing.png` and `dictation-pill-tidying.png`.
3. **Menu bar panel.** Click the Earshot menu bar icon, then press Command-Shift-4 or run
   `screencapture -T 3 -i ~/Desktop/menu-bar-panel.png` and drag around the open panel.
4. **MCP tools in Claude Code.** Run Earshot's MCP server connected to Claude Code, then in a terminal
   showing the tool list or a call result:
   `screencapture -T 3 -w ~/Desktop/mcp-in-claude-code.png`. Check that nothing private (real meeting
   titles, paths, keys) is visible before using it.

Also worth capturing for real, if the owner wants proof the renders match: the full Recordings window
(`screencapture -T 3 -w ~/Desktop/recordings-window.png`) and a recording's Summary and Transcript tabs
with speaker labels, which no render currently shows. Use sample or non-sensitive recordings.
