#!/usr/bin/env bash
set -euo pipefail

# Launch librespot as a Spotify Connect sink on the Pi.

if ! command -v librespot >/dev/null 2>&1; then
  echo "librespot is not installed. Install on the Pi first." >&2
  exit 1
fi

detect_usb_card() {
  awk '/USB/ { print $1; exit }' /proc/asound/cards 2>/dev/null
}

device="${LIBRESPOT_DEVICE:-auto}"
if [[ "$device" == "auto" ]]; then
  card="$(detect_usb_card || true)"
  if [[ -n "${card:-}" ]]; then
    device="hw:${card},0"
    echo "auto: using USB DAC on card ${card} (${device})" >&2
  else
    device="default"
    echo "auto: no USB card found; falling back to ALSA default" >&2
  fi
fi

name="${LIBRESPOT_NAME:-WFMU Pi}"
bitrate="${LIBRESPOT_BITRATE:-320}"
initial_volume="${LIBRESPOT_INITIAL_VOLUME:-100}"

# Credential cache lets the Pi log in to Spotify's servers directly (OAuth),
# so it appears in the app over the internet even on AP-isolated networks that
# block Spotify Connect's local zeroconf discovery. Populate it once with:
#   librespot --name "WFMU Pi" --cache <dir> --enable-oauth --oauth-port 0 ...
cache="${LIBRESPOT_CACHE:-$HOME/.cache/librespot}"
mkdir -p "$cache"

exec librespot \
  --name "$name" \
  --backend alsa \
  --device "$device" \
  --bitrate "$bitrate" \
  --initial-volume "$initial_volume" \
  --cache "$cache" \
  --disable-audio-cache
