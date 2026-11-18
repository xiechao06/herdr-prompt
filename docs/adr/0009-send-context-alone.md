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

Add `:HerdrContext` (visual range supported): the reference — `@src/x.lua:12-18`
— goes into the agent's input box **unsubmitted**, and focus moves there, so the
person types the question where the agent's own history, drafts and completion
are. No turn starts.

How the text gets there is the whole problem. herdr-core cannot paste without
submitting: `terminal.send` always presses Enter, and `terminal.keys` accepts
named keys only (`"@x.lua:2 hello"` is rejected as an unknown key). A bare
submitted mention is worse than useless — it spends a turn on a message that
asks nothing.

The app can do it. `herdr-app do terminal.paste` types the system clipboard into
the focused terminal and leaves it on the line. So the sequence is:

1. write `" @path:line"` to the clipboard (`+`) — a space *in front* of the
   reference, nothing after it,
2. `agent.focus --terminal t7`,
3. `terminal.paste`,
4. `terminal.keys { "ctrl+a" }`, so the cursor ends up at the start of the
   line, in front of the space.

Typing there gives `why is this slow? @x.lua:2`: the question comes first, one
space separates it from the mention, and the mention is not where the cursor
lands.

The cursor needs that fourth step because a paste leaves it after the text, and
three cheaper routes are dead:

- **A cursor key inside the clipboard.** Inside a **bracketed** paste the app
  wraps the text and the escape arrives as characters. A program that enables
  bracketed paste received `b'w\x1b[200~abc\x1b[DXY\x1b[201~'`: the `ESC[D`
  travelled as text. In a plain shell the same bytes *did* move the cursor,
  which is why that test looked like proof and was not.
- **`home`.** herdr-core sends `ESC[H` for it (measured), and an agent's input
  box ignores that sequence. It worked in a shell and did nothing in the real
  agent.
- **`left`, one per character.** It works, but the count assumes the pasted
  reference ends the input line; with text already there the cursor walks into
  it. Replaced.

`ctrl+a` (`\x01`) is the beginning of the line, independent of what the line
holds: in a live agent, pasting `" @x.lua:2"`, `ctrl+a`, then `q` gave
`q @x.lua:2`.

**It is not instant.** `hc` delivers keys only after about three seconds of
quiet, and our own paste starts that clock — measured 3.02 s right after a
paste against 0.03 s on a quiet terminal, unchanged by `HC_QUIET_MS` in the
client environment, and the core's config has no setting for it. The only
channel without that gate is the framed attach stream, where a viewer writes
keys as DATA (`[channel u32 LE][kind u8][len u32 LE][payload]`); it would also
remove the clipboard step. Not built: it needs a binary framed client and
viewer size ownership, which is a change of its own.

## Consequences

- One message shape for a bare mention, so the agent reads the file and asks
  what you want, in its own window, with its own context.
- Focus is a real side effect: the command moves you away from the buffer you
  were reading. That is the point of the command, which is why it is its own
  command and not a flag on `:HerdrPrompt`.
- Nothing is left in Neovim to review, so there is no float and no confirmation,
  consistent with 0008's "the reference is the context".
- Each step reports its own failure (`cannot use the clipboard`, `could not
  focus`, `could not paste`) rather than silently doing nothing: the first
  version ignored the exit status of the app commands, so a broken step looked
  exactly like a working one.
- Typing a long prompt inside Neovim is no longer possible. It was never the
  plugin's strength: the agent's input box has history, drafts and its own
  editing, and `hc send` (via the agent pane) is one keystroke away.
