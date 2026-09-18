#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/.dist/Murmur.app"

cd "$ROOT"
swift build -c "$CONFIG" --product Murmur

BIN="$(swift build -c "$CONFIG" --product Murmur --show-bin-path)/Murmur"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Murmur"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep --options runtime \
	--entitlements "$ROOT/Resources/Murmur.entitlements" \
	--sign - "$APP"

echo "$APP"
