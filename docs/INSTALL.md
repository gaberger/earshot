# Install Earshot

Earshot needs four things: a Mac that can run it, a few command-line tools, the speech and
speaker models, and the app itself. Plan on about 3 GB of downloads and 15 minutes.

Back to the [README](../README.md). Next: the [user guide](GUIDE.md).

## What you need

- A Mac with **Apple silicon** (M1 or later)
- **macOS 26.4** or later
- **Apple Intelligence** turned on, in System Settings → Apple Intelligence & Siri (for summaries)
- [**Homebrew**](https://brew.sh)
- About **3 GB** of free disk space for the models

## Step 1: Install the tools

```bash
brew install whisper-cpp ffmpeg uv
```

| Tool | What Earshot uses it for |
|---|---|
| `whisper-cpp` | Turns speech into text (`whisper-cli`) |
| `ffmpeg` | Converts any audio or video file into the format Whisper reads |
| `uv` | Runs the speaker-detection script and installs its Python packages |

## Step 2: Download the models

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

## Step 3: Install the app

Choose one.

### Option A: Download the disk image

1. Download **Earshot-&lt;version&gt;.dmg** from the latest
   [**release**](https://github.com/gaberger/earshot/releases/latest).
   (For a build of the newest commit instead, open the latest successful
   [**Build** run](https://github.com/gaberger/earshot/actions/workflows/build.yml), download the
   **Earshot-&lt;version&gt;** artifact while signed in to GitHub, and unzip it.)
2. Open the disk image and drag **Earshot** onto **Applications**.
3. Eject the disk image.

### Option B: Build from source

This needs **Xcode** (from the App Store; the command-line tools alone don't include `actool`).

```bash
git clone https://github.com/gaberger/earshot.git
cd earshot
bash EarshotApp/build.sh
```

This builds `Earshot.app`, installs it in `~/Applications`, and puts the `transcribe` and
`speakers` scripts in `~/.local/bin` so you can use them from the terminal too. To make your own
disk image afterwards, run `bash EarshotApp/make-dmg.sh` (→ `Earshot-<version>.dmg`).

## Step 4: Open Earshot for the first time

1. **Open the app.** The disk image app has no Apple Developer ID and is not notarized by Apple,
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

## Check that it works

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

## Update

To see which version you have, choose **Earshot → About Earshot**, or look at the bottom of the
menu bar panel. It reads like `1.0.0 (16, 3113bfa)`: the version, the build number, and the commit
it was built from.

- **Disk image:** download the new one and drag it onto **Applications** again. Choose **Replace**.
- **From source:** `git pull`, then `bash EarshotApp/build.sh`.

Your recordings, summaries, models and settings stay where they are.

## Uninstall

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

## Where things live

| What | Where |
|---|---|
| The app | `/Applications/Earshot.app` (disk image) or `~/Applications/Earshot.app` (built from source) |
| Recordings and results | `~/Recordings/whisper/` — per recording: audio, `.txt`, `.srt`, `.json`, `.summary.md`, `.name` |
| Helper scripts | Inside the app, in `Contents/Resources`. Source builds also put them in `~/.local/bin` for the terminal. |
| Models | `~/Models/whisper/`, `~/Models/speakers/` |
| Activity log | `~/Library/Logs/Earshot.log` — clicks, file names and results, never what was said |
