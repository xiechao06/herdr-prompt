# 0004 — One context payload shape: location line, then a fenced block

- Status: accepted
- Date: 2026-11-18

## Context

An agent reading a pasted message needs (a) where the code is, (b) the code, and
(c) no ambiguity about where the code stops. CopilotChat uses
` ```lang path=/f.lua start_line=1 end_line=9 ` with per-line number prefixes;
`herdr-nvim` uses a `path:12` / `path:12-18` location line.

## Decision

~~~~text
src/foo.lua:12-18
```lua
<code, verbatim>
```
~~~~

- Path relative to the **target agent's** `cwd` when it is inside it, absolute
  otherwise. A path only helps if it resolves from where the agent runs.
- No per-line number prefixes by default (`context.line_numbers = false`);
  the range in the location line is contiguous, so prefixes add noise.
- Default context: visual selection when the call came from visual mode,
  otherwise the current line. Prompts may override: `selection`, `line`,
  `buffer`, `gitdiff`, `none`.
- A prompt body may contain `{{context}}`; if it does not, the payload is
  appended after a blank line. Also `{{file}}` and `{{lines}}`.

## Consequences

- One shape to test, one shape to document, and the same shape whether the
  context came from a selection, a whole buffer, or a diff.
- Selections above `context.max_lines` (default 2000) are refused with the count
  and the setting name, never silently truncated: a dropped middle of a function
  reviews as a different function.
