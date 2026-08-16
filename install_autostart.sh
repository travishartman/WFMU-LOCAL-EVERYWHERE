#!/usr/bin/env bash
# Install + enable the systemd services that start the WFMU FM transmitter on boot.
#
#   si4713.service    -> tunes the SI4713 carrier + RDS on 91.1 MHz (oneshot, with retry)
#   wfmu-audio.service -> streams the Icecast relay through the USB DAC into the chip
#
# Run once on the Pi:
#   ./install_autostart.sh
# Then reboot to verify, or start immediately with the printed command.
#
# To change the broadcast frequency later, edit the ExecStart line in
# /etc/systemd/system/si4713.service and run: sudo systemctl daemon-reload

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/systemd"

for unit in si4713.service wfmu-audio.service; do
  if [ ! -f "$SRC/$unit" ]; then
    echo "Error: $SRC/$unit not found — did you git pull?" >&2
    exit 1
  fi
done

echo "Installing unit files to /etc/systemd/system ..."
sudo install -m 0644 "$SRC/si4713.service" /etc/systemd/system/si4713.service
sudo install -m 0644 "$SRC/wfmu-audio.service" /etc/systemd/system/wfmu-audio.service

echo "Reloading systemd and enabling services on boot ..."
sudo systemctl daemon-reload
sudo systemctl enable si4713.service wfmu-audio.service

# Persist the DAC Headphone volume (must be ~100) so audio survives reboots.
if command -v alsactl >/dev/null 2>&1; then
  echo "Saving current ALSA mixer levels (alsactl store) ..."
  sudo alsactl store || true
fi

# Login banner: print on-air status on every SSH login.
# Two delivery paths for robustness:
#   1. dynamic MOTD (/etc/update-motd.d) — works on images with pam_motd wired up
#   2. ~/.bashrc source line — the reliable fallback on Raspberry Pi OS Lite, whose
#      login PAM stack often shows only the static /etc/motd and never runs update-motd.d
# Run via `sh` so it works even if wfmu-status.sh lost its executable bit.
echo "Installing login status banner ..."
chmod +x "$HERE/wfmu-status.sh" 2>/dev/null || true
sudo tee /etc/update-motd.d/99-wfmu >/dev/null <<EOF
#!/bin/sh
exec sh "$HERE/wfmu-status.sh"
EOF
sudo chmod +x /etc/update-motd.d/99-wfmu

BASHRC="$HOME/.bashrc"
MARKER="# >>> wfmu status banner >>>"
if ! grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
  {
    echo ""
    echo "$MARKER"
    echo "case \$- in *i*) sh \"$HERE/wfmu-status.sh\" ;; esac"
    echo "# <<< wfmu status banner <<<"
  } >>"$BASHRC"
  echo "Added on-air banner to $BASHRC (shows on every interactive login)."
else
  echo "On-air banner already present in $BASHRC."
fi

cat <<'EOF'

Done. The radio will come up on 91.1 MHz automatically after every reboot.
Every time you SSH in, a banner shows whether it's ON AIR.

Start now without rebooting:
  sudo systemctl start si4713.service wfmu-audio.service

See status any time:
  ./wfmu-status.sh
  systemctl status si4713.service wfmu-audio.service
  journalctl -u si4713.service -u wfmu-audio.service -b
EOF
