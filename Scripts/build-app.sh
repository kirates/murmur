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

# TCC keys an ad-hoc signature on the binary hash, so every rebuild invalidates
# the user's Microphone and Accessibility grants. A real identity keeps them.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning \
	| awk -F'"' '/Apple Development/ {print $2; exit}')}"
: "${IDENTITY:=-}"

codesign --force --deep --options runtime \
	--entitlements "$ROOT/Resources/Murmur.entitlements" \
	--sign "$IDENTITY" "$APP"

echo "signed with: $IDENTITY" >&2

echo "$APP"
