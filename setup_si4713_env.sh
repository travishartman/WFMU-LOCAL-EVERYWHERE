#!/bin/sh
set -eu

# Prepare the Raspberry Pi OS environment for the SI4713 control script.
# Run this on the Pi from the repo root or any subdirectory.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR"

APT_PACKAGES="python3-venv i2c-tools libgpiod-dev python3-libgpiod python3-rpi.gpio python3-lgpio mpg123"

echo "Installing Raspberry Pi OS dependencies..."
sudo apt-get update
sudo apt-get install -y $APT_PACKAGES

echo "Recreating project virtualenv..."
rm -rf .venv
python3 -m venv .venv --system-site-packages

echo "Installing Python packages into the virtualenv..."
. .venv/bin/activate
pip install --upgrade pip
pip install adafruit-blinka adafruit-circuitpython-si4713

echo
echo "Setup complete. Next checks:"
echo "  1. Enable I2C in /boot/firmware/config.txt if needed: dtparam=i2c_arm=on"
echo "  2. Reboot after enabling I2C"
echo "  3. Verify the control script: .venv/bin/python si4713_control.py --help"
echo "  4. Verify the DAC: aplay -l"
echo "  5. Play audio explicitly to the current USB DAC: ./play_usb_dac.sh http://localhost:8000/wfmu.mp3 hw:1,0"