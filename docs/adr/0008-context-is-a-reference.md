# 0008 — Context is a reference, not a copy

- Status: accepted
- Date: 2026-11-18
- Supersedes the default half of 0004 (the fenced block stays, as an option)

## Context

0004 shipped the context as a location line plus every selected line in a fenced
block. In practice the agent being messaged runs **in the workspace with the
file on disk**: it opens the file itself, at the version that exists when it
looks. Copying the lines costs tokens, doubles the message, and can disagree
with the file by the time the agent reads it.

## Decision

The payload is the reference alone, written as an agent mention:

```
@src/herdr-prompt/init.lua:120
@src/herdr-prompt/init.lua:120-128
```

`@` because that is how an agent CLI is told "this file": the line reads as a
mention rather than prose. It comes **last**: the request, a blank line, then
the reference. The ask is what the agent has to act on, so it reads first; the
reference closes the message as the thing being pointed at. A prompt body may
place the payload anywhere itself with `{{context}}`.

(An earlier revision of this ADR put the reference first. Both read fine; this
is a preference, not a correctness argument, and `{{context}}` is the escape
hatch for prompts that want the other order.)

Always relative to the target agent's folder: `lua/x.lua` inside it,
`../other/x.lua` beside it. Never absolute — an absolute path leaks a home
directory into every message, and `..` resolves just as well from where the
agent runs. (0004 said "absolute outside the folder"; that is superseded.)
The lines are copied only when `context.code = true`, and **always** when there
is no path to point at (a scratch buffer), because a message that says `buffer`
and nothing else carries no context at all.

`context.max_lines` therefore guards copied code only: a bare reference has no
size to guard. `gitdiff` is unchanged — a diff has no single location, and its
content is the whole point.

## Consequences

- A prompt is now two short lines instead of a block. Selection size stops
  mattering, so the "narrow the selection" error almost never fires.
- The agent reads current truth from disk rather than a snapshot. That is what
  we want here: a review of a stale copy is worse than no copy.
- This assumes the agent can reach the file: same machine, same workspace. For
  an agent on another machine, or a file outside its folder, set
  `context.code = true`. There is no automatic detection of a remote agent yet.
- `context.line_numbers` only does something together with `code = true`.
