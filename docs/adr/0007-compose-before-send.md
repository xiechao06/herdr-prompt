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
- The float is for **catalog prompts** only: its job is to show a composed
  range and path before they are committed. Typed prompts left the picker
  entirely — see 0009, which replaced "Write my own…" with `:HerdrContext`.
- Two earlier versions were wrong, both same-day: the first opened the float
  with the cursor in normal mode *on the context's own location line* (typing
  "please fix this" ran as motions — `o` opened a line, `w` moved a word); the
  second added a typing space and insert mode but still asked for confirmation
  of text the person had just written. Both were dropped for one reason: the
  float reviews *composed* text, and an inline prompt is not composed.
