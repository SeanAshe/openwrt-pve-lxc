#!/usr/bin/env bash
# Put unofficial .apk files in a separate ImageBuilder repo (packages-extra).
# Mixing them into ib/packages/ rebuilds the official index and breaks apk.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IB="$ROOT/ib"
EXTRA_DIR="$IB/packages-extra"
EXTRA_LIST="$IB/extra-packages.list"

mkdir -p "$EXTRA_DIR"
: > "$EXTRA_LIST"

python3 - "$ROOT/packages" "$EXTRA_DIR" "$EXTRA_LIST" <<'PY'
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
    if apk.stat().st_size < 1024:
        raise SystemExit(f"{apk.name} is too small ({apk.stat().st_size} bytes), not a valid apk")
    pkg = pkgname_from_filename(apk.name)
    names.append(pkg)
    print(f"Extra apk: {apk.name} -> {pkg}")


if src_dir.is_dir():
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
        if not name.endswith(".apk"):
            continue
        if any(name.startswith(p) for p in prefixes):
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

shopt -s nullglob
extra_apks=("$EXTRA_DIR"/*.apk)
if [ ${#extra_apks[@]} -eq 0 ]; then
	echo "No extra apk files"
	exit 0
fi

echo "Generating ImageBuilder signing keys"
make -C "$IB" _check_keys

APK_BIN="$IB/staging_dir/host/bin/apk"
if [ ! -x "$APK_BIN" ]; then
	echo "ImageBuilder host apk not found: $APK_BIN" >&2
	exit 1
fi

KEY_SEC="$IB/keys/local-private-key.pem"
if [ ! -s "$KEY_SEC" ]; then
	echo "Local apk signing key was not created" >&2
	exit 1
fi

echo "Indexing extra apks in $EXTRA_DIR"
(
	cd "$EXTRA_DIR"
	"$APK_BIN" mkndx \
		--keys-dir "$IB/keys" \
		--sign "$KEY_SEC" \
		--allow-untrusted \
		--output packages.adb \
		*.apk
)

python3 - "$IB/Makefile" <<'PY'
from pathlib import Path
import sys

makefile = Path(sys.argv[1])
text = makefile.read_text(encoding="utf-8")
marker = "$(TOPDIR)/packages-extra/packages.adb"
if marker in text:
    print("Makefile already has packages-extra repository")
    raise SystemExit(0)

old = "--repository $(PACKAGE_DIR)/packages.adb"
new = old + " \\\n\t--repository $(TOPDIR)/packages-extra/packages.adb"
if old not in text:
    raise SystemExit("Could not patch ImageBuilder Makefile APK repositories")
makefile.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Patched ImageBuilder Makefile to use packages-extra")
PY
