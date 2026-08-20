#!/usr/bin/env bash
# HTTP contract for the Night Walker download page.
# Serves docs/ and asserts the public page + DMG, not source greps of the app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SITE="$ROOT/docs"
INDEX="$SITE/index.html"
DMG="$SITE/NightWalker.dmg"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ -f "$INDEX" ] || fail "docs/index.html missing"
[ -f "$DMG" ] || fail "docs/NightWalker.dmg missing"
[ -f "$SITE/.nojekyll" ] || fail "docs/.nojekyll missing"

DMG_SIZE="$(wc -c < "$DMG" | tr -d ' ')"
[ "$DMG_SIZE" -gt 100000 ] || fail "NightWalker.dmg is too small ($DMG_SIZE bytes)"

python3 - "$DMG" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = path.read_bytes()
if len(data) < 512:
    sys.exit("NightWalker.dmg is too small to be a UDIF image")
if data[-512:-508] != b"koly":
    sys.exit("NightWalker.dmg is missing the UDIF koly trailer")
print("ok: NightWalker.dmg is a UDIF disk image")
PY

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$SITE" >/dev/null 2>&1 &
SERVER_PID=$!
cleanup() {
    kill "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

python3 - "$PORT" "$DMG_SIZE" <<'PY'
import sys
import urllib.error
import urllib.request
from html.parser import HTMLParser

port = sys.argv[1]
expected_dmg_size = int(sys.argv[2])
base = f"http://127.0.0.1:{port}"


def fetch(path):
    url = base + path
    for attempt in range(20):
        try:
            with urllib.request.urlopen(url, timeout=2) as res:
                return res.status, res.headers, res.read()
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            import time
            time.sleep(0.05)
    sys.exit(f"could not fetch {url}")


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.title = []
        self.h1 = []
        self.links = []
        self.text = []
        self._capture = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "a" and "href" in attrs:
            self.links.append(attrs["href"])
        if tag in ("title", "h1"):
            self._capture = tag

    def handle_endtag(self, tag):
        if tag == self._capture:
            self._capture = None

    def handle_data(self, data):
        self.text.append(data)
        if self._capture == "title":
            self.title.append(data)
        if self._capture == "h1":
            self.h1.append(data)


status, headers, body = fetch("/")
if status != 200:
    sys.exit(f"GET / returned {status}")
ctype = headers.get("Content-Type", "")
if "text/html" not in ctype:
    sys.exit(f"GET / Content-Type was {ctype!r}, expected text/html")

html = body.decode("utf-8")
page = Page()
page.feed(html)
title = " ".join(page.title).strip()
h1 = " ".join(page.h1).split()
h1 = " ".join(h1)
text = " ".join(t.strip() for t in page.text if t.strip())

if "Night Walker" not in title:
    sys.exit(f"title was {title!r}, expected Night Walker")
if h1.replace("\n", " ") != "Night Walker":
    sys.exit(f"h1 was {h1!r}, expected Night Walker")
if "NightWalker.dmg" not in page.links:
    sys.exit(f"Download href missing NightWalker.dmg; links={page.links}")
if any("/Users/flo/Downloads" in href for href in page.links):
    sys.exit("page must not link at the captain Downloads path")
if "Download" not in text:
    sys.exit("primary CTA 'Download' missing from page text")
if "Color Filters on at sunset" not in text or "Off at sunrise" not in text:
    sys.exit("product line missing")
if "macOS 13+" not in text:
    sys.exit("Gatekeeper macOS 13+ line missing")
if "Intel or Apple Silicon" not in text:
    sys.exit("Gatekeeper architecture line missing")
if "Right-click" not in text or "Open the first time" not in text:
    sys.exit("Gatekeeper right-click → Open line missing")

dmg_status, dmg_headers, dmg_body = fetch("/NightWalker.dmg")
if dmg_status != 200:
    sys.exit(f"GET /NightWalker.dmg returned {dmg_status}")
if len(dmg_body) != expected_dmg_size:
    sys.exit(
        f"DMG Content-Length/body {len(dmg_body)} != file size {expected_dmg_size}"
    )
if dmg_body[-512:-508] != b"koly":
    sys.exit("served NightWalker.dmg is not a UDIF image")

print("ok: page title, h1, Download href, Gatekeeper copy")
print("ok: NightWalker.dmg served with matching bytes")
PY

echo "site-contract: all checks passed"
