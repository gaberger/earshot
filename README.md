<div align="center">

<img src="assets/earshot-logo.svg" alt="Earshot logo: sound waves reaching an ear" width="140">

# Earshot

**Private meeting notes that never leave your Mac.**

Record a meeting, get a transcript with speaker labels, and a summary in the format you need —<br>
all on-device, with no account, no cloud and no internet connection.

<img src="assets/badges/platform.svg" alt="macOS 26.4+ on Apple silicon">
<img src="assets/badges/privacy.svg" alt="100% on-device">
<img src="assets/badges/swift.svg" alt="Swift, SwiftUI">
<img src="assets/badges/speech.svg" alt="Speech: whisper.cpp">
<img src="assets/badges/speakers.svg" alt="Speakers: sherpa-onnx">
<img src="assets/badges/summaries.svg" alt="Summaries: Apple Foundation Models">

</div>

> [!IMPORTANT]
> **Nothing leaves this Mac.** Every model runs locally: Whisper for speech, a voice model for
> speakers, and Apple's on-device model for summaries. Turn off Wi-Fi and it all still works.
> Earshot never uses Apple's Private Cloud Compute.

---

## ✨ Features

| | |
|---|---|
| 🎙️ **Record** | One click to record from the microphone you choose, with a live level meter and timer. It stops by itself after a quiet spell, and warns you first. |
| 📂 **Import** | Drag in any audio or video file, or right-click it in Finder → **Open With → Earshot**. |
| 📝 **Transcribe** | Whisper large-v3-turbo on the GPU: about 45 seconds for a 14-minute call. Editable. |
| 🗣️ **Speakers** | Labels who spoke when. Click a speaker to rename them everywhere. |
| ✨ **Summarize** | Nine Plaud-style templates, from meeting minutes to sales calls, with action items. |
| ✏️ **Edit** | Fix the summary in a rich-text editor: headings, bold, bullets, checkboxes. Edited summaries are never replaced without asking. |
| 🌍 **Translate** | Turns speech in other languages into English text. |
| ⌨️ **Dictate** | Hold a shortcut (<kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>Space</kbd> unless you change it) in any app, speak, let go, and Earshot types what you said, into a form, an email, anywhere. A small **Listening…** indicator shows while it hears you. Off until you turn it on in Settings. |
| 🗂️ **Timeline** | Every recording by day, named by its summary or by you. |
| 🧭 **Menu bar** | The ear at the top of the screen: record without opening the window, see the timer, jump to recent recordings. |
| 📊 **Status bar** | What Earshot is doing now, plus live CPU, GPU and memory use, along the bottom of the window. |

## 🧭 How it works

```mermaid
flowchart LR
    mic([🎙️ Microphone]) --> wav[16 kHz WAV]
    file([📂 Audio / video file]) --> ff[ffmpeg]
    ff --> wav
    wav --> whisper["whisper.cpp<br/>large-v3-turbo · Metal"]
    whisper --> words[Words + timings]
    wav --> sherpa["sherpa-onnx · CoreML<br/>pyannote + WeSpeaker"]
    sherpa --> turns[Who spoke when]
    words --> merge{{Each sentence →<br/>its main speaker}}
    turns --> merge
    merge --> transcript[📝 Transcript]
    transcript --> fm["Apple Foundation Models<br/>on-device · guided generation"]
    fm --> summary[✨ Summary]
```

Apple's model fills in typed fields (title, overview, sections, action items with owner and due
date), and Earshot writes the Markdown. A small model stays far more accurate this way than when
it writes free text.

## 🧾 Summary templates

| Template | Sections |
|---|---|
| 👥 **Meeting minutes** *(default)* | One per topic · Decisions · Open questions |
| 📄 Quick summary | Key points |
| 💼 Sales call | Customer · Situation · Pain points · Requirements · Objections · Competitors · Budget & timeline · Next steps |
| 🤝 One-on-one | Updates · Challenges · Feedback · Decisions |
| ✅ Daily stand-up | One per person: Done / Next / Blocked |
| 🎤 Interview | Background · One per theme · Notable quotes |
| 🎓 Lecture or class notes | One per concept · Examples · Questions to review |
| 💡 Brainstorm | One per idea group · Most promising · Next steps |
| 🌊 Voice memo | Main points · Ideas |

