#!/usr/bin/env python3
"""Create the v1.1.0 GitHub release and upload the release APK.

Reads the token from git config only; never prints it. Logs everything else.
"""
import json
import mimetypes
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request

REPO = "Alex07lol/TorrentLens"
TAG = "v1.1.0"
APK = "build/app/outputs/flutter-apk/app-release.apk"
LOG = "/tmp/release.log"


def log(msg):
    with open(LOG, "a") as f:
        f.write(msg + "\n")
    print(msg, flush=True)


def token():
    url = subprocess.run(
        ["git", "config", "--get", "remote.origin.url"],
        capture_output=True, text=True,
    ).stdout.strip()
    m = re.match(r"https://(?:[^/@]+:)?([^@]+)@github\.com/", url)
    if not m:
        raise SystemExit("no credential in remote url")
    return urllib.parse.unquote(m.group(1))


TOK = token()
API = "https://api.github.com"


def call(url, data=None, headers=None, method=None):
    h = {
        "Authorization": "Bearer " + TOK,
        "Accept": "application/vnd.github+json",
        "User-Agent": "torrentlens-release",
    }
    if headers:
        h.update(headers)
    body = None
    if data is not None and not isinstance(data, bytes):
        body = json.dumps(data).encode()
        h["Content-Type"] = "application/json"
    elif isinstance(data, bytes):
        body = data
    req = urllib.request.Request(url, data=body, headers=h, method=method)
    try:
        r = urllib.request.urlopen(req, timeout=120)
        return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.load(e)
        except Exception:
            return e.code, {"raw": e.read()[:500].decode(errors="replace")}


def main():
    log("== publishing release " + TAG)

    # 1. Release exists already?
    st, existing = call(f"{API}/repos/{REPO}/releases/tags/{TAG}")
    if st == 200:
        release_id = existing["id"]
        log(f"release already exists (id {release_id}), reusing")
    elif st == 404:
        st, rel = call(
            f"{API}/repos/{REPO}/releases",
            data={
                "tag_name": TAG,
                "name": "TorrentLens 1.1.0",
                "body": _release_notes(),
                "draft": False,
                "prerelease": False,
            },
        )
        if st not in (200, 201):
            log(f"create release FAILED: HTTP {st} {rel}")
            raise SystemExit(1)
        release_id = rel["id"]
        log(f"release created (id {release_id}) url={rel.get('html_url')}")
    else:
        log(f"tag lookup failed: HTTP {st} {existing}")
        raise SystemExit(1)

    # 2. Drop any stale asset with the same name (retry safety).
    st, assets = call(f"{API}/repos/{REPO}/releases/{release_id}/assets")
    for a in assets if st == 200 else []:
        if a["name"] == "torrentlens-1.1.0-release.apk":
            call(f"{API}/repos/{REPO}/releases/assets/{a['id']}", method="DELETE")
            log(f"deleted stale asset id {a['id']}")

    # 3. Upload the APK.
    size = __import__("os").path.getsize(APK)
    log(f"uploading APK ({size} bytes)")
    ctype = mimetypes.guess_type(APK)[0] or "application/vnd.android.package-archive"
    with open(APK, "rb") as f:
        data = f.read()
    url = (
        f"https://uploads.github.com/repos/{REPO}/releases/{release_id}/assets"
        f"?name=torrentlens-1.1.0-release.apk"
    )
    st, resp = call(
        url,
        data=data,
        headers={"Content-Type": ctype, "Content-Length": str(len(data))},
        method="POST",
    )
    if st not in (200, 201):
        log(f"asset upload FAILED: HTTP {st} {resp}")
        raise SystemExit(1)
    log(f"asset uploaded id={resp['id']} size={resp['size']} url={resp['browser_download_url']}")
    log("== done")


def _release_notes():
    return """\
**TorrentLens 1.1.0** — first release build, with a designed interface.

### Highlights
- Genuine libtorrent engine (native `libtorrent4j`), magnet and `.torrent` import
- Browser-style tab workspace hosting pages, readers, the player and torrents
- Play-while-downloading with seek-aware piece prioritisation
- EPUB / PDF / comic / text readers and a Media3 player with subtitles
- GitHub publisher subscriptions with signed-manifest trust status
- Optional publisher-owned cloud sync; local-first without any account

### Interface (new in 1.1.0)
- Hand-tuned Material 3 light & dark schemes on the TorrentLens teal identity
- IBM Plex Sans (SIL OFL 1.1) bundled, with tabular figures so live speeds
  and sizes don't jitter
- Redesigned transfer cards: progress line, tabular readouts, clearer actions
- Dashboard now shows live aggregate transfer totals

### Install
Download `torrentlens-1.1.0-release.apk` (arm64, minSdk 28) and sideload it.
The APK is signed with the debug keystore; a Play-ready signing setup is future work.

SHA-256 checksums are listed in the release assets table below once generated.
"""


if __name__ == "__main__":
    main()
