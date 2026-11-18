# 0002 — One long-lived `hc connect` connection, JSON-RPC over NDJSON

- Status: accepted
- Date: 2026-11-18

## Context

Two ways to reach herdr-core from nvim: spawn `hc` per action
(`hc ls`, `hc send …`), or keep one `hc connect` process and speak its protocol.

`hc connect` is JSON-RPC 2.0, one message per line, protocol generation 1
(`hc schema` → OpenRPC 1.3.2, core 0.1.21). Verified live: `hello` returns
`{generation: 1, framed: false, methods: [...], features: [...]}`;
`terminal.list` returns terminal facts; `terminal.send {terminal, text}` returns
`{started, status, turn}`. `events.subscribe` pushes `event` notifications,
a `heartbeat` every 15 s, and `missed` + a fresh snapshot for a slow subscriber.

## Decision

One process per nvim session, started on first use, NDJSON (not `framed`), via
`vim.fn.jobstart` with `on_stdout` line splitting. Requests carry monotonic
integer `id`s and resolve a callback on match. Kill the job on `VimLeavePre`.

## Consequences

- Sending costs no process spawn; a picker refresh is one round trip.
- `events.subscribe` gives live agent status for free, so "did the agent answer"
  becomes a notification rather than polling (`hc read` in a loop).
- We own reconnect logic: core restart, `server.stop`, socket loss must all
  surface as a clear error, then reconnect on next use.
- **Shape trap**: `terminal.list` returns `status` as `{app, state}`, while
  `hc ls --json` flattens it to a string (`"done"`, `"working"`). All status
  handling in this plugin is written against the RPC shape; never mix the two.
