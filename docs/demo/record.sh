#!/bin/bash
# Record the README screencast: a real Herdr window, driven by script, captured
# with `herdr-app shot`, assembled with ImageMagick.
#
# What it needs: Herdr running with this plugin installed, ImageMagick
# (`magick`), nvim, and a minute where you are not using the window — it selects
# its own tabs to capture, so it takes focus for a moment at each frame.
#
# The agent it messages is a scratch program that reports program status
# (OSC 7501), so the demo never touches a real agent.
set -euo pipefail

REPO="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
OUT="${TMPDIR:-/tmp}/herdr-prompt-demo"
SOCK="$OUT/nvim.sock"
mkdir -p "$OUT"
rm -f "$OUT"/*.png "$SOCK"

cleanup() {
  herdr-app 'do' space.close --id "$SPACE" >/dev/null 2>&1 || true
  rm -f "$SOCK"
}
trap cleanup EXIT

# A stand-in agent: it reports status so herdr-core lists it, then echoes.
cat > "$OUT/agent.py" <<'PY'
import os, sys
sys.stdout.write("\x1b]7501;state=idle:app=demo\x1b\\")
sys.stdout.flush()
os.execvp("cat", ["cat"])
PY

# 1. A space of our own, with nvim and a control socket.
herdr-app 'do' space.new --name screencast --folder "$REPO" \
  --argv '["nvim","-n","--listen","SOCK","lua/herdr-prompt/init.lua"]' >/dev/null
SPACE=$(herdr-app ls | python3 -c '
import json, sys
for space in json.load(sys.stdin)["spaces"]:
    if space["name"] == "screencast":
        print(space["id"])
')
sleep 8   # nvim and the user's plugins take a moment

# 2. The stand-in agent in its own tab.
herdr-app 'do' terminal.open --folder "$REPO" --name "demo agent" \
  --argv "[\"python3\",\"$OUT/agent.py\"]" >/dev/null
sleep 3

read -r NVIM_TAB AGENT_TERM <<<"$(herdr-app ls | python3 -c '
import json, sys
tabs = [t for s in json.load(sys.stdin)["spaces"] if s["name"] == "screencast" for t in s["tabs"]]
nvim = next(t for t in tabs if t["name"] == "nvim")
agent = next(t for t in tabs if t["name"] == "demo agent")
print(nvim["id"], agent["terminals"][0]["terminal"], end=" ")
')"

# 3. Point the plugin at it.
nvim --server "$SOCK" --remote-send ":HerdrPromptTarget $AGENT_TERM<CR>"
nvim --server "$SOCK" --remote-send ':call cursor(300,5)<CR>'
sleep 1

# Refuse any frame taken while another tab is active: the window is the person's.
shot() { # tab, file
  herdr-app 'do' tab.select --id "$1" >/dev/null
  sleep 0.6
  now=$(herdr-app status | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tab",""))')
  [ "$now" = "$1" ] || { echo "refused $2: active tab is $now" >&2; return 1; }
  herdr-app shot "$2" >/dev/null
}

send() { nvim --server "$SOCK" --remote-send "$1"; }

shot "$NVIM_TAB" "$OUT/f1-line.png"
send ':HerdrPrompt<CR>';   sleep 1.5; shot "$NVIM_TAB" "$OUT/f2-picker.png"
send 'Review';             sleep 1.5; shot "$NVIM_TAB" "$OUT/f3-filter.png"
send '<CR>';               sleep 1.5; shot "$NVIM_TAB" "$OUT/f4-composed.png"
send '<C-s>';              sleep 2.5; shot "$NVIM_TAB" "$OUT/f5-sent.png"

# 4. Crop to the editor pane and assemble. Cropping keeps the sidebar (spaces,
#    agent names, machine names) out of a picture that goes in a public repo.
cd "$OUT"
for f in f1-line f2-picker f3-filter f4-composed f5-sent; do
  magick "$f.png" -crop 3140x1920+630+60 +repage -resize 1200x "crop-$f.png"
done
magick -delay 220 -loop 0 crop-f1-line.png crop-f2-picker.png crop-f3-filter.png \
  crop-f4-composed.png crop-f5-sent.png -layers Optimize "$REPO/docs/demo/flow.gif"

echo "wrote $REPO/docs/demo/flow.gif"
