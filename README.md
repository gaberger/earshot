# Transcribe

A small private Mac app that records meetings and voice notes, writes them out as
text with speaker labels, and summarizes them in Plaud-style formats. It runs
entirely on this Mac: no account, no internet, no audio or text sent anywhere.

Local repository only. Not published anywhere.

## What it does

A timeline of recordings on the left. For each one, a **Transcript** tab
(speech-to-text with speaker labels, editable) and a **Summary** tab (Markdown,
written by Apple's on-device model from a chosen template).

- **Record** from the microphone, then **Stop**. It transcribes, finds the
  speakers, then summarizes. Choose the microphone in **Settings** (⌘,).
- Import an existing audio or video file: drag it into the window, use
  **Import** (⌘O), or right-click it in Finder → **Open With → Transcribe**.
  Imported files are linked into the timeline, not copied.
- **Speakers**: lines are labeled `Speaker 1`, `Speaker 2`… Click a speaker above
  the transcript to rename them everywhere; the summary is rewritten with the
  name. Use the **Speakers** menu to redo detection with an exact number of people.
- **Templates**: Meeting minutes, Quick summary, Sales call, One-on-one, Daily
  stand-up, Interview, Lecture or class notes, Brainstorm, Voice memo. Pick one in
  the Summary tab; set the default in Settings.
- **Names**: a recording takes its summary's title until you name it. Rename it with
  the pencil next to the title, a double-click on the title, or right-click → Rename.
  The name is kept in a `.name` file beside the audio.
- **Translate**: turns speech in other languages into English text.
- Header bar: Record/Stop (with timer), Import, Translate, Summarize, Copy,
  Finder, Privacy (in-app docs), Settings, and a CPU · GPU · MEM meter.

For each recording, `~/Recordings/whisper/` holds the audio (or a link to it),
`.txt` (transcript), `.srt` (timestamps), `.json` (word timings) and
`.summary.md` (summary).

## How it works

```
Transcribe.app (SwiftUI)
  ├─ records the chosen microphone to 16 kHz mono WAV (AVCaptureSession)
  ├─ scripts/transcribe   → ~/.local/bin/transcribe
  │     ├─ ffmpeg        converts any audio/video to 16 kHz mono WAV
  │     └─ whisper-cli   whisper.cpp on the GPU (Metal); writes .txt, .srt, .json
  │           ├─ ggml-large-v3-turbo.bin   transcription
  │           ├─ ggml-large-v3-q5_0.bin    translation (turbo cannot translate)
  │           └─ ggml-silero-v5.1.2.bin    voice detection, skips silence
  ├─ scripts/speakers     → ~/.local/bin/speakers   (Python, run by uv)
  │     └─ sherpa-onnx on CoreML: pyannote segmentation + WeSpeaker voice embeddings;
  │        each sentence goes to whoever spoke most of it
  └─ Apple Foundation Models (SystemLanguageModel, on device)
        guided generation fills a typed summary (title, overview, sections,
        action items); the app writes the Markdown
```

### Speaker detection

The default threshold (0.7) was tuned on a real 14-minute, 3-voice call: 0.5 found
9 "speakers", 0.7 found the real ones. Automatic detection can merge two similar
voices in short clips, so choosing the exact number of people is the most accurate.
Fast back-and-forth inside one run-on sentence can land in the wrong turn.

### Summaries

Apple's on-device model reads about 4,000 tokens at a time (roughly 12 minutes of
speech once the summary format is included), so longer transcripts are summarized
in parts first. Needs macOS 26.4+ with Apple Intelligence on. The app never uses
`PrivateCloudComputeLanguageModel`, which runs on Apple's servers.

## Where things are

| What | Location |
|---|---|
| Source (this repo) | `TranscribeApp/` (app), `scripts/` (helpers) |
| The app | `~/Applications/Transcribe.app` |
| Helper scripts, installed by `build.sh` | `~/.local/bin/transcribe`, `~/.local/bin/speakers` |
| Recordings and results | `~/Recordings/whisper/` |
| App log | `~/Library/Logs/Transcribe.log` |
| Whisper models (~2.5 GB) | `~/Models/whisper/` |
| Speaker models (~32 MB) | `~/Models/speakers/` |

## Setup on a new Mac

```bash
brew install whisper-cpp ffmpeg uv
```

Models (not in git):

- Whisper: `ggml-large-v3-turbo.bin` and `ggml-large-v3-q5_0.bin` from
  https://huggingface.co/ggerganov/whisper.cpp, and `ggml-silero-v5.1.2.bin` from
  https://huggingface.co/ggml-org/whisper-vad, into `~/Models/whisper/`.
- Speakers, into `~/Models/speakers/`:
  `sherpa-onnx-pyannote-segmentation-3-0.tar.bz2` (unpack) from the
  `speaker-segmentation-models` release, and `wespeaker_en_voxceleb_resnet34_LM.onnx`
  from the `speaker-recongition-models` release, both at
  https://github.com/k2-fsa/sherpa-onnx/releases.

Then build and install:

```bash
bash TranscribeApp/build.sh
```

Needs Xcode (for `swiftc`). The app is ad-hoc signed, so it runs only on the Mac
that built it. The first speaker detection downloads `sherpa-onnx` from PyPI into
uv's cache.

## Command-line use

```bash
transcribe recording.m4a        # transcribe (writes .txt, .srt, .json)
transcribe -t interview.mp3     # translate to English
speakers recording.m4a          # add speaker labels to recording.txt
speakers recording.m4a -n 3     # exactly 3 speakers
```
