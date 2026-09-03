#!/usr/bin/env bash
# Copy extra .apk files into ImageBuilder and record their package names
# so they are actually installed (ImageBuilder only installs PACKAGES=).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IB="$ROOT/ib"
EXTRA_LIST="$IB/extra-packages.list"

mkdir -p "$IB/packages"
: > "$EXTRA_LIST"

python3 - "$ROOT/packages" "$IB/packages" "$EXTRA_LIST" <<'PY'
import json, os, re, ssl, sys, urllib.request
from pathlib import Path

src_dir, dest, extra_list = map(Path, sys.argv[1:])
dest.mkdir(parents=True, exist_ok=True)
names = []

def pkgname_from_filename(name: str) -> str:
    stem = name[:-4] if name.lower().endswith(".apk") else name
    match = re.match(r"^(.+?)[-_][0-9]", stem)
    return match.group(1) if match else stem


def remember(apk: Path) -> None:
    pkg = pkgname_from_filename(apk.name)
    names.append(pkg)
    print(f"Local apk: {apk.name} -> {pkg}")


for apk in sorted(src_dir.glob("*.apk")):
    target = dest / apk.name
    target.write_bytes(apk.read_bytes())
    remember(apk)

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
        remember(out)


latest_apks("vernesong/OpenClash", ["luci-app-openclash-"])
latest_apks(
    "jerrykuku/luci-theme-argon",
    [
        "luci-theme-argon-",
        "luci-app-argon-config-",
        "luci-i18n-argon-config-zh-cn-",
    ],
)

unique = list(dict.fromkeys(names))
extra_list.write_text("\n".join(unique) + ("\n" if unique else ""), encoding="utf-8")
print("Extra packages to install: " + " ".join(unique))
PY

# Force ImageBuilder to rebuild the local apk index so new files are visible.
rm -f "$IB/packages/packages.adb"
