# 0007 — The composed message is shown for editing before it is sent

- Status: accepted
- Date: 2026-11-18

## Context

A send is irreversible once the agent's turn starts. The composed message is
prompt body + a location header + a fenced code block; the two parts that are
easiest to get wrong (wrong range, wrong file) are exactly the parts the person
did not type.

## Decision

After picking a prompt, the composed text opens in a floating scratch buffer
(`filetype=markdown` so fences highlight). `<C-s>` sends the buffer's contents,
`<Esc>` / `<C-c>` cancels, ordinary editing works. `confirm = false` in
`setup()` skips the float and sends immediately (`submit = false` on a user
prompt skips only the send, leaving the text in the float).

## Consequences

- One keystroke more than "send immediately", in exchange for the range and path
  being visible before they are committed.
- The float is also the inline-prompt input: "Write my own…" is the same float,
  opened with two blank lines above the context and the cursor in insert mode.
  Typing space, then a blank line, then the payload; blank lines left empty are
  dropped on submit. One composition surface, not two.
- The first version skipped both, so an inline prompt opened in normal mode *on
  the context's own location line*: the first word typed ran as motions (`o`
  opened a line, `w` moved a word) and the message arrived mangled. Fixed the
  same day; the test now types into the float and checks the submitted text.
