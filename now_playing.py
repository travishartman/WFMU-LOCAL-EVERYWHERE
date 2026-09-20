#!/usr/bin/env python3
"""Print now-playing metadata for the current WFMU FM source.

Where metadata comes from:
  * Streams (keys 1-4): the LOCAL Icecast relay does not forward WFMU's ICY
    StreamTitle (it comes through empty), so we read the ICY inline metadata
    straight from the matching WFMU UPSTREAM stream instead. WFMU sends two
    title formats:
        '"Song" by Artist on Album on WFMU'   (freeform + Rock'n'Soul)
        'Artist - Song'                        (automated sister streams)
  * Spotify / librespot (key 5): metadata comes from a small state file that
    the librespot --onevent hook writes on every track change
    (see librespot_event.sh).

Modes:
  --once   Print the current metadata one time (used on load and on switch).
  --watch  Poll every INTERVAL seconds; print only when the info changes.

Fields printed: stream name, show, artist, album, song. Fields a given source
does not expose are shown as "-".
"""

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.request

AUDIO_ENV = "/etc/default/wfmu-audio"
SPOTIFY_SERVICE = "librespot-wfmu.service"
SPOTIFY_STATE = "/run/wfmu/nowplaying.json"
INTERVAL_SECONDS = 30
DASH = "-"

# Local relay mount filename -> (human name, WFMU upstream URL for metadata).
STREAMS = {
    "wfmu.mp3": ("WFMU Live", "http://stream0.wfmu.org/freeform-128k"),
    "drummer.mp3": ("Give the Drummer Radio", "http://stream0.wfmu.org/drummer"),
    "rocknsoul.mp3": ("Rock'n'Soul Radio", "http://stream0.wfmu.org/rocknsoul"),
    "sheena.mp3": ("Sheena's Jungle Room Radio", "http://stream0.wfmu.org/sheena"),
}

# '"Song" by Artist on Show on WFMU'  (trailing ' on WFMU' is stripped first)
_FREEFORM_RE = re.compile(r'^"(?P<song>.*)" by (?P<artist>.*?) on (?P<show>.*)$')


def _service_active(service):
    try:
        out = subprocess.run(
            ["systemctl", "is-active", service],
            capture_output=True, text=True, timeout=5,
        )
        return out.stdout.strip() == "active"
    except Exception:
        return False


def _current_stream_url():
    url = "http://localhost:8000/wfmu.mp3"
    try:
        with open(AUDIO_ENV) as f:
            for line in f:
                line = line.strip()
                if line.startswith("STREAM_URL="):
                    val = line.split("=", 1)[1].strip().strip('"').strip("'")
                    if val:
                        url = val
    except OSError:
        pass
    return url


def _mount_of(url):
    return url.rstrip("/").split("/")[-1]


def _read_icy_streamtitle(url, timeout=8, max_blocks=5):
    """Open a stream with ICY metadata enabled and return its StreamTitle.

    Icecast sends a metadata block every icy-metaint bytes, but most blocks are
    empty (length 0) between title changes. Scan up to max_blocks looking for
    the first non-empty StreamTitle so a listener connecting mid-track still
    gets the current title.
    """
    req = urllib.request.Request(
        url, headers={"Icy-MetaData": "1", "User-Agent": "VLC/3.0"})
    resp = urllib.request.urlopen(req, timeout=timeout)
    metaint = resp.headers.get("icy-metaint")
    if not metaint:
        return ""
    metaint = int(metaint)
    for _ in range(max_blocks):
        resp.read(metaint)                  # skip one audio block
        length_byte = resp.read(1)
        if not length_byte:
            break
        length = length_byte[0] * 16
        if not length:
            continue                        # empty metadata block, try next
        block = resp.read(length).decode("utf-8", "replace").strip("\x00")
        m = re.search(r"StreamTitle='(.*?)';", block)
        if m and m.group(1).strip():
            return m.group(1).strip()
    return ""


def _parse_title(title):
    """Parse a WFMU StreamTitle into (artist, show, song).

    The 'on X' field in WFMU's freeform format is the show/context line; album
    is not carried in the ICY title, so it stays empty for streams.
    """
    if not title:
        return DASH, DASH, DASH
    title = title.strip()

    # Freeform format: "Song" by Artist on Show on WFMU
    if title.startswith('"') and " by " in title:
        core = title
        if core.endswith(" on WFMU"):
            core = core[: -len(" on WFMU")]
        m = _FREEFORM_RE.match(core)
        if m:
            song = m.group("song").strip() or DASH
            artist = m.group("artist").strip() or DASH
            show = m.group("show").strip() or DASH
            return artist, show, song

    # Automated sister-stream format: Artist - Song (no show)
    if " - " in title:
        artist, song = title.split(" - ", 1)
        song = re.sub(r"^-+\s*", "", song.strip()) or song.strip()
        return artist.strip() or DASH, DASH, song or DASH

    # Unknown shape: keep the whole thing as the song.
    return DASH, DASH, title


def _stream_info(stream_url):
    mount = _mount_of(stream_url)
    name, upstream = STREAMS.get(mount, (mount, None))
    info = {"source": "stream", "stream": name,
            "show": DASH, "artist": DASH, "album": DASH, "song": DASH}
    if upstream:
        try:
            artist, show, song = _parse_title(_read_icy_streamtitle(upstream))
            info["artist"], info["show"], info["song"] = artist, show, song
        except Exception:
            pass
    return info


def _spotify_info():
    info = {"source": "spotify", "stream": "Spotify (WFMU Pi)",
            "show": DASH, "artist": DASH, "album": DASH, "song": DASH}
    try:
        with open(SPOTIFY_STATE) as f:
            data = json.load(f)
        info["artist"] = data.get("artist") or DASH
        info["album"] = data.get("album") or DASH
        info["song"] = data.get("song") or DASH
    except Exception:
        pass
    return info


def current_info():
    if _service_active(SPOTIFY_SERVICE):
        return _spotify_info()
    return _stream_info(_current_stream_url())


def _signature(info):
    return "|".join(info.get(k, "") for k in
                    ("source", "stream", "show", "artist", "album", "song"))


def format_info(info):
    show = info.get("show", DASH)
    artist = info.get("artist", DASH)
    album = info.get("album", DASH)
    song = info.get("song", DASH)

    lines = []
    if show and show != DASH:
        lines.append("*{}*".format(show))
    lines.append("NOW PLAYING:")
    if artist and artist != DASH:
        lines.append('"{}" by {}'.format(song, artist))
    elif song and song != DASH:
        lines.append('"{}"'.format(song))
    else:
        lines.append("(no track info)")
    if album and album != DASH:
        lines.append("Album: {}".format(album))
    return "\n".join(lines)


def watch(interval):
    last = None
    while True:
        info = current_info()
        sig = _signature(info)
        if sig != last:
            print(format_info(info), flush=True)
            last = sig
        time.sleep(interval)


def main(argv=None):
    parser = argparse.ArgumentParser(description="WFMU now-playing metadata")
    parser.add_argument("--once", action="store_true",
                        help="print current metadata once (default)")
    parser.add_argument("--watch", action="store_true",
                        help="poll every %d s, print only on change" % INTERVAL_SECONDS)
    parser.add_argument("--interval", type=int, default=INTERVAL_SECONDS,
                        help="watch interval in seconds")
    args = parser.parse_args(argv)

    if args.watch:
        try:
            watch(args.interval)
        except KeyboardInterrupt:
            return 0
    else:
        print(format_info(current_info()), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
