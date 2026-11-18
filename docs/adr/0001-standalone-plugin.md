# 0001 — A standalone plugin, not a herdr-nvim module

- Status: accepted
- Date: 2026-11-18

## Context

A working implementation of "send editor context to an agent pane" already ships
inside `herdr-nvim` (`lua/herdr-nvim/{agents,dispatch,comments,prompt,ui}.lua`),
installed at `~/.local/share/herdr-nvim/app/<hash>/`. It speaks to the Herdr app
through `herdr-nvim app-send` / `app-agents`, subcommands built around the older
`herdr` data model (`pane_id`, `workspace_id`, `tab_id`).

The app that is actually running here is Herdr **app** 0.1.16 over herdr-core
0.1.21. Its own manual says the app "does not arrange windows", and herdr-core
"runs programs in persistent terminals". The current API has no `pane_id` in the
send path at all: a message goes to a *terminal address* (`t7`).

## Decision

New plugin, own repository (`~/workspace/herdr-app-prompt`), depending on
`hc`/herdr-core only. No code shared with `herdr-nvim`, no `app-send`.

## Consequences

- Nothing to migrate and nothing to keep in sync with a pane-id translation
  layer that the current API no longer needs.
- The two plugins can be uninstalled independently.
- We may not reuse `herdr-nvim`'s UI code (`ui.lua`'s picker, decoration
  handling); the picker here is written fresh against `vim.ui.select`.
