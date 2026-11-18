# 0009 — A command that sends the reference alone, then focuses the agent

- Status: accepted
- Date: 2026-11-18

## Context

Most prompts are a sentence you would rather type in the agent's own window,
with the agent's own history, autocompletion and editing in front of you. What
Neovim has that the agent does not is the place you are looking at: the file and
the lines.

The prompt picker had a "Write my own…" row that asked for one line with
`vim.ui.input` and sent it with the context. That produced a one-line prompt
inside a system that is built for many-line conversation, and it competed with
the agent's own input box, which is better at exactly that job.

## Decision

Drop the inline row. The picker offers prompts and only prompts.

Add `:HerdrContext` (visual range supported): it sends the reference and nothing
else — `@src/x.lua:12-18` — then moves focus to that agent's pane so the next
keystroke is typed into the agent, not into Neovim.

## Consequences

- One message shape for a bare mention, so the agent reads the file and asks
  what you want, in its own window, with its own context.
- Focus is a real side effect: the command moves you away from the buffer you
  were reading. That is the point of the command, which is why it is its own
  command and not a flag on `:HerdrPrompt`.
- Nothing is left in Neovim to review, so there is no float and no confirmation,
  consistent with 0008's "the reference is the context".
- Typing a long prompt inside Neovim is no longer possible. It was never the
  plugin's strength: the agent's input box has history, drafts and its own
  editing, and `hc send` (via the agent pane) is one keystroke away.
