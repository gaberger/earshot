# Use Earshot from an agent

Back to the [README](../README.md). What a connected agent can see is covered in [Privacy](PRIVACY.md).

## MCP server

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

## Hear replies spoken (voice loop)

This is for Claude Code. `scripts/earshot-speak` reads Claude's reply aloud when a turn ends, using the macOS `say` command locally. Nothing leaves this Mac.

```bash
scripts/earshot-speak on        # speak replies for the session you run this from
scripts/earshot-speak on --all  # speak replies for every session
scripts/earshot-speak off       # stop speaking replies
scripts/earshot-speak status    # "on" or "off", then which session it is bound to
scripts/earshot-speak stop      # cut off the reply being spoken now
```

It is off until you run `on`. `on` binds the voice to the session you run it from, so you must run it from inside the Claude Code session you are talking to, for example by typing `!scripts/earshot-speak on` (the exclamation-mark prefix) in the prompt. Outside a session it refuses and tells you so. `on --all` speaks for every session. Other windows stay quiet; running `on` in another session moves the voice there. Add the Stop hook to your Claude Code settings:

```json
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/ABSOLUTE/PATH/TO/earshot/scripts/earshot-speak"}]}]}}
```

Code blocks, tables and URLs are skipped, and long replies are cut to about 280 characters. **Anyone nearby hears replies while it is on.** Pressing the dictation hotkey also stops the voice, so you can talk over it; this needs the rebuilt app.
