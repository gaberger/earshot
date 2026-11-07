# ADR-2611071200: Deferred work for the Earshot MCP server

**Status:** Proposed
**Date:** 2026-11-07

## Context

ADR-2611071100 shipped a serial, stateless, read-only server. Three limits were accepted on purpose.

## Decisions to take when they matter

1. **Search runs serially.** A search that matches nothing can delay a `ping` behind it; the 64 MiB
   byte budget bounds the delay. If it bites, add a worker thread plus a stdout lock.
2. **No search index.** Every search re-reads the files. If the budget is hit in real use, build an
   index in its own ADR (the app already has `SearchIndex.swift`).
3. **No JSON-RPC batches.** Only `2025-06-18` and `2024-11-05` are advertised because `2025-03-26`
   requires batch support. Add batches and that version together or not at all.
4. **Non-atomic writers.** The app and `transcribe` write `.txt`, `.summary.md` and `.name`
   separately, so a reader can see a new transcript with an old summary. A read-only server cannot
   fix this; writing via temp file and rename on the writer side would.

## Gate

`python3 -I scripts/earshot-mcp-test && python3 -I scripts/earshot-mcp-hardening-test`
