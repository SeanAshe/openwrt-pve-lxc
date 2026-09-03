#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/configs/x86_64.env"

DOWNLOAD_BASE="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET}/${SUBTARGET}"
IMAGEBUILDER_ARCHIVE="openwrt-imagebuilder-${OPENWRT_VERSION}-${TARGET}-${SUBTARGET}.Linux-x86_64.tar.zst"

cd "$ROOT"
rm -rf ib
curl -fsSL -o "$IMAGEBUILDER_ARCHIVE" "${DOWNLOAD_BASE}/${IMAGEBUILDER_ARCHIVE}"
echo "${IMAGEBUILDER_SHA256}  ${IMAGEBUILDER_ARCHIVE}" | sha256sum -c -

tar --zstd -xf "$IMAGEBUILDER_ARCHIVE"
rm -f "$IMAGEBUILDER_ARCHIVE"
mv openwrt-imagebuilder-* ib

make -C ib image \
	PROFILE="$PROFILE" \
	PACKAGES="$PACKAGES" \
	FILES="$ROOT/files" \
	EXTRA_IMAGE_NAME="$EXTRA_IMAGE_NAME" \
	BIN_DIR="$ROOT/ib/bin"

bash "$ROOT/scripts/pack-lxc.sh"
