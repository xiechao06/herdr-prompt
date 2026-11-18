# 0010 — The target picker can start a new agent, from the + menu's own list

- Status: accepted
- Date: 2026-11-18

## Context

Choosing a target assumed an agent was already running. Configuring the plugin
and then being told "no live agent terminals — start an agent in Herdr first" is
a dead end: the person has to leave Neovim, find the + menu, pick an agent, come
back, and re-run the command.

Herdr's + menu already knows every program it can start, with the command line
for each. That list lives in `knownAgents()`, a **mod** API — JavaScript running
inside the app. Nothing exposes it over `hc` or `herdr-app`.

But the menu caches what it last saw in the app's shared state, per machine:

```json
{"new-menu.agents": {"": [{"key": "pi", "name": "Pi", "run": ["pi"], "installed": true}, ...]}}
```

## Decision

`:HerdrPromptTarget` (and the first-send picker) end with a row
`➕  Start a new agent…`. Choosing it lists the + menu's entries — installed
first, then the rest marked *not installed* — read from that cache in
`shared.json`. Picking one runs the same call the menu runs:

```sh
herdr-app do tab.new --name "Pi" --argv '["pi"]'
```

which answers with the new terminal's address. The plugin then polls
`terminal.list` until that terminal reports an agent status, and makes it the
target. With no live agents at all, the command goes straight to this picker
instead of complaining.

## Consequences

- Starting an agent is one command away, in the place the person already is.
- The list is a **cache**: it is what the + menu drew the last time it opened.
  Add an agent to `programs.json` and it appears after the menu is opened once.
  The failure is visible and explained at that point, not silent.
- The app calls every entry with a `run` an "agent", so `nvim` (added to the
  menu for convenience) appears in this list too. A launched program that never
  reports status is reported as such — "running as t12 but reports no agent
  status, so it cannot receive prompts" — and is **not** adopted as the target,
  because `terminal.send` to it would type into a program that is not listening
  for prompts.
- Waiting is bounded (about 15 s of polling) and the launch itself is one
  `tab.new`, so a slow-starting agent costs a wait, not a hang.
