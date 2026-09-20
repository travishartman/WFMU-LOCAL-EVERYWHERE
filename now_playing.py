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
import html
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

# Local relay mount filename -> (human name, WFMU upstream URL, radiorethink code).
# The radiorethink station code drives the show/DJ lookup that WFMU's popup
# player uses (station codes discovered from the WFMU site).
STREAMS = {
    "wfmu.mp3": ("WFMU Live", "http://stream0.wfmu.org/freeform-128k", "wfmu"),
    "drummer.mp3": ("Give the Drummer Radio", "http://stream0.wfmu.org/drummer", "wfmugtd"),
    "rocknsoul.mp3": ("Rock'n'Soul Radio", "http://stream0.wfmu.org/rocknsoul", "wfmurnsi"),
    "sheena.mp3": ("Sheena's Jungle Room Radio", "http://stream0.wfmu.org/sheena", "wfmusjr"),
}

# radiorethink schedule endpoint that the WFMU popup player reads for show/DJ.
SCHEDULE_URL = ("https://www.radiorethink.com/tuner/queries/"
                "getScheduleDataOutput.cfm?stationCode={}&testTime=0&randval=1")
_H6_RE = re.compile(r"<h6>(.*?)</h6>", re.S)
_STRONG_RE = re.compile(r"<strong>(.*?)</strong>", re.S)
_WITH_RE = re.compile(r"with(.*?)<br>", re.S)

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


def _strip_tags(s):
    return html.unescape(re.sub(r"<[^>]+>", " ", s)).strip()


def _fetch_show_meta(code, timeout=6):
    """Return (dj, show, desc, sched) for a station from radiorethink."""
    req = urllib.request.Request(
        SCHEDULE_URL.format(code), headers={"User-Agent": "Mozilla/5.0"})
    text = urllib.request.urlopen(req, timeout=timeout).read().decode("utf-8", "replace")
    m = _H6_RE.search(text)
    block = m.group(1) if m else ""
    sm = _STRONG_RE.search(block)
    show = _strip_tags(sm.group(1)) if sm else ""
    dm = _WITH_RE.search(block)
    dj = _strip_tags(dm.group(1)) if dm else ""
    parts = [p for p in (_strip_tags(x) for x in re.split(r"<br\s*/?>", block)) if p]
    desc = parts[1] if len(parts) >= 2 else ""
    sched = ""
    if len(parts) >= 3:
        tm = re.search(r"\(([^)]*ET[^)]*)\)", parts[2])
        sched = (tm.group(1) if tm else parts[2]).strip()
    return dj, show, desc, sched


def _compose_show(dj, show):
    """Format the show line as '<DJ> on <SHOW>', degrading if a part is missing."""
    if dj and show:
        return "{} on {}".format(dj, show)
    return show or dj or DASH


def _stream_info(stream_url):
    mount = _mount_of(stream_url)
    name, upstream, code = STREAMS.get(mount, (mount, None, None))
    info = {"source": "stream", "stream": name, "show": DASH,
            "desc": DASH, "sched": DASH,
            "artist": DASH, "album": DASH, "song": DASH}
    if upstream:
        try:
            artist, icy_show, song = _parse_title(_read_icy_streamtitle(upstream))
            info["artist"], info["song"] = artist, song
            info["show"] = icy_show          # fallback if radiorethink is unreachable
        except Exception:
            pass
    if code:
        try:
            dj, show, desc, sched = _fetch_show_meta(code)
            composed = _compose_show(dj, show)
            if composed != DASH:
                info["show"] = composed
            if desc:
                info["desc"] = desc
            if sched:
                info["sched"] = sched
        except Exception:
            pass
    return info


def _spotify_info():
    info = {"source": "spotify", "stream": "Spotify (WFMU Pi)", "show": DASH,
            "desc": DASH, "sched": DASH,
            "artist": DASH, "album": DASH, "song": DASH}
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


def _show_signature(info):
    return "|".join(info.get(k, "") for k in
                    ("source", "stream", "show", "desc", "sched"))


def _track_signature(info):
    return "|".join(info.get(k, "") for k in ("artist", "album", "song"))


def _track_lines(info):
    artist = info.get("artist", DASH)
    album = info.get("album", DASH)
    song = info.get("song", DASH)
    lines = []
    if artist and artist != DASH:
        lines.append('"{}" by {}'.format(song, artist))
    elif song and song != DASH:
        lines.append('"{}"'.format(song))
    else:
        lines.append("(no track info)")
    if album and album != DASH:
        lines.append("Album: {}".format(album))
    return lines


def format_full(info):
    """Show header + description + schedule time, then the track."""
    lines = []
    show = info.get("show", DASH)
    if show and show != DASH:
        lines.append("*{}*".format(show))
    desc = info.get("desc", DASH)
    if desc and desc != DASH:
        lines.append(desc)
    sched = info.get("sched", DASH)
    if sched and sched != DASH:
        lines.append("({})".format(sched.strip("()").strip()))
    lines.append("NOW PLAYING:")
    lines.extend(_track_lines(info))
    return "\n".join(lines)


def format_track(info):
    """Only the track (used when the song/album changes but the show did not)."""
    return "\n".join(["NOW PLAYING:"] + _track_lines(info))


# format_info stays as the full view for --once and print-on-switch callers.
format_info = format_full


def watch(interval):
    last_show = None
    last_track = None
    while True:
        info = current_info()
        show_sig = _show_signature(info)
        track_sig = _track_signature(info)
        if show_sig != last_show:
            print(format_full(info), flush=True)
            last_show, last_track = show_sig, track_sig
        elif track_sig != last_track:
            print(format_track(info), flush=True)
            last_track = track_sig
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
