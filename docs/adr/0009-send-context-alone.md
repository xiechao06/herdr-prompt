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
The cursor is **not** moved. A paste leaves it at the end of the reference; the
person presses `ctrl+a` to get in front of it and types. Three routes were tried
and dropped:

- **A cursor key inside the clipboard.** Inside a **bracketed** paste the app
  wraps the text and the escape arrives as characters. A program with bracketed
  paste enabled received `b'w\x1b[200~abc\x1b[DXY\x1b[201~'`: the `ESC[D`
  travelled as text. In a plain shell the same bytes *did* move the cursor,
  which is why that test looked like proof and was not.
- **`home`.** herdr-core sends `ESC[H` for it (measured), and an agent's input
  box ignores that sequence. It worked in a shell and did nothing in the real
  agent.
- **`ctrl+a`, or `left` one per character.** Both work in the agent (verified:
  paste, `ctrl+a`, `q` → `q @x.lua:2`), but `hc` delivers keys only after about
  three seconds of quiet — measured 3.02 s right after a paste against 0.03 s on
  a quiet terminal, unchanged by `HC_QUIET_MS` in the client environment, and
  the core's config has no setting for it. Three seconds to move a cursor is
  worse than pressing `ctrl+a`, and a key that lands that late can arrive in the
  middle of the first word the person types.

The only channel without that gate is the framed attach stream, where a viewer
writes keys as DATA (`[channel u32 LE][kind u8][len u32 LE][payload]`). That
would make the move instant and could also drop the clipboard, at the cost of a
binary framed client and viewer size ownership. Not built; the plugin does less
and the person does one keystroke.

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
