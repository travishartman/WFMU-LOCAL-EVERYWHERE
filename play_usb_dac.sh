#!/bin/sh
set -eu

# Usage: ./play_usb_dac.sh [stream_url] [alsa_device]
# If ALSA is already configured to send audio to the USB DAC, leave the second
# argument unset and mpg123 will use the default output device.

stream_url="${1:-http://localhost:8000/wfmu.mp3}"
alsa_device="${2:-${ALSA_DEVICE:-default}}"

if ! command -v mpg123 >/dev/null 2>&1; then
  echo "mpg123 is required. Install it with: sudo apt-get install mpg123" >&2
  exit 1
fi

if [ "$alsa_device" = "default" ]; then
  exec mpg123 "$stream_url"
fi

exec mpg123 -a "$alsa_device" "$stream_url"