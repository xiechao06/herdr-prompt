# 0006 — User prompts are Markdown files with frontmatter

- Status: accepted
- Date: 2026-11-18

## Context

Writing a prompt mid-task should not require editing Lua, restarting nvim, or
reloading a module.

## Decision

`~/.config/herdr-prompt/prompts/*.md` (override with `user_prompts_dir`), each
file:

```markdown
---
name: Harden
description: Find missing input validation
context: buffer
submit: true
---
Find missing input validation in this code. ...
```

`name` defaults to the filename, `description` to the first body line,
`context` to `selection` (the global default), `submit` to `true`.
Files load lazily on each picker open, so an edit is picked up on the next
`:HerdrPrompt` with no reload. A Lua `prompts` table in `setup()` adds or
overrides entries for one-liners.

## Consequences

- Adding a prompt is `:e ~/.config/herdr-prompt/prompts/foo.md`, nothing else.
- The frontmatter parser is 20 lines of Lua in this repo rather than a
  dependency on a YAML library for six keys.
- A malformed file is skipped with a `vim.notify`, not a crash: one bad file
  must not hide the other nine.
