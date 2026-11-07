# Earshot website copy

> **RELEASE GATE.** Every feature this page describes (Dictation, Notes, Tidy up, the window outline, Press Return, the MCP server, spoken replies) exists only on the local `dictation` branch, 82 commits ahead of `main`, never pushed. The latest release, v1.0.4, has none of it. Do not publish this page until those features are merged, released (for example as 1.1.0) and the release notes and README match. Corrected 2026-11-07 after the claims review.

Page copy is everything above "Captions". Headings written as `## id` use the section ids from the ADR.

## Page metadata

- Title: Earshot - private meeting notes and dictation for Mac
- Meta description: Earshot records meetings on your Mac, transcribes them, labels who spoke and writes a summary. Everything runs on-device.
- Nav labels: What it is (#what) | How it works (#how) | Dictation (#dictation) | Notes (#notes) | Privacy (#privacy) | Install (#install)

## Hero

- h1: Meeting notes and dictation that stay on your Mac
- Subline: Earshot records a meeting, writes the transcript, labels who spoke and drafts the summary, all with models running on this Mac. Hold a shortcut in any app and it types what you say.
- Primary button: Download for Mac (links to the GitHub releases page)
- Secondary button: View on GitHub
- Requirement line: Requires a Mac with Apple silicon and macOS 26.4 or later.

## what

### Three separate functions in one app

- **Recordings.** Record a meeting or call through your microphone, or drop in an audio or video file. You get a transcript with speaker labels and a summary.
- **Notes.** Your own voice notes. Speak, press Stop, and the text is saved in a list. Nothing is typed into other apps.
- **Dictation.** Hold a shortcut in any app, speak, let go, and Earshot types what you said where your cursor is. It is off until you turn it on in Settings.

## how

### From a recording to a summary

1. **Record or import.** Record from the microphone you choose. Or drag in an audio or video file. A recording stops by itself after a quiet spell, and warns you first. Earshot records through your microphone, so the other side of a call is captured only if it comes out of your speakers; on headphones you get your own voice.
2. **Transcribe on this Mac.** Whisper large-v3-turbo runs on the Mac's GPU. The transcript is editable. It is made after you stop recording, not while you speak.
3. **See who spoke when.** A voice model labels the speakers. Click a speaker to rename them everywhere. Two similar voices in a short clip can merge into one.
4. **Get a summary.** Apple's on-device model writes a summary from one of nine templates, such as meeting minutes or sales call. Every summary ends with action items as checkboxes. You can edit it.

Summaries come from a small model. Check names and numbers before you share one.

## dictation

### Speak in any app. Earshot types it.

Click into any text field, hold the shortcut (Control, Option, Space unless you change it), speak, and let go. A second or two later the text appears where your cursor is.

- **Hold or tap.** By default you hold the keys while you talk. Or switch to tap to start, tap to stop.
- **Your shortcut.** Change it in Settings; it must include Control or Option, or be a function key.
- **Fix words it mishears.** Add corrections such as "ear shot" becoming "Earshot". They match whole words and ignore case.
- **Tidy up, if you want it.** Off by default. It removes ums and stutters and fixes punctuation using Apple's on-device model. It may reword slightly. If the model is unavailable, slow or drifts from what you said, your words are typed as spoken.
- **See where it will land.** While you dictate, a small fire burns around the edge of the window the words will be typed into. Earshot reads only the window's position and size. With Reduce Motion on, you get a plain static border. It is on by default; turn it off in Settings.
- **A pill shows what it is doing.** A small indicator near the bottom of the screen says Listening with a live level bar, then Transcribing, or Tidying when cleanup is on.
- **Press Return after typing.** Off by default. When on, Earshot presses Return once the text is typed, so a message sends or a form submits. Sending cannot be undone, so you must switch it on yourself. It never presses Return when nothing was typed, when the text was left on the clipboard instead, or in a secure input field.
- **Limits.** Dictation stops by itself after one minute, ignores a press shorter than a third of a second, and is unavailable while you are recording a meeting.

Earshot types by pasting, then puts back whatever was on your clipboard. If it cannot type safely, because Accessibility is not allowed or you switched windows before the text was ready, it leaves the text on your clipboard for you to paste yourself. Earshot saves no dictated text and no audio: the audio is deleted at once, except a clip that could not be transcribed, which waits in a private temporary file so you can retry it. Earshot does not type while macOS reports a secure input field, such as a password box.

The fire outline and the pill appear only while you dictate, so they are not in the screenshots on this page.

## notes

### Voice notes, text only

Notes is its own area, separate from Recordings. Press Record a note, speak, and press Stop. It is transcribed on this Mac and saved in a list grouped by day, with Copy and Delete on each note.

Only the text is kept. The audio is deleted at once.

## privacy

### What stays on this Mac

Every model Earshot uses runs locally: Whisper for speech, a voice model for speakers, and Apple's on-device model for summaries and for the optional tidy-up. There is no account and no cloud. Downloading the models, the speaker packages and Apple's on-device model needs the internet once. After that, turn off Wi-Fi and it all still works. Earshot never uses Apple's Private Cloud Compute, and it sends nothing about you or your recordings anywhere. The one thing it cannot control is your clipboard: when it leaves dictated text there (see Dictation), a clipboard manager or Universal Clipboard may see it.

### Where Earshot's promise stops

Two optional features involve an AI agent, and the agent is outside that promise.

- **The MCP server.** scripts/earshot-mcp is a small stdio server that lets an agent read your recordings. It starts no daemon, opens no port and uses no network. It exposes four read-only tools: list_recordings, get_transcript, get_summary and search, and they return names, transcripts and summaries, never audio. The agent you connect it to receives that text, and may send it to its own provider. The text comes from speech, so an agent should treat it as data, not as instructions.
- **Spoken replies with Claude Code.** scripts/earshot-speak is a Claude Code Stop hook. Once you add it to Claude Code settings and run earshot-speak on from inside the session, it speaks a short version of each reply (about 280 characters, with no code or links) using the macOS say command, locally. Claude Code itself is an agent with its own provider, which is outside Earshot's promise. Anyone nearby can hear the replies.

Connecting an agent is your choice.

## install

### Install Earshot

**You need:** a Mac with Apple silicon (M1 or later), macOS 26.4 or later, Apple Intelligence turned on (for summaries and the optional Tidy up), Homebrew, and about 3 GB of free disk space for the models.

**1. Install the tools**

    brew install whisper-cpp ffmpeg uv

**2. Download the models.**

    # Speech to text
    mkdir -p ~/Models/whisper && cd ~/Models/whisper
    curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin   # 1.6 GB, required
    curl -LO https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin      # 1 MB, skips silence
    curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-q5_0.bin     # 1.1 GB, only for Translate

    # Speaker labels
    mkdir -p ~/Models/speakers && cd ~/Models/speakers
    curl -L https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2 | tar xj
    curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/wespeaker_en_voxceleb_resnet34_LM.onnx

**3. Install the app. Choose one.**

- **Disk image.** Download the .dmg from the latest release on GitHub, open it, drag Earshot onto Applications, then eject it.
- **Build from source.** Needs Xcode. Run `git clone https://github.com/gaberger/earshot.git`, then `cd earshot`, then `bash EarshotApp/build.sh`. It installs Earshot.app in ~/Applications.

**4. Open it the first time.** Earshot is not notarized by Apple, so macOS says it cannot check the app from the disk image. Click Done, open System Settings, then Privacy & Security, scroll down and click Open Anyway. An app you built yourself opens normally.

**Permissions.** The first time you record, macOS asks for the microphone; click Allow. Dictation also asks for Accessibility, which is what lets Earshot type for you. After an update, macOS may forget the Accessibility permission; switch Earshot off and on again in the Accessibility list.


## footer

Earshot is open source under the MIT License. Links: GitHub (https://github.com/gaberger/earshot) | Releases (https://github.com/gaberger/earshot/releases) | README (https://github.com/gaberger/earshot#readme) | MCP (https://modelcontextprotocol.io)

## Captions

Caption notes from the claims review: the dictation image actually used on the page is the cropped render dictation-settings.png. Say that Tap mode is selected in it and that the default is Hold, and do not call the renders windows or OS screenshots (alt text says "in the app", not "in a dark window"). Consider repeating the words sample data near later screenshots.

Shared sample-data sentence (place once near the screenshots): All screenshots show sample data and are renders of the real app views, not captures of anyone's recordings.

- home: The Recordings home screen lists recordings by day with their length and status, with Import and Record buttons at the bottom. One entry spins while it transcribes and one shows an error in orange.
- recording: A recording in progress: a red Recording label, a running timer, a live level display, the microphone in use, and a Stop button. The text appears when you stop.
- detail-header: The top of one recording: its name, date and length, Transcribed and Summarized badges, Summarize, Copy and Finder buttons, and Summary and Transcript tabs.
- dictation-on: The Dictation settings with Dictate into any app switched on, tap mode chosen, the shortcut, the window highlight, the off-by-default Tidy up and Press Return options, and a corrections list. The orange banner is the prompt shown when Accessibility is not yet allowed.
- dictation-page: The Dictation page in its default state: hold mode, the Control-Option-Space shortcut, the window highlight on, Tidy up and Press Return off, and a Fix words it mishears table.
- notes: The Notes list: short voice notes grouped by day, each with its length, a Copy button and a Delete button, plus Record a note and Clear all.
- notes-recording: Recording a note: a Recording label, timer and level display with a Stop button above the saved notes.
- sidebar-nav: The sidebar switches between the three functions: Recordings, Notes and Dictation. The picture shows two states, with Recordings selected and then Dictation.
- sidebar-status: The status panel at the bottom of the sidebar. It reads Ready, on this Mac with the speech model and microphone name, or shows Recording with a timer.
- home-narrow: The same Recordings screen in a narrow window; the list and buttons fit the smaller width.

## Claims table

| Claim | Source |
|---|---|
| Three separate functions Recordings, Notes, Dictation | README.md, Notes section, the "three separate functions" sentence (line 128) |
| Record from chosen mic, level meter, timer; stops after quiet spell and warns | README.md Features table, Record row (line 32) |
| Drag in audio/video; right-click, Open With, Earshot | README.md Features, Import row (line 33) |
| Timeline by day | README.md Features, Timeline row |
| Whisper large-v3-turbo on the GPU; editable transcript | README.md Features, Transcribe row (line 34); "How it works" flowchart |
| Transcription after stopping, not live | README.md "Check that it works"; recording.png text "The text appears here when you stop" |
| Speaker labels, rename everywhere; Speakers menu more accurate | README.md Features, Speakers row; Accuracy notes TIP |
| Nine templates, action items as checkboxes; named templates | README.md Summary templates table and the line under it |
| Summary edit; Earshot asks before replacing | README.md Features, Edit row; Accuracy notes |
| Check names and numbers | README.md Accuracy notes, Summaries |
| Summaries need Apple Intelligence | README.md "What you need" |
| Hold shortcut, speak, let go, text typed; default Control-Option-Space; off until turned on | README.md Features Dictate row (line 39); Dictation section |
| Text appears a second or two later | README.md Dictation section, first paragraph |
| Hold or tap mode | README.md "Hold, or tap" bullet (line 104); ADR-2611062045 |
| Shortcut changeable, must include Control or Option or be function key | README.md "Change the shortcut" bullet |
| Corrections: whole words, ignore case, longest wins; apply to notes | README.md "Fix words it mishears" bullet; Notes paragraph; ADR-2611062045 |
| Tidy up: off by default, on-device model, may reword, falls back to spoken words | README.md "Tidy up what I say" bullet (line 109); ADR-2611071000 |
| Fire outline, position and size only, Reduce Motion static border, can be turned off | README.md "The window outline" bullet (line 116); ADR-2611071400; dictation-page.png |
| Pill: Listening with level bar, Transcribing, Tidying, never takes focus | README.md "The indicator" bullet; ADR-2611071300; EarshotApp/Dictation.swift indicatorText(tidying:) line 104; EarshotApp/DictationHUD.swift line 31 |
| Press Return: off by default, once after typing, exceptions (no text, clipboard fallback, secure field) | README.md line 120; ADR-2611071500 decisions 1-3 |
| Dictation keeps nothing; audio deleted except failed clip retried | README.md "Dictation keeps nothing" (line 122) and the line before it |
| No typing in password fields; off while a meeting is recorded | README.md line 132 |
| Notes: Record a note, grouped by day, Copy, Delete, Clear all; only text kept; audio deleted at once | README.md Notes paragraph (line 126); notes.png |
| All models local; no account; works with Wi-Fi off; never Private Cloud Compute | README.md IMPORTANT box (lines 21-24) |
| Works offline only after models and speaker packages are downloaded | README.md Install steps 2 and 4 ("After this, nothing needs the internet") |
| Activity log never records what was said | README.md "Check that it works" and "Where things live" |
| MCP server: stdio, no daemon, no port, no network, four read-only tools | README.md MCP section (lines 295-311); ADR-2611071100 decisions 1-2 |
| Agent may send text to its own provider; outside promise | README.md MCP "Privacy" paragraph (line 311) |
| Spoken replies: Stop hook, macOS say, local, off until on, anyone nearby hears | README.md "Hear replies spoken" section; ADR-2611071600 |
| Claude Code is an agent with its own provider | ADR-2611071700 decision 4 and references (the agent caveat); README does not say it in these words |
| Requirements: Apple silicon (M1 or later), macOS 26.4, Homebrew, about 3 GB | README.md "What you need" |
| 3 GB and 15 minutes | README.md Installation intro |
| brew command; model commands | README.md Step 1 and Step 2 (copied verbatim) |
| DMG and build-from-source options; Xcode; ~/Applications | README.md Step 3, options A and B |
| Not notarized; Done, Privacy & Security, Open Anyway; self-built opens normally | README.md Step 4 item 1 (line 218) |
| Microphone prompt on first Record; Accessibility needed to type; macOS may forget it after an update | README.md Dictation section (line 96) and line 133 |
| 30 MB speaker packages download once | README.md Step 4 item 4 (line 225) |
| MIT License | LICENSE line 1 |
| Repo and releases URLs | site/check.py (required links); README.md Option A |
| Fire and pill not in screenshots; screenshots are sample-data renders | ADR-2611071700 decision 3 |
| Caption details | Viewed /tmp/earshot-ui/*.png |
