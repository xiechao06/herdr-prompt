# 0005 — Catalog prompts are rewritten, not copied, from CopilotChat

- Status: accepted
- Date: 2026-11-18

## Context

`CopilotChat.nvim`'s `prompts.lua` has two layers: `prompt` (the task) and
`system_prompt` (a persona, e.g. "You are a code reviewer…"). CopilotChat sends
the persona in the API's `system` role.

This plugin sends into a **terminal agent's turn**. There is no system channel:
anything we send is a user message, sitting next to the agent's own system
prompt, which we cannot see or replace. Prepending "You are a code reviewer"
therefore competes with instructions that already say what the agent is.

## Decision

Take CopilotChat's seven prompt bodies as the source of truth for *what to ask*
(Explain, Review, Fix, Optimize, Docs, Tests, Commit) and drop every
`system_prompt`. Rewrite each body to be short, imperative, and to state the
output shape inline where the shape matters (Review: `path:line: problem`).
`Commit` takes `gitdiff` context; it is in scope.

## Consequences

- No persona text in any message; one fewer way for the agent to be confused.
- We diverge from the linked file, so it cannot be synced wholesale. The
  ADR is the record of why.
- A user who wants personas can write one as a user prompt — it is just text,
  and the plugin does not treat user prompts differently from catalog prompts.
