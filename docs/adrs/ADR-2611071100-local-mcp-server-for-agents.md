# ADR-2611071100: A local, read-only MCP server for agents

**Status:** Accepted
**Date:** 2026-11-07
**Drivers:** jamiepine/voicebox exposes its voice features to agents over MCP and REST. The same
idea fits Earshot's other half: an agent that can read your meeting transcripts and summaries on
this Mac. Only Voicebox's public GitHub page was read, so the idea is borrowed, not copied code.

## Context

Earshot keeps one set of plain files per recording in `~/Recordings/whisper` (`WHISPER_REC_DIR`
overrides it, as the `transcribe` script already does): `<id>.txt`, `.srt`, `.json`,
`.summary.md`, `.name`, plus the audio. Nothing makes them reachable by an agent except pasting.

## Decision

1. **A stdio MCP server, `scripts/earshot-mcp`**, a stdlib-only Python 3 script like the other
   helper scripts. It reads the recordings directory directly. It does not depend on the app being
   open, starts no daemon, opens no port and uses no network.
2. **Read-only tools only:** `list_recordings` (id, name, whether a summary exists, modified
   time, newest first), `get_transcript(id)`, `get_summary(id)`, `search(query)` (case-insensitive,
   over names, transcripts and summaries; returns id and a short snippet).
3. **Safe by construction.** An `id` is a bare file stem. Anything containing a path separator, a
   `..`, a NUL or a leading dot is rejected, so a tool can never read outside the directory. Tool
   errors are returned as MCP tool errors (`isError`), never a crash; a malformed request gets a
   JSON-RPC error and the server keeps running.
4. **Protocol:** newline-delimited JSON-RPC 2.0 on stdin/stdout: `initialize`,
   `notifications/initialized` (no reply), `ping`, `tools/list`, `tools/call`. An unknown method is
   error `-32601`. Logs go to stderr only, never stdout, and never carry transcript text.
5. **Privacy:** it exposes what the user already keeps on disk, to the agent the user connects it
   to. That agent may send the text to its own provider, which is the user's choice and outside
   Earshot's "nothing leaves this Mac" promise. The README says so next to the setup line.

Not in this change: writing or deleting recordings, starting a recording, transcribing a file,
an HTTP/REST endpoint, and a Settings switch. Each can be its own ADR.

## Consequences

- Agents get recordings and summaries with one config line, and the app is not touched.
- A new trust boundary: whoever can run the script can read every transcript. It is the same
  access the user's own account already has.

## Implementation

Gate, written before the code: `python3 -I scripts/earshot-mcp-test` exits 0. It builds a fixture
directory, drives the real server over stdio, and checks the protocol, each tool, path-traversal
refusal, error handling and that stdout carries only JSON-RPC. It fails itself if fewer than 24
checks ran. It also runs from `EarshotApp/Tests/run.sh`.

## References

- ADR-2611071000-dictation-cleanup-with-on-device-model
- https://github.com/jamiepine/voicebox (GitHub page only)
- https://modelcontextprotocol.io
