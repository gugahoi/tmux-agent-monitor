#!/usr/bin/env bash
# Manual demo recording: sets up the isolated tmux scenario, then records an
# asciinema cast. You drive the keys when recording starts.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOCK=tam-demo

"$REPO/docs/demo-setup.sh" "$SOCK"

cat <<EOF
Scenario live. What's stamped:
  api      🔴 wait    4m    claude
  web      🔴 wait   12s  opencode
  dotfiles 🟢 done    9m    pi
  demo     (your recording shell)

Recording starts: asciinema rec -c "tmux -L $SOCK attach" docs/demo.cast
Suggested choreography (in front of the camera):
  1. hold ~1s on the plain session
  2. switch between sessions a couple of times (C-b s / :ls) to show agents
  3. press A (the picker opens; longest-waiting first) — hold ~2s
  4. Enter — jumps to 🔴 api
  5. Ctrl+D ends the recording

Convert to GIF:
  agg docs/demo.cast docs/demo.gif    # brew install agg the first time

Cleanup: tmux -L $SOCK kill-server
EOF

# drive the keys from a side-script so recording is one take; attach first
cat > /tmp/demo-drive-$$.sh <<'INNER'
#!/usr/bin/env bash
sock="$1"
sleep 1.5                                   # settle after attach
tmux -L "$sock" send-keys -t demo:1.1 ":ls" # browse sessions
sleep 2
tmux -L "$sock" send-keys -t demo:1.1 Enter # back to session
sleep 1
tmux -L "$sock" send-keys -t demo:1.1 A     # open picker
sleep 3                                     # sit on the picker
tmux -L "$sock" send-keys -t demo:1.1 Enter # jump to longest-waiting
sleep 2
tmux -L "$sock" send-keys -t demo:1.1 C-d   # end recording
INNER
chmod +x /tmp/demo-drive-$$.sh

( /tmp/demo-drive-$$.sh "$SOCK" ) &

exec asciinema rec -c "tmux -L $SOCK attach" "$REPO/docs/demo.cast"
