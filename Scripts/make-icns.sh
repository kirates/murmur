#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/.build/icon"
SET="$WORK/Murmur.iconset"
OUT="$ROOT/Resources/Murmur.icns"

mkdir -p "$WORK"
swift "$ROOT/Scripts/make-icon.swift" "$WORK/icon_1024.png"

rm -rf "$SET"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
	sips -z $size $size "$WORK/icon_1024.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
	sips -z $((size * 2)) $((size * 2)) "$WORK/icon_1024.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$SET" -o "$OUT"
echo "$OUT"
