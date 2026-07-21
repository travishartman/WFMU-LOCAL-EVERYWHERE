"""Resolve a working WFMU live stream URL.

Transmission method (FM out, Bluetooth, line-out, etc.) is not decided yet —
this module only answers "what URL do I read the audio from."
"""

import urllib.request

PLAYLISTS = {
    "mp3": "http://wfmu.org/wfmu_mp3.pls",
    "aac": "http://wfmu.org/wfmu_aac.pls",
    "dialup": "http://wfmu.org/wfmu32.pls",
    "drummer": "http://wfmu.org/wfmu_drummer.pls",
}


def _parse_pls(text):
    urls = []
    for line in text.splitlines():
        if line.startswith("File") and "=" in line:
            urls.append(line.split("=", 1)[1].strip())
    return urls


def candidate_urls(stream="mp3"):
    """Fetch the .pls for `stream` and return its listed mountpoints, in order."""
    with urllib.request.urlopen(PLAYLISTS[stream], timeout=8) as resp:
        return _parse_pls(resp.read().decode())


def find_working_stream(stream="mp3", timeout=8):
    """Return the first mountpoint that responds with audio, or None."""
    for url in candidate_urls(stream):
        req = urllib.request.Request(url, headers={"User-Agent": "VLC/3.0"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                if resp.status == 200:
                    return url
        except Exception:
            continue
    return None


if __name__ == "__main__":
    for name in PLAYLISTS:
        url = find_working_stream(name)
        print(f"{name}: {url or 'unreachable'}")
