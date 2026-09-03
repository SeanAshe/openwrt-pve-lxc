#!/usr/bin/env bash
# Download OpenClash and Argon apks from GitHub Releases.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/files/root/luci-extras}"
mkdir -p "$DEST"
rm -f "$DEST"/*.apk

python3 - "$DEST" <<'PY'
import json, os, ssl, sys, urllib.request
from pathlib import Path

dest = Path(sys.argv[1])
dest.mkdir(parents=True, exist_ok=True)

ctx = ssl.create_default_context()
headers = {
    "Accept": "application/vnd.github+json",
    "User-Agent": "openwrt-pve-lxc",
}
token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
if token:
    headers["Authorization"] = f"Bearer {token}"


def latest_apks(repo, prefixes, optional=False):
    api = f"https://api.github.com/repos/{repo}/releases/latest"
    req = urllib.request.Request(api, headers=headers)
    with urllib.request.urlopen(req, context=ctx, timeout=60) as resp:
        release = json.load(resp)
    found = []
    for asset in release["assets"]:
        name = asset["name"]
        if name.endswith(".apk") and any(name.startswith(p) for p in prefixes):
            found.append(asset)
    missing = [p for p in prefixes if not any(a["name"].startswith(p) for a in found)]
    if missing and not optional:
        raise SystemExit(f"{repo}: missing apk for {missing}")
    for asset in found:
        out = dest / asset["name"]
        print(f"Downloading {repo} {asset['name']}")
        dl_headers = {"User-Agent": "openwrt-pve-lxc"}
        if token:
            dl_headers["Authorization"] = f"Bearer {token}"
        req = urllib.request.Request(
            asset["browser_download_url"],
            headers=dl_headers,
        )
        with urllib.request.urlopen(req, context=ctx, timeout=180) as resp:
            data = resp.read()
        if len(data) < 1024:
            raise SystemExit(f"{asset['name']} is too small ({len(data)} bytes)")
        out.write_bytes(data)


latest_apks("vernesong/OpenClash", ["luci-app-openclash-"])
latest_apks(
    "jerrykuku/luci-theme-argon",
    ["luci-theme-argon-", "luci-app-argon-config-"],
)
latest_apks(
    "jerrykuku/luci-theme-argon",
    ["luci-i18n-argon-config-zh-cn-"],
    optional=True,
)
print("Downloaded:")
for path in sorted(dest.glob("*.apk")):
    print(f"  {path.name} ({path.stat().st_size} bytes)")
PY
