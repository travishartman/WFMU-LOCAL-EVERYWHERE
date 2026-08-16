#!/usr/bin/env bash
# Rebuild a fresh Raspberry Pi OS install into a working WFMU transmitter.
# Run this ON THE PI, from inside the cloned repo:
#   cd ~/WFMU-LOCAL-EVERYWHERE/recovery && ./rebuild_from_scratch.sh
#
# It reuses the repo's existing setup scripts so there's a single source of truth:
#   - enables the I2C bus
#   - installs apt deps + the Python venv        (../setup_si4713_env.sh)
#   - installs + enables the autostart services  (../install_autostart.sh)
#   - hardens the journal to RAM (SD-card protection)
#
# NOT handled here: the Icecast relay that serves http://localhost:8000/wfmu.mp3.
# Set that up per now.md — the audio service depends on it.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

echo "== 1/4  Enabling I2C bus =="
CONFIG=/boot/firmware/config.txt
[ -f "$CONFIG" ] || CONFIG=/boot/config.txt   # older layout fallback
if grep -q '^dtparam=i2c_arm=on' "$CONFIG" 2>/dev/null; then
  echo "I2C already enabled in $CONFIG"
elif grep -q 'dtparam=i2c_arm' "$CONFIG" 2>/dev/null; then
  sudo sed -i 's/^#\?dtparam=i2c_arm=.*/dtparam=i2c_arm=on/' "$CONFIG"
  echo "Enabled I2C in $CONFIG (reboot needed)."
else
  echo 'dtparam=i2c_arm=on' | sudo tee -a "$CONFIG" >/dev/null
  echo "Appended dtparam=i2c_arm=on to $CONFIG (reboot needed)."
fi

echo "== 2/4  Installing deps + Python venv =="
( cd "$REPO" && ./setup_si4713_env.sh )

echo "== 3/4  Installing + enabling autostart services =="
( cd "$REPO" && chmod +x install_autostart.sh && ./install_autostart.sh )

echo "== 4/4  Hardening journal to RAM (SD-card protection) =="
if [ -f /etc/systemd/journald.conf ]; then
  sudo sed -i 's/^#\?Storage=.*/Storage=volatile/' /etc/systemd/journald.conf
  sudo systemctl restart systemd-journald || true
  echo "journald Storage=volatile"
fi

cat <<'EOF'

Rebuild complete.

Remaining manual step:
  - Set up the Icecast relay (http://localhost:8000/wfmu.mp3) per now.md, then
    ensure the DAC "Headphone" level is up (play_usb_dac.sh now sets it to 100%).

Finish:
  sudo reboot
After reboot it should come up broadcasting on 91.1 hands-off. Verify:
  systemctl status si4713.service wfmu-audio.service
  journalctl -u si4713.service -b
EOF
