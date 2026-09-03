#!/usr/bin/env bash
# Copy extra .apk files into ImageBuilder, including OpenClash and Argon.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IB="$ROOT/ib"

mkdir -p "$IB/packages"

if ls "$ROOT/packages/"*.apk >/dev/null 2>&1; then
	cp "$ROOT/packages/"*.apk "$IB/packages/"
fi

python3 - "$IB/packages" <<'PY'
import json, os, ssl, sys, urllib.request
from pathlib import Path

dest = Path(sys.argv[1])
ctx = ssl.create_default_context()
headers = {
    "Accept": "application/vnd.github+json",
    "User-Agent": "openwrt-pve-lxc",
}
token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
if token:
    headers["Authorization"] = f"Bearer {token}"


def latest_apks(repo, prefixes):
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
    if missing:
        raise SystemExit(f"{repo}: missing apk for {missing}")
    for asset in found:
        out = dest / asset["name"]
        print(f"Downloading {repo} {asset['name']}")
        req = urllib.request.Request(
            asset["browser_download_url"],
            headers={"User-Agent": "openwrt-pve-lxc"},
        )
        with urllib.request.urlopen(req, context=ctx, timeout=180) as resp, out.open("wb") as fh:
            fh.write(resp.read())


latest_apks("vernesong/OpenClash", ["luci-app-openclash-"])
latest_apks(
    "jerrykuku/luci-theme-argon",
    [
        "luci-theme-argon-",
        "luci-app-argon-config-",
        "luci-i18n-argon-config-zh-cn-",
    ],
)
PY
