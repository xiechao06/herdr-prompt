# herdr-prompt

Send a prompt from Neovim to a coding agent running in the [Herdr](https://herdr.dev) app,
with the current line or the visual selection attached as context.

- Picks the agent once per Neovim session (or `:HerdrPromptTarget t7`).
- Seven catalog prompts (Explain, Review, Fix, Optimize, Docs, Tests, Commit) and
  your own prompts as Markdown files.
- Shows the composed message for editing before it is sent.
- Talks to `herdr-core` directly over `hc connect` (JSON-RPC 2.0), so it works in
  a Herdr pane or in any terminal where `hc` can reach the core.

Not a chat UI: the agent works in its own pane, and this plugin does not read its
answers back. See `docs/adr/0007-compose-before-send.md` for why the message is
confirmed before sending.

## Install

Link the checkout into your Neovim config, so nvim loads the repo itself and
edits are live — there is nothing to copy or sync:

```sh
ln -s ~/workspace/herdr-app-prompt ~/.config/nvim/herdr-prompt
```

then, with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
-- ~/.config/nvim/lua/plugins/herdr-prompt.lua
return {
  dir = vim.fn.expand("~/.config/nvim/herdr-prompt"),
  name = "herdr-prompt",
  event = "VeryLazy",
  opts = { confirm = true },
}
```

`opts` is passed to `setup()`; see [Configuration](#configuration). To use the
repo directly instead of a link, point `dir` at it. Native package loading works
too: `ln -s ~/workspace/herdr-app-prompt
~/.local/share/nvim/site/pack/herdr/start/herdr-prompt`, then call
`require("herdr-prompt").setup({})` from your own config.

`hc` must be on `PATH` (`~/.local/bin/hc`, installed with Herdr). Nothing else is
required: no picker plugin (it uses `vim.ui.select`, which `dressing.nvim` makes
nice), no treesitter, no LSP.

## Use

| Command | What it does |
| --- | --- |
| `:HerdrPrompt` | Pick a prompt; the current line is the context |
| `:'<,'>HerdrPrompt` | Pick a prompt; the selection is the context |
| `:HerdrPrompt Review` | Skip the picker, send the Review prompt |
| `:HerdrPromptTarget` | Choose which agent gets prompts |
| `:HerdrPromptTarget t7` | Point at `t7` without a picker |
| `:HerdrPromptStop` | Close the connection to herdr-core |

Default keymaps: `<leader>ap` (normal and visual), `<leader>at`. Set
`keymaps = { prompt = "", target = "" }` to keep your own.

After a prompt is composed, a floating buffer shows the whole message —
prompt body, location line, fenced code. `<C-s>` sends, `<Esc>` cancels, and you
can edit anything first (fix the range, drop the code, reword the ask).

**Write my own…** opens the same float with two blank lines above the context and
the cursor in insert mode: type your question, and the code goes below it. Blank
lines you leave empty are not sent.

## Context

| Kind | What is attached |
| --- | --- |
| `line` | The current line (default for `:HerdrPrompt`) |
| `selection` | The visual selection (default for `:'<,'>HerdrPrompt`) |
| `buffer` | The whole buffer |
| `gitdiff` | `git diff --cached`, or `git diff` when nothing is staged |
| `none` | Nothing |

The payload is one shape: a location line, then a fenced block.

`````text
src/herdr-prompt/init.lua:120-128
```lua
local function do_send(agent, text)
...
```
`````

The path is relative to the **target agent's** folder, so it resolves from where
the agent runs; a file outside it keeps its absolute path.

## Your own prompts

Drop a Markdown file in `~/.config/nvim/herdr-prompts/` (override with
`user_prompts_dir`):

```markdown
---
name: Harden
description: Find missing input validation
context: buffer
submit: true
---
Find missing input validation in this code. Report each gap as `path:line: what
is missing`, then suggest the smallest fix.
```

| Key | Default | Meaning |
| --- | --- | --- |
| `name` | filename | Picker label and `:HerdrPrompt <name>` |
| `description` | first body line | Shown next to the name |
| `context` | the call site | `line`, `selection`, `buffer`, `gitdiff`, `none` |
| `submit` | `true` | `false` leaves the text in the float without sending |

Files are read each time the picker opens, so an edit lands on the next
`:HerdrPrompt` with no reload. A body may place the context with `{{context}}`
(also `{{file}}`, `{{lines}}`); without a placeholder the payload is appended
after a blank line.

## Configuration

```lua
require("herdr-prompt").setup({
  hc = "hc",
  target = nil,           -- e.g. "t7"; nil asks on first send
  confirm = true,         -- show the float; false sends immediately
  focus_agent = false,    -- `herdr-app do agent.focus` after a send
  prompts = {},           -- extra prompts, same shape as the catalog
  user_prompts_dir = nil, -- nil = <nvim config>/herdr-prompts
  context = {
    line_numbers = false, -- prefix code lines with their number
    max_lines = 2000,     -- refuse anything larger instead of truncating
  },
  keymaps = {
    prompt = "<leader>ap",
    target = "<leader>at",
  },
})
```

## Behaviour worth knowing

- **A blocked agent is refused.** `blocked` means a person is needed; sending into
  a permission dialog is never helpful. Answer it in its pane.
- **A working agent gets a warning, then the message.** The text is pasted into
  its input, where the agent decides what to do with it.
- **The target is not persisted.** A new Neovim session asks again (one keystroke
  with one agent). A target that has since finished is reported, never silently
  replaced by another agent.
- **The agent you are already sending to is marked `✓`** at the top of its row
  and named in the picker's prompt, so re-opening the picker tells you where
  prompts currently go without opening one.
- **Rows read `address · app · status · pane`**, e.g.
  `t1m · pi · done · agent_workspace / 1`: the address is what
  `:HerdrPromptTarget` takes, and the pane label is what the Herdr window shows,
  so a row can be matched by eye. The folder is the agent's *current* one, not
  where it was launched, so it can differ from the folder you started it in.
- **The terminal nvim itself runs in is not offered** (`HC_TERMINAL_ID`), so you
  cannot send a prompt into the window you are reading.
- **Nothing is read back.** `hc read`/`events.subscribe` could show the answer in
  a split; that is deliberately not in this version.

## Development

```sh
nvim --headless -u NONE -l tests/smoke.lua
```

The smoke test drives the real `hc connect` socket: it starts a `cat` terminal,
sends a composed Review message through the plugin's own path, and checks the
bytes that arrived before removing the terminal. It never sends to a live agent.

Design records: `docs/adr/`, vocabulary: `GLOSSARY.md`.
