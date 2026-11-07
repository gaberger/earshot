# Security policy

Earshot handles private audio and transcripts, so security reports are taken seriously.

## Supported versions

Only the latest release receives security fixes. You can find it on the
[latest release page](https://github.com/gaberger/earshot/releases/latest).
If you run an older build, update before reporting.

## Reporting a vulnerability

Please do not open a public issue. Use the private form instead:
[Report a vulnerability](https://github.com/gaberger/earshot/security/advisories/new).

Include:

- what you found
- the steps to reproduce it
- the Earshot version shown in Earshot, About Earshot
- the macOS version
- the impact you expect

## What to expect

- An acknowledgement within a few days. This is a target, not a guarantee.
- An assessment of the report.
- A fix in a new release.
- Credit in the release notes, if you want it.

Please allow time for a release to ship before you publish details.

## Scope

These count as vulnerabilities:

- Anything that sends audio, transcripts, notes or summaries off the Mac,
  against the promise in [docs/PRIVACY.md](docs/PRIVACY.md).
- Dictation text pasted into the wrong window, left on the clipboard
  unexpectedly, or typed into a secure input field, and any misuse of the
  Accessibility permission.
- The MCP server `scripts/earshot-mcp` reading outside the recordings folder,
  writing anything, or exposing audio. Its tool output is untrusted text that
  comes from speech, so an agent should treat it as data and not as
  instructions.
- The spoken-replies hook `scripts/earshot-speak` running or stopping a
  process it should not, or reading anything it should not.
- The helper scripts in `scripts` and the build and release workflow in
  `.github`, as a supply-chain surface.

## Out of scope

- The app not being notarized by Apple. This is documented, with the Open
  Anyway step.
- Attacks that need an already compromised Mac or an administrator account.
- Bugs in upstream components such as whisper.cpp, sherpa-onnx or Apple
  frameworks. Report those to their own projects.
- An AI agent you connect sending the text it reads to its own provider. This
  is documented.
- Slowing the app down with very large local files.

Related: [docs/PRIVACY.md](docs/PRIVACY.md)
