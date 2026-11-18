# Glossary

Terms used in this plugin's design. One meaning each; if a word is not here, we
have not decided it yet.

**Herdr app** — the macOS desktop app (`dev.herdr.app`, `/Applications/Herdr.app`)
that shows spaces, tabs and panes. It owns the window only.

**herdr-core** — the daemon behind the app. It owns the terminals, keeps them
alive when the window closes, and reports agent status. Its CLI is `hc`.

**hc** — the herdr-core CLI. `hc ls` lists terminals; `hc send <t> <text>` pastes
text into a terminal and presses Enter. This is the only transport this plugin
needs.

**agent terminal** — a terminal whose foreground program is a coding agent
(`pi`, `claude`, `codex`, …). `hc ls` shows it as `{address, agent, state,
status, cwd}`. Named "agent" here, never "session".

**target** — the one agent terminal a message is sent to. Chosen once, kept for
the rest of the nvim session.

**status** — what the *agent* reports: `idle`, `working`, `done`, `blocked`,
`error`. Over JSON-RPC it arrives as the `state` field of the `status` object,
which is why the code stores it as `status`.

**state** — what the *terminal* reports: `live` or `finished`. Never the same
word as status, and confusing them is how a finished agent gets a message.

**context** — the code shipped with a message: a file path, a line range, and
the text itself.

**context payload** — the exact bytes appended to a prompt: location header plus
a fenced block. Deliberately one shape, so every prompt and the agent's reading
of it stay predictable.

**prompt** — the text a person means to say. Either a **catalog prompt**
(shipped, parameterised, e.g. Explain / Review / Tests) or a **user prompt**
(written by the person, lives on disk, same shape as a catalog prompt).

**context send** — `:HerdrContext`: the reference alone, sent, with focus moved
to the agent's pane. Not a prompt: it carries no question.

**send** — one `hc send` invocation: paste, then Enter. Irreversible once the
agent's turn starts.

**waiting** — after a send, the agent works in its own pane. Whether this plugin
watches that pane is a design decision, not an assumption.
