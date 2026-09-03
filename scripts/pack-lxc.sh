#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/configs/x86_64.env"

mkdir -p "$ROOT/out"

BUILD_STAMP="${BUILD_STAMP:-$(TZ=Asia/Shanghai date +%Y%m%d-%H%M)}"
OUTPUT_NAME="openwrt-${OPENWRT_VERSION}-x86-64-pve-lxc-${BUILD_STAMP}.tar.gz"

src="$(
	find "$ROOT/ib" -type f -name '*rootfs.tar.gz' \
		! -name '*squashfs*' ! -name '*ext4*' \
		| head -n 1
)"

if [ -z "$src" ]; then
	echo "No rootfs.tar.gz found under ib/" >&2
	find "$ROOT/ib" -type f -name '*.tar.gz' -o -name '*.img*' >&2 || true
	exit 1
fi

dst="$ROOT/out/${OUTPUT_NAME}"
cp -f "$src" "$dst"
(cd "$ROOT/out" && sha256sum "$OUTPUT_NAME" > "${OUTPUT_NAME}.sha256")

if [ -n "${GITHUB_ENV:-}" ]; then
	echo "OUTPUT_NAME=$OUTPUT_NAME" >> "$GITHUB_ENV"
	echo "BUILD_STAMP=$BUILD_STAMP" >> "$GITHUB_ENV"
fi

echo "Packed $src -> $dst"
cat "$dst.sha256"
