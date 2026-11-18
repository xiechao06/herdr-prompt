# 0003 — The target is chosen once per nvim session

- Status: accepted
- Date: 2026-11-18

## Context

Sending needs a destination. `terminal.list` can report several live agent
terminals at once (verified: two `pi` terminals, in two different spaces).

## Decision

First send with no target opens a picker over live agent terminals
(`state: "live"` and a non-null `status.app`), labelled
`address · app · status · name? · where`, e.g.
`t1m · pi · done · agent_workspace / 1`. The choice is remembered in process
memory for the rest of the nvim session. `:HerdrPromptTarget` re-opens the picker;
`:HerdrPromptTarget t1m` sets it directly.

## Consequences

- The common path is one keystroke, and it matches the stated requirement that
  the agent is chosen at the start rather than per message.
- A finished target fails loudly instead of silently retargeting: choosing a
  different agent is an explicit act, never an inference.
- Not persisted across restarts (no file, no per-project cache). Re-picking on
  a new nvim session costs one keystroke and keeps state out of the repo.
- The address leads the label because it is the name `:HerdrPromptTarget`
  takes: a label you can type back is worth more than a pretty one.
- `where` is the pane label the Herdr window itself shows (`<space> / <tab>`),
  so a row can be matched to the window by eye. Without labels (a plain
  terminal) it falls back to the folder's tail.
- The folder in that label, and the base paths are relativised against, is
  `foreground.cwd` — the agent's *current* folder. `cwd` is where it was
  launched and goes stale as soon as an agent cds; herdr-core's manual says
  so, and using it was a bug fixed the same day (see the commit log).
- A terminal that is itself the one nvim runs in (`HC_TERMINAL_ID`) is not
  offered: you would be typing into the window you are reading.