Every summary starts with the date, length and speakers, and ends with action items as checkboxes.

## ⌨️ Shortcuts

| Keys | Action |
|---|---|
| <kbd>⌘</kbd> <kbd>R</kbd> | Record / Stop |
| <kbd>⌘</kbd> <kbd>O</kbd> | Import a file |
| <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>C</kbd> | Copy the open tab |
| <kbd>⌘</kbd> <kbd>,</kbd> | Settings: microphone, speakers, default template |
| <kbd>⌘</kbd> <kbd>?</kbd> | How Earshot works |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>Space</kbd> | Dictate: hold, speak, release (in any app, once turned on in Settings; you can change the keys) |

### Dictation

Turn on **Settings → Dictation → Dictate into any app**. Earshot asks for **Microphone** and
**Accessibility** access (System Settings → Privacy & Security); Accessibility is what lets it type
for you. Then click into any text field, hold <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>Space</kbd>, speak, and
let go. A second or two later the text appears where your cursor is.

- **Change the shortcut** under **Settings → Dictation → Shortcut**: click it and press the keys you
  want. It must include <kbd>⌃</kbd> or <kbd>⌥</kbd> (or be a function key such as <kbd>F5</kbd>), so it
  never steals ordinary typing, and shortcuts macOS already owns can't be chosen. **Reset** brings back
  the default. If another app already uses your choice, Earshot says so.
- **Hold, or tap.** By default you hold the keys while you talk. Under **Settings → Dictation → Mode**
  you can switch to **Tap to start, tap to stop**, which is easier for long dictations. A change
  applies from your next dictation.
- **Fix words it mishears** under **Settings → Dictation → Corrections**: one per line, as
  `ear shot => Earshot`. Matching ignores case and only hits whole words, and the longest phrase wins.
- **Tidy up what I say** under **Settings → Dictation → Tidy up** (off by default) removes ums and stutters and fixes punctuation using Apple's on-device model. It may reword slightly; if the model is unavailable, slow or drifts from what you said, your words are typed as spoken.
- **The indicator.** While you hold the keys a small **Listening…** pill with a live level bar floats
  near the bottom of the screen you're on, so you can see the microphone is hearing you. It switches
  to **Transcribing…** after you let go, then disappears as the text arrives. It never takes focus
  from the field you're typing into.
- **The window outline.** While you dictate, a little fire licks around the edge of the window your
  words will be typed into (low embers while it transcribes), so you can see where they will land. Earshot
  reads only that window's position and size, never its title or contents. With **Reduce Motion** on you
  get a plain static border instead. Turn it off under **Settings → Dictation → Highlight the window I am
  dictating into**.

- **Press Return after typing** under **Settings → Dictation → Submit** (off by default) presses Return once the text is typed, so a message sends or a form submits. It does not press Return when there is no text, when the text was left on the clipboard because Earshot can't type yet, or when a secure input field is active.
- It transcribes on this Mac with the same Whisper model as recordings. The audio is deleted at once. The one exception is a clip that could not be transcribed: it stays in a private temporary file until your next dictation, so **Retry last dictation** in the menu bar can try it again.
- **Dictation keeps nothing.** What you say is typed into the app in front and that is all: no text and no audio is saved.

### Notes: your own voice notes

**Notes** is a separate area, with its own **Record a note** button. Press it, speak, press **Stop**, and the note is transcribed on this Mac and saved in the Notes list, grouped by day, with Copy and Delete on each. Nothing is typed into other apps. Only the text is kept, in `~/Library/Application Support/Earshot/notes.json`; the audio is deleted at once. Corrections from **Dictation** apply to notes too. A note cannot start while a meeting is being recorded or while you are dictating. **Clear all** deletes every note.

