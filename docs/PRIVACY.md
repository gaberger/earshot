# Privacy

Back to the [README](../README.md).

Every model runs on this Mac. There is no account and no cloud, and Earshot never uses Apple's Private Cloud Compute.

## What stays on the Mac
 Audio is recorded, transcribed (Whisper), labelled by speaker and
summarized (Apple's on-device model) on this Mac. There is no account, no server and no analytics.
Earshot itself sends nothing about you or your recordings anywhere. The activity log records steps
and results, never what was said: when a tool fails, the log gets its name and exit code, and the
error text, which can quote the recording, is shown in the app only. The log and the notes file can
be read only by your macOS user account.
Call audio, if you turn it on in Settings, is captured from all system audio or from an input device you choose and mixed into the same recording file. It stays on this Mac like the microphone audio, and it can contain other people's voices, so getting their consent is your responsibility. It asks for macOS's System Audio Recording permission only for All system audio, and never for Dictation or Notes.
Notes you type while recording a meeting are saved beside that recording (`.notes.md`, readable only by
you) and go to Apple's on-device model with the transcript when it is summarized.

## What can leave the Mac, or be seen


- **One-time downloads.** The speech and speaker models are fetched by Earshot from Hugging Face and
  GitHub only when you click **Download**, each checked against a fixed SHA-256, with nothing about
  you sent. Apple's on-device model is downloaded by macOS. The tools that run the models are inside
  the app. After that, nothing needs the internet.
- **The clipboard.** When dictated text cannot be typed safely (Earshot is not allowed to type, or you
  switched windows), it is left on the clipboard. It stays there until you copy something else, and a
  clipboard-history tool may record it.
- **Any agent you connect.** Through the MCP server or the spoken replies hook, an agent can see what
  you let it read, and it may send that text to its own provider. That is your choice and outside
  what Earshot controls.

## Dictation and notes

- **Dictation keeps nothing.** What you say is typed into the app in front and that is all: no text and no audio is saved. The exceptions are the ones named above: one failed clip kept in a private temporary file until your next dictation, and the clipboard when Earshot is not allowed to type or you switched windows.

Dictation text is typed into the app in front. The clipboard exception is described above. Notes keep only the text, in `~/Library/Application Support/Earshot/notes.json`, and the audio is deleted at once.

See [Agents](AGENTS.md) for what a connected agent can read, and the [user guide](GUIDE.md) for how dictation behaves.

To report a security problem, follow the [security policy](../SECURITY.md).
