# Screencast

`flow.gif` is a recording of the plugin running in a real Herdr window:

1. the cursor on a line in `lua/herdr-prompt/init.lua`,
2. `:HerdrPrompt` — the seven catalog prompts,
3. typing `Review` to filter,
4. the composed message, with `@lua/herdr-prompt/init.lua:300` at the end,
5. `<C-s>` sends it.

`record.sh` regenerates it. It creates its own space, starts Neovim with a
control socket so the frames are driven exactly, and targets a scratch program
that reports program status (OSC 7501 `state=idle:app=demo`) — so the recording
never messages a real agent.

Two things the script is careful about, both learned the hard way:

- **It refuses a frame if another tab is active.** `herdr-app shot` captures the
  window, so a frame taken while you are reading something else shows your work,
  not the demo. `shot()` re-selects its tab and verifies with `herdr-app status`
  before every capture.
- **It crops to the editor pane.** The window also draws the sidebar with your
  spaces, agent names and machine names. Cropping keeps those out of a file that
  goes in a public repository.
