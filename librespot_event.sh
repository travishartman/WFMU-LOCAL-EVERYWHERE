#!/bin/sh
# librespot --onevent hook: capture Spotify track metadata for now_playing.py.
#
# librespot runs this program on player events and passes data via environment
# variables. The exact set depends on the librespot build; commonly available
# on a track change are: PLAYER_EVENT, TRACK_ID, NAME, ARTISTS, ALBUM.
# ARTISTS may be newline- or comma-separated when a track has multiple artists.
#
# We only act on events that carry track identity, and write a small JSON state
# file that now_playing.py reads. Missing fields are written as empty strings.
set -eu

STATE_DIR=/run/wfmu
STATE_FILE="$STATE_DIR/nowplaying.json"

case "${PLAYER_EVENT:-}" in
  track_changed|playing|started|changed|preloading) : ;;
  *) exit 0 ;;
esac

mkdir -p "$STATE_DIR"

# Collapse multi-artist newlines into ", " and strip surrounding whitespace.
artist=$(printf '%s' "${ARTISTS:-}" | tr '\n' ',' | sed -e 's/,\{1,\}/, /g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/, *$//')
album=$(printf '%s' "${ALBUM:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
song=$(printf '%s' "${NAME:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

# JSON-escape backslashes and double quotes in each field.
esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

tmp="$STATE_FILE.tmp"
cat >"$tmp" <<EOF
{
  "event": "$(esc "${PLAYER_EVENT:-}")",
  "track_id": "$(esc "${TRACK_ID:-}")",
  "artist": "$(esc "$artist")",
  "album": "$(esc "$album")",
  "song": "$(esc "$song")"
}
EOF
mv -f "$tmp" "$STATE_FILE"