Earshot now has three separate functions: **Recordings** (meetings and calls), **Notes** (voice notes you record in Earshot) and **Dictation** (typing into any app).
- The microphone is open only while you hold the keys. A tap shorter than a third of a second does
  nothing, and a hold stops by itself after a minute.
- It types by pasting, then puts back whatever was on your clipboard.
- It won't type into password fields, and it's off while a meeting is being recorded.
- The app isn't notarized, so macOS may forget the Accessibility permission after an update. If
  Dictation stops typing, switch Earshot off and on again in the Accessibility list.

## 🚀 Installation

Earshot needs four things: a Mac that can run it, a few command-line tools, the speech and
speaker models, and the app itself. Plan on about 3 GB of downloads and 15 minutes.

### What you need

- A Mac with **Apple silicon** (M1 or later)
- **macOS 26.4** or later
- **Apple Intelligence** turned on, in System Settings → Apple Intelligence & Siri (for summaries)
- [**Homebrew**](https://brew.sh)
- About **3 GB** of free disk space for the models

### Step 1: Install the tools

```bash
brew install whisper-cpp ffmpeg uv
```

| Tool | What Earshot uses it for |
|---|---|
| `whisper-cpp` | Turns speech into text (`whisper-cli`) |
| `ffmpeg` | Converts any audio or video file into the format Whisper reads |
| `uv` | Runs the speaker-detection script and installs its Python packages |

### Step 2: Download the models

The models are too big for git, so you download them once. Earshot looks for them in
`~/Models/whisper` and `~/Models/speakers`.

```bash
# Speech to text
mkdir -p ~/Models/whisper && cd ~/Models/whisper
curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin   # 1.6 GB, required
curl -LO https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin      # 1 MB, skips silence
curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-q5_0.bin     # 1.1 GB, only for Translate

# Speaker labels
mkdir -p ~/Models/speakers && cd ~/Models/speakers
curl -L https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2 | tar xj
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/wespeaker_en_voxceleb_resnet34_LM.onnx
```

| Model | Needed for | If it's missing |
|---|---|---|
| `ggml-large-v3-turbo.bin` | Every transcript | Transcription fails |
| `ggml-silero-v5.1.2.bin` | Skipping silence | Whisper may invent words in quiet stretches |
| `ggml-large-v3-q5_0.bin` | **Translate** | Only translation fails |
| `sherpa-onnx-pyannote-segmentation-3-0/`, `wespeaker_en_voxceleb_resnet34_LM.onnx` | Speaker labels | No speaker labels. Turn off **Identify speakers** in Settings. |

### Step 3: Install the app

Choose one.

#### Option A: Download the disk image

1. Download **Earshot-&lt;version&gt;.dmg** from the latest
   [**release**](https://github.com/gaberger/earshot/releases/latest).
   (For a build of the newest commit instead, open the latest successful
   [**Build** run](https://github.com/gaberger/earshot/actions/workflows/build.yml), download the
   **Earshot-&lt;version&gt;** artifact while signed in to GitHub, and unzip it.)
2. Open the disk image and drag **Earshot** onto **Applications**.
3. Eject the disk image.

#### Option B: Build from source

This needs **Xcode** (from the App Store; the command-line tools alone don't include `actool`).

```bash
git clone https://github.com/gaberger/earshot.git
cd earshot
bash EarshotApp/build.sh
```

This builds `Earshot.app`, installs it in `~/Applications`, and puts the `transcribe` and
`speakers` scripts in `~/.local/bin` so you can use them from the terminal too. To make your own
disk image afterwards, run `bash EarshotApp/make-dmg.sh` (→ `Earshot-<version>.dmg`).

### Step 4: Open Earshot for the first time

1. **Open the app.** The disk image app has no Apple Developer ID and isn't notarized by Apple,
   so the first time, macOS says it can't check it. Click **Done**, then go to
   **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
   (An app you built yourself opens normally.)
2. **Allow the microphone.** The first time you click **Record**, macOS asks. Click **Allow**.
   To change it later: System Settings → Privacy & Security → Microphone.
3. **Pick your microphone** in **Settings** (<kbd>⌘</kbd> <kbd>,</kbd>) if you don't want the
   system default.
4. **Get the speaker packages while you're online.** The first speaker detection downloads
   `sherpa-onnx` (about 30 MB) into uv's cache. To do it now instead of during your first meeting:

   ```bash
   uv run --quiet --script /Applications/Earshot.app/Contents/Resources/speakers --help
   ```

   (Use `~/Applications/Earshot.app` if you built from source.) After this, nothing needs the internet.

### Check that it works

Record a few seconds of speech and click **Stop**. The status bar at the bottom shows
*Transcribing*, then *Finding speakers*, then *Summarizing*, and the summary appears.

If a step fails, Earshot shows the error above the tabs:

| Error | Fix |
|---|---|
| `Model not found: …/ggml-large-v3-turbo.bin` | Download the model in step 2, to exactly that folder |
| `whisper-cli: command not found` or `ffmpeg: command not found` | `brew install whisper-cpp ffmpeg` |
| `Speaker detection failed: … model files missing` | Download the speaker models in step 2 |
| `Apple Intelligence is off` | Turn it on in System Settings → Apple Intelligence & Siri |
| `Apple's on-device model is still downloading` | Wait for macOS to finish downloading it, then click **Summarize** |

`~/Library/Logs/Earshot.log` records each step and its result (never what was said).

### Update

To see which version you have, choose **Earshot → About Earshot**, or look at the bottom of the
menu bar panel. It reads like `1.0.0 (16, 3113bfa)`: the version, the build number, and the commit
it was built from.

- **Disk image:** download the new one and drag it onto **Applications** again. Choose **Replace**.
- **From source:** `git pull`, then `bash EarshotApp/build.sh`.

Your recordings, summaries, models and settings stay where they are.

### Uninstall

1. Quit Earshot, then drag it from Applications to the Trash.
2. Remove the parts you no longer want:

   ```bash
   rm -f ~/.local/bin/transcribe ~/.local/bin/speakers   # terminal scripts (source builds only)
   rm -rf ~/Models/whisper ~/Models/speakers             # models, about 3 GB
   rm -f ~/Library/Logs/Earshot.log                      # activity log
   defaults delete com.gaberger.earshot                  # settings
   defaults delete local.whisper.transcribe 2>/dev/null  # settings from versions before the Earshot name
   ```

3. Your recordings are in `~/Recordings/whisper`. Delete that folder only if you don't want them.

## 📁 Where things live

| What | Where |
|---|---|
| The app | `/Applications/Earshot.app` (disk image) or `~/Applications/Earshot.app` (built from source) |
| Recordings and results | `~/Recordings/whisper/` — per recording: audio, `.txt`, `.srt`, `.json`, `.summary.md`, `.name` |
| Helper scripts | Inside the app, in `Contents/Resources`. Source builds also put them in `~/.local/bin` for the terminal. |
| Models | `~/Models/whisper/`, `~/Models/speakers/` |
| Activity log | `~/Library/Logs/Earshot.log` — clicks, file names and results, never what was said |

## 💻 Command line

The scripts the app runs work on their own too:

```bash
transcribe meeting.m4a          # → meeting.txt, .srt, .json
transcribe -t interview.mp3     # translate to English
speakers meeting.m4a            # add speaker labels to meeting.txt
speakers meeting.m4a -n 3       # exactly 3 speakers
```

## 🔌 Use Earshot from an agent (MCP)

`scripts/earshot-mcp` is a small stdio [MCP](https://modelcontextprotocol.io) server that lets an agent read your recordings. It needs only the system Python 3, starts no daemon and opens no port.

```bash
claude mcp add --scope user earshot -- /abs/path/to/earshot/scripts/earshot-mcp
# recordings somewhere else (name first: -e takes several values and would swallow it):
claude mcp add --scope user earshot -e WHISPER_REC_DIR=/path -- /abs/path/to/earshot/scripts/earshot-mcp
```

The default scope is project-local; `--scope user` makes it available everywhere.

It exposes four read-only tools: `list_recordings`, `get_transcript`, `get_summary` and `search`.

**Privacy:** it exposes what you already keep on disk to the agent you connect it to. That agent may send the text to its own provider, which is your choice and outside Earshot's "nothing leaves this Mac" promise.

Tool output is untrusted text from audio, so an agent should treat it as data, not instructions. Symlinked recording files are refused. A file still being written may be read as a prefix, and a transcript may briefly be newer than its summary because the files are written separately.

## 🔬 Accuracy notes

> [!TIP]
> If you know how many people were in a meeting, choose the number in the **Speakers** menu above
> the transcript. It is more accurate than detecting it.

- **Speaker detection** was tuned on a real 14-minute, 3-voice call: the library default found 9
  "speakers", and Earshot's setting (0.7) found the real ones. Two similar voices in a short clip
  can still merge, and fast back-and-forth inside one run-on sentence can land in the wrong turn.
- **Summaries** come from a small on-device model. It reads about 12 minutes of speech at once, so
  longer recordings are summarized in parts first. Check names and numbers before you share one.
- **Transcripts** can mishear names and jargon. Correct the Transcript tab, then click
  **Summarize** to rewrite the summary.
- **Summaries** can be corrected directly: click **Edit** above the summary. Earshot marks it
  as edited and asks before a new summary replaces it.

## 🏷️ Versions and releases

The version lives in one place, the [`VERSION`](VERSION) file, as `MAJOR.MINOR.PATCH`
([semantic versioning](https://semver.org)): bump PATCH for fixes, MINOR for new features,
MAJOR for changes that break how things worked before. `build.sh` stamps it into the app with a
build number (the commit count, so it only goes up) and the commit hash, marked `-dirty` when
built from uncommitted changes.

To release, write the notes in `docs/releases/<version>.md` (they must name `Earshot-<version>.dmg`
and say the About version reads `<version>`), then, from `main`:

```bash
scripts/release minor -m "what's new"    # or patch, major, or an exact version like 1.1.0
scripts/release minor --dry-run          # check everything, change nothing
scripts/release minor -m "..." --push    # also push main and the tag to origin and github
```

The script refuses unless you're on `main` with a clean tree, the notes exist, the version is newer
and the tests pass. It bumps `VERSION`, commits it with the notes, and tags `v<version>`. Without
`--push` it prints the push commands. `scripts/release-test` checks the script itself.

The tag makes CI build the disk image and publish it as a
[GitHub release](https://github.com/gaberger/earshot/releases) with the notes file.
CI stops if the tag and `VERSION` don't match.

## 🗂️ Project layout

```
.
├── VERSION                the app's version (MAJOR.MINOR.PATCH); see Versions and releases
├── .github/workflows/     CI: build, test and disk image on every push; a release for each v* tag
├── EarshotApp/
│   ├── Earshot.swift      the whole app: timeline, tabs, recording, speakers, summaries
│   ├── RichText.swift     the rich summary editor, and Markdown ↔ formatted text
│   ├── Tests/             editor tests in a real text view: bash EarshotApp/Tests/run.sh
│   ├── Info.plist         name, icon, microphone permission text, file types it opens
│   ├── build.sh           builds and installs the app and the scripts
│   └── make-dmg.sh        packs the built app into Earshot-<version>.dmg (drag to Applications)
├── scripts/
│   ├── transcribe         whisper.cpp wrapper
│   └── speakers           speaker detection (Python, run by uv)
└── assets/
    ├── Earshot.icon/      the app icon: layered Icon Composer file (background + glass layers)
    ├── menubar.svg        the menu bar ear (a template image macOS tints)
    ├── earshot-logo.svg   the flat logo for this README
    └── badges/            the badges above, drawn locally
```

<div align="center">
<br>
<sub>Built on <a href="https://github.com/ggml-org/whisper.cpp">whisper.cpp</a>,
<a href="https://github.com/k2-fsa/sherpa-onnx">sherpa-onnx</a> and Apple's Foundation Models framework.<br>
Local repository · not published.</sub>
</div>
