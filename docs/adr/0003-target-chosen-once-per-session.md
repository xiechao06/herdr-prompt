# 0003 — The target is chosen once per nvim session

- Status: accepted
- Date: 2026-11-18

## Context

Sending needs a destination. `terminal.list` can report several live agent
terminals at once (verified: two `pi` terminals, in two different spaces).

## Decision

First send with no target opens a picker over live agent terminals
(`state: "live"` and a non-null `status.app`), showing
`app · state · cwd-tail · name`. The choice is remembered in process memory for
the rest of the nvim session. `:HerdrPromptTarget` re-opens the picker;
`:HerdrPromptTarget t1m` sets it directly.

## Consequences

- The common path is one keystroke, and it matches the stated requirement that
  the agent is chosen at the start rather than per message.
- A finished target fails loudly instead of silently retargeting: choosing a
  different agent is an explicit act, never an inference.
- Not persisted across restarts (no file, no per-project cache). Re-picking on
  a new nvim session costs one keystroke and keeps state out of the repo.
