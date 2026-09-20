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

for unit in si4713.service wfmu-audio.service librespot-wfmu.service; do
  if [ ! -f "$SRC/$unit" ]; then
    echo "Error: $SRC/$unit not found — did you git pull?" >&2
    exit 1
  fi
done

echo "Installing unit files to /etc/systemd/system ..."
sudo install -m 0644 "$SRC/si4713.service" /etc/systemd/system/si4713.service
sudo install -m 0644 "$SRC/wfmu-audio.service" /etc/systemd/system/wfmu-audio.service
sudo install -m 0644 "$SRC/librespot-wfmu.service" /etc/systemd/system/librespot-wfmu.service

echo "Installing helper scripts ..."
sudo install -m 0755 "$HERE/switch_source.sh" /usr/local/bin/wfmu-switch-source
sudo install -m 0755 "$HERE/radio_hotkeys.sh" /usr/local/bin/wfmu-radio-hotkeys
sudo install -m 0755 "$HERE/start_librespot.sh" /usr/local/bin/wfmu-start-librespot
sudo install -m 0755 "$HERE/now_playing.py" /usr/local/bin/wfmu-nowplaying
sudo install -m 0755 "$HERE/librespot_event.sh" /usr/local/bin/wfmu-librespot-event
sudo install -m 0755 "$HERE/wfmu-status.sh" /usr/local/bin/wfmu-status

# Passwordless sudo for the switch helper so the login hotkeys can change streams
# without a password prompt interrupting the key loop.
echo "Installing sudoers rule for passwordless stream switching ..."
TARGET_USER="${SUDO_USER:-$(id -un)}"
sudo tee /etc/sudoers.d/wfmu-switch >/dev/null <<EOF
$TARGET_USER ALL=(root) NOPASSWD: /usr/local/bin/wfmu-switch-source
EOF
sudo chmod 0440 /etc/sudoers.d/wfmu-switch
if ! sudo visudo -cf /etc/sudoers.d/wfmu-switch >/dev/null 2>&1; then
  echo "WARNING: sudoers syntax check failed; removing the rule." >&2
  sudo rm -f /etc/sudoers.d/wfmu-switch
fi

# Short global commands: wfmu1..wfmu5 -> wfmu-switch-source 1..5
echo "Installing wfmu1..wfmu5 shortcut commands ..."
for n in 1 2 3 4 5; do
  printf '#!/bin/sh\nexec wfmu-switch-source %s "$@"\n' "$n" \
    | sudo tee "/usr/local/bin/wfmu$n" >/dev/null
  sudo chmod 0755 "/usr/local/bin/wfmu$n"
done

echo "Seeding runtime config files (preserving existing local edits) ..."
if [ ! -f /etc/default/wfmu-audio ]; then
  echo "STREAM_URL=http://localhost:8000/wfmu.mp3" | sudo tee /etc/default/wfmu-audio >/dev/null
fi
if [ ! -f /etc/default/wfmu-sources ]; then
  sudo install -m 0644 "$HERE/wfmu-sources.conf.example" /etc/default/wfmu-sources
fi
if [ ! -f /etc/default/librespot-wfmu ]; then
  sudo tee /etc/default/librespot-wfmu >/dev/null <<'EOF'
LIBRESPOT_NAME="WFMU Pi"
LIBRESPOT_DEVICE=auto
LIBRESPOT_BITRATE=320
LIBRESPOT_INITIAL_VOLUME=100
EOF
fi

echo "Reloading systemd and enabling services on boot ..."
sudo systemctl daemon-reload
sudo systemctl enable si4713.service wfmu-audio.service
sudo systemctl disable librespot-wfmu.service >/dev/null 2>&1 || true

# Persist the DAC Headphone volume (must be ~100) so audio survives reboots.
if command -v alsactl >/dev/null 2>&1; then
  echo "Saving current ALSA mixer levels (alsactl store) ..."
  sudo alsactl store || true
fi

# Login experience: drop interactive logins straight into the WFMU hotkey
# environment, which shows the banner (dog & cow logo + on-air status), the
# current now-playing (updating every 30s), and reads keys 1-5 to switch streams
# (q to quit to a normal shell). Set WFMU_NO_HOTKEYS=1 to bypass.
#
# The old MOTD/banner-only path is removed so the banner isn't printed twice.
echo "Installing login hotkey environment ..."
sudo rm -f /etc/update-motd.d/99-wfmu

TARGET_USER="${SUDO_USER:-$(id -un)}"
TARGET_HOME="$(eval echo "~$TARGET_USER")"
BASHRC="$TARGET_HOME/.bashrc"

# Remove the previous banner-only snippet if present (migration).
if [ -f "$BASHRC" ] && grep -qF "# >>> wfmu status banner >>>" "$BASHRC"; then
  sudo sed -i '/# >>> wfmu status banner >>>/,/# <<< wfmu status banner <<</d' "$BASHRC"
fi

MARKER="# >>> wfmu hotkeys >>>"
if ! grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
  sudo tee -a "$BASHRC" >/dev/null <<'EOF'

# >>> wfmu hotkeys >>>
# Launch the WFMU hotkey environment on interactive login (q to quit to a shell).
case $- in
  *i*)
    if [ -t 0 ] && [ -t 1 ] && [ -z "${WFMU_NO_HOTKEYS:-}" ] && command -v wfmu-radio-hotkeys >/dev/null 2>&1; then
      wfmu-radio-hotkeys
    fi
    ;;
esac
# <<< wfmu hotkeys <<<
EOF
  sudo chown "$TARGET_USER":"$TARGET_USER" "$BASHRC" 2>/dev/null || true
  echo "Added hotkey auto-launch to $BASHRC."
else
  echo "Hotkey auto-launch already present in $BASHRC."
fi

cat <<'EOF'

Done. The radio comes up on 91.1 MHz automatically after every reboot, and
interactive logins drop into the WFMU hotkey environment:
  banner (dog & cow logo + on-air status)
  now playing (updates every 30s)
  keys: 1=live 2=drummer 3=rocknsoul 4=sheena 5=spotify | n=now playing s=status q=quit

Bypass the hotkeys for one session with:  WFMU_NO_HOTKEYS=1 bash

Run the pieces by hand any time:
  wfmu-status         # banner only
  wfmu-nowplaying     # current track once
  wfmu-radio-hotkeys  # the full hotkey environment
EOF
