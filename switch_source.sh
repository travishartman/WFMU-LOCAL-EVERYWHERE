#!/usr/bin/env bash
set -euo pipefail

# Switch playback source by key number while preserving boot defaults.
#
# Keys:
#   1 -> WFMU live (main)
#   2 -> Rock'n'Soul Radio
#   3 -> Give the Drummer Radio
#   4 -> Sheena's Jungle Room
#   5 -> Spotify (librespot-wfmu.service)

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

key="${1:-}"
if [[ -z "$key" ]]; then
  echo "Usage: $0 <1|2|3|4|5|status>" >&2
  exit 1
fi

AUDIO_ENV="/etc/default/wfmu-audio"
SOURCE_ENV="/etc/default/wfmu-sources"
SPOTIFY_ENV="/etc/default/librespot-wfmu"

# Keep defaults consistent with current architecture: localhost relay mounts.
KEY1_URL="http://localhost:8000/wfmu.mp3"
KEY2_URL="http://localhost:8000/rocknsoul.mp3"
KEY3_URL="http://localhost:8000/drummer.mp3"
KEY4_URL="http://localhost:8000/sheena.mp3"

SPOTIFY_SERVICE="librespot-wfmu.service"

if [[ -r "$SOURCE_ENV" ]]; then
  # shellcheck disable=SC1090
  . "$SOURCE_ENV"
fi

if [[ -r "$SPOTIFY_ENV" ]]; then
  # shellcheck disable=SC1090
  . "$SPOTIFY_ENV"
fi

write_audio_env() {
  local stream_url="$1"
  umask 022
  cat >"$AUDIO_ENV" <<EOF
STREAM_URL=$stream_url
EOF
}

preflight_local_mount() {
  local stream_url="$1"
  if [[ "$stream_url" == http://localhost:* || "$stream_url" == http://127.0.0.1:* ]]; then
    curl -fsS --max-time 5 -I "$stream_url" >/dev/null
  fi
}

switch_to_stream() {
  local label="$1"
  local stream_url="$2"

  echo "Selecting: $label"
  if ! preflight_local_mount "$stream_url"; then
    echo "ERROR: stream preflight failed for $stream_url" >&2
    if [[ "$stream_url" != "$KEY1_URL" ]]; then
      echo "Falling back to WFMU live." >&2
      write_audio_env "$KEY1_URL"
      systemctl restart wfmu-audio.service || true
    fi
    exit 1
  fi

  systemctl stop "$SPOTIFY_SERVICE" >/dev/null 2>&1 || true
  write_audio_env "$stream_url"
  systemctl restart wfmu-audio.service

  if ! systemctl is-active --quiet wfmu-audio.service; then
    echo "ERROR: wfmu-audio.service did not become active." >&2
    write_audio_env "$KEY1_URL"
    systemctl restart wfmu-audio.service || true
    exit 1
  fi

  echo "Active stream URL: $stream_url"
  echo "Done: $label"
}

switch_to_spotify() {
  echo "Selecting: Spotify"
  systemctl stop wfmu-audio.service || true
  systemctl start "$SPOTIFY_SERVICE"

  if ! systemctl is-active --quiet "$SPOTIFY_SERVICE"; then
    echo "ERROR: $SPOTIFY_SERVICE did not become active; returning to WFMU live." >&2
    write_audio_env "$KEY1_URL"
    systemctl restart wfmu-audio.service || true
    exit 1
  fi

  echo "Done: Spotify (connect from Spotify app to device name in librespot config)"
}

show_status() {
  local audio_state spotify_state url
  audio_state="$(systemctl is-active wfmu-audio.service 2>/dev/null || echo unknown)"
  spotify_state="$(systemctl is-active "$SPOTIFY_SERVICE" 2>/dev/null || echo unknown)"
  url="$(sed -n 's/^STREAM_URL=//p' "$AUDIO_ENV" 2>/dev/null || true)"
  [[ -z "$url" ]] && url="$KEY1_URL"

  echo "wfmu-audio.service: $audio_state"
  echo "$SPOTIFY_SERVICE: $spotify_state"
  echo "configured stream URL: $url"
}

case "$key" in
  1) switch_to_stream "WFMU live" "$KEY1_URL" ;;
  2) switch_to_stream "Rock'n'Soul Radio" "$KEY2_URL" ;;
  3) switch_to_stream "Give the Drummer Radio" "$KEY3_URL" ;;
  4) switch_to_stream "Sheena's Jungle Room" "$KEY4_URL" ;;
  5) switch_to_spotify ;;
  status|s|S) show_status ;;
  *)
    echo "Invalid key: $key (expected 1,2,3,4,5,status)" >&2
    exit 1
    ;;
esac
