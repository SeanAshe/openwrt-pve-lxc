#!/usr/bin/env bash
# Copy extra .apk files from packages/ into ImageBuilder.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IB="$ROOT/ib"

mkdir -p "$IB/packages"

if ls "$ROOT/packages/"*.apk >/dev/null 2>&1; then
	cp "$ROOT/packages/"*.apk "$IB/packages/"
fi
