# Privacy

Back to the [README](../README.md).

Every model runs on this Mac. There is no account and no cloud, and Earshot never uses Apple's Private Cloud Compute.

## What stays on the Mac
 Audio is recorded, transcribed (Whisper), labelled by speaker and
summarized (Apple's on-device model) on this Mac. There is no account, no server and no analytics.
Earshot itself sends nothing about you or your recordings anywhere. The activity log records steps
and results, never what was said.

## What can leave the Mac, or be seen


- **One-time downloads.** The speech models, the speaker packages (`sherpa-onnx`, fetched by `uv` the
  first time speakers are detected) and Apple's on-device model are downloaded once. After that,
  nothing needs the internet.
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
