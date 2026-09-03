#!/usr/bin/env bash
# Copy local .apk files and fetch GuNanOvO Tailscale into ImageBuilder.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IB="$ROOT/ib"
ARCH_PACKAGES="${ARCH_PACKAGES:-x86_64}"
KEY_NAME='gunanovo@github.io.pub'
FEED="https://gunanovo.github.io/openwrt-tailscale/${ARCH_PACKAGES}/packages.adb"

mkdir -p "$IB/packages" "$IB/keys"

if ls "$ROOT/packages/"*.apk >/dev/null 2>&1; then
	cp "$ROOT/packages/"*.apk "$IB/packages/"
fi

cp "$ROOT/files/etc/apk/keys/${KEY_NAME}" "$IB/keys/${KEY_NAME}"

if [ -f "$IB/repositories" ] && ! grep -Fqx "$FEED" "$IB/repositories"; then
	echo "$FEED" >> "$IB/repositories"
fi

python3 - "$IB/packages" "$ARCH_PACKAGES" <<'PY'
import json, ssl, sys, urllib.request
from pathlib import Path

dest, arch = Path(sys.argv[1]), sys.argv[2]
api = "https://api.github.com/repos/GuNanOvO/openwrt-tailscale/releases/latest"
ctx = ssl.create_default_context()
req = urllib.request.Request(api, headers={"Accept": "application/vnd.github+json", "User-Agent": "openwrt-pve-lxc"})
with urllib.request.urlopen(req, context=ctx, timeout=60) as resp:
    release = json.load(resp)

asset = next((a for a in release["assets"] if a["name"].endswith(f"_{arch}.apk")), None)
if asset is None:
    raise SystemExit(f"No Tailscale apk found for {arch}")

out = dest / asset["name"]
print(f"Downloading {asset['name']}")
req = urllib.request.Request(asset["browser_download_url"], headers={"User-Agent": "openwrt-pve-lxc"})
with urllib.request.urlopen(req, context=ctx, timeout=120) as resp, out.open("wb") as fh:
    fh.write(resp.read())
print(f"Saved {out}")
PY
