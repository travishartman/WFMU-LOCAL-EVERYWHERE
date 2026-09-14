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
headphone_level="${HEADPHONE_LEVEL:-75%}"
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

# Ordered fallback stream list:
# 1. Requested stream (or key 1 default)
# 2. Main WFMU local relay
# 3. Direct WFMU upstream stream (if local icecast is down)
# 4. Give the Drummer local relay (wfmu2)
# 5. Direct Give the Drummer upstream stream
# 6. Rock'n'Soul local relay (wfmu3)
# 7. Direct Rock'n'Soul upstream stream
# 8. Sheena's Jungle Room local relay (wfmu4)
# 9. Direct Sheena upstream stream

FALLBACK_STREAMS="
http://localhost:8000/wfmu.mp3
http://stream0.wfmu.org/freeform-128k
http://localhost:8000/drummer.mp3
http://stream0.wfmu.org/drummer
http://localhost:8000/rocknsoul.mp3
http://stream0.wfmu.org/rocknsoul
http://localhost:8000/sheena.mp3
http://stream0.wfmu.org/sheena
"

build_stream_list() {
  local target="$1"
  printf '%s\n' "$target"
  for s in $FALLBACK_STREAMS; do
    if [ "$s" != "$target" ]; then
      printf '%s\n' "$s"
    fi
  done
}

# Run mpg123 with a retry-same-stream loop for transient hiccups.
# If a stream crashes within MIN_PLAY_SECONDS repeatedly (MAX_HICCUP_RETRIES times),
# it is considered dead and we rotate to the next fallback stream.
MIN_PLAY_SECONDS=15
MAX_HICCUP_RETRIES=3

play_stream_with_resilience() {
  local streams
  streams="$(build_stream_list "$stream_url")"

  while true; do
    while IFS= read -r current_url; do
      [ -z "$current_url" ] && continue
      local hiccup_count=0

      while [ "$hiccup_count" -lt "$MAX_HICCUP_RETRIES" ]; do
        echo "Playing stream: $current_url (attempt $((hiccup_count + 1))/$MAX_HICCUP_RETRIES)" >&2
        local start_time
        start_time="$(date +%s)"

        if [ "$alsa_device" = "default" ]; then
          mpg123 "$current_url" || true
        else
          mpg123 -a "$alsa_device" "$current_url" || true
        fi

        local end_time elapsed
        end_time="$(date +%s)"
        elapsed=$((end_time - start_time))

        if [ "$elapsed" -ge "$MIN_PLAY_SECONDS" ]; then
          # Stream ran stably for a while; treat this as a normal disconnect / transient glitch.
          # Reset hiccup count and retry the same stream immediately.
          echo "Stream ran for ${elapsed}s before disconnecting. Retrying same stream: $current_url" >&2
          hiccup_count=0
        else
          hiccup_count=$((hiccup_count + 1))
          echo "Stream dropped quickly (${elapsed}s < ${MIN_PLAY_SECONDS}s). Hiccup count: $hiccup_count/$MAX_HICCUP_RETRIES" >&2
        fi

        sleep 2
      done

      echo "Stream $current_url failed $MAX_HICCUP_RETRIES times consecutively. Falling back to next stream in chain..." >&2
    done <<EOF
$streams
EOF

    echo "All streams exhausted in fallback chain. Restarting chain from top..." >&2
    sleep 3
  done
}

play_stream_with_resilience