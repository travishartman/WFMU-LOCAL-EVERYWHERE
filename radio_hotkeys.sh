#!/usr/bin/env bash
set -euo pipefail

# Terminal-only source control. Keys only work while this script is running
# in the focused terminal/SSH session.

SWITCHER="$(command -v wfmu-switch-source || true)"

if [[ -z "$SWITCHER" ]]; then
  echo "Missing switch helper: wfmu-switch-source (not on PATH — did you run install_autostart.sh?)" >&2
  exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

cat <<'EOF'
Terminal hotkeys enabled (this window only):
  1 = WFMU live
  2 = Rock'n'Soul Radio
  3 = Give the Drummer Radio
  4 = Sheena's Jungle Room Radio
  5 = Spotify

Extra keys:
  s = show status
  q = quit
EOF

while true; do
  IFS= read -r -s -n 1 key
  case "$key" in
    1|2|3|4|5)
      echo
      "$SWITCHER" "$key" || true
      echo "Press 1-5, s, or q..."
      ;;
    s|S)
      echo
      "$SWITCHER" status || true
      echo "Press 1-5, s, or q..."
      ;;
    q|Q)
      echo
      echo "Exiting terminal hotkeys."
      exit 0
      ;;
    *)
      # Ignore other keys silently.
      ;;
  esac
done
