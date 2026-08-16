#!/bin/sh
set -eu

# Usage: ./play_usb_dac.sh [stream_url] [alsa_device]
#
#   alsa_device:
#     auto        (default) - find the USB DAC by name, use hw:<card>,0
#     hw:N,0                 - force a specific ALSA device
#     default               - use the ALSA default sink (no explicit device)
#
# Auto-detect is preferred: USB audio cards can shuffle index on boot, so
# pinning to "hw:1" is fragile. "auto" locates the card by name instead.

stream_url="${1:-http://localhost:8000/wfmu.mp3}"
alsa_device="${2:-${ALSA_DEVICE:-auto}}"

if ! command -v mpg123 >/dev/null 2>&1; then
  echo "mpg123 is required. Install it with: sudo apt-get install mpg123" >&2
  exit 1
fi

# Find the USB DAC's ALSA card index by name. /proc/asound/cards lists lines like
#   1 [Audio          ]: USB-Audio - KT USB Audio
# Pick the first card whose description mentions USB (skips vc4hdmi/bcm2835).
detect_usb_card() {
  awk '/USB/ { print $1; exit }' /proc/asound/cards 2>/dev/null
}

if [ "$alsa_device" = "auto" ]; then
  card="$(detect_usb_card || true)"
  if [ -z "${card:-}" ]; then
    echo "auto: no USB audio card found; falling back to ALSA default" >&2
    alsa_device="default"
  else
    alsa_device="hw:${card},0"
    echo "auto: using USB DAC on card ${card} (${alsa_device})" >&2
  fi
fi

# The USB DAC's volume control resets low (~30 = near-silent) and alsactl doesn't
# reliably restore it on boot, so set it here every time audio starts.
# Level is overridable: HEADPHONE_LEVEL=90% ./play_usb_dac.sh ...
headphone_level="${HEADPHONE_LEVEL:-100%}"
case "$alsa_device" in
  hw:*)
    card="$(printf '%s' "$alsa_device" | sed 's/^hw:\([0-9][0-9]*\).*/\1/')"
    if command -v amixer >/dev/null 2>&1; then
      # Prefer the DAC's "Headphone" control; if a different DAC is swapped in,
      # fall back to the first mixer control it exposes.
      if ! amixer -c "$card" -- sset Headphone "$headphone_level" >/dev/null 2>&1; then
        first_ctl="$(amixer -c "$card" scontrols 2>/dev/null \
          | sed -n "s/.*'\\([^']*\\)'.*/\\1/p" | head -n 1)"
        if [ -n "${first_ctl:-}" ]; then
          amixer -c "$card" -- sset "$first_ctl" "$headphone_level" >/dev/null 2>&1 \
            || echo "warning: could not set volume on card $card" >&2
        else
          echo "warning: no mixer control found on card $card" >&2
        fi
      fi
    fi
    ;;
esac

if [ "$alsa_device" = "default" ]; then
  exec mpg123 "$stream_url"
fi

exec mpg123 -a "$alsa_device" "$stream_url"