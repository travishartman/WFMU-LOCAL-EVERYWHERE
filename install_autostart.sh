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

cat <<'EOF'

Done. The radio will come up on 91.1 MHz automatically after every reboot.

Start now without rebooting:
  sudo systemctl start si4713.service wfmu-audio.service

Check status / logs:
  systemctl status si4713.service wfmu-audio.service
  journalctl -u si4713.service -u wfmu-audio.service -b

Reminder: if 'aplay -l' ever shows the USB DAC on a card other than 1, edit the
hw:1,0 argument in /etc/systemd/system/wfmu-audio.service, then:
  sudo systemctl daemon-reload && sudo systemctl restart wfmu-audio.service
EOF
