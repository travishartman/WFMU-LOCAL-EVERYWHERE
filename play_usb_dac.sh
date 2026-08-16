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

# The USB DAC's "Headphone" control resets to ~30 (near-silent) and alsactl
# doesn't reliably restore it on boot, so set it here every time audio starts.
# Level is overridable: HEADPHONE_LEVEL=90% ./play_usb_dac.sh ...
headphone_level="${HEADPHONE_LEVEL:-100%}"
case "$alsa_device" in
  hw:*)
    card="$(printf '%s' "$alsa_device" | sed 's/^hw:\([0-9][0-9]*\).*/\1/')"
    if command -v amixer >/dev/null 2>&1; then
      amixer -c "$card" -- sset Headphone "$headphone_level" >/dev/null 2>&1 \
        || echo "warning: could not set Headphone level on card $card" >&2
    fi
    ;;
esac

if [ "$alsa_device" = "default" ]; then
  exec mpg123 "$stream_url"
fi

exec mpg123 -a "$alsa_device" "$stream_url"