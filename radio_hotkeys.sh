#!/usr/bin/env bash
set -euo pipefail

# WFMU login/console control. Shows the banner + now-playing, then reads single
# keys 1-5 to switch streams (q to quit). Runs as the normal user; the switch
# helper self-elevates via sudo (see the NOPASSWD sudoers rule installed by
# install_autostart.sh), so no password prompt interrupts the hotkeys.

SWITCHER="$(command -v wfmu-switch-source || true)"

if [[ -z "$SWITCHER" ]]; then
  echo "Missing switch helper: wfmu-switch-source (not on PATH — did you run install_autostart.sh?)" >&2
  exit 1
fi

# Show the WFMU banner (dog & cow logo + on-air status) once at the top.
STATUS="$(command -v wfmu-status || true)"
[[ -n "$STATUS" ]] && "$STATUS" || true

# Background now-playing watcher: prints track metadata on load and whenever it
# changes (polls every 30s). Runs only for the life of this listener.
NOWPLAYING="$(command -v wfmu-nowplaying || true)"
NP_PID=""
if [[ -n "$NOWPLAYING" ]]; then
  "$NOWPLAYING" --watch &
  NP_PID=$!
  # shellcheck disable=SC2064
  trap "kill $NP_PID 2>/dev/null || true" EXIT
fi

cat <<'EOF'

WFMU hotkeys — press a key (this window only):
  1 = WFMU live
  2 = Give the Drummer Radio
  3 = Rock'n'Soul Radio
  4 = Sheena's Jungle Room Radio
  5 = Spotify
  n = show now playing    s = show status    q = quit
EOF

while true; do
  IFS= read -r -s -n 1 key
  case "$key" in
    1|2|3|4|5)
      echo
      "$SWITCHER" "$key" || true
      echo "Press 1-5, n, s, or q..."
      ;;
    n|N)
      echo
      [[ -n "$NOWPLAYING" ]] && "$NOWPLAYING" --once || echo "now-playing helper not installed"
      echo "Press 1-5, n, s, or q..."
      ;;
    s|S)
      echo
      [[ -n "$STATUS" ]] && "$STATUS" || true
      echo "Press 1-5, n, s, or q..."
      ;;
    q|Q)
      echo
      echo "Exiting WFMU hotkeys."
      exit 0
      ;;
    *)
      # Ignore other keys silently.
      ;;
  esac
done
