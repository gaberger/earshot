<div align="center">

<img src="assets/earshot-logo.png" alt="Earshot logo: a charcoal tile with an orange ear and orange sound waves" width="140">

# Earshot

**Meeting notes and dictation that stay on your Mac.**

Earshot records your meetings, writes the transcript, labels who spoke and drafts the summary. Hold a shortcut in any app and it types what you say. Everything runs on your Mac.

[Download Earshot](https://github.com/gaberger/earshot/releases/latest) · [Install guide](docs/INSTALL.md) · [User guide](docs/GUIDE.md)

Requires a Mac with Apple silicon and macOS 26.4 or later.

<img src="assets/badges/platform.svg" alt="macOS 26.4+ on Apple silicon">
<img src="assets/badges/privacy.svg" alt="100% on-device">
<img src="assets/badges/swift.svg" alt="Swift, SwiftUI">
<img src="assets/badges/speech.svg" alt="Speech: whisper.cpp">
<img src="assets/badges/speakers.svg" alt="Speakers: sherpa-onnx">
<img src="assets/badges/summaries.svg" alt="Summaries: Apple Foundation Models">

<img src="assets/screenshots/recordings.png" alt="The Recordings view: a sidebar with Recordings, Notes and Dictation, a search bar and your recordings listed by day" width="900">

</div>

## Meetings, written up

Record a call, or drop in any audio or video file. Whisper turns it into a transcript on your Mac, Earshot labels who spoke when, and a summary with action items is drafted from one of nine templates. Edit anything you like: Earshot never replaces a summary you changed without asking.

<img src="assets/screenshots/recording-open.png" alt="An open recording with a back link at the top left and Summary and Transcript tabs" width="900">

## Find anything

One search bar looks across your recordings, notes and settings, or press ⌘K from anywhere in the app. Recordings, Notes and Dictation are one click apart in the sidebar.

<img src="assets/screenshots/search.png" alt="Typing in the search bar finds matching recordings and settings" width="900">

## Dictate into any app

Hold a shortcut, speak, and let go: Earshot types what you said where your cursor is. Fix the words it mishears, and optionally tidy up the ums. A fire outline shows which window it will type into. The details are in the [User guide](docs/GUIDE.md).

<img src="assets/screenshots/dictation.png" alt="The Dictation view with every option and a prompt shown until Accessibility is allowed" width="900">

## Voice notes

Press record, say it, and get the text. Only the text is kept, so a note stays small and easy to search.

<img src="assets/screenshots/notes.png" alt="The Notes view with your own voice notes grouped by day" width="900">

All screenshots show sample data and are renders of the real app views, not captures of anyone's recordings. The title bar is drawn, and the native toolbar, the bottom status bar and the dictation fire outline and pill are not in them.

## Private by design

Every model runs on your Mac: Whisper for speech, a voice model for speakers and Apple's on-device model for summaries. There is no account and no cloud. If you connect an AI agent, what you let it read goes to that agent, and you can read [exactly what that means](docs/PRIVACY.md).

## Works with your agents

A read-only MCP server lets an agent such as Claude Code read your transcripts and summaries. An optional hook speaks replies aloud. [Set up agents](docs/AGENTS.md).

## Get started

Download the disk image from the latest release, drag Earshot to Applications and open it. The app is not notarized by Apple, so macOS asks you to confirm the first time with Open Anyway in System Settings. The models download once. The steps are in the [install guide](docs/INSTALL.md).

## Documentation

- [Install guide](docs/INSTALL.md)
- [User guide](docs/GUIDE.md)
- [Privacy](docs/PRIVACY.md)
- [Agents](docs/AGENTS.md)
- [Development](docs/DEVELOPMENT.md)
- [Release notes](docs/releases)
- [Security policy](SECURITY.md)

<div align="center">
<sub>Open source under the <a href="LICENSE">MIT License</a>. Built on <a href="https://github.com/ggml-org/whisper.cpp">whisper.cpp</a>, <a href="https://github.com/k2-fsa/sherpa-onnx">sherpa-onnx</a> and Apple Foundation Models.</sub>
</div>
